import Foundation
import SwiftData
import Testing
@testable import Notez

/// A fresh in-memory store per test, opened with the app's real schema and
/// migration plan, plus builders for the usual fixtures.
struct TestStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        let schema = Schema(versionedSchema: NotezSchema.self)
        let config = ModelConfiguration(
            UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        container = try ModelContainer(for: schema, migrationPlan: NotezMigrationPlan.self, configurations: config)
    }

    @discardableResult
    func note(
        _ title: String, parent: Note? = nil, project: Project? = nil, sortIndex: Double = 0,
        text: String? = nil, updatedAt: Date? = nil
    ) -> Note {
        let note = Note(title: title, parent: parent, sortIndex: sortIndex)
        note.project = project
        if let updatedAt { note.updatedAt = updatedAt }
        context.insert(note)
        if let text {
            let body = NoteBody()
            body.plainText = text
            context.insert(body)
            note.body = body
        }
        try? context.save()
        return note
    }

    @discardableResult
    func project(_ name: String, sortIndex: Double = 0) -> Project {
        let project = Project(name: name, sortIndex: sortIndex)
        context.insert(project)
        try? context.save()
        return project
    }

    func count<T: PersistentModel>(_ type: T.Type) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>())) ?? -1
    }
}

/// Throwaway settings, deleted when the test's suite instance goes away, so
/// tests never see each other's (or the dev app's) window state.
final class ScratchDefaults {
    let name = "notez.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init(welcomeSeeded: Bool = true) {
        defaults = UserDefaults(suiteName: name)!
        // Most tests don't want the welcome pages appearing in their store.
        defaults.set(welcomeSeeded, forKey: "seed.welcome.v1")
    }

    deinit { UserDefaults.standard.removePersistentDomain(forName: name) }
}

/// Polls `condition` while letting the main run loop (and so WebKit) work.
func waitUntil(
    timeout: Duration = .seconds(10), _ what: String = "condition",
    sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting for \(what)", sourceLocation: sourceLocation)
            throw CancellationError()
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}

@Test func hostRunsInTestMode() {
    // The guard that keeps tests away from the dev app's real store and settings.
    #expect(AppLaunch.isTesting)
    #expect(AppLaunch.defaults != UserDefaults.standard)
}
