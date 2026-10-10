import Foundation
import Testing
@testable import Notez

/// The copy taken before a new version opens (and maybe migrates) the store.
@Suite final class StoreBackupTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "backup-tests-\(UUID().uuidString)")
    let settings = ScratchDefaults()
    var storeURL: URL { dir.appending(path: "default.store") }
    var backups: URL { StoreBackup.folder(for: storeURL) }

    init() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appending(path: ".default_SUPPORT/_EXTERNAL_DATA"), withIntermediateDirectories: true)
        for name in ["default.store", "default.store-wal", "default.store-shm", ".default_SUPPORT/_EXTERNAL_DATA/blob"] {
            try Data(name.utf8).write(to: dir.appending(path: name))
        }
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    private func backUp(_ version: String) {
        StoreBackup.backUpIfVersionChanged(storeURL: storeURL, version: version, defaults: settings.defaults)
    }

    private func backupFolders() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)) ?? []
    }

    @Test func copiesTheStoreWithItsSidecarsAndImages() throws {
        backUp("1.0 (1)")
        let folder = try #require(backupFolders().first)
        #expect(folder.lastPathComponent.hasSuffix("from unknown to 1.0 (1)"))
        for name in ["default.store", "default.store-wal", "default.store-shm", ".default_SUPPORT/_EXTERNAL_DATA/blob"] {
            let copy = try Data(contentsOf: folder.appending(path: name))
            #expect(copy == Data(name.utf8), "\(name)")
        }
    }

    @Test func onlyOncePerVersion() {
        backUp("1.0 (1)")
        backUp("1.0 (1)")
        #expect(backupFolders().count == 1)
        backUp("1.1 (2)")
        #expect(backupFolders().count == 2)
    }

    @Test func keepsTheNewestFive() {
        for build in 1...7 { backUp("1.\(build) (\(build))") }
        #expect(backupFolders().count == 5)
    }

    @Test func noStoreYetMeansNothingToCopy() throws {
        try FileManager.default.removeItem(at: storeURL)
        backUp("1.0 (1)")
        #expect(backupFolders().isEmpty)
        #expect(settings.defaults.string(forKey: "store.lastLaunchedVersion") == "1.0 (1)")
    }
}
