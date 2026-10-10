import Foundation

/// Copies the SwiftData store aside the first time a new app version launches,
/// before the container opens (and possibly migrates) it. Keeps the newest few.
enum StoreBackup {
    private static let lastVersionKey = "store.lastLaunchedVersion"
    private static let keep = 5

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    static func folder(for storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appending(path: "Backups", directoryHint: .isDirectory)
    }

    static func backUpIfVersionChanged(storeURL: URL, version: String = appVersion, defaults: UserDefaults = .standard) {
        let previous = defaults.string(forKey: lastVersionKey)
        guard previous != version else { return }
        // Recorded before opening the store, so a build that fails to open it
        // doesn't take a fresh backup per launch and rotate the good ones out.
        defaults.set(version, forKey: lastVersionKey)

        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return }

        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let name = "\(stamp) from \(previous ?? "unknown") to \(version)"
        let dest = folder(for: storeURL).appending(path: name, directoryHint: .isDirectory)

        // SQLite needs the -wal/-shm files too, and external-storage blobs
        // live in the hidden ".<store>_SUPPORT" folder next to it.
        let dir = storeURL.deletingLastPathComponent()
        let base = storeURL.lastPathComponent
        let support = "." + storeURL.deletingPathExtension().lastPathComponent + "_SUPPORT"
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for file in [base, base + "-wal", base + "-shm", support] {
                let src = dir.appending(path: file)
                if fm.fileExists(atPath: src.path) {
                    try fm.copyItem(at: src, to: dest.appending(path: file))
                }
            }
            print("[store] backed up to \(dest.path)")
        } catch {
            print("[store] backup failed: \(error)")
        }
        prune(folder(for: storeURL))
    }

    private static func prune(_ folder: URL) {
        let fm = FileManager.default
        let all = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        // Names start with an ISO timestamp, so name order is age order.
        let sorted = all.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for old in sorted.dropLast(keep) { try? fm.removeItem(at: old) }
    }
}
