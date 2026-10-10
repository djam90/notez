import type { Extensions } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import { TableKit } from '@tiptap/extension-table'
import { TaskList, TaskItem } from '@tiptap/extension-list'
import Image from '@tiptap/extension-image'
import Highlight from '@tiptap/extension-highlight'
import Typography from '@tiptap/extension-typography'
import { Markdown } from '@tiptap/markdown'

// Everything that defines the document schema and markdown support. Kept apart
// from the UI-only extensions in main.ts so tests can build an identical
// schema without booting the whole page.
export function contentExtensions(): Extensions {
  return [
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
  ]
}
