import Foundation
import SwiftData
import Testing
@testable import Notez

/// Window state and the mutations views call. Each store builds a real (but
/// never shown) editor web view, which is fine: these tests don't wait for it.
@Suite struct NotesStoreTests {
    let store: TestStore
    let settings = ScratchDefaults()
    init() throws { store = try TestStore() }

    private func makeWindow() -> NotesStore {
        NotesStore(context: store.context, defaults: settings.defaults)
    }

    // MARK: - Creating and deleting

    @Test func newPagesGoToTheTopAndOpen() {
        store.note("Existing", sortIndex: 0)
        let window = makeWindow()
        let note = window.newNote(title: "Fresh")
        #expect(note.sortIndex == -1)
        #expect(window.selectedID == note.id)
        #expect(window.context.siblings(of: nil).min { $0.sortIndex < $1.sortIndex }?.id == note.id)
    }

    @Test func newSubpageExpandsItsParent() {
        let parent = store.note("Parent")
        let window = makeWindow()
        window.open(parent.id)
        window.newSubnote()
        #expect(parent.children?.count == 1)
        #expect(window.expanded.contains(parent.id))
    }

    @Test func newPageLandsInTheOpenPagesProject() {
        let work = store.project("Work")
        let root = store.note("Root", project: work)
        let child = store.note("Child", parent: root)
        let window = makeWindow()
        window.open(child.id)
        window.newPage(title: "Next")
        let created = store.context.siblings(of: nil).first { $0.title == "Next" }
        #expect(created?.project?.id == work.id)
    }

    @Test func deletingTheOpenPageSelectsItsParent() {
        let parent = store.note("Parent")
        let child = store.note("Child", parent: parent)
        let window = makeWindow()
        window.open(child.id)
        window.delete(child)
        #expect(window.selectedID == parent.id)
    }

    @Test func deletingAnAncestorOfTheOpenPageMovesSelectionAbove() {
        let root = store.note("Root")
        let middle = store.note("Middle", parent: root)
        let leaf = store.note("Leaf", parent: middle)
        let window = makeWindow()
        window.open(leaf.id)
        window.delete(middle)
        #expect(window.selectedID == root.id)
        #expect(store.context.note(leaf.id) == nil)
    }

    @Test func deletingAnotherPageKeepsSelection() {
        let open = store.note("Open")
        let other = store.note("Other")
        let window = makeWindow()
        window.open(open.id)
        window.delete(other)
        #expect(window.selectedID == open.id)
    }

    @Test func pinToggles() {
        let note = store.note("Note")
        let window = makeWindow()
        window.togglePin(note)
        #expect(note.isPinned)
        window.togglePin(note)
        #expect(!note.isPinned)
    }

    // MARK: - Moving

    @Test func movingIntoAPageExpandsIt() {
        let parent = store.note("Parent")
        let page = store.note("Page")
        let window = makeWindow()
        window.move(page, into: parent)
        #expect(page.parent?.id == parent.id)
        #expect(window.expanded.contains(parent.id))
    }

    @Test func movingIntoACollapsedProjectRevealsIt() {
        let work = store.project("Work")
        let page = store.note("Page")
        let window = makeWindow()
        window.collapsedProjects = [work.id]
        window.move(page, into: nil, project: work)
        #expect(!window.collapsedProjects.contains(work.id))
    }

    @Test func openingAPageRevealsItInTheSidebar() {
        let work = store.project("Work")
        let root = store.note("Root", project: work)
        let middle = store.note("Middle", parent: root)
        let leaf = store.note("Leaf", parent: middle)
        let window = makeWindow()
        window.collapsedProjects = [work.id]
        window.open(leaf.id)
        #expect(window.expanded.isSuperset(of: [root.id, middle.id]))
        #expect(!window.collapsedProjects.contains(work.id))
    }

    @Test func collapseAllClosesEveryPage() {
        let window = makeWindow()
        window.expanded = [UUID(), UUID()]
        window.collapseAll()
        #expect(window.expanded.isEmpty)
    }

    // MARK: - Projects

    @Test func newProjectsGoLastWithATrimmedName() {
        store.project("First", sortIndex: 0)
        let window = makeWindow()
        window.beginNewProject()
        #expect(window.projectPrompt == .new)
        window.projectName = "  Second  "
        window.commitProjectPrompt(.new)
        #expect(window.projectPrompt == nil)
        #expect(store.context.projects().map(\.name) == ["First", "Second"])
    }

    @Test func blankProjectNamesAreIgnored() {
        let window = makeWindow()
        window.projectName = "   "
        window.commitProjectPrompt(.new)
        #expect(store.context.projects().isEmpty)
    }

    @Test func renamingAProject() {
        let project = store.project("Old")
        let window = makeWindow()
        window.beginRename(project)
        #expect(window.projectName == "Old")
        window.projectName = "New"
        window.commitProjectPrompt(.rename(project))
        #expect(project.name == "New")
    }

    @Test func moveUpAndDownStopAtTheEnds() {
        let a = store.project("A", sortIndex: 0)
        let b = store.project("B", sortIndex: 1)
        let window = makeWindow()
        window.moveProject(b, by: -1)
        #expect(store.context.projects().map(\.name) == ["B", "A"])
        window.moveProject(b, by: -1)
        #expect(store.context.projects().map(\.name) == ["B", "A"])
        window.moveProject(a, by: 1)
        #expect(store.context.projects().map(\.name) == ["B", "A"])
    }

    // MARK: - Palettes

    @Test func paletteShortcutsToggleAndSwap() {
        let window = makeWindow()
        window.togglePalette(.commands)
        #expect(window.palette == .commands)
        window.togglePalette(.quickOpen)
        #expect(window.palette == .quickOpen)
        window.togglePalette(.quickOpen)
        #expect(window.palette == nil)
    }

    // MARK: - Remembered state

    @Test func sidebarStateSurvivesRelaunch() {
        let expanded = UUID(), collapsed = UUID()
        let first = makeWindow()
        first.expanded = [expanded]
        first.collapsedProjects = [collapsed]

        let second = makeWindow()
        #expect(second.expanded == [expanded])
        #expect(second.collapsedProjects == [collapsed])
    }

    @Test func reopensTheLastPage() {
        let note = store.note("Last")
        let first = makeWindow()
        first.open(note.id)
        first.selectionChanged() // the view calls this when selection changes

        #expect(makeWindow().selectedID == note.id)
    }

    @Test func forgetsALastPageThatWasDeleted() {
        let note = store.note("Gone")
        let first = makeWindow()
        first.open(note.id)
        first.selectionChanged()
        store.context.delete(note)

        #expect(makeWindow().selectedID == nil)
    }
}

@Suite struct WelcomeSeedTests {
    let store: TestStore
    init() throws { store = try TestStore() }

    @Test func firstLaunchSeedsAndOpensTheWelcomePage() {
        let settings = ScratchDefaults(welcomeSeeded: false)
        let window = NotesStore(context: store.context, defaults: settings.defaults)
        let welcome = store.context.siblings(of: nil).first
        #expect(welcome?.title == "Welcome to Notez")
        #expect(welcome?.children?.count == 1)
        #expect(welcome?.body?.pendingMarkdown.contains("## Shortcuts") == true)
        #expect(window.selectedID == welcome?.id)
    }

    @Test func seedsOnlyOnce() {
        let settings = ScratchDefaults(welcomeSeeded: false)
        Seed.welcomeIfNeeded(in: store.context, defaults: settings.defaults)
        let pages = store.count(Note.self)
        store.context.delete(store.context.siblings(of: nil)[0])
        #expect(Seed.welcomeIfNeeded(in: store.context, defaults: settings.defaults) == nil)
        #expect(store.count(Note.self) < pages)
    }

    @Test func neverSeedsIntoAStoreWithPages() {
        store.note("Mine")
        let settings = ScratchDefaults(welcomeSeeded: false)
        #expect(Seed.welcomeIfNeeded(in: store.context, defaults: settings.defaults) == nil)
        #expect(store.count(Note.self) == 1)
    }
}
