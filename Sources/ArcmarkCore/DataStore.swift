import Foundation

final class DataStore {
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let dataURL: URL

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

        do {
            let data = try Data(contentsOf: dataURL)
            let decoder = JSONDecoder()
            let state = try decoder.decode(AppState.self, from: data)
            return state
        } catch {
            let fallback = Self.defaultState()
            save(fallback)
            return fallback
        }
    }

    func save(_ state: AppState) {
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
