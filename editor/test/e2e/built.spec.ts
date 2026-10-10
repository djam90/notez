import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { expect, test } from './fixtures'

// Smoke test of the committed bundle the app ships (not the dev server), so a
// broken build is caught. It can't tell whether the bundle is stale: rebuild
// with `npm run build` after editing src/ (CLAUDE.md, hard rule 1).
test.use({ editorURL: pathToFileURL(resolve(import.meta.dirname, '../../../Notez/Resources/editor.html')).href })

test('built editor.html boots, renders markdown and saves edits', async ({ notez, page }) => {
  await notez.load({ id: 'built', title: 'Built', markdown: '# Hello\n\n- [ ] task\n\n| A |\n| --- |\n| 1 |' })
  await expect(notez.body.locator('h1')).toHaveText('Hello')
  await expect(notez.body.locator('table')).toHaveCount(1)
  await notez.nextChange('built')
  const before = await notez.count()
  await page.keyboard.type('more')
  const saved = await notez.nextChange('built', before)
  expect(saved.text).toContain('more')
})
