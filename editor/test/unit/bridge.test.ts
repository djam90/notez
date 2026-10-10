import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { afterEach, beforeAll, describe, expect, test, vi } from 'vitest'
import type { Editor, JSONContent } from '@tiptap/core'
import type { OutgoingMessage } from '../../src/bridge'

// Boots the real main.ts against a fake WKWebView message handler, so this
// exercises the production bridge path (not the browser dev host) and pins the
// message shapes EditorController.handle reads.

const sent: OutgoingMessage[] = []
let bootMessages: OutgoingMessage[] = []
let editor: Editor
const ASSET = 'notez://asset/00000000-0000-0000-0000-000000000001'

beforeAll(async () => {
  const html = readFileSync(resolve(import.meta.dirname, '../../editor.html'), 'utf8')
  document.body.innerHTML = html.slice(html.indexOf('<body>') + 6, html.indexOf('</body>'))
  Object.assign(window, {
    webkit: { messageHandlers: { notez: { postMessage: (m: OutgoingMessage) => sent.push(structuredClone(m)) } } },
  })
  await import('../../src/main')
  editor = (window as unknown as { editor: Editor }).editor
  bootMessages = [...sent]
})

afterEach(() => {
  vi.useRealTimers()
  sent.length = 0
})

const changes = () => sent.filter((m) => m.type === 'change')
const docOf = (m: OutgoingMessage) => JSON.parse((m as { doc: string }).doc) as JSONContent
const title = () => document.getElementById('title') as HTMLTextAreaElement
const paraDoc = (t: string) =>
  JSON.stringify({ type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: t }] }] })

describe('boot', () => {
  test('posts ready once and exposes the native API', async () => {
    expect(bootMessages).toEqual([{ type: 'ready' }])
    expect(Object.keys(window.notez).sort()).toEqual(
      ['flush', 'focus', 'focusTitle', 'getMarkdown', 'load', 'pickImage', 'resolveUpload'].sort(),
    )
  })
})

describe('load and save', () => {
  test('load shows the doc without saving it back', () => {
    window.notez.load({ id: 'a', title: 'Alpha', doc: paraDoc('hello'), focus: 'none' })
    expect(title().value).toBe('Alpha')
    expect(editor.getText()).toBe('hello')
    window.notez.flush()
    expect(changes()).toHaveLength(0)
  })

  test('an edit posts one debounced change with the fields native reads', () => {
    vi.useFakeTimers()
    window.notez.load({ id: 'a', title: 'Alpha', doc: paraDoc('hello'), focus: 'none' })
    editor.commands.insertContentAt(editor.state.doc.content.size - 1, ' world')
    editor.commands.insertContentAt(editor.state.doc.content.size - 1, '!')
    vi.advanceTimersByTime(299)
    expect(changes()).toHaveLength(0)
    vi.advanceTimersByTime(1)
    expect(changes()).toHaveLength(1)
    const msg = changes()[0]
    expect(Object.keys(msg).sort()).toEqual(['doc', 'id', 'text', 'title', 'type'])
    expect(msg).toMatchObject({ type: 'change', id: 'a', title: 'Alpha', text: 'hello world!' })
    expect(docOf(msg)).toEqual(editor.getJSON())
  })

  test('text puts each block on its own line (search and previews rely on it)', () => {
    window.notez.load({ id: 'b', title: '', doc: null, markdown: '# H\n\n- one\n- two', focus: 'none' })
    // Nested blocks (list > item > paragraph) each add a separator, so lists
    // produce blank lines. Native turns newlines into spaces for previews.
    expect((changes()[0] as { text: string }).text.trim().split(/\n+/)).toEqual(['H', 'one', 'two'])
  })

  test('title edits save too', () => {
    vi.useFakeTimers()
    window.notez.load({ id: 'a', title: 'Alpha', doc: paraDoc('x'), focus: 'none' })
    title().value = 'Renamed'
    title().dispatchEvent(new Event('input'))
    vi.advanceTimersByTime(300)
    expect(changes()).toEqual([expect.objectContaining({ id: 'a', title: 'Renamed' })])
  })

  test('switching notes flushes the old note first, under its own id', () => {
    window.notez.load({ id: 'a', title: 'Alpha', doc: paraDoc('x'), focus: 'none' })
    editor.commands.insertContentAt(1, 'edited ')
    window.notez.load({ id: 'b', title: 'Beta', doc: paraDoc('y'), focus: 'none' })
    expect(changes()).toHaveLength(1)
    expect(changes()[0]).toMatchObject({ id: 'a', title: 'Alpha', text: 'edited x' })
    expect(editor.getText()).toBe('y')
  })

  test('reloading the open note drops unsaved edits (native wins)', () => {
    vi.useFakeTimers()
    window.notez.load({ id: 'a', title: 'Alpha', doc: paraDoc('x'), focus: 'none' })
    editor.commands.insertContentAt(1, 'local ')
    window.notez.load({ id: 'a', title: 'Alpha', doc: paraDoc('from api'), focus: 'none' })
    vi.advanceTimersByTime(1000)
    expect(changes()).toHaveLength(0)
    expect(editor.getText()).toBe('from api')
  })

  test('switching notes resets undo history', () => {
    window.notez.load({ id: 'a', title: '', doc: paraDoc('first'), focus: 'none' })
    editor.commands.insertContentAt(1, 'typed ')
    window.notez.load({ id: 'b', title: '', doc: paraDoc('second'), focus: 'none' })
    expect(editor.can().undo()).toBe(false)
    editor.commands.undo()
    expect(editor.getText()).toBe('second')
  })

  // On iOS TipTap's focus() focuses the DOM synchronously, which dispatches a
  // transaction mid-command. If that transaction changed the doc (the trailing
  // paragraph after a table or list) the command's own one threw.
  test('focusing the body after load works on iOS when the doc ends in a block', () => {
    const platform = Object.getOwnPropertyDescriptor(Navigator.prototype, 'platform')!
    Object.defineProperty(navigator, 'platform', { value: 'iPhone', configurable: true })
    try {
      editor.commands.blur()
      const md = '| A | B |\n| --- | --- |\n| 1 | 2 |'
      expect(() => window.notez.load({ id: 'ios', title: '', doc: null, markdown: md, focus: 'body' })).not.toThrow()
      // A stored doc without the trailing paragraph, then Enter in the title.
      const list = { type: 'bulletList', content: [{ type: 'listItem', content: [{ type: 'paragraph' }] }] }
      window.notez.load({ id: 'ios2', title: '', doc: JSON.stringify({ type: 'doc', content: [list] }), focus: 'none' })
      editor.commands.blur()
      expect(() => editor.commands.focus('start')).not.toThrow()
      expect(editor.state.selection.from).toBe(3)
    } finally {
      delete (navigator as { platform?: string }).platform
      Object.defineProperty(Navigator.prototype, 'platform', platform)
    }
  })

  test('a corrupt doc opens empty instead of throwing', () => {
    expect(() => window.notez.load({ id: 'c', title: 'Bad', doc: '{oops', focus: 'none' })).not.toThrow()
    expect(editor.getText()).toBe('')
  })
})

describe('pending markdown', () => {
  test('replaces an empty doc and is saved as JSON straight away', () => {
    window.notez.load({ id: 'm', title: 'Seed', doc: null, markdown: '# Hi\n\n- [x] done', focus: 'none' })
    expect(changes()).toHaveLength(1)
    const saved = docOf(changes()[0])
    expect(saved.content!.map((n) => n.type)).toEqual(['heading', 'taskList', 'paragraph'])
    expect(saved).toEqual(editor.getJSON())
  })

  test('is appended to an existing doc', () => {
    window.notez.load({ id: 'm', title: 'T', doc: paraDoc('kept'), markdown: '## Added', focus: 'none' })
    const saved = docOf(changes()[0])
    expect(saved.content![0].content![0].text).toBe('kept')
    expect(saved.content![1]).toMatchObject({ type: 'heading', attrs: { level: 2 } })
  })
})

describe('export', () => {
  test('getMarkdown prefixes the title as H1', () => {
    window.notez.load({ id: 'e', title: 'Page', doc: null, markdown: 'Some **bold**', focus: 'none' })
    expect(window.notez.getMarkdown()).toBe('# Page\n\nSome **bold**')
  })
})

describe('paste', () => {
  function paste(data: { text?: string; html?: string; files?: File[] }) {
    const types = [...(data.text != null ? ['text/plain'] : []), ...(data.html != null ? ['text/html'] : [])]
    const event = {
      clipboardData: {
        files: data.files ?? [],
        types: data.files?.length ? [...types, 'Files'] : types,
        getData: (t: string) => (t === 'text/plain' ? (data.text ?? '') : t === 'text/html' ? (data.html ?? '') : ''),
      },
      preventDefault() {},
    } as unknown as ClipboardEvent
    let handled = false
    editor.view.someProp('handlePaste', (f) => (handled = f(editor.view, event, editor.state.selection.content()) || handled))
    return handled
  }

  test('markdown text is converted to rich content', () => {
    window.notez.load({ id: 'p', title: '', doc: null, focus: 'none' })
    expect(paste({ text: '| A | B |\n| --- | --- |\n| 1 | 2 |\n\n- [ ] task' })).toBe(true)
    const types = editor.getJSON().content!.map((n) => n.type)
    expect(types).toContain('table')
    expect(types).toContain('taskList')
  })

  test('plain text and HTML pastes fall through to ProseMirror', () => {
    window.notez.load({ id: 'p', title: '', doc: null, focus: 'none' })
    expect(paste({ text: 'just words' })).toBe(false)
    expect(paste({ text: '# looks like md', html: '<h1>but html wins</h1>' })).toBe(false)
  })

  test('an image goes through uploadImage and only the asset URL lands in the doc', async () => {
    window.notez.load({ id: 'img', title: '', doc: null, focus: 'none' })
    const png = new File([new Uint8Array([137, 80, 78, 71])], 'shot.png', { type: 'image/png' })
    expect(paste({ files: [png] })).toBe(true)

    await vi.waitFor(() => expect(sent.some((m) => m.type === 'uploadImage')).toBe(true))
    const upload = sent.find((m) => m.type === 'uploadImage') as Extract<OutgoingMessage, { type: 'uploadImage' }>
    expect(Object.keys(upload).sort()).toEqual(['base64', 'mime', 'requestId', 'type'])
    expect(upload.mime).toBe('image/png')
    expect(upload.base64).toBe('iVBORw==')
    expect(upload.base64.startsWith('data:')).toBe(false)

    // What EditorController does after storing the Asset.
    window.notez.resolveUpload(upload.requestId, ASSET)
    await vi.waitFor(() => expect(editor.getJSON().content!.some((n) => n.type === 'image')).toBe(true))
    window.notez.flush()
    const saved = changes().at(-1)!
    expect((saved as { doc: string }).doc).toContain(ASSET)
    expect((saved as { doc: string }).doc).not.toContain('data:')
  })

  test('a failed upload inserts nothing', async () => {
    window.notez.load({ id: 'img2', title: '', doc: null, focus: 'none' })
    paste({ files: [new File(['x'], 'a.png', { type: 'image/png' })] })
    await vi.waitFor(() => expect(sent.some((m) => m.type === 'uploadImage')).toBe(true))
    const upload = sent.find((m) => m.type === 'uploadImage') as Extract<OutgoingMessage, { type: 'uploadImage' }>
    window.notez.resolveUpload(upload.requestId, null)
    await Promise.resolve()
    expect(editor.getJSON().content!.some((n) => n.type === 'image')).toBe(false)
  })
})

describe('errors', () => {
  test('uncaught errors are forwarded as log messages', () => {
    window.dispatchEvent(new ErrorEvent('error', { message: 'boom', filename: 'main.ts', lineno: 7 }))
    expect(sent).toContainEqual({ type: 'log', message: 'boom @ main.ts:7' })
  })
})
