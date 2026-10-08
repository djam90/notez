// Messaging between the editor and the native (Swift) host.
//
// JS -> native: window.webkit.messageHandlers.notez.postMessage(msg)
// native -> JS: window.notez.<method>(...) via evaluateJavaScript

export type NoteDoc = {
  id: string
  title: string
  /** TipTap JSON document, serialised. Null for a brand new note. */
  doc: string | null
  /** Used when `doc` is null, e.g. seeded or imported notes. */
  markdown?: string | null
  focus?: 'title' | 'body' | 'none'
}

export type OutgoingMessage =
  | { type: 'ready' }
  | { type: 'change'; id: string; title: string; doc: string; text: string }
  | { type: 'uploadImage'; requestId: string; mime: string; base64: string }
  | { type: 'openURL'; url: string }
  | { type: 'log'; message: string }

type WebkitWindow = Window & {
  webkit?: { messageHandlers?: { notez?: { postMessage: (msg: unknown) => void } } }
}

const handler = (window as WebkitWindow).webkit?.messageHandlers?.notez

/** True when running inside the app; false in `npm run dev` in a browser. */
export const isNative = !!handler

// Surface JS errors in the native console (Xcode / `log stream`).
window.addEventListener('error', (e) => post({ type: 'log', message: `${e.message} @ ${e.filename}:${e.lineno}` }))
window.addEventListener('unhandledrejection', (e) => post({ type: 'log', message: `Unhandled: ${e.reason}` }))

export function post(msg: OutgoingMessage) {
  if (handler) {
    handler.postMessage(msg)
  } else {
    devHost(msg)
  }
}

// --- Image upload round trip -------------------------------------------------

const pendingUploads = new Map<string, (url: string | null) => void>()

export function uploadImage(file: Blob): Promise<string | null> {
  return new Promise((resolve) => {
    const reader = new FileReader()
    reader.onload = () => {
      const dataURL = reader.result as string
      const base64 = dataURL.slice(dataURL.indexOf(',') + 1)
      const requestId = crypto.randomUUID()
      pendingUploads.set(requestId, resolve)
      post({ type: 'uploadImage', requestId, mime: file.type || 'image/png', base64 })
    }
    reader.onerror = () => resolve(null)
    reader.readAsDataURL(file)
  })
}

export function resolveUpload(requestId: string, url: string | null) {
  pendingUploads.get(requestId)?.(url)
  pendingUploads.delete(requestId)
}

// --- Browser dev host --------------------------------------------------------
// Lets you iterate on the editor with `npm run dev` without the app.

function devHost(msg: OutgoingMessage) {
  switch (msg.type) {
    case 'change':
      localStorage.setItem('notez-dev', JSON.stringify(msg))
      break
    case 'uploadImage':
      setTimeout(() => resolveUpload(msg.requestId, `data:${msg.mime};base64,${msg.base64}`))
      break
    case 'log':
      console.warn(msg.message)
      break
    case 'openURL':
      window.open(msg.url, '_blank')
      break
    case 'ready': {
      const saved = localStorage.getItem('notez-dev')
      const parsed = saved ? JSON.parse(saved) : null
      setTimeout(() =>
        window.notez.load({
          id: 'dev',
          title: parsed?.title ?? '',
          doc: parsed?.doc ?? null,
          focus: 'body',
        }),
      )
      break
    }
  }
}
