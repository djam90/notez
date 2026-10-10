import { describe, expect, test, vi } from 'vitest'
import type { JSONContent } from '@tiptap/core'
import { filterSlashItems, slashItems } from '../../src/slash'
import { findAll, makeEditor } from './helpers'

const items = slashItems(() => {})
const titles = (query: string) => filterSlashItems(items, query).map((i) => i.title)

describe('slash menu filtering', () => {
  test('empty query lists everything in menu order', () => {
    expect(titles('')).toEqual([
      'Text',
      'Heading 1',
      'Heading 2',
      'Heading 3',
      'Bullet list',
      'Numbered list',
      'To-do list',
      'Table',
      'Image',
      'Quote',
      'Code block',
      'Divider',
    ])
  })

  test('matches titles case-insensitively', () => {
    expect(titles('ta')).toEqual(['To-do list', 'Table'])
    expect(titles('TAB')).toEqual(['Table'])
    expect(titles('head')).toEqual(['Heading 1', 'Heading 2', 'Heading 3'])
  })

  test('matches keywords', () => {
    expect(titles('h2')).toEqual(['Heading 2'])
    expect(titles('todo')).toEqual(['To-do list'])
    expect(titles('grid')).toEqual(['Table'])
    expect(titles('photo')).toEqual(['Image'])
    expect(titles('hr')).toEqual(['Divider'])
    expect(titles('blockquote')).toEqual(['Quote'])
  })

  test('does not match hints', () => {
    expect(titles('3×3')).toEqual([])
    expect(titles('```')).toEqual([])
  })

  test('no match gives an empty list', () => {
    expect(titles('zzz')).toEqual([])
  })
})

describe('every slash item runs on a real editor', () => {
  // Content as it is mid-command: the paragraph holds the typed "/query".
  const query = '/query'
  const range = { from: 1, to: 1 + query.length }

  const expected: Record<string, (d: JSONContent) => void> = {
    Text: (d) => expect(d.content![0].type).toBe('paragraph'),
    'Heading 1': (d) => expect(d.content![0]).toMatchObject({ type: 'heading', attrs: { level: 1 } }),
    'Heading 2': (d) => expect(d.content![0]).toMatchObject({ type: 'heading', attrs: { level: 2 } }),
    'Heading 3': (d) => expect(d.content![0]).toMatchObject({ type: 'heading', attrs: { level: 3 } }),
    'Bullet list': (d) => expect(d.content![0].type).toBe('bulletList'),
    'Numbered list': (d) => expect(d.content![0].type).toBe('orderedList'),
    'To-do list': (d) => expect(d.content![0]).toMatchObject({ type: 'taskList', content: [{ attrs: { checked: false } }] }),
    Table: (d) => {
      const rows = findAll(d, 'tableRow')
      expect(rows).toHaveLength(3)
      expect(rows.map((r) => r.content!.length)).toEqual([3, 3, 3])
      expect(rows[0].content!.every((c) => c.type === 'tableHeader')).toBe(true)
      expect(rows[1].content!.every((c) => c.type === 'tableCell')).toBe(true)
    },
    Image: (d) => expect(findAll(d, 'image')).toHaveLength(0),
    Quote: (d) => expect(d.content![0].type).toBe('blockquote'),
    'Code block': (d) => expect(d.content![0].type).toBe('codeBlock'),
    Divider: (d) => expect(d.content![0].type).toBe('horizontalRule'),
  }

  test('expectations cover every item', () => {
    expect(Object.keys(expected).sort()).toEqual(items.map((i) => i.title).sort())
  })

  test.each(items.map((i) => [i.title]))('%s', (title) => {
    const pickImage = vi.fn()
    const item = slashItems(pickImage).find((i) => i.title === title)!
    const editor = makeEditor({ type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: query }] }] })
    editor.commands.setTextSelection(range.to)
    expect(() => item.run(editor, range)).not.toThrow()
    const json = editor.getJSON()
    expect(editor.getText()).not.toContain(query)
    expected[title](json)
    expect(pickImage).toHaveBeenCalledTimes(title === 'Image' ? 1 : 0)
    editor.destroy()
  })
})
