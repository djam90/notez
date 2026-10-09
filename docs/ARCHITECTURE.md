# Architecture

Notez is a native SwiftUI app (one multiplatform target for macOS, iPadOS and iOS) with a rich-text editor running inside one long-lived `WKWebView`. Everything you click is native, and everything you type goes into the editor.

```
┌──────────────────────────── SwiftUI window ─────────────────────────────┐
│ SidebarView (List + DisclosureGroup tree)  │  NoteDetailView             │
│   @Query all Note rows (metadata only)     │   ┌───────────────────────┐ │
│                                            │   │ EditorView            │ │
│ QuickSwitcher (overlay, ⌘K)                │   │  = the one WKWebView  │ │
│                                            │   │  TipTap editor.html   │ │
│        NotesStore (per window, @Observable)│   └──────────▲────────────┘ │
│          selection, tree ops, search       │              │ JS bridge    │
│          owns EditorController ────────────┼──────────────┘              │
└─────────────────────────────────┬──────────────────────────────────────┘
                                  │ ModelContext (main)
                     SwiftData store (SQLite + external blobs)
                                  │ optional
                               CloudKit (private DB)
```

## Why this stack

| Requirement | Decision |
| --- | --- |
| Mac + iPhone + iPad, "lightning fast to click around" | Native SwiftUI for the shell: sidebar, switcher, menus, keyboard shortcuts. No web navigation anywhere. |
| Tables and good formatting, on iOS too | Native text views can't do it. `NSTextTable` is macOS-only and TextKit 2 has no tables. TipTap (ProseMirror) has mature tables, so it runs in a web view. |
| Embedded images | Stored as SwiftData external-storage blobs and served to the editor over a custom URL scheme, so documents never contain base64. |
| Sync across devices | SwiftData + CloudKit (`cloudKitDatabase: .automatic`). The schema is CloudKit-compatible from day one. |
| Quick dumping | New pages go to the top, the title is focused, Enter jumps to the body, ⌘K can create a page from the search text. |

We rejected Next.js in a webview: SSR/routing gives nothing to an offline app and costs startup time. We rejected React Native: rich text still ends up in a webview, and its macOS support is weak. We rejected Tauri: iCloud sync on iOS would need custom native plugins.

## Repository layout

```
Notez.xcodeproj/                 Hand-written project, objectVersion 77
  project.pbxproj                Uses PBXFileSystemSynchronizedRootGroup: every file
                                 under Notez/ is in the target automatically
  xcshareddata/xcschemes/        Shared "Notez" scheme
Notez/
  NotezApp.swift                 @main, ModelContainer, menu Commands
  Models/Note.swift              Note, Project, NoteBody, Asset (@Model)
  Models/Schema.swift            VersionedSchema + migration plan
  Store/StoreBackup.swift        Backs up the store when a new version first launches
  Views/StoreErrorView.swift     Shown if the store can't be opened
  Store/NotesStore.swift         Per-window state + all mutations + search
  Store/Seed.swift               First-launch welcome page
  Views/ContentView.swift        Creates the store once, NavigationSplitView
  Views/SidebarView.swift        Pinned, project sections, page tree, drag/drop, context menus
  Views/NoteDetailView.swift     Editor host + empty state + toolbar
  Views/QuickSwitcher.swift      ⌘K jump/create
  Views/ProjectMenus.swift       Project icon/colour choices, style pickers, Move to Project menu
  Editor/EditorController.swift  Owns the WKWebView, JS bridge, delegates
  Editor/NotezSchemeHandler.swift notez:// scheme: editor HTML + image assets
  Editor/EditorView.swift        NS/UIViewRepresentable returning the shared web view
  API/                           Local REST + MCP server for AI tools (macOS), see API.md
  Views/APISettingsView.swift    Settings > AI Access (macOS)
  Resources/editor.html          BUILT ARTIFACT from editor/ (committed)
  Assets.xcassets                AppIcon (empty slots), AccentColor
editor/                          TipTap editor source (vanilla TypeScript, no framework)
  editor.html                    Vite entry
  src/main.ts                    Editor setup, bubble menus, load/save, native API
  src/bridge.ts                  Message types, post(), image upload round trip, dev host
  src/slash.ts                   "/" command menu
  src/style.css                  All editor styling (light + dark)
  vite.config.ts                 Single-file build into ../Notez/Resources
scripts/                         setup / build / run helpers
docs/                            This file, FEATURES.md, API.md
```

## Data model (`Notez/Models/Note.swift`)

```
Note ──parent──▶ Note            (tree; children inverse, cascade delete)
Note ──project─▶ Project         (top-level pages only; notes inverse, nullify)
Note ──body───▶ NoteBody         (1:1, cascade)
Note ──assets─▶ [Asset]          (1:n, cascade)
```

| Model | Fields | Notes |
| --- | --- | --- |
| `Note` | `id: UUID`, `title`, `icon` (emoji or empty), `preview` (first 160 chars, single line), `isPinned`, `sortIndex: Double`, `createdAt`, `updatedAt`, `parent`, `project`, `children`, `body`, `assets` | Kept small on purpose. The sidebar `@Query` loads every `Note`. |
| `Project` | `id: UUID`, `name`, `icon` (SF Symbol), `color` (`ProjectStyle` key), `sortIndex`, `createdAt`, `notes` | A sidebar section. Only top-level pages set `Note.project`; sub-pages follow their root (`Note.rootProject`). Deleting a project nullifies, so its pages become unfiled. |
| `NoteBody` | `doc` (TipTap JSON string), `plainText` (for search), `pendingMarkdown`, `note` | Only faulted in when a note is opened or searched. `pendingMarkdown` is markdown awaiting conversion by the editor (seed, local API writes): it replaces an empty `doc` or is appended to an existing one, then cleared on the next save. |
| `Asset` | `id: UUID`, `data` (`@Attribute(.externalStorage)`), `mimeType`, `createdAt`, `note` | Image bytes live outside SQLite. |

**Versioning and migration.** `Models/Schema.swift` declares `NotezSchemaV1` (all four models) and `NotezMigrationPlan`. `NotezApp` opens the store with `Schema(versionedSchema: NotezSchema.self)` and the plan. Verified on a real store:

- Adding a property with a default, or removing one, migrates automatically even without a new version.
- An incompatible change (for example String → Date) fails to open the store. `NotezApp` then shows `StoreErrorView` instead of crashing, and the store is left untouched.
- Such changes need a frozen copy of the old models plus a `.custom` stage. The steps are in the comment in `Schema.swift`.

**Backups.** `StoreBackup.backUpIfVersionChanged` runs in `NotezApp.init` before the container opens. When `"<CFBundleShortVersionString> (<CFBundleVersion>)"` differs from `UserDefaults["store.lastLaunchedVersion"]`, it copies `default.store`, `-wal`, `-shm` and `.default_SUPPORT/` into `Application Support/Backups/<timestamp> from <old> to <new>/`, then prunes to the newest 5. The version is recorded before opening, so a build that fails to open the store doesn't take repeated backups and rotate the good ones out.

**Dev and release data.** Debug builds use bundle ID `io.github.djam90.notez.dev` ("Notez Dev"), so they have their own container, store and UserDefaults. Release (`scripts/release-mac.sh`) is `io.github.djam90.notez`.

CloudKit compatibility rules, which must hold for any new field:

- Every stored property has a default value.
- Every relationship is optional and has an inverse.
- No `@Attribute(.unique)`. Uniqueness of `id` is by convention (`UUID()`).

**Ordering.** `sortIndex` is a `Double`. New pages get `min(siblings) - 1`, so they land at the top. Re-parented pages get `max(siblings) + 1`, so they land at the bottom. Doubles leave room for future fractional reordering without renumbering.

**Document format.** TipTap/ProseMirror JSON is the source of truth because it is lossless for tables, merged cells, image sizes and task state. Markdown is only an import/export format.

## The editor web view

### Lifecycle

- `EditorController` is created by `NotesStore.init`, which `ContentView` creates once per window in `.onAppear`. Never create a store in a view `init` or `State(initialValue:)`: SwiftUI re-runs `init`, and each run would spin up another `WKWebView`. That bug showed up as a blank editor during development.
- The web view loads `notez://app/editor.html` once. `EditorView` (`NSViewRepresentable`/`UIViewRepresentable`) only returns `controller.webView`, so SwiftUI can rebuild the view tree (for example on iPhone push/pop) without reloading anything.
- `NoteDetailView` keeps the editor mounted even when no note is selected (`opacity(0)`), so it is warm before the first open.
- If the WebContent process crashes, `webViewWebContentProcessDidTerminate` reloads the page and reopens the current note.

### `notez://` scheme (`NotezSchemeHandler`)

| URL | Response |
| --- | --- |
| `notez://app/editor.html` | Bundled `editor.html` (read once, cached in memory) |
| `notez://asset/<uuid>` | `Asset.data` with its MIME type. Cached in an `NSCache` (200 MB cost limit). `Cache-Control: immutable` because assets never change. |
| `notez://note/<uuid>` | Never fetched. Clicking such a link routes to `EditorController.onOpenNote`, which opens that page (hook for future `[[page links]]`). |

All navigation away from `notez://` is cancelled. External links are handed to `NSWorkspace`/`UIApplication`.

### JS ⇄ native bridge

**Native → JS:** `webView.evaluateJavaScript("window.notez.<method>(<json args>)")` via `EditorController.call`. Calls made before the page reports `ready` are queued in a single slot (`pendingLoad`, last write wins), which is fine because only the latest `load` matters.

| `window.notez.*` | Purpose |
| --- | --- |
| `load({id, title, doc, markdown, focus})` | Flush the previous note, then swap in this one. `doc` is a TipTap JSON string or null. `markdown` (pending markdown) becomes the doc when `doc` is null and is appended to it otherwise, and the result is saved straight away. `focus` is `title`, `body` or `none`. Reloading the already-open id skips the flush: native changed the note (local API) and its version wins. |
| `flush()` | Send any pending change now |
| `resolveUpload(requestId, url)` | Finish an image upload |
| `focus()`, `focusTitle()`, `pickImage()` | UI helpers (`pickImage` clicks a hidden `<input type=file>`) |
| `getMarkdown()` | `# Title\n\n` plus the TipTap markdown serialisation (used by Copy as Markdown) |

**JS → native:** `window.webkit.messageHandlers.notez.postMessage(msg)`. The handler is registered through `WeakMessageHandler` to avoid the `WKUserContentController` retain cycle.

| `type` | Payload | Native handling |
| --- | --- | --- |
| `ready` | none | Mark ready, run the queued call |
| `change` | `id, title, doc, text` | Look up `Note` by id (fast path: `currentNote`), lazily create `NoteBody`, write `title/doc/plainText/preview/updatedAt`, clear `pendingMarkdown`. SwiftData autosave persists it. |
| `uploadImage` | `requestId, mime, base64` | Insert `Asset` attached to `currentNote`, save, reply `resolveUpload(requestId, "notez://asset/<id>")` |
| `openURL` | `url` | `notez://note/…` opens a page, anything else opens externally |
| `log` | `message` | `print("[editor] …")`. `window.onerror` and unhandled rejections are forwarded this way. |

### Load and save flow

```
user picks note in sidebar
  → List selection binding sets store.selectedID
  → .onChange(selectedID) → store.selectionChanged()
      → UserDefaults "lastOpened" = id
      → editor.load(note, focus)
          → JS load(): flush() previous note (posts `change` for the OLD id first)
                       parse doc JSON (or markdown) → fresh EditorState (new undo history)
                       restore title, scroll to top, focus

user types
  → TipTap onUpdate / title input → scheduleSave() (300 ms debounce)
  → flush(): post {type: change, id, title, doc: JSON, text}
  → EditorController.applyChange → SwiftData
  → @Query in sidebar re-renders the title live
```

Messages share a single ordered channel, so the old note's final `change` always arrives before anything for the new note. `visibilitychange`/`pagehide` also flush, so backgrounding the app on iOS doesn't lose the last 300 ms.

Switching notes replaces the whole `EditorState` (`view.updateState(EditorState.create({doc, plugins}))`) rather than calling `setContent`. That resets undo history so ⌘Z can't undo into the previous note. ProseMirror then rebuilds plugin views, which is cheap.

### Images

1. Paste/drop (`handlePaste`/`handleDrop`) or file picker → `uploadImage(blob)` in `bridge.ts` reads it as base64 and posts `uploadImage` with a random `requestId`.
2. Native stores an `Asset` and replies with `notez://asset/<id>`.
3. JS resolves the pending promise and inserts `setImage({src})`.
4. Rendering fetches through the scheme handler (cache, then SwiftData fetch).

On macOS, `<input type=file>` needs `WKUIDelegate.runOpenPanel` (implemented, images only). On iOS, WebKit shows the native photo/camera sheet itself. `NSCameraUsageDescription` is set in build settings.

## Window state (`NotesStore`)

- `selectedID: UUID?` is bound to the sidebar `List(selection:)`.
- `expanded: Set<UUID>` is persisted to `UserDefaults["sidebar.expanded"]`. `isExpanded(id)` returns a `Binding` for `DisclosureGroup`.
- `collapsedProjects: Set<UUID>` is persisted to `UserDefaults["sidebar.collapsedProjects"]`. Project sections default to expanded. `isProjectExpanded(id)` returns the `Section(isExpanded:)` binding.
- `showSwitcher` shows the ⌘K overlay (no animation, deliberately not a sheet).
- `projectPrompt` (`.new` / `.rename(Project)`) plus `projectName` drive the name alert in `NotesWindow`.
- `pendingFocus` (not observed) tells the next `selectionChanged()` where to put the caret: the title for brand-new pages, the body for pages created from ⌘K with a title.
- Menu commands reach the active window's store through `@FocusedValue(\.store)`, which `.focusedSceneValue(\.store, store)` provides.

Changes made outside the editor (the local API) reach open windows through a weak registry of stores: `NotesStore.reloadEverywhere(id)` reloads a page that is open, and `noteWillBeDeletedEverywhere(note)` moves selection off a page about to be deleted. Lookups, `move` (including the project rules), project ordering/deletion and search live in a `ModelContext` extension so the API can use them without a window.

Mutations: `newNote(parent:in:title:)`, `newPage(title:)` (top level, in the open page's project), `newSubnote()`, `delete(_:)` (moves selection to the parent if the selected page or an ancestor is deleted), `togglePin(_:)`, `move(_:into:project:)` (refuses self and descendant targets to prevent cycles; nil parent means top level of `project`), `beginNewProject()`, `beginRename(_:)`, `commitProjectPrompt(_:)`, `setIcon`, `setColor`, `moveProject(_:before:)` / `moveProject(_:by:)` (renumber `sortIndex` 0…n), `delete(_: Project)`, `copyMarkdown()`.

Search (`search(_:)`): an empty query returns the 20 most recently updated pages. Otherwise it fetches title matches (`localizedStandardContains`, newest first), then `NoteBody.plainText` matches, de-duplicated and capped at 50. Both run as SQLite predicates.

## Local API and MCP server

On macOS, `APIServer` (created once in `NotezApp.init`, so it runs with no windows) serves a REST API and an MCP server on `127.0.0.1` for AI tools. Opt-in from Settings, bearer-token auth. Reads export TipTap JSON to markdown in Swift; writes go through `pendingMarkdown`. Full details in [API.md](API.md).

## Build and project configuration

- **Single target, three platforms:** `SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx`, `SDKROOT = auto`, `TARGETED_DEVICE_FAMILY = 1,2`, no Mac Catalyst. Deployment target 26.0 on iOS and macOS.
- **Swift 6** with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency. Everything is main-actor unless marked otherwise, which suits WebKit and SwiftData's `mainContext`. `MemberImportVisibility` is on, so files must import the module that defines a member they use (for example `UniformTypeIdentifiers` for `.image`).
- **Generated Info.plist** (`GENERATE_INFOPLIST_FILE`) with `INFOPLIST_KEY_*` settings. No entitlements file. The macOS sandbox is enabled through `ENABLE_APP_SANDBOX`, `ENABLE_USER_SELECTED_FILES = readonly`, `ENABLE_OUTGOING_NETWORK_CONNECTIONS` and `ENABLE_INCOMING_NETWORK_CONNECTIONS` (local API).
- **Editor bundle:** Vite + `vite-plugin-singlefile` inline all JS/CSS into one ~550 KB HTML file (~175 KB gzip). One file means one scheme request at startup and zero network. The built file is committed so Xcode builds don't need Node.

## Debugging

- In Debug builds `webView.isInspectable = true`. On a Mac, use Safari > Develop > (device or Mac) > Notez to get the full web inspector on the editor.
- JS errors print to the Xcode console as `[editor] message @ file:line`.
- `npm run dev` in `editor/` runs the editor in a browser with a mock host (`devHost` in `bridge.ts`): saves go to `localStorage`, uploads become data URLs, and `window.editor` is exposed.
