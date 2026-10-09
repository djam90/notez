# Features

Each feature below covers what it does for the user and how it's built. File references point at symbols rather than line numbers. See [ARCHITECTURE.md](ARCHITECTURE.md) for the overall design.

Status key: ✅ verified working · 🟡 built and compiles, not yet exercised end-to-end (see [Verification status](#verification-status))

---

## Pages and hierarchy

### Nested pages ✅
Any page can contain sub-pages, to any depth, like Notion. The sidebar shows a collapsible tree under **Pages**.

- **Model:** `Note.parent` / `Note.children` (cascade delete) in `Models/Note.swift`.
- **UI:** `SidebarView` filters `@Query(sort: \Note.sortIndex)` to roots, and `NoteTree` renders each node recursively. Leaf pages render as plain `NoteRow`s. Pages with children render as `DisclosureGroup(isExpanded: store.isExpanded(id))`.
- **Children order:** `Note.sortedChildren`, by `sortIndex`.

### Projects ✅ (sidebar rendering) / 🟡 (flows)
Group top-level pages into named projects. Each project is a collapsible sidebar section between **Pinned** and **Pages**. **Pages** holds unfiled pages.

- **Create:** **File > New Project…** (⌘⌥N) or the sidebar folder+ button. Opens a name alert (`NotesStore.projectPrompt`).
- **Header context menu:** New Page, Rename…, Icon, Color, Move Up/Down, Delete Project. Deleting keeps the pages, they move to **Pages**.
- **Icon and colour:** the header shows `Project.icon` (SF Symbol) tinted with `Project.color`. Choices live in `ProjectStyle` (`Views/ProjectMenus.swift`). Unknown values fall back to the defaults.
- **Reorder:** drag a project header onto another to place it above, or onto **Pages** to move it last. Project drags carry a `project:` prefix so page drop targets ignore them. Also Move Up/Down in the context menu (`NotesStore.moveProject`).
- **Filing pages:** drag a row onto a project header, or **Move to Project** in the row context menu or the page **⋯** menu (`MoveToProjectMenu`). Sub-pages follow their top-level page.
- **New pages** from ⌘N, the ✎ button and ⌘K go into the open page's project, like a new note in the current folder. An empty project shows a **New Page** row.
- The macOS subtitle and ⌘K results show the project at the start of the path (`Note.location`).
- Collapse state persists (`NotesStore.collapsedProjects`). Opening a page in a collapsed project expands it.
- New projects go to the bottom.

### Expansion state persists 🟡
Expanded or collapsed folders survive relaunch. `NotesStore.expanded` is a `Set<UUID>` written to `UserDefaults["sidebar.expanded"]` in `didSet`. Creating a sub-page or moving a page into a parent auto-expands the parent. Opening a page via ⌘K or a link calls `revealInSidebar`, which expands its ancestors.

### New page / new sub-page 🟡
- **⌘N** (menu **File > New Page**, sidebar ✎ button, empty-state button) creates a top-level page in the open page's project.
- **⌘⇧N** (**File > New Sub-page**, row context menu, detail **⋯** menu) creates a child of the selected page.
- New pages go to the **top** of their level (`sortIndex = min(siblings) - 1`) so quick dumps are easy to find. The title field is focused.
- Implementation: `NotesStore.newNote(parent:title:)`.

### Drag to re-nest 🟡
Drag a page row onto another row to make it a child. Drag it onto the **Pages** header to move it to the top level. Rows are `.draggable(note.id.uuidString)` and `.dropDestination(for: String.self)`, calling `NotesStore.move(id:into:)`. Moves that would create a cycle (onto itself or a descendant) are ignored. **Move to Top Level** is also in the row context menu.

There is no drag to reorder siblings yet, only re-parenting.

### Pinning 🟡
Pin from the row context menu, the detail toolbar pin button, or **Page > Pin** (⌘⇧D). Pinned pages appear in a **Pinned** section above **Pages**. This is a `Note.isPinned` flag, filtered in `SidebarView.pinned`.

### Delete 🟡
Row context menu, detail **⋯ > Delete Page**, or **Page > Delete Page** (⌘⇧⌫). This permanently deletes the page, all its descendants, their bodies and images (cascade). If the open page is deleted, or is inside the deleted subtree, selection moves to the deleted page's parent. There is no undo or trash yet.

### Page icons 🟡
`Note.icon` holds an optional emoji shown in the sidebar instead of the default `doc.text` symbol. The welcome page uses 👋. There is no UI to set icons yet.

### Reopen where you left off ✅
The last opened page id is saved to `UserDefaults["lastOpened"]` in `NotesStore.selectionChanged()` and restored in `NotesStore.init`.

### Welcome page ✅
On first launch with an empty store, `Seed.welcomeIfNeeded` creates **Welcome to Notez** (with a shortcuts table, a task list and a quote) plus a child page. The content is stored as markdown in `NoteBody.pendingMarkdown`. On first open the editor converts it to TipTap JSON and saves it back, which clears `pendingMarkdown`. A `UserDefaults` flag (`seed.welcome.v1`) stops it from re-seeding.

---

## Navigation

### ⌘K quick switcher (jump or create) 🟡
**Go > Quick Open…** (⌘K) or the sidebar 🔍 button opens a palette over the window (`Views/QuickSwitcher.swift`). It is an overlay, not a `.sheet`: sheets animate in and out, which made jumping to a page feel laggy. Now it opens and closes within a frame (checked on a frame-by-frame screen recording). Click outside to dismiss.

- With an empty query it lists the 20 most recently edited pages.
- Typing searches titles first, then full text (`NotesStore.search`), showing the breadcrumb path or a preview under each result.
- **↑/↓** move the highlight (`onKeyPress`), **Enter** opens it, **Esc** closes.
- If no result's title exactly matches the query, the last row is **Create "<query>"**. Choosing it makes a new top-level page with that title and puts the caret in the body, so you can type ⌘K, a title, Enter, and start writing.

### Breadcrumbs ✅ (iOS) / 🟡 (macOS)
The detail navigation title is the page title. On macOS, `navigationSubtitle` shows the ancestor path ("Projects / Notez").

### Keyboard-driven sidebar 🟡
Selecting with the arrow keys in the sidebar loads pages without stealing focus (`load(..., focus: .none)`), so you can arrow through notes quickly.

---

## Editor: writing

The editor is TipTap 3 (ProseMirror) configured in `editor/src/main.ts`.

### Title ✅
A large auto-growing `<textarea id="title">` above the body, in the same web view, so moving between title and body is seamless. **Enter** or **↓** at the end of the title moves to the start of the body. **↑** at the very start of the body moves back to the title. Title edits save with the body and update the sidebar live.

### Rich text and markdown shortcuts ✅
StarterKit gives you paragraphs, H1-H3 (`#`, `##`, `###`), bullet (`-`) and numbered (`1.`) lists, blockquote (`>`), code block (`` ``` ``), horizontal rule (`---`), bold/italic/strike/inline code (⌘B, ⌘I, `**`, `_`, `` ` ``), underline (⌘U), and undo/redo. `Typography` adds smart quotes, arrows and ellipses. `Highlight` adds marker highlights.

### "/" command menu ✅
Typing `/` opens a filterable block menu (`editor/src/slash.ts`): Text, Heading 1-3, Bullet list, Numbered list, To-do list, Table, Image, Quote, Code block, Divider. Typing filters by title and keywords (`/ta` → To-do list, Table). **↑/↓**, **Enter/Tab** to pick, **Esc** to dismiss. Built on `@tiptap/suggestion`, with a plain DOM menu positioned from `clientRect`. It flips above the caret near the bottom of the window.

### Task lists ✅
`TaskList` + `TaskItem` (nestable). Type `[] ` or use `/todo`. Checked items are struck through and muted.

### Paste markdown → rich text ✅
If the clipboard has `text/plain` but no `text/html` and it looks like markdown (`looksLikeMarkdown`: headings, lists, quotes, fences, pipe tables, `**bold**`, `[links](…)`), it is parsed with `@tiptap/markdown` and inserted as rich content. Tables, task lists and formatting all survive. Rich HTML pastes (from browsers, Docs, etc.) go through ProseMirror's normal HTML parsing.

### Formatting bubble (desktop) ✅
Selecting text shows a floating bar: **B I U S `</>` H Link** (`formatMenu` in `main.ts`, `@tiptap/extension-bubble-menu`). Active marks are highlighted. **Link** swaps the bar for an inline URL field: Enter applies, an empty value removes the link, Esc cancels. (`window.prompt` doesn't work in WKWebView, which is why the field is inline.) The bubble is hidden on touch devices (`pointer: coarse`) so it doesn't fight the iOS edit menu.

### Links 🟡
`autolink` turns typed or pasted URLs into links. Clicking a link while editing does nothing, so you can edit the link text. **⌘-click** (or tap on touch devices) posts `openURL`, and native opens it in the default browser. `notez://note/<uuid>` links open the page in-app.

### Autosave ✅
Every edit is debounced 300 ms, then posted as a `change` message and written to SwiftData. Saves are also flushed on note switch, `visibilitychange` and `pagehide`. There is no save button.

### Placeholder ✅
An empty body shows "Type '/' for commands, or just start dumping…". An empty title shows "Untitled".

---

## Editor: tables ✅

- Insert with `/table` (3×3 with header row) or by pasting a markdown or HTML table.
- **Tab / Shift-Tab** move between cells. Tab in the last cell adds a row.
- **Resizable columns:** drag a column border (`TableKit` with `resizable: true`).
- **Table bubble** appears above the table whenever the caret is inside one (`tableMenu`): **+ Row, + Col, − Row, − Col, Header** (toggle header row), **Merge** (merge selected cells or split a merged one), **Delete** table. It is anchored to the table element via `getReferencedVirtualElement` → `tableElementAtSelection()`.
- **Cell selection:** drag across cells to select a range (blue overlay), then merge.
- **Styling:** the header row is shaded, cells have borders that follow the light/dark theme, and wide tables scroll horizontally.

---

## Editor: images

### Insert ✅ (browser) / 🟡 (native)
- **Paste** an image (screenshot, copied image) or **drag-drop** image files. `handlePaste`/`handleDrop` handle them, and drops land where you release.
- **⌘⇧I**, the toolbar 🖼 button, or `/image` open a file picker. On macOS that's an `NSOpenPanel` limited to images. On iOS it's the system Photo Library / Camera / Files sheet.
- **Resize** by dragging the handles on a selected image (aspect ratio locked, min 48 px).

### Storage
The bytes are sent to native once (base64 over the bridge) and stored as an `Asset` with `@Attribute(.externalStorage)`. The document only holds `notez://asset/<uuid>`. `NotezSchemeHandler` serves them with an in-memory `NSCache`. The full flow is in [ARCHITECTURE.md › Images](ARCHITECTURE.md#images).

---

## Export

### Copy page as Markdown 🟡
**Edit > Copy Page as Markdown** (⌘⌥C) or detail **⋯ > Copy as Markdown**. `EditorController.markdown()` calls `window.notez.getMarkdown()` (title as H1 + TipTap's markdown serialiser) and puts the result on the system pasteboard. Image references come out as `notez://asset/…` URLs, which only resolve inside Notez.

---

## AI access (macOS)

### MCP server and REST API ✅
**Settings > AI Access** turns on a local server so AI tools can list, search, read, create, edit (replace or append), move, pin and delete pages while the app is running. Claude Code and Claude Desktop connect over MCP (`/mcp`); scripts can use REST (`/api/notes`, `/api/search`, `/api/assets`). Loopback only, bearer token, off by default. Bodies are markdown. Open pages reload when the API changes them. See [API.md](API.md).

- **Verified:** every REST route and MCP method with curl, auth/Origin rejection, LAN IP refused, cycle-move rejection leaves the page untouched, Welcome page JSON → markdown matches its source, Claude Code (`claude -p` with an HTTP MCP config) searching and reading a page, editor append/replace on load in the browser dev host, Settings pane (screenshot, toggle off/on including rapid toggling), an open page reloading live with an API title change + appended table, deleting the open page via the API (selection clears, no crash).
- **Not yet:** Claude Desktop via `mcp-remote`, changing the port from Settings.

## Platform behaviour

| | macOS | iPad | iPhone |
| --- | --- | --- | --- |
| Layout | Two-column `NavigationSplitView`, 1100×720 default | Two-column, sidebar can be hidden | Stack: sidebar → page |
| Menu commands / shortcuts | Menu bar | Hardware-keyboard menu (hold ⌘) | Hardware keyboard only |
| Formatting bubble | Yes | No (touch) | No (touch) |
| Image picker | NSOpenPanel | Photos / Camera / Files | Photos / Camera / Files |
| Appearance | Follows system light/dark (web view is transparent) | same | same |

## Versions and data safety ✅

- **Separate dev app:** Debug builds are "Notez Dev" with their own data. The everyday app is installed by `scripts/release-mac.sh <x.y.z>`, which bumps the version, backs up data to `~/Notez-backups/`, installs to `/Applications`, commits and tags.
- **Backup on upgrade:** the first launch of a new version copies the store to `Application Support/Backups/` (newest 5 kept) before opening it (`StoreBackup`).
- **Safe failure:** if migration fails, `StoreErrorView` explains it and shows the backups path. The app doesn't crash and doesn't modify the store.
- Verified on Mac with the dev store: adopting the versioned schema on an existing store, the backup, an automatic additive migration and reverting it, and the error screen for an incompatible change.

## Sync

### iCloud sync 🟡 (needs setup)
`ModelConfiguration(cloudKitDatabase: .automatic)` syncs the private CloudKit database once the target has an iCloud/CloudKit container entitlement (setup steps in the README). Without the entitlement, data is local only. The models already follow CloudKit's rules (defaults everywhere, optional relationships, no unique constraints).

---

## Verification status

What has been confirmed in practice so far:

- **iPad + iPhone simulators (screenshots):** project sections in the sidebar (temporary seed), welcome seed, markdown conversion, table/task/code/quote rendering, persistence across relaunch, reopen last page, light theme, layout.
- **Editor in a browser (`npm run dev`, scripted):** title → body navigation, slash menu filtering and insertion, table insert + Tab navigation, table bubble, formatting bubble position, markdown paste → table/tasks/bold, image paste, debounced save.
- **macOS:** builds and launches. The UI has not been visually reviewed yet. Local API and MCP server exercised with curl and Claude Code.

Not exercised end-to-end yet: project create/rename/delete/move flows, ⌘K switcher, drag-to-re-nest, pin/delete flows, native image upload round trip (`uploadImage` → `Asset` → `notez://asset`), the macOS open panel, Copy as Markdown, link opening, CloudKit sync.

## Known limitations / next ideas

- No trash or undo for page deletion.
- Images belong to the page they were first added to. Copying an image into another page and then deleting the original page breaks it. Images removed from a document are never garbage-collected.
- No sibling reordering by drag.
- No icon picker UI.
- Search is substring matching (`localizedStandardContains`) with no ranking or FTS index.
- iOS has no formatting toolbar or link editor, only markdown shortcuts, `/` commands and autolink.
- The local API can't upload images, and its markdown drops underline, image sizes and merged cells.
- Ideas: global quick-capture hotkey or menu bar extra on Mac, iOS Share Extension and widget, `[[` page links (the `notez://note/` route already works), markdown/folder export, app icon.
