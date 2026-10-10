// jsdom gaps that ProseMirror and main.ts touch. Layout APIs only need to
// exist, not be accurate, for document-level tests.
window.matchMedia ??= ((query: string) => ({
  matches: false,
  media: query,
  onchange: null,
  addListener() {},
  removeListener() {},
  addEventListener() {},
  removeEventListener() {},
  dispatchEvent: () => false,
})) as typeof window.matchMedia
window.scrollTo = () => {}
Element.prototype.scrollIntoView = () => {}
const rect = () => new DOMRect(0, 0, 0, 0)
const rects = () => Object.assign([], { item: () => null }) as unknown as DOMRectList
Range.prototype.getBoundingClientRect = rect
Range.prototype.getClientRects = rects
document.elementFromPoint = () => null
