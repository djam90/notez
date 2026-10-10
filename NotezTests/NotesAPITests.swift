import Foundation
import SwiftData
import Testing
@testable import Notez

/// The operations behind both the REST routes and the MCP tools. These write
/// the user's real notes on behalf of AI tools, so validation matters.
@Suite struct NotesAPITests {
    let store: TestStore
    let api: NotesAPI
    init() throws {
        store = try TestStore()
        api = NotesAPI(context: store.context)
    }

    private func call(_ op: (NotesAPI.Args) throws -> Any, _ args: NotesAPI.Args = [:]) throws -> [String: Any] {
        try #require(try op(args) as? [String: Any])
    }

    private func expectError(
        _ status: Int, sourceLocation: SourceLocation = #_sourceLocation, _ body: () throws -> Any
    ) {
        do {
            _ = try body()
            Issue.record("expected an API error \(status)", sourceLocation: sourceLocation)
        } catch let error as APIError {
            #expect(error.status == status, "\(error.message)", sourceLocation: sourceLocation)
        } catch {
            Issue.record("unexpected error \(error)", sourceLocation: sourceLocation)
        }
    }

    private func titles(_ result: [String: Any], _ key: String = "notes") -> [String] {
        (result[key] as? [[String: Any]] ?? []).compactMap { $0["title"] as? String }
    }

    // MARK: - Reading

    @Test func listsEveryPageDepthFirstInSidebarOrder() throws {
        let a = store.note("A", sortIndex: 0)
        store.note("A2", parent: a, sortIndex: 2)
        store.note("A1", parent: a, sortIndex: 1)
        store.note("B", sortIndex: 1)
        #expect(titles(try call(api.list)) == ["A", "A1", "A2", "B"])
    }

    @Test func listsOneLevel() throws {
        let a = store.note("A", sortIndex: 0)
        store.note("A1", parent: a)
        store.note("B", sortIndex: 1)
        #expect(titles(try call(api.list, ["parentId": "root"])) == ["A", "B"])
        #expect(titles(try call(api.list, ["parentId": a.id.uuidString])) == ["A1"])
    }

    @Test func listsOneProject() throws {
        let work = store.project("Work")
        let plans = store.note("Plans", project: work)
        store.note("Q4", parent: plans)
        store.note("Unfiled")
        #expect(titles(try call(api.list, ["projectId": work.id.uuidString])) == ["Plans", "Q4"])
        #expect(titles(try call(api.list, ["projectId": "none"])) == ["Unfiled"])
    }

    @Test func summariesDescribeWhereAPageLives() throws {
        let work = store.project("Work")
        let plans = store.note("Plans", project: work)
        let q4 = store.note("Q4", parent: plans)
        let item = try call(api.get, ["id": q4.id.uuidString])
        #expect(item["parentId"] as? String == plans.id.uuidString)
        #expect(item["projectId"] as? String == work.id.uuidString)
        #expect(item["project"] as? String == "Work")
        #expect(item["path"] as? String == "Plans")
        #expect(item["childCount"] as? Int == 0)
    }

    @Test func getReturnsMarkdownAndChildren() throws {
        let page = store.note("Page")
        store.note("Child", parent: page)
        page.body = NoteBody(markdown: "Hello **world**")
        let item = try call(api.get, ["id": page.id.uuidString])
        #expect(item["markdown"] as? String == "Hello **world**")
        #expect((item["children"] as? [[String: Any]])?.first?["title"] as? String == "Child")
    }

    @Test func badIDsAreRejected() {
        expectError(400) { try api.get([:]) }
        expectError(400) { try api.get(["id": "nope"]) }
        expectError(404) { try api.get(["id": UUID().uuidString]) }
    }

    @Test func searchReturnsSnippets() throws {
        let long = String(repeating: "a ", count: 60) + "needle" + String(repeating: " b", count: 60)
        store.note("Haystack", text: long)
        let results = try #require(try call(api.search, ["query": "needle"])["results"] as? [[String: Any]])
        let snippet = try #require(results.first?["snippet"] as? String)
        #expect(snippet.contains("needle"))
        #expect(snippet.hasPrefix("…") && snippet.hasSuffix("…"))
    }

    @Test func searchClampsTheLimit() throws {
        for i in 0..<3 { store.note("Match \(i)") }
        #expect((try call(api.search, ["query": "match", "limit": 0])["results"] as? [Any])?.count == 1)
        #expect((try call(api.search, ["query": "match", "limit": "2"])["results"] as? [Any])?.count == 2)
        expectError(400) { try api.search([:]) }
    }

    // MARK: - Creating

    @Test func createdPagesGoToTheTopWithPendingMarkdown() throws {
        store.note("Existing", sortIndex: 0)
        let item = try call(api.create, ["title": "New", "markdown": "- [ ] task", "icon": "🔥", "pinned": true])
        let note = try #require(store.context.note(UUID(uuidString: item["id"] as! String)!))
        #expect(note.sortIndex == -1)
        #expect(note.icon == "🔥")
        #expect(note.isPinned)
        #expect(note.body?.pendingMarkdown == "- [ ] task")
        #expect(note.body?.doc == "")
        #expect(note.preview == "- [ ] task")
        #expect(item["markdown"] as? String == "- [ ] task")
    }

    @Test func createsSubpagesAndFiledPages() throws {
        let parent = store.note("Parent")
        let work = store.project("Work")
        let child = try call(api.create, ["title": "Child", "parentId": parent.id.uuidString])
        let filed = try call(api.create, ["title": "Filed", "projectId": work.id.uuidString])
        #expect(child["parentId"] as? String == parent.id.uuidString)
        #expect(filed["projectId"] as? String == work.id.uuidString)
    }

    @Test func createRejectsBadInput() {
        let parent = store.note("Parent")
        let work = store.project("Work")
        expectError(400) {
            try api.create(["title": "x", "parentId": parent.id.uuidString, "projectId": work.id.uuidString])
        }
        expectError(400) { try api.create(["title": 5]) }
        expectError(404) { try api.create(["title": "x", "parentId": UUID().uuidString]) }
        expectError(404) { try api.create(["title": "x", "projectId": UUID().uuidString]) }
        #expect(store.count(Note.self) == 1)
    }

    // MARK: - Updating

    @Test func markdownReplacesTheBody() throws {
        let page = store.note("Page")
        page.body = NoteBody()
        page.body?.doc = #"{"type":"doc"}"#
        _ = try api.update(["id": page.id.uuidString, "markdown": "fresh"])
        #expect(page.body?.doc == "", "the stale document must not win over the new markdown")
        #expect(page.body?.pendingMarkdown == "fresh")
        #expect(page.body?.plainText == "fresh")
    }

    @Test func appendMarkdownAddsAParagraph() throws {
        let page = store.note("Page")
        page.body = NoteBody(markdown: "one")
        _ = try api.update(["id": page.id.uuidString, "appendMarkdown": "two"])
        _ = try api.update(["id": page.id.uuidString, "appendMarkdown": ""])
        #expect(page.body?.pendingMarkdown == "one\n\ntwo")
        #expect(page.body?.plainText == "one\ntwo")
    }

    @Test func contentChangesBumpUpdatedAt() throws {
        let page = store.note("Page", updatedAt: .distantPast)
        _ = try api.update(["id": page.id.uuidString, "pinned": true])
        #expect(page.updatedAt == .distantPast)
        _ = try api.update(["id": page.id.uuidString, "title": "Renamed"])
        #expect(page.updatedAt > .distantPast)
        #expect(page.title == "Renamed")
    }

    @Test func movingToRootKeepsTheProject() throws {
        let work = store.project("Work")
        let root = store.note("Root", project: work)
        let child = store.note("Child", parent: root)
        _ = try api.update(["id": child.id.uuidString, "parentId": "root"])
        #expect(child.parent == nil)
        #expect(child.project?.id == work.id)
    }

    @Test func projectIDFilesAtTheTopLevel() throws {
        let work = store.project("Work")
        let root = store.note("Root")
        let child = store.note("Child", parent: root)
        _ = try api.update(["id": child.id.uuidString, "projectId": work.id.uuidString])
        #expect(child.parent == nil)
        #expect(child.project?.id == work.id)
        _ = try api.update(["id": child.id.uuidString, "projectId": "none"])
        #expect(child.project == nil)
    }

    @Test func invalidMovesChangeNothing() {
        let root = store.note("Root")
        let child = store.note("Child", parent: root)
        let work = store.project("Work")
        expectError(400) { try api.update(["id": root.id.uuidString, "parentId": child.id.uuidString, "title": "X"]) }
        expectError(400) { try api.update(["id": root.id.uuidString, "parentId": root.id.uuidString]) }
        expectError(400) {
            try api.update(["id": child.id.uuidString, "parentId": root.id.uuidString, "projectId": work.id.uuidString])
        }
        #expect(root.title == "Root")
        #expect(root.parent == nil)
    }

    // MARK: - Deleting

    @Test func deleteCountsSubpages() throws {
        let root = store.note("Root")
        let child = store.note("Child", parent: root)
        store.note("Grandchild", parent: child)
        store.note("Other")
        let result = try call(api.delete, ["id": root.id.uuidString])
        #expect(result["pagesDeleted"] as? Int == 3)
        #expect(store.count(Note.self) == 1)
    }

    // MARK: - Projects

    @Test func createsProjectsAtTheBottom() throws {
        store.project("First", sortIndex: 4)
        let item = try call(api.createProject, ["name": "  Second ", "icon": "briefcase", "color": "blue"])
        #expect(item["name"] as? String == "Second")
        #expect(store.context.projects().map(\.name) == ["First", "Second"])
        #expect(store.context.projects().last?.icon == "briefcase")
    }

    @Test func projectValidation() {
        let project = store.project("P")
        expectError(400) { try api.createProject([:]) }
        expectError(400) { try api.createProject(["name": "  "]) }
        expectError(400) { try api.createProject(["name": "x", "icon": "not-a-symbol"]) }
        expectError(400) { try api.createProject(["name": "x", "color": "chartreuse"]) }
        expectError(400) { try api.updateProject(["id": project.id.uuidString, "name": ""]) }
        expectError(400) { try api.updateProject(["id": project.id.uuidString, "beforeId": project.id.uuidString]) }
        expectError(404) { try api.updateProject(["id": UUID().uuidString]) }
        #expect(store.context.projects().map(\.name) == ["P"])
    }

    @Test func reordersProjects() throws {
        let a = store.project("A", sortIndex: 0)
        let b = store.project("B", sortIndex: 1)
        _ = try api.updateProject(["id": b.id.uuidString, "beforeId": a.id.uuidString])
        #expect(store.context.projects().map(\.name) == ["B", "A"])
        _ = try api.updateProject(["id": b.id.uuidString, "beforeId": "end"])
        #expect(store.context.projects().map(\.name) == ["A", "B"])
    }

    @Test func listsProjectsWithPageCounts() throws {
        let work = store.project("Work")
        let plans = store.note("Plans", project: work)
        store.note("Sub", parent: plans)
        store.note("Unfiled")
        let result = try call(api.listProjects)
        let first = try #require((result["projects"] as? [[String: Any]])?.first)
        #expect(first["pageCount"] as? Int == 1)
        #expect(result["unfiledPageCount"] as? Int == 1)
    }

    @Test func deletingAProjectUnfilesItsPages() throws {
        let work = store.project("Work")
        let page = store.note("Plans", project: work)
        let result = try call(api.deleteProject, ["id": work.id.uuidString])
        #expect(result["pagesUnfiled"] as? Int == 1)
        #expect(page.project == nil)
        #expect(store.count(Note.self) == 1)
    }

    // MARK: - Assets

    @Test func servesAssets() throws {
        let page = store.note("Page")
        let asset = Asset(data: Data([1, 2, 3]), mimeType: "image/jpeg", note: page)
        store.context.insert(asset)
        let served = try api.asset(asset.id.uuidString)
        #expect(served.data == Data([1, 2, 3]))
        #expect(served.mimeType == "image/jpeg")
        expectError(400) { try api.asset("nope") }
        expectError(404) { try api.asset(UUID().uuidString) }
    }
}
