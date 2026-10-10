import { ASSET_PREFIX, expect, test } from './fixtures'

const paraDoc = (t: string) =>
  JSON.stringify({ type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: t }] }] })

test.describe('load and save', () => {
  test('a stored doc renders and is not saved back untouched', async ({ notez }) => {
    await notez.load({ id: 'a', title: 'Alpha', doc: paraDoc('hello there') })
    await expect(notez.title).toHaveValue('Alpha')
    await expect(notez.body).toHaveText('hello there')
    await notez.page.evaluate(() => window.notez.flush())
    expect((await notez.sent()).filter((m) => m.type === 'change')).toEqual([])
  })

  test('pending markdown renders and is saved as JSON straight away', async ({ notez }) => {
    const md = '# Welcome\n\n| Key | Action |\n| --- | --- |\n| ⌘K | Open |\n\n- [x] done\n- [ ] todo\n\n> quote'
    await notez.load({ id: 'seed', title: 'Seed', markdown: md })
    await expect(notez.body.locator('h1')).toHaveText('Welcome')
    await expect(notez.body.locator('table th')).toHaveText(['Key', 'Action'])
    await expect(notez.body.locator('ul[data-type="taskList"] > li')).toHaveCount(2)
    await expect(notez.body.locator('blockquote')).toHaveText('quote')
    const saved = await notez.nextChange('seed')
    expect(saved.json.content.map((n: { type: string }) => n.type)).toEqual(['heading', 'table', 'taskList', 'blockquote', 'paragraph'])
  })

  test('Enter in the title moves to the body, and typing saves with plain text', async ({ notez, page }) => {
    await notez.load({ id: 'n', title: '', focus: 'title' })
    await expect(notez.title).toBeFocused()
    await page.keyboard.type('My page')
    await page.keyboard.press('Enter')
    await expect(notez.body).toBeFocused()
    await expect(notez.title).toHaveValue('My page')
    const before = await notez.count()
    await page.keyboard.type('first line')
    const saved = await notez.nextChange('n', before, (c) => c.text === 'first line')
    expect(saved).toMatchObject({ id: 'n', title: 'My page', text: 'first line' })
    expect(saved.json.content[0]).toMatchObject({ type: 'paragraph', content: [{ type: 'text', text: 'first line' }] })
  })

  // Regression: on iOS (and any Safari UA) TipTap's focus() focuses the DOM
  // synchronously, and the trailing-paragraph fix-up for a doc ending in a
  // block made the focus command throw.
  test('Enter in the title of a doc ending in a table moves to the body', async ({ notez, page }) => {
    const table = { type: 'table', content: [{ type: 'tableRow', content: [{ type: 'tableCell', content: [{ type: 'paragraph' }] }] }] }
    await notez.load({ id: 'tbl', title: 'Grid', doc: JSON.stringify({ type: 'doc', content: [table] }), focus: 'title' })
    await page.keyboard.press('Enter')
    await expect(notez.body).toBeFocused()
    await page.keyboard.type('cell')
    await expect(notez.body.locator('td')).toHaveText('cell')
  })

  test('ArrowUp at the start of the body returns to the end of the title', async ({ notez, page }) => {
    await notez.load({ id: 'n', title: 'Heading', doc: paraDoc('body'), focus: 'body' })
    await notez.body.locator('p').first().click({ position: { x: 1, y: 5 } })
    await expect.poll(() => notez.page.evaluate(() => getSelection()?.anchorOffset)).toBe(0)
    await page.keyboard.press('ArrowUp')
    await expect(notez.title).toBeFocused()
    expect(await notez.title.evaluate((el: HTMLTextAreaElement) => el.selectionStart)).toBe('Heading'.length)
  })

  test('typing in quick succession posts one debounced save', async ({ notez, page }) => {
    await notez.load({ id: 'd', title: 't' })
    const before = await notez.count()
    await page.keyboard.type('abc')
    const saved = await notez.nextChange('d', before, (c) => c.text === 'abc')
    expect(saved.text).toBe('abc')
    const changes = (await notez.sent()).slice(before).filter((m) => m.type === 'change')
    expect(changes).toHaveLength(1)
  })

  test('switching notes does not leak undo history', async ({ notez, page }) => {
    await notez.load({ id: 'a', title: 'A', doc: paraDoc('first'), focus: 'body' })
    await page.keyboard.type(' typed in A')
    await notez.load({ id: 'b', title: 'B', doc: paraDoc('second'), focus: 'body' })
    const flushed = await notez.nextChange('a')
    expect(flushed.text).toBe('first typed in A')

    await page.keyboard.press('ControlOrMeta+z')
    await page.keyboard.press('ControlOrMeta+z')
    await expect(notez.body).toHaveText('second')
    // Undo still works for edits made in the new note.
    await page.keyboard.type('!')
    await expect(notez.body).toHaveText('second!')
    await page.keyboard.press('ControlOrMeta+z')
    await expect(notez.body).toHaveText('second')
  })
})

test.describe('slash menu', () => {
  const menu = (p: import('@playwright/test').Page) => p.locator('.slash-menu')

  test('/tab then Enter inserts a 3x3 table with a header row', async ({ notez, page }) => {
    await notez.load({ id: 's', title: '' })
    await page.keyboard.type('/tab')
    await expect(menu(page).locator('.slash-item')).toHaveText([/Table/])
    const before = await notez.count()
    await page.keyboard.press('Enter')
    await expect(menu(page)).toHaveCount(0)
    await expect(notez.body.locator('table tr')).toHaveCount(3)
    await expect(notez.body.locator('table tr').first().locator('th')).toHaveCount(3)
    await expect(notez.body).not.toContainText('/tab')
    const saved = await notez.nextChange('s', before, (c) => c.json.content[0]?.type === 'table')
    expect(saved.json.content[0].type).toBe('table')
  })

  test('filters by keyword and navigates with the arrow keys', async ({ notez, page }) => {
    await notez.load({ id: 's', title: '' })
    await page.keyboard.type('/ta')
    const items = menu(page).locator('.slash-item')
    await expect(items).toHaveText([/To-do list/, /Table/])
    await expect(menu(page).locator('.active')).toHaveText(/To-do list/)
    await page.keyboard.press('ArrowDown')
    await expect(menu(page).locator('.active')).toHaveText(/Table/)
    await page.keyboard.press('ArrowDown')
    await expect(menu(page).locator('.active')).toHaveText(/To-do list/)
    await page.keyboard.press('ArrowUp')
    await expect(menu(page).locator('.active')).toHaveText(/Table/)
    await page.keyboard.press('ArrowUp')
    await page.keyboard.press('Enter')
    await expect(notez.body.locator('ul[data-type="taskList"]')).toHaveCount(1)
  })

  test('Escape closes the menu and keeps the typed text', async ({ notez, page }) => {
    await notez.load({ id: 's', title: '' })
    await page.keyboard.type('/quo')
    await expect(menu(page)).toBeVisible()
    await page.keyboard.press('Escape')
    await expect(menu(page)).toHaveCount(0)
    await expect(notez.body).toHaveText('/quo')
  })

  test('clicking an item runs it', async ({ notez, page }) => {
    await notez.load({ id: 's', title: '' })
    await page.keyboard.type('/')
    await menu(page).getByText('Heading 2').click()
    await page.keyboard.type('Sub')
    await expect(notez.body.locator('h2')).toHaveText('Sub')
  })
})

test.describe('paste', () => {
  test('markdown text becomes rich content', async ({ notez }) => {
    await notez.load({ id: 'p', title: '' })
    await notez.paste({ text: '## Pasted\n\nSome **bold** text\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n- [ ] task' })
    await expect(notez.body.locator('h2')).toHaveText('Pasted')
    await expect(notez.body.locator('strong')).toHaveText('bold')
    await expect(notez.body.locator('table td')).toHaveText(['1', '2'])
    await expect(notez.body.locator('ul[data-type="taskList"] > li > div')).toHaveText(['task'])
  })

  test('plain text stays plain', async ({ notez }) => {
    await notez.load({ id: 'p', title: '' })
    await notez.paste({ text: 'just some words' })
    await expect(notez.body).toHaveText('just some words')
    await expect(notez.body.locator('h1, h2, strong, table')).toHaveCount(0)
  })

  test('an image goes through uploadImage and only the asset URL is saved', async ({ notez }) => {
    await notez.load({ id: 'img', title: '' })
    await notez.paste({ png: true })
    await expect(notez.body.locator(`img[src^="${ASSET_PREFIX}"]`)).toHaveCount(1)
    const upload = (await notez.sent()).find((m) => m.type === 'uploadImage')
    expect(upload).toMatchObject({ mime: 'image/png', base64: expect.stringMatching(/^iVBOR/) })
    const saved = await notez.nextChange('img')
    expect(saved.doc).toContain(ASSET_PREFIX)
    expect(saved.doc).not.toContain('data:')
  })
})

test.describe('formatting bubble', () => {
  test('appears on selection and applies marks', async ({ notez, page }) => {
    await notez.load({ id: 'f', title: '', doc: paraDoc('make this bold') })
    const bold = page.locator('.bubble button[title^="Bold"]')
    await expect(bold).toBeHidden()
    await notez.body.getByText('make this bold').dblclick()
    await expect(bold).toBeVisible()
    await bold.click()
    await expect(notez.body.locator('strong')).toHaveCount(1)
    await expect(bold).toHaveClass(/on/)
    const saved = await notez.nextChange('f', 0, (c) => JSON.stringify(c.json).includes('"bold"'))
    expect(JSON.stringify(saved.json)).toContain('"bold"')
  })

  test('link button opens an inline input that applies and removes links', async ({ notez, page }) => {
    await notez.load({ id: 'l', title: '', doc: paraDoc('docs') })
    await notez.body.getByText('docs').dblclick()
    await page.locator('.bubble button[title="Link"]').click()
    const input = page.locator('.bubble .link-input')
    await expect(input).toBeFocused()
    await input.fill('https://example.com')
    await input.press('Enter')
    await expect(notez.body.locator('a')).toHaveAttribute('href', 'https://example.com')
    await expect(input).toHaveCount(0)

    // Reopening prefills the current URL; clearing it removes the link.
    await notez.body.getByText('docs').dblclick()
    await page.locator('.bubble button[title="Link"]').click()
    await expect(input).toHaveValue('https://example.com')
    await input.fill('')
    await input.press('Enter')
    await expect(notez.body.locator('a')).toHaveCount(0)
  })

  test('Escape in the link input cancels', async ({ notez, page }) => {
    await notez.load({ id: 'l', title: '', doc: paraDoc('docs') })
    await notez.body.getByText('docs').dblclick()
    await page.locator('.bubble button[title="Link"]').click()
    await page.locator('.bubble .link-input').fill('https://nope.example')
    await page.keyboard.press('Escape')
    await expect(page.locator('.bubble .link-input')).toHaveCount(0)
    await expect(notez.body.locator('a')).toHaveCount(0)
  })
})

test.describe('tables and tasks', () => {
  test('the table bubble adds a row', async ({ notez, page }) => {
    await notez.load({ id: 't', title: '', markdown: '| A | B |\n| --- | --- |\n| 1 | 2 |' })
    await notez.body.locator('td').first().click()
    await page.locator('.bubble button[title="Add row below"]').click()
    await expect(notez.body.locator('tr')).toHaveCount(3)
  })

  test('toggling a task checkbox persists in the saved JSON', async ({ notez }) => {
    await notez.load({ id: 'task', title: '', markdown: '- [ ] write tests\n- [x] read code' })
    await notez.nextChange('task')
    const before = await notez.count()
    const box = notez.body.getByRole('checkbox', { name: 'Task item checkbox for write tests' })
    await expect(box).not.toBeChecked()
    await box.click()
    await expect(box).toBeChecked()
    const saved = await notez.nextChange('task', before)
    const checked = saved.json.content[0].content.map((i: { attrs: { checked: boolean } }) => i.attrs.checked)
    expect(checked).toEqual([true, true])
  })
})

test.describe('browser dev host', () => {
  test('saves to localStorage and restores on reload', async ({ devHost, page }) => {
    await page.evaluate(() => localStorage.removeItem('notez-dev'))
    await page.reload()
    await page.waitForFunction(() => !!window.notez)
    await expect(devHost.body).toBeFocused()
    await page.keyboard.type('persisted')
    await page.waitForFunction(() => localStorage.getItem('notez-dev')?.includes('persisted'))
    await page.reload()
    await expect(devHost.body).toHaveText('persisted')
  })

  // The dev host has no Asset store, so uploads come back as data URLs by
  // design. The native contract (no data: in saved docs) is covered above.
  test('image paste round trips through the dev host as a data URL', async ({ devHost }) => {
    await devHost.paste({ png: true })
    await expect(devHost.body.locator('img[src^="data:image/png;base64,"]')).toHaveCount(1)
  })
})
