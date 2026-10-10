import type { JSONContent } from '@tiptap/core'

// Pure document helpers used by load() and paste, kept DOM-free for tests.

export function looksLikeMarkdown(text: string) {
  return /^(#{1,6} |\s*[-*+] |\s*\d+\. |> |```|\|.+\|)|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)/m.test(text)
}

/** Stored doc JSON, or null when missing or corrupt (the note then opens empty). */
export function parseDoc(doc: string | null | undefined): JSONContent | null {
  try {
    return doc ? JSON.parse(doc) : null
  } catch {
    return null
  }
}

/** Pending markdown replaces an empty doc, or is appended to an existing one. */
export function appendParsed(json: JSONContent | null, parsed: JSONContent): JSONContent {
  return json ? { ...json, content: [...trimEmptyTail(json.content ?? []), ...(parsed.content ?? [])] } : parsed
}

export function trimEmptyTail(content: JSONContent[]) {
  const out = [...content]
  while (out.length && out[out.length - 1].type === 'paragraph' && !out[out.length - 1].content?.length) out.pop()
  return out
}
