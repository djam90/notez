import { describe, expect, test } from 'vitest'
import type { JSONContent } from '@tiptap/core'
import { doc, findAll, fromMarkdown, normalise, para, text, toMarkdown } from './helpers'

// Markdown is only an import (pending markdown, paste) and export (Copy as
// Markdown) format. These pin what survives the trip so a TipTap upgrade that
// changes it is noticed.

/** md -> JSON -> md -> JSON must give the same document both times. */
function expectRoundTrip(md: string) {
  const json = fromMarkdown(md)
  const out = toMarkdown(json)
  expect(normalise(fromMarkdown(out))).toEqual(normalise(json))
  return { json, out }
}

const ASSET = 'notez://asset/123e4567-e89b-12d3-a456-426614174000'

describe('markdown round trips', () => {
  test('headings 1-3', () => {
    const { json, out } = expectRoundTrip('# One\n\n## Two\n\n### Three\n')
    expect(json.content!.map((n) => [n.type, n.attrs?.level])).toEqual([
      ['heading', 1],
      ['heading', 2],
      ['heading', 3],
    ])
    expect(out.trim()).toBe('# One\n\n## Two\n\n### Three')
  })

  test('bullet, ordered and nested lists', () => {
    const { json, out } = expectRoundTrip('- one\n- two\n  - nested\n\n1. first\n2. second\n')
    expect(json.content!.map((n) => n.type)).toEqual(['bulletList', 'orderedList'])
    expect(findAll(json, 'bulletList')).toHaveLength(2)
    expect(out).toContain('- two\n  - nested')
    expect(out).toContain('1. first\n2. second')
  })

  test('task lists keep checked state, including nested items', () => {
    const { json, out } = expectRoundTrip('- [ ] todo\n- [x] done\n  - [x] nested done\n')
    expect(findAll(json, 'taskItem').map((n) => n.attrs?.checked)).toEqual([false, true, true])
    expect(out).toContain('- [ ] todo\n- [x] done\n  - [x] nested done')
  })

  test('table with a header row', () => {
    const { json, out } = expectRoundTrip('| A | B |\n| --- | --- |\n| 1 | 2 |\n')
    const rows = findAll(json, 'tableRow')
    expect(rows).toHaveLength(2)
    expect(rows[0].content!.map((c) => c.type)).toEqual(['tableHeader', 'tableHeader'])
    expect(rows[1].content!.map((c) => c.type)).toEqual(['tableCell', 'tableCell'])
    expect(out).toContain('| A   | B   |\n| --- | --- |\n| 1   | 2   |')
  })

  test('code block keeps its language', () => {
    const { json, out } = expectRoundTrip('```swift\nlet x = 1\n```\n')
    expect(json.content![0]).toMatchObject({ type: 'codeBlock', attrs: { language: 'swift' } })
    expect(out.trim()).toBe('```swift\nlet x = 1\n```')
  })

  test('blockquote and divider', () => {
    const { json, out } = expectRoundTrip('> quoted\n\n---\n\nafter\n')
    expect(json.content!.map((n) => n.type)).toEqual(['blockquote', 'horizontalRule', 'paragraph'])
    expect(out).toContain('> quoted')
    expect(out).toContain('---')
  })

  test('inline marks: bold, italic, strike, code, highlight, link', () => {
    const md = 'a **b** *i* ~~s~~ `c` ==h== [l](https://example.com)\n'
    const { json, out } = expectRoundTrip(md)
    const marks = findAll(json, 'text').flatMap((t) => t.marks?.map((m) => m.type) ?? [])
    expect(marks).toEqual(['bold', 'italic', 'strike', 'code', 'highlight', 'link'])
    expect(out.trim()).toBe(md.trim())
  })

  test('notez:// page links survive', () => {
    const { json } = expectRoundTrip('[page](notez://note/123)\n')
    expect(findAll(json, 'text')[0].marks![0]).toMatchObject({ type: 'link', attrs: { href: 'notez://note/123' } })
  })

  test('images keep notez://asset URLs and alt text', () => {
    const { json, out } = expectRoundTrip(`![diagram](${ASSET})\n`)
    expect(json.content![0]).toMatchObject({ type: 'image', attrs: { src: ASSET, alt: 'diagram' } })
    expect(out.trim()).toBe(`![diagram](${ASSET})`)
  })

  test('hard breaks', () => {
    const { json } = expectRoundTrip('a  \nb\n')
    expect(json.content![0].content!.map((n) => n.type)).toEqual(['text', 'hardBreak', 'text'])
  })

  test('a mixed page is stable after the first export', () => {
    const md = [
      '# Title',
      'Some **bold** and ==marked== text.',
      '- [ ] task',
      '| H |\n| --- |\n| v |',
      '```ts\nconst a = 1\n```',
      '> quote',
      `![x](${ASSET})`,
    ].join('\n\n')
    const first = toMarkdown(fromMarkdown(md))
    expect(toMarkdown(fromMarkdown(first))).toBe(first)
  })
})

describe('documented lossy or surprising conversions', () => {
  const cell = (t: string, type = 'tableCell', attrs: JSONContent['attrs'] = {}): JSONContent => ({
    type,
    attrs,
    content: [para(text(t))],
  })

  test('underline exports as ++text++ and parses back', () => {
    const json = doc(para(text('u', [{ type: 'underline' }])))
    expect(toMarkdown(json).trim()).toBe('++u++')
    expect(normalise(fromMarkdown('++u++'))).toEqual(normalise(json))
  })

  test('image size is dropped', () => {
    const json = doc({ type: 'image', attrs: { src: ASSET, alt: 'a', width: 200, height: 100 } })
    expect(normalise(json).content![0].attrs).toMatchObject({ width: 200, height: 100 })
    const out = toMarkdown(json)
    expect(out.trim()).toBe(`![a](${ASSET})`)
    expect(fromMarkdown(out).content![0].attrs?.width).toBeUndefined()
  })

  test('merged cells are split, with an empty filler cell', () => {
    const json = doc({
      type: 'table',
      content: [
        { type: 'tableRow', content: [cell('A', 'tableHeader'), cell('B', 'tableHeader')] },
        { type: 'tableRow', content: [cell('wide', 'tableCell', { colspan: 2 })] },
      ],
    })
    const back = fromMarkdown(toMarkdown(json))
    const cells = findAll(back, 'tableRow')[1].content!
    expect(cells).toHaveLength(2)
    expect(cells.map((c) => c.attrs?.colspan ?? 1)).toEqual([1, 1])
  })

  test('a table without a header row gains an empty one', () => {
    const json = doc({
      type: 'table',
      content: [
        { type: 'tableRow', content: [cell('A'), cell('B')] },
        { type: 'tableRow', content: [cell('1'), cell('2')] },
      ],
    })
    const rows = findAll(fromMarkdown(toMarkdown(json)), 'tableRow')
    expect(rows).toHaveLength(3)
    expect(rows[0].content!.every((c) => c.type === 'tableHeader' && !c.content![0].content?.length)).toBe(true)
  })

  test('<, > and & export as HTML entities but parse back as plain text', () => {
    const json = doc(para(text('a < b & c -> d')))
    const out = toMarkdown(json)
    expect(out.trim()).toBe('a &lt; b &amp; c -&gt; d')
    expect(normalise(fromMarkdown(out))).toEqual(normalise(json))
  })
})
