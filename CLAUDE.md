# CLAUDE.md

Notez: a fast native notes app (Notion-like nested pages, tables, embedded images) for macOS, iPadOS and iOS. It is a SwiftUI shell plus SwiftData/CloudKit storage, with a TipTap editor running in one persistent WKWebView.

Read these before non-trivial work:
- `docs/ARCHITECTURE.md`: design, data model, JS⇄native bridge protocol, load/save flow
- `docs/FEATURES.md`: every feature, how it's built, what is verified vs untested, known limitations
- `docs/API.md`: the local MCP server + REST API for AI tools (macOS)

## Commands

```sh
scripts/setup.sh              # fresh clone / new worktree: npm ci in editor/
scripts/build.sh              # editor + macOS + iOS sim (default "all")
scripts/build.sh editor|mac|ios
scripts/run-mac.sh            # build + relaunch the Mac app
scripts/run-sim.sh            # build + install + launch on sim, streams console
SIM_NAME="iPad Pro 11-inch (M5)" scripts/run-sim.sh --screenshot   # saves /tmp/notez-sim.png

cd editor && npm run dev        # editor alone in a browser: http://localhost:5173/editor.html
cd editor && npm run typecheck
```

- **`xcode-select` on this machine points at CommandLineTools.** Raw `xcodebuild`/`simctl` fail unless `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` is set. `scripts/env.sh` handles this, so prefer the scripts.
- DerivedData goes to `./build/` (gitignored, per worktree).
- macOS builds use `CODE_SIGN_IDENTITY=-` (ad-hoc). No team is configured.
- There are no tests yet. "Verified" means it builds on both platforms and you looked at it (see Verifying changes).

## Layout

```
Notez/                      SwiftUI app, single multiplatform target
  NotezApp.swift            @main, ModelContainer, menu Commands (via @FocusedValue(\.store))
  Models/Note.swift         Note (metadata), NoteBody (doc JSON + plainText), Asset (image blob)
  Store/NotesStore.swift    per-window @Observable state + ALL mutations + search
  Store/Seed.swift          first-launch welcome page (markdown → converted by editor)
  Views/                    ContentView, SidebarView, NoteDetailView, QuickSwitcher
  Editor/                   EditorController (WKWebView + bridge), NotezSchemeHandler, EditorView
  API/                      NotesAPI (ops shared by REST + MCP), MCPHandler, APIServer (macOS), MarkdownExport
  Resources/editor.html     BUILT from editor/ (committed, don't hand-edit)
editor/src/                 main.ts (TipTap setup/menus/load/save), bridge.ts, slash.ts, style.css
scripts/                    env/setup/build/run helpers
docs/                       ARCHITECTURE.md, FEATURES.md
```

The Xcode project uses **file-system synchronized groups** (objectVersion 77). Any file you add under `Notez/` is automatically compiled or bundled. Don't add `PBXFileReference`/`PBXBuildFile` entries to `project.pbxproj`. Resources are bundled flat, so look them up with `Bundle.main.url(forResource:withExtension:)` and no subdirectory.

## Hard rules

1. **Editor changes need a rebuild + commit of the artifact.** After editing anything in `editor/`, run `scripts/build.sh editor` and commit `Notez/Resources/editor.html` together with the source. Xcode never runs Node, so an un-rebuilt bundle means the app silently runs old editor code.
2. **One store and one web view per window.** `NotesStore` (which owns `EditorController` → `WKWebView`) is created in `ContentView.onAppear` and held in `@State var store: NotesStore?`. Never construct it in a view `init`, `State(initialValue:)` or a computed property. SwiftUI re-runs inits, and each run creates and loads another web view. This exact bug caused a blank editor before.
3. **Never recreate or reload the web view to switch notes.** Switching is `editor.load(note)` → `window.notez.load(...)`. `EditorView.make*View` must keep returning `controller.webView`.
4. **Keep SwiftData models CloudKit-compatible:** every stored property has a default, every relationship is optional with an inverse, no `@Attribute(.unique)`, no non-optional to-one relationships. Breaking this breaks sync later, possibly with no visible error now.
5. **Keep `Note` light.** The sidebar `@Query` loads every `Note`. Large or unbounded data (document JSON, full text, blobs) belongs in `NoteBody` or `Asset`, never on `Note`.
6. **TipTap JSON (`NoteBody.doc`) is the source of truth.** Markdown is only import (`pendingMarkdown`, paste) and export (`getMarkdown`). Don't store HTML or markdown as the primary format.
7. **Images never go into the document as base64.** Use the `uploadImage` bridge → `Asset` → `notez://asset/<uuid>` flow.
8. **All web view loads go through `notez://`.** `decidePolicyFor` cancels any other navigation and opens it externally. Don't add `file://` loads or remote URLs to the editor.
9. **The bridge contract has two sides.** If you change a message shape, update `editor/src/bridge.ts` types, the `editor/src/main.ts` usage, `EditorController.handle`/`call`, and the tables in `docs/ARCHITECTURE.md`.

## Conventions

- **Swift 6, default actor isolation = MainActor** (build setting). Don't sprinkle `@MainActor`. Mark things `nonisolated` only when they truly need to leave the main actor.
- **`MemberImportVisibility` is on.** Import the module that defines a member you use (for example `import UniformTypeIdentifiers` for `UTType.image`), or the build fails.
- **Platform splits** use `#if os(macOS)` / `#else` inline, kept small (see `EditorView`, `EditorController.open`, `NotesStore.copyMarkdown`). Most UI code is shared.
- Mutations go through `NotesStore` methods, not ad-hoc in views. Views call `store.x(...)`.
- New menu commands go in `NotezCommands` and reach the window via `@FocusedValue(\.store)`. Disable them when `store?.selectedNote == nil` if they need a page.
- Prefer SF Symbols and system components (`ContentUnavailableView`, `Label`, `.toolbar`). Keep the native look.
- Editor code is **vanilla TypeScript, no UI framework.** Keep it that way for startup speed and bundle size. Menus are small DOM builders (`buildMenu`, `renderMenu` in `slash.ts`).
- CSS uses the custom properties in `:root` plus the `prefers-color-scheme: dark` override. Any new UI must use those variables so dark mode works. The page background is transparent so the native window background shows through.
- Comments are sparse and explain *why*. Match the existing density.
- No em dashes in docs, comments or commit messages. Use commas or hyphens.
- Commit messages: short imperative summary, with an optional body explaining why. Don't mention AI assistance.

## Recipes

**Add a field to a model.** Give it a default value. Put it on `NoteBody` if it can be large. Lightweight migration is automatic for additive changes with defaults. Update `docs/ARCHITECTURE.md` › Data model.

**Add a slash command.** Add an entry to `slashItems` in `editor/src/slash.ts` (`title`, `hint`, `keywords`, `run(editor, range)` that starts with `chain(e, r)` so it deletes the `/query`). Then rebuild the editor.

**Add a JS → native message.** Add it to the `OutgoingMessage` union in `bridge.ts`, handle it in `devHost` (browser mock), add a `case` in `EditorController.handle`, and document it.

**Add a native → JS call.** Add a method to the `api` object at the bottom of `main.ts`, then call it with `call("method", args...)` wrapped in `run { }` from `EditorController`. Args are JSON-serialised with `JSONSerialization`, so pass `[String: Any]`, strings, numbers or `NSNull`.

**Add a TipTap extension.** Run `npm i @tiptap/extension-x` in `editor/`, register it in the `extensions` array in `main.ts`, and style it in `style.css` (light + dark). Check that it still round-trips through `getJSON()` → `nodeFromJSON` (it will if it is a normal node or mark). If it should survive markdown paste or export, check that it has markdown support.

**Add a menu command or shortcut.** Add it to `NotezCommands` in `NotezApp.swift`. Avoid ⌘K (quick open), ⌘B/I/U and other editor-reserved shortcuts. WebKit gets key events first, and anything the page handles never reaches the menu.

## Verifying changes

Always build both platforms (`scripts/build.sh mac && scripts/build.sh ios`). Platform `#if` branches mean one can break silently.

- **Editor behaviour:** `cd editor && npm run dev`, open `/editor.html`. The dev host mocks the native side (localStorage saves, data-URL uploads) and `window.editor` is exposed for scripted checks such as `editor.getHTML()` or `editor.isActive('table')`. This is the fastest loop for anything in `editor/`.
- **Native rendering:** `scripts/run-sim.sh --screenshot` (iPhone) or with `SIM_NAME="iPad Pro 11-inch (M5)"`, then view `/tmp/notez-sim.png`. You can't tap in the simulator from the CLI, so to exercise a flow, seed state (see `Seed.swift`) or use `npm run dev`.
- **JS errors in the app:** `scripts/run-sim.sh` streams the console. Look for `[editor] …` lines (forwarded `window.onerror` / unhandled rejections). Safari > Develop gives the full inspector on Debug builds.
- **Fresh state on the simulator:** `xcrun simctl uninstall <udid> io.github.djam90.notez` (wipes the store and UserDefaults, so the welcome page re-seeds).
- Update the ✅/🟡 markers and "Verification status" in `docs/FEATURES.md` when you verify or add something.

## Gotchas

- **Bubble menus:** `.bubble` needs `width: max-content` and the menus use `strategy: 'fixed'`. Without them Floating UI measures the element at full width and pins it to x=0.
- **Two BubbleMenus** need distinct names (`BubbleMenu.extend({ name: 'tableMenu' })`) and distinct `pluginKey`s.
- **`window.prompt`/`alert`/`confirm` do nothing in WKWebView** (no UI delegate panels are implemented). Build inline UI instead, like the link input in `promptLink`.
- **macOS `<input type=file>`** only works because `EditorController` implements `runOpenPanelWith`. iOS handles it natively.
- **Switching notes uses `view.updateState(EditorState.create(...))`**, not `setContent`, so undo history doesn't leak between notes. If you add plugins with external state, make sure they survive plugin-view recreation.
- **`EditorController.run` queues only the last call** made before `ready`. Fine for `load`, wrong for anything that must not be dropped.
- **`change` messages for the previous note arrive after selection has moved.** `EditorController.note(with:)` handles this by fetching by id. Don't assume `currentNote` is the target.
- **Deleting a `Note` cascades to its children, body and assets.** There is no trash yet.
- **CloudKit is off** until a team + iCloud container are configured in Xcode (README). `.automatic` quietly falls back to local-only.
- **The local API writes markdown to `pendingMarkdown`**, not JSON. After any API change to a page, call `NotesStore.reloadEverywhere(id)`, or an open editor overwrites it on the next keystroke. API tool/route changes need `docs/API.md` updated too.
- **Testing the API:** it's off by default. The sandboxed prefs live at `~/Library/Containers/io.github.djam90.notez/Data/Library/Preferences/io.github.djam90.notez.plist` (`api.enabled`, `api.token`), so `defaults write <that path minus .plist> api.enabled -bool true` before launching, then `curl -H "Authorization: Bearer $(defaults read … api.token)" http://127.0.0.1:6683/api/notes`.
- **Bundle ID is `io.github.djam90.notez`.** `scripts/env.sh` hardcodes it for simctl.

## Worktrees

Committed: all source, the built `Notez/Resources/editor.html`, the Xcode project and the shared scheme. Not committed: `editor/node_modules`, `build/` and `xcuserdata`. In a new worktree, Xcode builds immediately. Run `scripts/setup.sh` only if you'll touch `editor/`. Each worktree has its own `build/` DerivedData, but the simulator app and its data are shared across worktrees (same bundle ID).
