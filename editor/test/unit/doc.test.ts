import { describe, expect, test } from 'vitest'
import type { JSONContent } from '@tiptap/core'
import { appendParsed, looksLikeMarkdown, parseDoc, trimEmptyTail } from '../../src/doc'
import { doc, fromMarkdown, makeEditor, normalise, para, text } from './helpers'

describe('looksLikeMarkdown (paste detection)', () => {
  test.each([
    '# Heading',
    '###### Six',
    '- item',
    '  * indented item',
    '+ plus item',
    '1. numbered',
    '> quote',
    '```js',
    '| a | b |',
    'some **bold** text',
    'see [docs](https://example.com)',
    'intro line\n- list on line two',
  ])('treats %j as markdown', (s) => expect(looksLikeMarkdown(s)).toBe(true))

  test.each([
    'just a sentence',
    '#hashtag',
    'price is 5 * 3',
    'a single *emphasis*',
    'https://example.com',
    '',
  ])('leaves %j as plain text', (s) => expect(looksLikeMarkdown(s)).toBe(false))
})

describe('parseDoc', () => {
  test('null, empty and corrupt docs open as empty', () => {
    expect(parseDoc(null)).toBeNull()
    expect(parseDoc('')).toBeNull()
    expect(parseDoc('{not json')).toBeNull()
  })

  test('parses stored JSON', () => {
    expect(parseDoc(JSON.stringify(doc(para(text('x')))))).toEqual(doc(para(text('x'))))
  })
})

describe('pending markdown merge', () => {
  const parsed = fromMarkdown('## Added\n\nmore')

  test('replaces a missing doc', () => {
    expect(appendParsed(null, parsed)).toBe(parsed)
  })

  test('appends after existing content, dropping trailing empty paragraphs', () => {
    const existing = doc(para(text('kept')), para(), { type: 'paragraph' })
    const merged = appendParsed(existing, parsed)
    expect(merged.content!.map((n) => n.type)).toEqual(['paragraph', 'heading', 'paragraph'])
    expect(merged.content![0]).toEqual(para(text('kept')))
    expect(existing.content).toHaveLength(3)
  })

  test('trimEmptyTail keeps non-paragraph and non-empty tails', () => {
    const hr = { type: 'horizontalRule' }
    expect(trimEmptyTail([para(text('a')), hr, para()])).toEqual([para(text('a')), hr])
    expect(trimEmptyTail([para(), para()])).toEqual([])
  })
})

describe('JSON is the source of truth: load -> getJSON is lossless', () => {
  // Attributes markdown can't carry, which is why JSON is what gets stored.
  const rich: JSONContent = doc(
    { type: 'heading', attrs: { level: 2 }, content: [text('Title')] },
    para(
      text('u', [{ type: 'underline' }]),
      text(' h', [{ type: 'highlight' }]),
      text(' l', [{ type: 'link', attrs: { href: 'notez://note/abc' } }]),
    ),
    { type: 'image', attrs: { src: 'notez://asset/1', alt: 'a', width: 320, height: 200 } },
    {
      type: 'table',
      content: [
        {
          type: 'tableRow',
          content: [
            { type: 'tableHeader', attrs: { colwidth: [150] }, content: [para(text('H'))] },
            { type: 'tableHeader', content: [para(text('I'))] },
          ],
        },
        { type: 'tableRow', content: [{ type: 'tableCell', attrs: { colspan: 2 }, content: [para(text('wide'))] }] },
      ],
    },
    {
      type: 'taskList',
      content: [
        { type: 'taskItem', attrs: { checked: true }, content: [para(text('done'))] },
        { type: 'taskItem', attrs: { checked: false }, content: [para(text('todo'))] },
      ],
    },
    { type: 'codeBlock', attrs: { language: 'ts' }, content: [text('let a = 1')] },
    para(),
  )

  test('normalised doc survives a save/load cycle unchanged', () => {
    const stored = JSON.stringify(normalise(rich))
    const editor = makeEditor(JSON.parse(stored))
    expect(JSON.stringify(editor.getJSON())).toBe(stored)
    editor.destroy()
  })

  test('nodeFromJSON (the load() path) round trips too', () => {
    const json = normalise(rich)
    const editor = makeEditor()
    expect(editor.schema.nodeFromJSON(json).toJSON()).toEqual(json)
    editor.destroy()
  })

  test('attributes markdown would drop are kept', () => {
    const json = normalise(rich)
    const find = (type: string) => JSON.stringify(json).includes(type)
    expect(find('"width":320')).toBe(true)
    expect(find('"colspan":2')).toBe(true)
    expect(find('"colwidth":[150]')).toBe(true)
    expect(find('"underline"')).toBe(true)
  })
})
