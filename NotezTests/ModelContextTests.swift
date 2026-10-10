import Foundation
import SwiftData
import Testing
@testable import Notez

/// The lookups, move rules and search shared by windows and the local API.
@Suite struct ModelContextTests {
    let store: TestStore
    var context: ModelContext { store.context }
    init() throws { store = try TestStore() }

    @Test func findsNotesByID() {
        let note = store.note("Hello")
        #expect(context.note(note.id)?.title == "Hello")
        #expect(context.note(UUID()) == nil)
    }

    @Test func topLevelSiblingsExcludeSubpages() {
        let a = store.note("A")
        store.note("A1", parent: a)
        store.note("B")
        #expect(Set(context.siblings(of: nil).map(\.title)) == ["A", "B"])
        #expect(context.siblings(of: a).map(\.title) == ["A1"])
    }

    // MARK: - Moving pages

    @Test func movingIntoAPageAppendsAndDropsTheProject() {
        let work = store.project("Work")
        let page = store.note("Page", project: work)
        let parent = store.note("Parent")
        store.note("First", parent: parent, sortIndex: 0)
        store.note("Last", parent: parent, sortIndex: 5)

        #expect(context.move(page, into: parent, project: work))
        #expect(page.parent?.id == parent.id)
        #expect(page.project == nil, "sub-pages follow their root's project")
        #expect(page.sortIndex == 6)
        #expect(parent.sortedChildren.last?.id == page.id)
    }

    @Test func refusesToMoveAPageIntoItselfOrItsSubpages() {
        let root = store.note("Root")
        let child = store.note("Child", parent: root)
        let grandchild = store.note("Grandchild", parent: child)

        #expect(!context.move(root, into: root))
        #expect(!context.move(root, into: child))
        #expect(!context.move(root, into: grandchild))
        #expect(root.parent == nil)
    }

    @Test func movingToWhereItAlreadyIsDoesNothing() {
        let work = store.project("Work")
        let page = store.note("Page", project: work, sortIndex: 3)
        #expect(!context.move(page, into: nil, project: work))
        #expect(page.sortIndex == 3)
    }

    @Test func movingToTheTopLevelOfAProject() {
        let work = store.project("Work")
        let root = store.note("Root")
        let child = store.note("Child", parent: root)

        #expect(context.move(child, into: nil, project: work))
        #expect(child.parent == nil)
        #expect(child.project?.id == work.id)
        #expect(context.move(child, into: nil, project: nil))
        #expect(child.project == nil)
    }

    // MARK: - Projects

    @Test func projectsComeBackInSidebarOrder() {
        store.project("B", sortIndex: 2)
        store.project("A", sortIndex: 1)
        #expect(context.projects().map(\.name) == ["A", "B"])
    }

    @Test func movingAProjectRenumbersEveryone() {
        let a = store.project("A", sortIndex: 0)
        store.project("B", sortIndex: 1)
        let c = store.project("C", sortIndex: 2)

        context.moveProject(c, before: a)
        #expect(context.projects().map(\.name) == ["C", "A", "B"])
        #expect(context.projects().map(\.sortIndex) == [0, 1, 2])

        context.moveProject(c, before: nil)
        #expect(context.projects().map(\.name) == ["A", "B", "C"])

        context.moveProject(a, before: a)
        #expect(context.projects().map(\.name) == ["A", "B", "C"])
    }

    @Test func deletingAProjectUnfilesItsPages() throws {
        let work = store.project("Work")
        let page = store.note("Plans", project: work)
        context.deleteProject(work)
        try context.save()
        #expect(context.projects().isEmpty)
        #expect(context.note(page.id)?.project == nil)
    }

    // MARK: - Search

    @Test func titleMatchesRankAboveBodyMatches() {
        let inBody = store.note("Weekend", text: "remember the groceries", updatedAt: .now)
        let inTitle = store.note("Groceries", updatedAt: .distantPast)
        #expect(context.searchNotes("grocer").map(\.id) == [inTitle.id, inBody.id])
    }

    @Test func searchIgnoresCaseAndAccents() {
        store.note("Café ideas")
        #expect(context.searchNotes("CAFE").map(\.title) == ["Café ideas"])
    }

    @Test func aPageMatchingTwiceIsListedOnce() {
        store.note("Groceries", text: "groceries list")
        #expect(context.searchNotes("groceries").count == 1)
    }

    @Test func emptyQueryListsTheTwentyMostRecent() {
        for i in 0..<25 { store.note("Note \(i)", updatedAt: Date(timeIntervalSince1970: Double(i))) }
        let results = context.searchNotes("  ")
        #expect(results.count == 20)
        #expect(results.first?.title == "Note 24")
    }

    @Test func searchRespectsTheLimit() {
        for i in 0..<5 { store.note("Match \(i)") }
        #expect(context.searchNotes("match", limit: 3).count == 3)
    }

    @Test func noMatchesIsEmpty() {
        store.note("Something")
        #expect(context.searchNotes("zebra").isEmpty)
    }
}
