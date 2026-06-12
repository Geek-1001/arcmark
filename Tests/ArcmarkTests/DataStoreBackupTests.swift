import XCTest
@testable import ArcmarkCore

final class DataStoreBackupTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeState(name: String) -> AppState {
        let workspace = Workspace(id: UUID(), name: name, colorId: .defaultColor(), items: [])
        return AppState(schemaVersion: 1, workspaces: [workspace], selectedWorkspaceId: workspace.id, isSettingsSelected: false)
    }

    private func dataURL(in directory: URL) -> URL {
        directory.appendingPathComponent("data.json")
    }

    private func backupsDirectory(in directory: URL) -> URL {
        directory.appendingPathComponent("Backups")
    }

    private func backupURLs(in directory: URL) -> [URL] {
        let backups = backupsDirectory(in: directory)
        let contents = (try? FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix("data-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func testLoadCreatesBackup() throws {
        let directory = makeTempDirectory()
        DataStore(baseDirectory: directory).save(makeState(name: "A"))

        _ = DataStore(baseDirectory: directory).load()

        let backups = backupURLs(in: directory)
        XCTAssertEqual(backups.count, 1)
        let backupData = try Data(contentsOf: backups[0])
        let liveData = try Data(contentsOf: dataURL(in: directory))
        XCTAssertEqual(backupData, liveData)
    }

    func testRelaunchWithUnchangedDataDoesNotDuplicateBackup() {
        let directory = makeTempDirectory()
        DataStore(baseDirectory: directory).save(makeState(name: "A"))

        _ = DataStore(baseDirectory: directory).load()
        _ = DataStore(baseDirectory: directory).load()

        XCTAssertEqual(backupURLs(in: directory).count, 1)
    }

    func testBackupRotationKeepsTenMostRecent() {
        let directory = makeTempDirectory()
        var allNames = Set<String>()

        // Each fresh instance backs up the previous on-disk state before writing
        // a distinct new one; the final load() backs up the 12th state.
        for index in 0..<12 {
            DataStore(baseDirectory: directory).save(makeState(name: "Workspace \(index)"))
            backupURLs(in: directory).forEach { allNames.insert($0.lastPathComponent) }
            Thread.sleep(forTimeInterval: 0.005)
        }
        _ = DataStore(baseDirectory: directory).load()
        backupURLs(in: directory).forEach { allNames.insert($0.lastPathComponent) }

        XCTAssertEqual(allNames.count, 12)
        let remaining = backupURLs(in: directory).map(\.lastPathComponent)
        XCTAssertEqual(remaining.count, 10)
        XCTAssertEqual(Set(remaining), Set(allNames.sorted().suffix(10)))
    }

    func testSaveWithoutPriorLoadStillBacksUp() throws {
        let directory = makeTempDirectory()
        DataStore(baseDirectory: directory).save(makeState(name: "A"))
        let originalData = try Data(contentsOf: dataURL(in: directory))

        DataStore(baseDirectory: directory).save(makeState(name: "B"))

        let backups = backupURLs(in: directory)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0]), originalData)
    }

    func testFirstLaunchCreatesNoBackup() {
        let directory = makeTempDirectory()

        _ = DataStore(baseDirectory: directory).load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: dataURL(in: directory).path))
        XCTAssertTrue(backupURLs(in: directory).isEmpty)
    }
}
