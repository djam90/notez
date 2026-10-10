import CoreData
import Foundation
import SwiftData
import Testing
@testable import Notez

/// Every model shape that has shipped must still open in the current build.
///
/// `Fixtures/store-*.store` are real SQLite stores written by older builds
/// (`scripts/make-store-fixture.sh`). Each holds `StoreFixture`'s pages, and
/// each test opens a copy with the current schema and migration plan, exactly
/// as the app does on launch, then checks nothing was lost.
@Suite struct MigrationTests {
    nonisolated static let fixtures: [URL] = (Bundle(for: BundleToken.self)
        .urls(forResourcesWithExtension: "store", subdirectory: nil) ?? [])
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    @Test func planEndsAtTheCurrentSchema() {
        let last = NotezMigrationPlan.schemas.last.map { ObjectIdentifier($0) }
        #expect(last == ObjectIdentifier(NotezSchema.self))
    }

    @Test func schemaVersionsOnlyGoUp() {
        let versions = NotezMigrationPlan.schemas.map { $0.versionIdentifier }
        #expect(zip(versions, versions.dropFirst()).allSatisfy { $0 < $1 })
        #expect(NotezMigrationPlan.stages.count == versions.count - 1, "one stage between each pair of versions")
    }

    @Test func thereAreFixtures() {
        #expect(!Self.fixtures.isEmpty)
    }

    @Test(arguments: fixtures)
    func opensStoresFromOlderBuilds(_ fixture: URL) throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "default.store")
        try FileManager.default.copyItem(at: fixture, to: url)

        let schema = Schema(versionedSchema: NotezSchema.self)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: NotezMigrationPlan.self, configurations: config)
        try StoreFixture.verify(container.mainContext)
    }

    /// Model changes need a fresh fixture, so the next change after them is
    /// tested against what actually shipped.
    @Test func newestFixtureMatchesTheCurrentModels() throws {
        let newest = try #require(Self.fixtures.last)
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: newest)
        let stored = metadata[NSStoreModelVersionHashesKey] as? [String: Data] ?? [:]
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: NotezSchema.models))
        #expect(
            stored == model.entityVersionHashesByName,
            "The models changed since \(newest.lastPathComponent). Run scripts/make-store-fixture.sh and commit the new fixture."
        )
    }

    /// Writes the fixture for `scripts/make-store-fixture.sh`. Skipped otherwise.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NOTEZ_WRITE_FIXTURE"] != nil))
    func writeFixture() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "notez-fixture")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: NotezSchema.self)
        let config = ModelConfiguration(schema: schema, url: dir.appending(path: "fixture.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: NotezMigrationPlan.self, configurations: config)
        try StoreFixture.write(container.mainContext)
        try StoreFixture.verify(container.mainContext)
    }
}

private nonisolated final class BundleToken {}

/// The pages every fixture holds. Keep `write` producing the same content
/// forever; if a migration transforms data, update `verify` to the new shape.
enum StoreFixture {
    static let image = Data(repeating: 7, count: 2048)

    static func write(_ context: ModelContext) throws {
        let work = Project(name: "Work", sortIndex: 0)
        work.icon = "briefcase"
        work.color = "blue"
        context.insert(work)

        let plans = Note(title: "Plans", sortIndex: 0)
        plans.icon = "📋"
        plans.isPinned = true
        plans.project = work
        context.insert(plans)
        let body = NoteBody()
        body.doc = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Ship it"}]}]}"#
        body.plainText = "Ship it"
        context.insert(body)
        plans.body = body
        plans.setPreview(from: body.plainText)

        let q4 = Note(title: "Q4", parent: plans, sortIndex: 0)
        context.insert(q4)
        let pending = NoteBody(markdown: "- [ ] launch")
        context.insert(pending)
        q4.body = pending
        context.insert(Asset(data: image, mimeType: "image/png", note: q4))

        context.insert(Note(title: "Inbox", sortIndex: 1))
        try context.save()
    }

    static func verify(_ context: ModelContext) throws {
        #expect(try context.fetchCount(FetchDescriptor<Note>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<NoteBody>()) == 2)

        let work = try #require(context.projects().first)
        #expect(work.name == "Work")
        #expect(work.icon == "briefcase")
        #expect(work.color == "blue")

        let roots = context.siblings(of: nil).sorted { $0.sortIndex < $1.sortIndex }
        #expect(roots.map(\.title) == ["Plans", "Inbox"])
        let plans = try #require(roots.first)
        #expect(plans.project?.id == work.id)
        #expect(plans.icon == "📋")
        #expect(plans.isPinned)
        #expect(plans.preview == "Ship it")
        #expect(plans.body?.doc.contains("Ship it") == true)
        #expect(roots.last?.project == nil)

        let q4 = try #require(plans.children?.first)
        #expect(q4.title == "Q4")
        #expect(q4.rootProject?.id == work.id)
        #expect(q4.body?.pendingMarkdown == "- [ ] launch")
        #expect(q4.assets?.first?.data == image)
        #expect(q4.assets?.first?.mimeType == "image/png")
    }
}
