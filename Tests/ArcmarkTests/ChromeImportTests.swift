import Testing
import Foundation
@testable import ArcmarkCore

@Suite("Chrome Import Tests")
struct ChromeImportTests {

    // MARK: - Helpers

    /// Create a minimal valid Chrome bookmarks HTML file
    private func createBookmarksHTML(body: String) -> String {
        return """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
        \(body)
        </DL><p>
        """
    }

    /// Write HTML string to a temp file and return its URL
    private func writeTempFile(_ content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_bookmarks_\(UUID().uuidString).html")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Clean up temp file
    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Basic Link Parsing

    @Test("Basic link parsing extracts URL and title")
    func testBasicLinkParsing() async throws {
        let html = createBookmarksHTML(body: """
            <DT><H3>Bookmarks bar</H3>
            <DL><p>
                <DT><A HREF="https://example.com" ADD_DATE="1234567890">Example Site</A>
            </DL><p>
        """)

        let fileURL = try writeTempFile(html)
        defer { cleanup(fileURL) }

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            #expect(importResult.linksImported == 1)
            #expect(importResult.foldersImported == 0)

            let nodes = importResult.workspace.nodes
            #expect(nodes.count == 1)

            if case .link(let link) = nodes[0] {
                #expect(link.title == "Example Site")
                #expect(link.url == "https://example.com")
            } else {
                Issue.record("Expected a link node")
            }
        case .failure(let error):
            Issue.record("Import should succeed: \(error)")
        }
    }

    // MARK: - Folder with Nested Links

    @Test("Folder with nested links preserves hierarchy")
    func testFolderWithNestedLinks() async throws {
        let html = createBookmarksHTML(body: """
            <DT><H3>Bookmarks bar</H3>
            <DL><p>
                <DT><H3>My Folder</H3>
                <DL><p>
                    <DT><A HREF="https://one.com">One</A>
                    <DT><A HREF="https://two.com">Two</A>
                </DL><p>
            </DL><p>
        """)

        let fileURL = try writeTempFile(html)
        defer { cleanup(fileURL) }

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            #expect(importResult.linksImported == 2)
            #expect(importResult.foldersImported == 1)

            let nodes = importResult.workspace.nodes
            #expect(nodes.count == 1) // One folder

            if case .folder(let folder) = nodes[0] {
                #expect(folder.name == "My Folder")
                #expect(folder.children.count == 2)
            } else {
                Issue.record("Expected a folder node")
            }
        case .failure(let error):
            Issue.record("Import should succeed: \(error)")
        }
    }

    // MARK: - Deep Nesting

    @Test("Deep nesting (3+ levels) is preserved")
    func testDeepNesting() async throws {
        let html = createBookmarksHTML(body: """
            <DT><H3>Bookmarks bar</H3>
            <DL><p>
                <DT><H3>Level 1</H3>
                <DL><p>
                    <DT><H3>Level 2</H3>
                    <DL><p>
                        <DT><H3>Level 3</H3>
                        <DL><p>
                            <DT><A HREF="https://deep.com">Deep Link</A>
                        </DL><p>
                    </DL><p>
                </DL><p>
            </DL><p>
        """)

        let fileURL = try writeTempFile(html)
        defer { cleanup(fileURL) }

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            #expect(importResult.linksImported == 1)
            #expect(importResult.foldersImported == 3)

            // Navigate down the hierarchy
            if case .folder(let l1) = importResult.workspace.nodes[0] {
                #expect(l1.name == "Level 1")
                if case .folder(let l2) = l1.children[0] {
                    #expect(l2.name == "Level 2")
                    if case .folder(let l3) = l2.children[0] {
                        #expect(l3.name == "Level 3")
                        if case .link(let link) = l3.children[0] {
                            #expect(link.url == "https://deep.com")
                        } else {
                            Issue.record("Expected link at level 3")
                        }
                    } else {
                        Issue.record("Expected folder at level 2")
                    }
                } else {
                    Issue.record("Expected folder at level 1")
                }
            } else {
                Issue.record("Expected folder at root")
            }
        case .failure(let error):
            Issue.record("Import should succeed: \(error)")
        }
    }

    // MARK: - Top-Level Folders Flattened

    @Test("Top-level Chrome folders are flattened into root")
    func testTopLevelFoldersFlattened() async throws {
        let html = createBookmarksHTML(body: """
            <DT><H3>Bookmarks bar</H3>
            <DL><p>
                <DT><A HREF="https://bar.com">Bar Link</A>
            </DL><p>
            <DT><H3>Other bookmarks</H3>
            <DL><p>
                <DT><A HREF="https://other.com">Other Link</A>
            </DL><p>
        """)

        let fileURL = try writeTempFile(html)
        defer { cleanup(fileURL) }

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            #expect(importResult.linksImported == 2)
            // Both top-level folders flattened, so no folders in output
            #expect(importResult.foldersImported == 0)

            let nodes = importResult.workspace.nodes
            #expect(nodes.count == 2) // Both links at root level

            if case .link(let link1) = nodes[0] {
                #expect(link1.url == "https://bar.com")
            }
            if case .link(let link2) = nodes[1] {
                #expect(link2.url == "https://other.com")
            }
        case .failure(let error):
            Issue.record("Import should succeed: \(error)")
        }
    }

    // MARK: - Empty Bookmarks File

    @Test("Empty bookmarks file returns noBookmarksFound error")
    func testEmptyBookmarksFile() async throws {
        let html = createBookmarksHTML(body: "")

        let fileURL = try writeTempFile(html)
        defer { cleanup(fileURL) }

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fileURL)

        switch result {
        case .success:
            Issue.record("Should fail with noBookmarksFound")
        case .failure(let error):
            #expect(error == .noBookmarksFound)
        }
    }

    // MARK: - Invalid HTML File

    @Test("Invalid/non-HTML file returns invalidHTML error")
    func testInvalidHTMLFile() async throws {
        let content = "This is just plain text, not a bookmark file."

        let fileURL = try writeTempFile(content)
        defer { cleanup(fileURL) }

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fileURL)

        switch result {
        case .success:
            Issue.record("Should fail with invalidHTML")
        case .failure(let error):
            #expect(error == .invalidHTML)
        }
    }

    // MARK: - HTML Entities Decoded

    @Test("HTML entities are decoded in titles")
    func testHTMLEntitiesDecoded() async throws {
        let html = createBookmarksHTML(body: """
            <DT><H3>Bookmarks bar</H3>
            <DL><p>
                <DT><A HREF="https://example.com">Tom &amp; Jerry&#39;s &lt;Site&gt;</A>
            </DL><p>
        """)

        let fileURL = try writeTempFile(html)
        defer { cleanup(fileURL) }

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            if case .link(let link) = importResult.workspace.nodes[0] {
                #expect(link.title == "Tom & Jerry's <Site>")
            } else {
                Issue.record("Expected a link node")
            }
        case .failure(let error):
            Issue.record("Import should succeed: \(error)")
        }
    }

    // MARK: - Order Preserved

    @Test("Links appear in file order")
    func testOrderPreserved() async throws {
        let html = createBookmarksHTML(body: """
            <DT><H3>Bookmarks bar</H3>
            <DL><p>
                <DT><A HREF="https://first.com">First</A>
                <DT><A HREF="https://second.com">Second</A>
                <DT><A HREF="https://third.com">Third</A>
            </DL><p>
        """)

        let fileURL = try writeTempFile(html)
        defer { cleanup(fileURL) }

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            let nodes = importResult.workspace.nodes
            #expect(nodes.count == 3)

            if case .link(let l1) = nodes[0] { #expect(l1.title == "First") }
            if case .link(let l2) = nodes[1] { #expect(l2.title == "Second") }
            if case .link(let l3) = nodes[2] { #expect(l3.title == "Third") }
        case .failure(let error):
            Issue.record("Import should succeed: \(error)")
        }
    }

    // MARK: - Empty Title

    @Test("Link with empty title uses Untitled")
    func testEmptyTitleUsesUntitled() async throws {
        let html = createBookmarksHTML(body: """
            <DT><H3>Bookmarks bar</H3>
            <DL><p>
                <DT><A HREF="https://example.com"></A>
            </DL><p>
        """)

        let fileURL = try writeTempFile(html)
        defer { cleanup(fileURL) }

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            if case .link(let link) = importResult.workspace.nodes[0] {
                #expect(link.title == "Untitled")
            } else {
                Issue.record("Expected a link node")
            }
        case .failure(let error):
            Issue.record("Import should succeed: \(error)")
        }
    }

    // MARK: - Workspace Properties

    @Test("Workspace created with correct name and colorId")
    func testWorkspaceProperties() async throws {
        let html = createBookmarksHTML(body: """
            <DT><H3>Bookmarks bar</H3>
            <DL><p>
                <DT><A HREF="https://example.com">Example</A>
            </DL><p>
        """)

        let fileURL = try writeTempFile(html)
        defer { cleanup(fileURL) }

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            #expect(importResult.workspace.name == "Imported Bookmarks")
            #expect(importResult.workspace.colorId == .ember)
        case .failure(let error):
            Issue.record("Import should succeed: \(error)")
        }
    }

    // MARK: - File Not Found

    @Test("File not found returns fileNotFound error")
    func testFileNotFound() async throws {
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent_bookmarks_\(UUID().uuidString).html")

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fakeURL)

        switch result {
        case .success:
            Issue.record("Should fail with fileNotFound")
        case .failure(let error):
            #expect(error == .fileNotFound)
        }
    }

    // MARK: - Invalid URLs Skipped

    @Test("javascript: and chrome:// URLs are skipped")
    func testInvalidURLsSkipped() async throws {
        let html = createBookmarksHTML(body: """
            <DT><H3>Bookmarks bar</H3>
            <DL><p>
                <DT><A HREF="javascript:void(0)">JS Link</A>
                <DT><A HREF="chrome://settings">Chrome Settings</A>
                <DT><A HREF="">Empty URL</A>
                <DT><A HREF="https://valid.com">Valid Link</A>
            </DL><p>
        """)

        let fileURL = try writeTempFile(html)
        defer { cleanup(fileURL) }

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            #expect(importResult.linksImported == 1)
            if case .link(let link) = importResult.workspace.nodes[0] {
                #expect(link.url == "https://valid.com")
            }
        case .failure(let error):
            Issue.record("Import should succeed: \(error)")
        }
    }

    // MARK: - HTML Entities in Folder Names

    @Test("HTML entities decoded in folder names")
    func testHTMLEntitiesInFolderNames() async throws {
        let html = createBookmarksHTML(body: """
            <DT><H3>Bookmarks bar</H3>
            <DL><p>
                <DT><H3>Tom &amp; Jerry&#39;s Folder</H3>
                <DL><p>
                    <DT><A HREF="https://example.com">Link</A>
                </DL><p>
            </DL><p>
        """)

        let fileURL = try writeTempFile(html)
        defer { cleanup(fileURL) }

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            if case .folder(let folder) = importResult.workspace.nodes[0] {
                #expect(folder.name == "Tom & Jerry's Folder")
            } else {
                Issue.record("Expected a folder node")
            }
        case .failure(let error):
            Issue.record("Import should succeed: \(error)")
        }
    }

    // MARK: - HTML Entity Double-Decoding Prevention

    @Test("HTML entities with escaped ampersands are not double-decoded")
    func testHTMLEntitiesNotDoubleDeccoded() async throws {
        let html = createBookmarksHTML(body: """
            <DT><H3>Bookmarks bar</H3>
            <DL><p>
                <DT><A HREF="https://example.com">A &amp;lt; B</A>
                <DT><A HREF="https://example2.com">Use &amp;amp; for ampersands</A>
            </DL><p>
        """)

        let fileURL = try writeTempFile(html)
        defer { cleanup(fileURL) }

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            let nodes = importResult.workspace.nodes
            #expect(nodes.count == 2)

            if case .link(let link1) = nodes[0] {
                #expect(link1.title == "A &lt; B")
            } else {
                Issue.record("Expected a link node")
            }

            if case .link(let link2) = nodes[1] {
                #expect(link2.title == "Use &amp; for ampersands")
            } else {
                Issue.record("Expected a link node")
            }
        case .failure(let error):
            Issue.record("Import should succeed: \(error)")
        }
    }

    // MARK: - Mixed Content

    @Test("Mixed folders and links at same level")
    func testMixedContent() async throws {
        let html = createBookmarksHTML(body: """
            <DT><H3>Bookmarks bar</H3>
            <DL><p>
                <DT><A HREF="https://standalone.com">Standalone</A>
                <DT><H3>My Folder</H3>
                <DL><p>
                    <DT><A HREF="https://nested.com">Nested</A>
                </DL><p>
                <DT><A HREF="https://another.com">Another</A>
            </DL><p>
        """)

        let fileURL = try writeTempFile(html)
        defer { cleanup(fileURL) }

        let result = await ChromeImportService.shared.importFromChrome(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            #expect(importResult.linksImported == 3)
            #expect(importResult.foldersImported == 1)

            let nodes = importResult.workspace.nodes
            #expect(nodes.count == 3)

            if case .link(let l1) = nodes[0] { #expect(l1.title == "Standalone") }
            if case .folder(let f) = nodes[1] { #expect(f.name == "My Folder") }
            if case .link(let l2) = nodes[2] { #expect(l2.title == "Another") }
        case .failure(let error):
            Issue.record("Import should succeed: \(error)")
        }
    }
}

// MARK: - Equatable for ChromeImportError (for test assertions)

extension ChromeImportError: Equatable {
    public static func == (lhs: ChromeImportError, rhs: ChromeImportError) -> Bool {
        switch (lhs, rhs) {
        case (.fileNotFound, .fileNotFound): return true
        case (.invalidHTML, .invalidHTML): return true
        case (.noBookmarksFound, .noBookmarksFound): return true
        case (.parsingFailed(let a), .parsingFailed(let b)): return a == b
        default: return false
        }
    }
}
