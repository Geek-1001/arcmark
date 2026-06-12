import Foundation
import os

final class DataStore {
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let dataURL: URL
    private let logger = Logger(subsystem: "com.arcmark.app", category: "store")
    private var hasBackedUpThisSession = false
    private let backupKeepCount = 10
    private let backupTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss-SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseDirectory = appSupport.appendingPathComponent("Arcmark", isDirectory: true)
        }
        self.dataURL = self.baseDirectory.appendingPathComponent("data.json")
    }

    func load() -> AppState {
        ensureDirectories()
        guard fileManager.fileExists(atPath: dataURL.path) else {
            let defaultState = Self.defaultState()
            save(defaultState)
            return defaultState
        }

        backupDataFileIfNeeded()

        do {
            let data = try Data(contentsOf: dataURL)
            let decoder = JSONDecoder()
            let state = try decoder.decode(AppState.self, from: data)
            return state
        } catch {
            // Leave data.json untouched so a newer-schema or corrupt file can be
            // recovered (e.g. by re-upgrading); it is only overwritten on the
            // first actual mutation, and the pre-decode backup exists by then.
            logger.error("Failed to decode data.json; leaving file untouched: \(error.localizedDescription, privacy: .public)")
            return Self.defaultState()
        }
    }

    func save(_ state: AppState) {
        backupDataFileIfNeeded()
        ensureDirectories()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: dataURL, options: [.atomic])
        } catch {
            // Failing silently to avoid crashing; this can be surfaced later in a UI.
        }
    }

    func iconsDirectory() -> URL {
        let iconsURL = baseDirectory.appendingPathComponent("Icons", isDirectory: true)
        if !fileManager.fileExists(atPath: iconsURL.path) {
            try? fileManager.createDirectory(at: iconsURL, withIntermediateDirectories: true)
        }
        return iconsURL
    }

    func notesDirectory() -> URL {
        let notesURL = baseDirectory.appendingPathComponent("Notes", isDirectory: true)
        if !fileManager.fileExists(atPath: notesURL.path) {
            try? fileManager.createDirectory(at: notesURL, withIntermediateDirectories: true)
        }
        return notesURL
    }

    func noteFileURL(for id: UUID) -> URL {
        notesDirectory().appendingPathComponent("\(id.uuidString).md")
    }

    func agentEndpointFileURL() -> URL {
        baseDirectory.appendingPathComponent("agent-endpoint.json")
    }

    /// Copies data.json into `Backups/` once per session, before this process
    /// first writes to it. Skips the copy when the file is byte-identical to the
    /// newest existing backup so repeated relaunches don't rotate away the last
    /// good backup. Keeps the `backupKeepCount` most recent backups.
    private func backupDataFileIfNeeded() {
        guard !hasBackedUpThisSession else { return }
        hasBackedUpThisSession = true

        guard fileManager.fileExists(atPath: dataURL.path) else { return }

        do {
            let data = try Data(contentsOf: dataURL)
            let backupsURL = backupsDirectory()
            if let newest = sortedBackupURLs(in: backupsURL).last,
               let newestData = try? Data(contentsOf: newest),
               newestData == data {
                return
            }
            let timestamp = backupTimestampFormatter.string(from: Date())
            let backupURL = backupsURL.appendingPathComponent("data-\(timestamp).json")
            try data.write(to: backupURL, options: [.atomic])
            pruneBackups(in: backupsURL)
        } catch {
            logger.error("Failed to back up data.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func backupsDirectory() -> URL {
        let backupsURL = baseDirectory.appendingPathComponent("Backups", isDirectory: true)
        if !fileManager.fileExists(atPath: backupsURL.path) {
            try? fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        }
        return backupsURL
    }

    /// Backup filenames are fixed-width UTC timestamps, so lexicographic order
    /// equals chronological order.
    private func sortedBackupURLs(in backupsURL: URL) -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix("data-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func pruneBackups(in backupsURL: URL) {
        let backups = sortedBackupURLs(in: backupsURL)
        guard backups.count > backupKeepCount else { return }
        for url in backups.dropLast(backupKeepCount) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func ensureDirectories() {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    static func defaultState() -> AppState {
        let workspace = Workspace(
            id: UUID(),
            name: "Inbox",
            colorId: .defaultColor(),
            items: []
        )
        return AppState(schemaVersion: 1, workspaces: [workspace], selectedWorkspaceId: workspace.id, isSettingsSelected: false)
    }
}
