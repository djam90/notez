import { Editor, type JSONContent } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import { TableKit } from '@tiptap/extension-table'
import { TaskList, TaskItem } from '@tiptap/extension-list'
import Image from '@tiptap/extension-image'
import Highlight from '@tiptap/extension-highlight'
import Typography from '@tiptap/extension-typography'
import { Placeholder } from '@tiptap/extensions'
import { Markdown } from '@tiptap/markdown'
import { BubbleMenu } from '@tiptap/extension-bubble-menu'
import { EditorState } from '@tiptap/pm/state'
import { post, uploadImage, resolveUpload, type NoteDoc } from './bridge'
import { SlashCommand, slashItems } from './slash'
import './style.css'

const SAVE_DELAY_MS = 300
const isTouch = matchMedia('(pointer: coarse)').matches

const titleEl = document.getElementById('title') as HTMLTextAreaElement
const fileInput = document.getElementById('file-input') as HTMLInputElement

let currentId: string | null = null
let saveTimer: number | undefined
let dirty = false

// --- Editor ------------------------------------------------------------------

const formatMenu = document.createElement('div')
formatMenu.className = 'bubble'
const tableMenu = document.createElement('div')
tableMenu.className = 'bubble'

const editor = new Editor({
  element: document.getElementById('editor')!,
  extensions: [
    StarterKit.configure({
      link: { openOnClick: false, autolink: true, defaultProtocol: 'https' },
    }),
    TableKit.configure({ table: { resizable: true } }),
    TaskList,
    TaskItem.configure({ nested: true }),
    Image.configure({ resize: { enabled: true, alwaysPreserveAspectRatio: true, minWidth: 48 } }),
    Highlight,
    Typography,
    Markdown,
    Placeholder.configure({ placeholder: "Type '/' for commands, or just start dumping…" }),
    SlashCommand(slashItems(() => fileInput.click())),
    BubbleMenu.configure({
      pluginKey: 'formatMenu',
      element: formatMenu,
      shouldShow: ({ editor, from, to }) =>
        from !== to && !editor.isActive('image') && !editor.isActive('table') && !isTouch,
      options: { strategy: 'fixed', placement: 'top' },
    }),
    BubbleMenu.extend({ name: 'tableMenu' }).configure({
      pluginKey: 'tableMenu',
      element: tableMenu,
      shouldShow: ({ editor }) => editor.isActive('table'),
      options: { strategy: 'fixed', placement: 'top-start' },
      getReferencedVirtualElement: () => tableElementAtSelection(),
    }),
  ],
  editorProps: {
    attributes: { spellcheck: 'true' },
    handlePaste: (_view, event) => {
      const data = event.clipboardData
      if (!data) return false
      const images = [...data.files].filter((f) => f.type.startsWith('image/'))
      if (images.length) {
        images.forEach(insertImageFile)
        return true
      }
      // Pasting raw markdown (e.g. from an LLM or a README) -> rich content.
      const text = data.getData('text/plain')
      if (!data.types.includes('text/html') && looksLikeMarkdown(text)) {
        editor.commands.insertContent(text, { contentType: 'markdown' })
        return true
      }
      return false
    },
    handleDrop: (view, event) => {
      const files = [...(event.dataTransfer?.files ?? [])].filter((f) => f.type.startsWith('image/'))
      if (!files.length) return false
      const pos = view.posAtCoords({ left: event.clientX, top: event.clientY })?.pos
      if (pos != null) editor.commands.setTextSelection(pos)
      files.forEach(insertImageFile)
      return true
    },
    handleClickOn: (_view, _pos, _node, _nodePos, event) => {
      const link = (event.target as HTMLElement).closest('a')
      if (link?.href && (event.metaKey || event.ctrlKey || isTouch)) {
        post({ type: 'openURL', url: link.href })
        return true
      }
      return false
    },
  },
  onUpdate: () => scheduleSave(),
})

function looksLikeMarkdown(text: string) {
  return /^(#{1,6} |\s*[-*+] |\s*\d+\. |> |```|\|.+\|)|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)/m.test(text)
}

async function insertImageFile(file: Blob) {
  const url = await uploadImage(file)
  if (url) editor.chain().focus().setImage({ src: url }).run()
}

fileInput.addEventListener('change', () => {
  ;[...(fileInput.files ?? [])].forEach(insertImageFile)
  fileInput.value = ''
})

// --- Bubble menus ------------------------------------------------------------

type MenuButton = [label: string, title: string, run: () => void, active?: () => boolean]

function buildMenu(el: HTMLElement, buttons: MenuButton[]) {
  const nodes = buttons.map(([label, title, run, active]) => {
    const b = document.createElement('button')
    b.innerHTML = label
    b.title = title
    b.onmousedown = (e) => {
      e.preventDefault()
      run()
      refresh()
    }
    return { b, active }
  })
  const refresh = () => nodes.forEach(({ b, active }) => b.classList.toggle('on', !!active?.()))
  el.replaceChildren(...nodes.map((n) => n.b))
  editor.on('selectionUpdate', refresh)
  editor.on('transaction', refresh)
}

const c = () => editor.chain().focus()

buildMenu(formatMenu, [
  ['<b>B</b>', 'Bold ⌘B', () => c().toggleBold().run(), () => editor.isActive('bold')],
  ['<i>I</i>', 'Italic ⌘I', () => c().toggleItalic().run(), () => editor.isActive('italic')],
  ['<u>U</u>', 'Underline ⌘U', () => c().toggleUnderline().run(), () => editor.isActive('underline')],
  ['<s>S</s>', 'Strikethrough', () => c().toggleStrike().run(), () => editor.isActive('strike')],
  ['<code>&lt;/&gt;</code>', 'Inline code', () => c().toggleCode().run(), () => editor.isActive('code')],
  ['<mark>H</mark>', 'Highlight', () => c().toggleHighlight().run(), () => editor.isActive('highlight')],
  ['Link', 'Link', () => promptLink(), () => editor.isActive('link')],
])

buildMenu(tableMenu, [
  ['+ Row', 'Add row below', () => c().addRowAfter().run()],
  ['+ Col', 'Add column right', () => c().addColumnAfter().run()],
  ['− Row', 'Delete row', () => c().deleteRow().run()],
  ['− Col', 'Delete column', () => c().deleteColumn().run()],
  ['Header', 'Toggle header row', () => c().toggleHeaderRow().run()],
  ['Merge', 'Merge / split cells', () => c().mergeOrSplit().run()],
  ['Delete', 'Delete table', () => c().deleteTable().run()],
])

function tableElementAtSelection() {
  const { node } = editor.view.domAtPos(editor.state.selection.from)
  const el = node instanceof Element ? node : node.parentElement
  return el?.closest('.tableWrapper') ?? el?.closest('table') ?? null
}

// Inline URL field inside the format bubble (window.prompt isn't available
// in WKWebView without extra native plumbing).
function promptLink() {
  const buttons = [...formatMenu.children]
  const input = document.createElement('input')
  input.className = 'link-input'
  input.placeholder = 'Paste link, Enter to apply'
  input.value = (editor.getAttributes('link').href as string | undefined) ?? ''
  const restore = () => formatMenu.replaceChildren(...buttons)
  input.onkeydown = (e) => {
    if (e.key === 'Enter') {
      e.preventDefault()
      const url = input.value.trim()
      if (url) c().extendMarkRange('link').setLink({ href: url }).run()
      else c().extendMarkRange('link').unsetLink().run()
      restore()
    } else if (e.key === 'Escape') {
      e.preventDefault()
      restore()
      editor.commands.focus()
    }
  }
  input.onblur = restore
  formatMenu.replaceChildren(input)
  input.focus()
}

// --- Title -------------------------------------------------------------------

function autosizeTitle() {
  titleEl.style.height = 'auto'
  titleEl.style.height = `${titleEl.scrollHeight}px`
}

titleEl.addEventListener('input', () => {
  autosizeTitle()
  scheduleSave()
})

titleEl.addEventListener('keydown', (e) => {
  const atEnd = titleEl.selectionStart === titleEl.value.length
  if (e.key === 'Enter' || (e.key === 'ArrowDown' && atEnd)) {
    e.preventDefault()
    editor.commands.focus('start')
  }
})

editor.view.dom.addEventListener('keydown', (e) => {
  if (e.key === 'ArrowUp' && editor.state.selection.from <= 1) {
    e.preventDefault()
    titleEl.focus()
    titleEl.setSelectionRange(titleEl.value.length, titleEl.value.length)
  }
})

// --- Persistence -------------------------------------------------------------

function scheduleSave() {
  dirty = true
  clearTimeout(saveTimer)
  saveTimer = window.setTimeout(flush, SAVE_DELAY_MS)
}

function flush() {
  clearTimeout(saveTimer)
  if (!dirty || !currentId) return
  dirty = false
  post({
    type: 'change',
    id: currentId,
    title: titleEl.value,
    doc: JSON.stringify(editor.getJSON()),
    text: editor.getText({ blockSeparator: '\n' }),
  })
}

function load(note: NoteDoc) {
  // Reloading the open note means native changed it (the local API), and that
  // version wins over unsaved keystrokes.
  if (note.id === currentId) clearTimeout(saveTimer)
  else flush()
  currentId = note.id
  titleEl.value = note.title
  autosizeTitle()

  let json: JSONContent | null = null
  try {
    json = note.doc ? JSON.parse(note.doc) : null
  } catch {
    json = null
  }
  // Pending markdown (seeded, or written through the local API) replaces an
  // empty doc, or is appended to an existing one.
  const fromMarkdown = !!note.markdown && !!editor.markdown
  if (fromMarkdown) {
    const parsed = editor.markdown!.parse(note.markdown!)
    json = json ? { ...json, content: [...trimEmptyTail(json.content ?? []), ...(parsed.content ?? [])] } : parsed
  }

  // Fresh EditorState so undo history doesn't leak between notes.
  const doc = json ? editor.schema.nodeFromJSON(json) : editor.schema.topNodeType.createAndFill()!
  editor.view.updateState(EditorState.create({ doc, plugins: editor.state.plugins }))
  // Markdown-sourced notes get converted and persisted as JSON straight away.
  dirty = fromMarkdown
  if (fromMarkdown) flush()
  window.scrollTo(0, 0)

  if (note.focus === 'title') titleEl.focus()
  else if (note.focus === 'body') editor.commands.focus('end')
}

function trimEmptyTail(content: JSONContent[]) {
  const out = [...content]
  while (out.length && out[out.length - 1].type === 'paragraph' && !out[out.length - 1].content?.length) out.pop()
  return out
}

// Flush when the app is backgrounded / window closed so nothing is lost.
document.addEventListener('visibilitychange', () => document.hidden && flush())
window.addEventListener('pagehide', flush)

// --- Native API --------------------------------------------------------------

const api = {
  load,
  flush,
  resolveUpload,
  focus: () => editor.commands.focus(),
  focusTitle: () => titleEl.focus(),
  pickImage: () => fileInput.click(),
  getMarkdown: () => `# ${titleEl.value}\n\n${editor.getMarkdown()}`,
}

declare global {
  interface Window {
    notez: typeof api
  }
}

window.notez = api
post({ type: 'ready' })

if (import.meta.env.DEV) Object.assign(window, { editor })
