import { test as base, expect, type Page } from '@playwright/test'
import type { NoteDoc, OutgoingMessage } from '../../src/bridge'

declare global {
  interface Window {
    __sent: OutgoingMessage[]
  }
}

export const ASSET_PREFIX = 'notez://asset/'

type Change = Extract<OutgoingMessage, { type: 'change' }>
// Tests dig into the saved doc freely, as JSON.parse would let them.
export type SavedChange = Change & { json: any }

/**
 * Stands in for EditorController: a WKWebView-style message handler that
 * records every message and answers uploadImage with an asset URL, so tests
 * run the production bridge path instead of the browser dev host.
 */
function installFakeNative() {
  window.__sent = []
  let assets = 0
  ;(window as unknown as { webkit: unknown }).webkit = {
    messageHandlers: {
      notez: {
        postMessage(msg: OutgoingMessage) {
          window.__sent.push(JSON.parse(JSON.stringify(msg)))
          if (msg.type === 'uploadImage') {
            const id = String(++assets).padStart(12, '0')
            setTimeout(() => window.notez.resolveUpload(msg.requestId, `notez://asset/00000000-0000-0000-0000-${id}`))
          }
        },
      },
    },
  }
}

export class Notez {
  readonly title
  readonly body

  constructor(readonly page: Page) {
    this.title = page.locator('#title')
    this.body = page.locator('#editor .ProseMirror')
  }

  async load(note: Partial<NoteDoc> & { id: string }) {
    const full = { title: '', doc: null, focus: 'body', ...note } as NoteDoc
    await this.page.evaluate((n) => window.notez.load(n), full)
    // TipTap focuses in a requestAnimationFrame outside WebKit, so typing
    // straight away would race it.
    if (full.focus === 'body') await expect(this.body).toBeFocused()
    if (full.focus === 'title') await expect(this.title).toBeFocused()
  }

  sent() {
    return this.page.evaluate(() => window.__sent)
  }

  /**
   * Waits for a `change` for `id` posted after `since` messages that passes
   * `until`, and returns the latest one. Pass `until` whenever an earlier
   * debounced save (the title, a half-typed command) could land first: under
   * load it does.
   */
  async nextChange(id: string, since = 0, until: (change: SavedChange) => boolean = () => true) {
    let found: SavedChange | undefined
    await expect
      .poll(async () => {
        const changes = (await this.sent())
          .slice(since)
          .filter((m): m is Change => m.type === 'change' && m.id === id)
          .map((m) => ({ ...m, json: JSON.parse(m.doc) }))
        found = changes.filter(until).at(-1)
        return found !== undefined
      })
      .toBe(true)
    return found!
  }

  async count() {
    return this.page.evaluate(() => window.__sent.length)
  }

  json() {
    return this.page.evaluate(() => (window as unknown as { editor: { getJSON(): unknown } }).editor.getJSON())
  }

  /** Dispatches a paste the way WebKit delivers one: a ClipboardEvent on the editor. */
  async paste(data: { text?: string; html?: string; png?: boolean }) {
    await this.body.evaluate((el, data) => {
      const dt = new DataTransfer()
      if (data.text != null) dt.setData('text/plain', data.text)
      if (data.html != null) dt.setData('text/html', data.html)
      if (data.png) {
        // 1x1 transparent PNG.
        const b64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
        const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))
        dt.items.add(new File([bytes], 'shot.png', { type: 'image/png' }))
      }
      el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }))
    }, data)
  }
}

type Fixtures = { editorURL: string; notez: Notez; devHost: Notez }

export const test = base.extend<Fixtures>({
  editorURL: ['/editor.html', { option: true }],
  notez: async ({ page, editorURL }, use) => {
    const errors: string[] = []
    page.on('pageerror', (e) => errors.push(e.message))
    await page.addInitScript(installFakeNative)
    await page.goto(editorURL)
    await page.waitForFunction(() => window.__sent?.some((m) => m.type === 'ready'))
    await use(new Notez(page))
    // Uncaught errors are what native would see as `[editor]` log lines.
    const logs = (await page.evaluate(() => window.__sent)).filter((m) => m.type === 'log')
    expect([...errors, ...logs.map((m) => (m as { message: string }).message)]).toEqual([])
  },
  // The plain `npm run dev` experience: no native handler, saves go to localStorage.
  devHost: async ({ page }, use) => {
    await page.goto('/editor.html')
    await page.waitForFunction(() => !!window.notez)
    await use(new Notez(page))
  },
})

export { expect }
