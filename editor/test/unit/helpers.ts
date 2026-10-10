import { Editor, type JSONContent } from '@tiptap/core'
import { contentExtensions } from '../../src/extensions'

// Same schema and markdown config as the app, without the page UI.
export function makeEditor(content?: JSONContent | string) {
  return new Editor({ extensions: contentExtensions(), content })
}

const shared = makeEditor()

export function fromMarkdown(md: string): JSONContent {
  return shared.markdown!.parse(md)
}

export function toMarkdown(json: JSONContent): string {
  shared.commands.setContent(json)
  return shared.getMarkdown()
}

/** What the editor stores after loading `json` (schema defaults filled in). */
export function normalise(json: JSONContent): JSONContent {
  shared.commands.setContent(json)
  return shared.getJSON()
}

export const text = (t: string, marks?: JSONContent['marks']): JSONContent =>
  marks ? { type: 'text', text: t, marks } : { type: 'text', text: t }
export const para = (...content: JSONContent[]): JSONContent => ({ type: 'paragraph', content })
export const doc = (...content: JSONContent[]): JSONContent => ({ type: 'doc', content })

/** All nodes of a type, depth first. */
export function findAll(json: JSONContent, type: string): JSONContent[] {
  const out: JSONContent[] = []
  const walk = (n: JSONContent) => {
    if (n.type === type) out.push(n)
    n.content?.forEach(walk)
  }
  walk(json)
  return out
}
