import { Extension, type Editor, type Range } from '@tiptap/core'
import Suggestion, { type SuggestionProps } from '@tiptap/suggestion'
import { PluginKey } from '@tiptap/pm/state'

// Notion-style "/" command menu.

export type SlashItem = {
  title: string
  hint: string
  keywords: string
  run: (editor: Editor, range: Range) => void
}

export function slashItems(pickImage: () => void): SlashItem[] {
  const chain = (e: Editor, r: Range) => e.chain().focus().deleteRange(r)
  return [
    { title: 'Text', hint: 'Plain paragraph', keywords: 'p paragraph', run: (e, r) => chain(e, r).setParagraph().run() },
    { title: 'Heading 1', hint: '#', keywords: 'h1 title', run: (e, r) => chain(e, r).setHeading({ level: 1 }).run() },
    { title: 'Heading 2', hint: '##', keywords: 'h2 subtitle', run: (e, r) => chain(e, r).setHeading({ level: 2 }).run() },
    { title: 'Heading 3', hint: '###', keywords: 'h3', run: (e, r) => chain(e, r).setHeading({ level: 3 }).run() },
    { title: 'Bullet list', hint: '-', keywords: 'ul unordered', run: (e, r) => chain(e, r).toggleBulletList().run() },
    { title: 'Numbered list', hint: '1.', keywords: 'ol ordered', run: (e, r) => chain(e, r).toggleOrderedList().run() },
    { title: 'To-do list', hint: '[]', keywords: 'task todo check', run: (e, r) => chain(e, r).toggleTaskList().run() },
    {
      title: 'Table',
      hint: '3×3',
      keywords: 'grid',
      run: (e, r) => chain(e, r).insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run(),
    },
    { title: 'Image', hint: 'Upload', keywords: 'picture photo', run: (e, r) => (chain(e, r).run(), pickImage()) },
    { title: 'Quote', hint: '>', keywords: 'blockquote', run: (e, r) => chain(e, r).toggleBlockquote().run() },
    { title: 'Code block', hint: '```', keywords: 'pre snippet', run: (e, r) => chain(e, r).toggleCodeBlock().run() },
    { title: 'Divider', hint: '---', keywords: 'hr rule separator', run: (e, r) => chain(e, r).setHorizontalRule().run() },
  ]
}

/** Case-insensitive substring match on title and keywords (not the hint). */
export function filterSlashItems(items: SlashItem[], query: string) {
  const q = query.toLowerCase()
  return items.filter((i) => `${i.title} ${i.keywords}`.toLowerCase().includes(q))
}

export function SlashCommand(items: SlashItem[]) {
  return Extension.create({
    name: 'slashCommand',
    addProseMirrorPlugins() {
      return [
        Suggestion<SlashItem, SlashItem>({
          editor: this.editor,
          pluginKey: new PluginKey('slashCommand'),
          char: '/',
          command: ({ editor, range, props }) => props.run(editor, range),
          items: ({ query }) => filterSlashItems(items, query),
          render: renderMenu,
        }),
      ]
    },
  })
}

function renderMenu() {
  let el: HTMLDivElement | null = null
  let props: SuggestionProps<SlashItem, SlashItem> | null = null
  let active = 0

  const draw = () => {
    if (!el || !props) return
    if (props.items.length === 0) {
      el.hidden = true
      return
    }
    el.hidden = false
    el.replaceChildren(
      ...props.items.map((item, i) => {
        const row = document.createElement('button')
        row.className = 'slash-item' + (i === active ? ' active' : '')
        row.innerHTML = `<span>${item.title}</span><kbd>${item.hint}</kbd>`
        row.onmousedown = (e) => {
          e.preventDefault()
          props?.command(item)
        }
        return row
      }),
    )
    el.querySelector('.active')?.scrollIntoView({ block: 'nearest' })
    const rect = props.clientRect?.()
    if (rect) {
      const below = rect.bottom + 6
      const fitsBelow = below + el.offsetHeight < window.innerHeight
      el.style.left = `${Math.min(rect.left, window.innerWidth - el.offsetWidth - 8)}px`
      el.style.top = `${fitsBelow ? below : rect.top - el.offsetHeight - 6}px`
    }
  }

  return {
    onStart(p: SuggestionProps<SlashItem, SlashItem>) {
      props = p
      active = 0
      el = document.createElement('div')
      el.className = 'slash-menu'
      document.body.appendChild(el)
      draw()
    },
    onUpdate(p: SuggestionProps<SlashItem, SlashItem>) {
      props = p
      active = Math.min(active, Math.max(0, p.items.length - 1))
      draw()
    },
    onKeyDown({ event }: { event: KeyboardEvent }) {
      if (!props || props.items.length === 0) return false
      const n = props.items.length
      if (event.key === 'ArrowDown') {
        active = (active + 1) % n
      } else if (event.key === 'ArrowUp') {
        active = (active - 1 + n) % n
      } else if (event.key === 'Enter' || event.key === 'Tab') {
        props.command(props.items[active])
        return true
      } else if (event.key === 'Escape') {
        el?.remove()
        el = null
        return true
      } else {
        return false
      }
      draw()
      return true
    },
    onExit() {
      el?.remove()
      el = null
      props = null
    },
  }
}
