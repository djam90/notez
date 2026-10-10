# CLAUDE.md

Notez: a fast native notes app (Notion-like nested pages, tables, embedded images) for macOS, iPadOS and iOS. It is a SwiftUI shell plus SwiftData/CloudKit storage, with a TipTap editor running in one persistent WKWebView.

Read these before non-trivial work:
- `README.md`: what the app does today (feature list, shortcuts), develop/release workflow
- `docs/ARCHITECTURE.md`: design, data model, JS⇄native bridge protocol, load/save flow, versioning/backups
- `docs/FEATURES.md`: every feature, how it's built, what is verified vs untested, known limitations
- `docs/API.md`: the local MCP server + REST API for AI tools (macOS)

## Keep the docs current (every commit)

These docs are how future sessions learn what exists. They must describe the build as it is **after your commit**, so update them **in the same commit** as the code:

| You changed | Update |
| --- | --- |
| Any user-visible feature, shortcut or menu item | `README.md` › Features (one line), `docs/FEATURES.md` (how it works + ✅/🟡 status + limitations) |
| Models, store, bridge, flows, build/release config | `docs/ARCHITECTURE.md` |
| A script, workflow, rule, convention, gotcha, or something you learned the hard way | `CLAUDE.md` (Commands / Hard rules / Gotchas / Lessons) |
| Removed or replaced something | Delete or rewrite the old text. Stale docs are worse than none. |

`scripts/githooks/commit-msg` enforces this. It rejects a commit that touches `Notez/`, `editor/src/` or `scripts/` without touching `README.md`, `CLAUDE.md` or `docs/`. Use `[skip docs]` in the message only for changes with nothing to document (pure refactor, typo, internal fix). `scripts/setup.sh` enables the hook (`core.hooksPath`, shared by all worktrees). Never bypass it with `--no-verify`.

## Commands

```sh
scripts/setup.sh              # fresh clone / new worktree: docs hook + npm ci in editor/
scripts/build.sh              # editor + macOS + iOS sim (default "all")
scripts/build.sh editor|mac|ios
scripts/run-mac.sh            # build + relaunch the Mac Debug app ("Notez Dev")
scripts/release-mac.sh [minor] # ship this worktree: rebase on origin/main, push + tag, back up, install
scripts/screenshot-mac.sh     # screenshot ONLY the Notez Dev window → /tmp/notez-mac.png
scripts/run-sim.sh            # build + install + launch on sim, streams console
SIM_NAME="iPad Pro 11-inch (M5)" scripts/run-sim.sh --screenshot   # saves /tmp/notez-sim.png

scripts/test.sh               # unit (Swift) + editor (Vitest + Playwright), about 20 s. Run before every commit
scripts/test.sh unit|editor   # one suite
scripts/test.sh ui            # XCUITest smoke tests. TAKES OVER THE USER'S MAC, ask first (see Testing)
scripts/make-store-fixture.sh # after any model change: snapshot the store for MigrationTests

cd editor && npm run dev        # editor alone in a browser: http://localhost:5173/editor.html
cd editor && npm run typecheck  # src, then tests and configs
cd editor && npm run test:watch # Vitest in watch mode
```

- **`xcode-select` on this machine points at CommandLineTools.** Raw `xcodebuild`/`simctl` fail unless `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` is set. `scripts/env.sh` handles this, so prefer the scripts.
- DerivedData goes to `./build/` (gitignored, per worktree).
- macOS builds use `CODE_SIGN_IDENTITY=-` (ad-hoc). No team is configured.
- "Verified" means the tests pass, it builds on both platforms, and for UI you looked at it (see Testing and Verifying changes).

## Layout

```
Notez/                      SwiftUI app, single multiplatform target
  NotezApp.swift            @main, ModelContainer, menu Commands (via @FocusedValue(\.store))
  Models/Note.swift         Note (metadata), Project (sidebar group), NoteBody (doc JSON + plainText), Asset (image blob)
  Models/Schema.swift       VersionedSchema + migration plan (read its comment before changing a model)
  Store/NotesStore.swift    per-window @Observable state + ALL mutations + search
  Store/StoreBackup.swift   copies the store aside when a new app version first launches
  Store/Seed.swift          first-launch welcome page (markdown → converted by editor)
  Views/                    ContentView, SidebarView (+ ProjectSection), NoteDetailView, QuickSwitcher (⌘K overlay), CommandPalette (⌘⇧K), Palette (shared overlay panel),
                            ProjectMenus (icon/colour choices, Move to Project), StoreErrorView
  Editor/                   EditorController (WKWebView + bridge), NotezSchemeHandler, EditorView
  API/                      NotesAPI (ops shared by REST + MCP), MCPHandler, APIServer (macOS), MarkdownExport
  Resources/editor.html     BUILT from editor/ (committed, don't hand-edit)
editor/src/                 main.ts (TipTap setup/menus/load/save), extensions.ts (schema + markdown), doc.ts (pure load
                            helpers), bridge.ts, slash.ts, style.css
editor/test/                unit/ (Vitest, jsdom), e2e/ (Playwright: WebKit + Chromium against npm run dev)
NotezTests/                 Swift Testing unit tests, hosted in Notez Dev. Fixtures/store-*.store = stores from older builds
NotezUITests/               XCUITest smoke tests (launch, ⌘K, ⇧⌘K, ⌘N)
scripts/                    env/setup/build/run/release/screenshot helpers, githooks/commit-msg (docs check)
docs/                       ARCHITECTURE.md, FEATURES.md
```

The Xcode project uses **file-system synchronized groups** (objectVersion 77). Any file you add under `Notez/`, `NotezTests/` or `NotezUITests/` is automatically compiled or bundled into that target. Don't add `PBXFileReference`/`PBXBuildFile` entries to `project.pbxproj`. Resources are bundled flat, so look them up with `Bundle.main.url(forResource:withExtension:)` and no subdirectory.

## Hard rules

1. **Editor changes need a rebuild + commit of the artifact.** After editing anything in `editor/`, run `scripts/build.sh editor` and commit `Notez/Resources/editor.html` together with the source. Xcode never runs Node, so an un-rebuilt bundle means the app silently runs old editor code.
2. **One store and one web view per window.** `NotesStore` (which owns `EditorController` → `WKWebView`) is created in `ContentView.onAppear` and held in `@State var store: NotesStore?`. Never construct it in a view `init`, `State(initialValue:)` or a computed property. SwiftUI re-runs inits, and each run creates and loads another web view. This exact bug caused a blank editor before.
3. **Never recreate or reload the web view to switch notes.** Switching is `editor.load(note)` → `window.notez.load(...)`. `EditorView.make*View` must keep returning `controller.webView`.
4. **Never risk the user's real data.** Debug builds are `io.github.djam90.notez.dev` with their own store. The Release app in `/Applications` (`io.github.djam90.notez`) holds real notes. Don't run, migrate-test or delete anything against the release container, and only run `scripts/release-mac.sh` when asked.
5. **Keep SwiftData models CloudKit-compatible:** every stored property has a default, every relationship is optional with an inverse, no `@Attribute(.unique)`, no non-optional to-one relationships. Breaking this breaks sync later, possibly with no visible error now.
6. **Keep `Note` light.** The sidebar `@Query` loads every `Note`. Large or unbounded data (document JSON, full text, blobs) belongs in `NoteBody` or `Asset`, never on `Note`.
7. **TipTap JSON (`NoteBody.doc`) is the source of truth.** Markdown is only import (`pendingMarkdown`, paste) and export (`getMarkdown`). Don't store HTML or markdown as the primary format.
8. **Images never go into the document as base64.** Use the `uploadImage` bridge → `Asset` → `notez://asset/<uuid>` flow.
9. **All web view loads go through `notez://`.** `decidePolicyFor` cancels any other navigation and opens it externally. Don't add `file://` loads or remote URLs to the editor.
10. **The bridge contract has two sides.** If you change a message shape, update `editor/src/bridge.ts` types, the `editor/src/main.ts` usage, `EditorController.handle`/`call`, and the tables in `docs/ARCHITECTURE.md`.

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

**Add a field to a model.** Give it a default value. Put it on `NoteBody` if it can be large. Additive changes migrate automatically, with no new schema version. Renames, type changes and data transforms need a new `VersionedSchema` and a migration stage (see the comment in `Models/Schema.swift`). Then run `scripts/test.sh unit`: `MigrationTests` opens every committed `Fixtures/store-*.store` with the new models, and `newestFixtureMatchesTheCurrentModels` fails until you run `scripts/make-store-fixture.sh` and commit the new fixture. Never delete or regenerate old fixtures, they are what shipped. `CloudKitCompatibilityTests` enforce hard rule 5. Update `docs/ARCHITECTURE.md` › Data model.

**Add a test.** Swift: add a file under `NotezTests/` with `import Testing` and `@testable import Notez`, use `TestStore()` for an in-memory store and `ScratchDefaults()` for settings (`TestSupport.swift`). Never use `UserDefaults.standard` or the default `ModelContainer` in tests. Editor: pure logic goes in `editor/test/unit/*.test.ts` (import from `extensions.ts`/`doc.ts`, not `main.ts`, which boots on import), user flows in `editor/test/e2e/editor.spec.ts` using the `notez` fixture. A bug fix should come with a test that fails without it.

**Add a slash command.** Add an entry to `slashItems` in `editor/src/slash.ts` (`title`, `hint`, `keywords`, `run(editor, range)` that starts with `chain(e, r)` so it deletes the `/query`). Then rebuild the editor.

**Add a JS → native message.** Add it to the `OutgoingMessage` union in `bridge.ts`, handle it in `devHost` (browser mock), add a `case` in `EditorController.handle`, and document it.

**Add a native → JS call.** Add a method to the `api` object at the bottom of `main.ts`, then call it with `call("method", args...)` wrapped in `run { }` from `EditorController`. Args are JSON-serialised with `JSONSerialization`, so pass `[String: Any]`, strings, numbers or `NSNull`.

**Add a TipTap extension.** Run `npm i @tiptap/extension-x` in `editor/`, register it in the `extensions` array in `main.ts`, and style it in `style.css` (light + dark). Check that it still round-trips through `getJSON()` → `nodeFromJSON` (it will if it is a normal node or mark). If it should survive markdown paste or export, check that it has markdown support.

**Add a menu command or shortcut.** Add it to `NotezCommands` in `NotezApp.swift`. If it's useful without a page-specific UI, add it to `CommandPalette.commands` too. Avoid ⌘K (quick open), ⌘⇧K (command palette), ⌘B/I/U and other editor-reserved shortcuts. WebKit gets key events first, and anything the page handles never reaches the menu.

## Testing

`scripts/test.sh` runs the two fast suites. Run it before every commit; `scripts/release-mac.sh` runs it too and refuses to release on a failure.

| Suite | Where | What it covers | Time |
| --- | --- | --- | --- |
| Swift unit (`NotezTests`) | Swift Testing, hosted in Notez Dev | model rules, move/search, `NotesStore`, local API + MCP, markdown export, backups, migrations from `Fixtures/`, CloudKit rules, and the real bundled editor driven off-screen through the bridge (pending markdown conversion, Swift vs editor markdown agreement, API round trip) | ~5 s incl. build check |
| Editor unit (`editor/test/unit`) | Vitest + jsdom | markdown round trips, doc helpers, slash items, the production bridge path with a fake `webkit.messageHandlers` | ~1 s |
| Editor e2e (`editor/test/e2e`) | Playwright, WebKit + Chromium, starts Vite on :5199 | typing, saving, slash menu, paste, bubbles, tables, tasks, image upload, undo isolation, the committed `editor.html` | ~12 s |
| UI (`NotezUITests`) | XCUITest | the real app: launch renders the welcome page, ⌘K, ⇧⌘K, ⌘N | ~40 s |

- **UI tests take over the user's Mac.** macOS enters "Automation Running" mode and drives the real keyboard and mouse, so the user can't work while they run. They also quit any running Notez Dev. Never run `scripts/test.sh ui` (or `all`) without asking the user first, and never add it to scripts that run unattended. Run it, with permission, after changing startup, `ContentView`, menus or palettes.
- **Tests never touch real data.** Hosted unit tests and `-ui-testing` launches set `AppLaunch.isTesting`: in-memory store, `notez.tests` UserDefaults suite, no backups, no API server. The unit test host also sets the activation policy to `.prohibited`, so it shows no window and never steals focus.
- Failures print a short summary; the full log is `build/test-<Target>.log` and `open build/TestResults/<Target>.xcresult` shows everything in Xcode.
- One-off setup per machine for e2e: `scripts/setup.sh` installs the Playwright browsers (cached in `~/Library/Caches/ms-playwright`).

## Verifying changes

Run `scripts/test.sh`, and always build both platforms (`scripts/build.sh mac && scripts/build.sh ios`). Platform `#if` branches mean one can break silently.

- **Editor behaviour:** `cd editor && npm run dev`, open `/editor.html`. The dev host mocks the native side (localStorage saves, data-URL uploads) and `window.editor` is exposed for scripted checks such as `editor.getHTML()` or `editor.isActive('table')`. This is the fastest loop for anything in `editor/`.
- **Mac window:** `scripts/run-mac.sh`, then `scripts/screenshot-mac.sh` and view `/tmp/notez-mac.png`. Never use plain `screencapture` (whole screen = the user's private apps). **Always look at the Mac window after touching `NotezApp`/`ContentView`/startup code, and before every `scripts/release-mac.sh`.** A blank window once shipped because this was skipped.
- **Native rendering:** `scripts/run-sim.sh --screenshot` (iPhone) or with `SIM_NAME="iPad Pro 11-inch (M5)"`, then view `/tmp/notez-sim.png`. You can't tap in the simulator from the CLI, so to exercise a flow, seed state (see `Seed.swift`) or use `npm run dev`.
- **JS errors in the app:** `scripts/run-sim.sh` streams the console. Look for `[editor] …` lines (forwarded `window.onerror` / unhandled rejections). Safari > Develop gives the full inspector on Debug builds.
- **Fresh state on the simulator:** `xcrun simctl uninstall <udid> io.github.djam90.notez.dev` (wipes the store and UserDefaults, so the welcome page re-seeds).
- Update the ✅/🟡 markers and "Verification status" in `docs/FEATURES.md` when you verify or add something.

## Gotchas

- **Speed is a feature: no animated transitions on navigation.** `.sheet` animates in and out on macOS (~0.3 s each way), which made ⌘K feel laggy, so it's an overlay now. Use overlays or inline UI for anything on the path to opening a page.
- **Menus ignore `foregroundStyle`.** SF Symbols in context menus and pickers render as monochrome templates. For coloured menu icons use `ProjectStyle.menuImage(_:color:)`, which bakes the colour into a non-template image.
- **`onAppear` never fires on an empty `Group`.** Give it a real view (`Color.clear`), as `ContentView` does.

- **Hosted tests share the dev app's bundle ID and sandbox.** Anything the app does at launch also runs before every unit test run, which is why `AppLaunch.isTesting` gates the store, backups and API server. Tests that write files must use `FileManager.default.temporaryDirectory` (the container's tmp), and can't read the repo, so fixtures are bundled resources (flat: give them unique names).
- **`JSONSerialization` throws an Objective-C exception, not a Swift error, on a bare string or number.** In a test that crashes the whole host. Pass raw JSON text (`Data("...".utf8)`) when testing malformed input.
- **`NotezUITests` doesn't use default MainActor isolation** (it conflicts with `XCTestCase`). Mark test methods `@MainActor` as in Apple's template.
- **`xcodebuild` passes `TEST_RUNNER_FOO=x` to the test host as `FOO=x`.** `make-store-fixture.sh` uses this to enable the fixture writer.
- **Playwright WebKit takes TipTap's Safari/iOS code paths** (desktop Safari user agent), which the Mac WKWebView doesn't. That's how it caught an iOS-only crash: `focus()` dispatching a transaction mid-command when a doc ends in a block. `load()` now normalises the trailing paragraph up front.
- **In e2e, wait for the save you expect: `nextChange(id, before, (c) => c.text === '...')`.** Without the predicate an earlier debounced save (the title, a half-typed `/command`) can land first under load and match instead. Check new e2e tests with `npx playwright test --repeat-each=6 --workers=10`. Place the caret by clicking: outside WebKit, `focus()` runs in a `requestAnimationFrame` and races typing.

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
- **Testing the API:** test against **Notez Dev**, never the installed app. It's off by default. The sandboxed prefs live at `~/Library/Containers/io.github.djam90.notez.dev/Data/Library/Preferences/io.github.djam90.notez.dev.plist` (`api.enabled`, `api.token`), so `defaults write <that path minus .plist> api.enabled -bool true` before launching, then `curl -H "Authorization: Bearer $(defaults read … api.token)" http://127.0.0.1:6684/api/notes`. Debug defaults to port 6684 and Release to 6683, so both apps can run at once.
- **Bundle IDs:** Debug is `io.github.djam90.notez.dev` (display name "Notez Dev", red DEV badge on the Mac Dock icon), Release is `io.github.djam90.notez`. Both executables are named `Notez`, so never `pkill -x Notez`. Match the full path as `run-mac.sh` does. `scripts/env.sh` defines `BUNDLE_ID` (dev) and `RELEASE_BUNDLE_ID`. Don't use personal identifiers (name, email, domain) in the repo. It's public.

## Worktrees

Committed: all source, the built `Notez/Resources/editor.html`, the Xcode project and the shared scheme. Not committed: `editor/node_modules`, `build/` and `xcuserdata`. In a new worktree, Xcode builds immediately. Run `scripts/setup.sh` only if you'll touch `editor/`. Each worktree has its own `build/` DerivedData, but the dev app and its data (Mac and simulator) are shared across worktrees (same bundle ID).

**One feature per worktree, released from that worktree.** The user works on features in parallel Paseo worktrees and ships each with `scripts/release-mac.sh` run from inside it. The script rebases the branch onto `origin/main`, checks the iOS build, bumps the version (patch by default, `minor`/`major`/`x.y.z` to override), builds Release, pushes `HEAD:main` and the tag atomically, then backs up data, installs and checks a window appears. Feature branches are never pushed on their own, `main` on GitHub is the release history. Other worktrees pick up the new main when they next release, and the script lists the ones that are behind.

- The release runs `scripts/test.sh unit editor` after rebasing and stops on a failure. It does not run the UI tests (they take over the Mac).
- **Lesson:** the old script tagged whatever branch it ran on and never pushed, so v0.3.2 was installed from a feature branch that never reached main. Releasing from main would have rolled those changes back. Never release without pushing.
- If the rebase conflicts the script stops. Run `git rebase origin/main`, resolve, rebuild, release again.
