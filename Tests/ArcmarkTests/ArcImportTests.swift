import XCTest
@testable import ArcmarkCore

final class ArcImportTests: XCTestCase {

    // MARK: - Test Data Generation

    /// Creates minimal valid Arc JSON data for testing
    private func createArcJSON(
        spaces: [[String: Any?]],
        items: [[String: Any?]]
    ) throws -> Data {
        let arcData: [String: Any] = [
            "version": 1,
            "sidebar": [
                "containers": [
                    ["global": [:]], // Empty global container
                    [
                        "spaces": spaces,
                        "items": items,
                        "topAppsContainerIDs": []
                    ]
                ]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: arcData, options: [])
    }

    /// Creates a test space with optional title
    private func createSpace(id: String = "space1", title: String?, containerIDs: [String] = ["pinned", "container1"]) -> [String: Any?] {
        return [
            "id": id,
            "title": title,
            "containerIDs": containerIDs
        ]
    }

    /// Creates a test link item with optional title
    private func createLinkItem(
        id: String,
        parentID: String,
        savedTitle: String?,
        savedURL: String?
    ) -> [String: Any?] {
        return [
            "id": id,
            "title": savedTitle as Any, // Item-level title (not used for links)
            "parentID": parentID,
            "childrenIds": nil,
            "data": [
                "tab": [
                    "savedTitle": savedTitle as Any,
                    "savedURL": savedURL as Any,
                    "timeLastActiveAt": 1234567890.0
                ]
            ]
        ]
    }

    /// Creates a test folder item with optional title
    private func createFolderItem(
        id: String,
        parentID: String,
        title: String?,
        childrenIds: [String] = []
    ) -> [String: Any?] {
        return [
            "id": id,
            "title": title,
            "parentID": parentID,
            "childrenIds": childrenIds,
            "data": nil
        ]
    }

    // MARK: - Null Field Tests

    func testSpaceWithNullTitle() async throws {
        // Arrange: Create Arc data with a space that has null title
        let spaces = [
            createSpace(id: "space1", title: nil) // NULL title
        ]

        let items = [
            createLinkItem(
                id: "link1",
                parentID: "container1",
                savedTitle: "Example Link",
                savedURL: "https://example.com"
            )
        ]

        let jsonData = try createArcJSON(spaces: spaces, items: items)

        // Act: Write to temp file and import
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        try jsonData.write(to: tempURL)

        let service = ArcImportService.shared
        let result = await service.importFromArc(fileURL: tempURL)

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)

        // Assert: Import should succeed with fallback to "Untitled"
        switch result {
        case .success(let importResult):
            XCTAssertEqual(importResult.workspacesCreated, 1, "Should import workspace even with null title")
            XCTAssertEqual(importResult.workspaces[0].name, "Untitled", "Should use 'Untitled' for null space title")
            XCTAssertEqual(importResult.linksImported, 1, "Should import the link")
        case .failure(let error):
            XCTFail("Import should succeed with null space title, but failed with: \(error)")
        }
    }

    func testLinkWithNullSavedTitle() async throws {
        // Arrange: Create Arc data with a link that has null savedTitle
        let spaces = [
            createSpace(id: "space1", title: "My Space")
        ]

        let items = [
            createLinkItem(
                id: "link1",
                parentID: "container1",
                savedTitle: nil, // NULL savedTitle
                savedURL: "https://example.com"
            )
        ]

        let jsonData = try createArcJSON(spaces: spaces, items: items)

        // Act
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        try jsonData.write(to: tempURL)

        let service = ArcImportService.shared
        let result = await service.importFromArc(fileURL: tempURL)

        try? FileManager.default.removeItem(at: tempURL)

        // Assert: Import should succeed with fallback to "Untitled"
        switch result {
        case .success(let importResult):
            XCTAssertEqual(importResult.linksImported, 1, "Should import link even with null savedTitle")
            let firstNode = importResult.workspaces[0].nodes.first
            if case .link(let link) = firstNode {
                XCTAssertEqual(link.title, "Untitled", "Should use 'Untitled' for null savedTitle")
                XCTAssertEqual(link.url, "https://example.com")
            } else {
                XCTFail("Expected link node")
            }
        case .failure(let error):
            XCTFail("Import should succeed with null savedTitle, but failed with: \(error)")
        }
    }

    func testLinkWithNullSavedURL() async throws {
        // Arrange: Create Arc data with a link that has null savedURL
        let spaces = [
            createSpace(id: "space1", title: "My Space")
        ]

        let items = [
            createLinkItem(
                id: "link1",
                parentID: "container1",
                savedTitle: "Example Link",
                savedURL: nil // NULL savedURL
            )
        ]

        let jsonData = try createArcJSON(spaces: spaces, items: items)

        // Act
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        try jsonData.write(to: tempURL)

        let service = ArcImportService.shared
        let result = await service.importFromArc(fileURL: tempURL)

        try? FileManager.default.removeItem(at: tempURL)

        // Assert: Link with null URL should be skipped (invalid)
        switch result {
        case .success(let importResult):
            XCTAssertEqual(importResult.linksImported, 0, "Should skip link with null savedURL")
        case .failure(let error):
            XCTFail("Import should succeed but skip invalid link, but failed with: \(error)")
        }
    }

    func testFolderWithNullTitle() async throws {
        // Arrange: Create Arc data with a folder that has null title
        let spaces = [
            createSpace(id: "space1", title: "My Space")
        ]

        let items = [
            createFolderItem(
                id: "folder1",
                parentID: "container1",
                title: nil, // NULL title
                childrenIds: ["link1"]
            ),
            createLinkItem(
                id: "link1",
                parentID: "folder1",
                savedTitle: "Child Link",
                savedURL: "https://example.com"
            )
        ]

        let jsonData = try createArcJSON(spaces: spaces, items: items)

        // Act
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        try jsonData.write(to: tempURL)

        let service = ArcImportService.shared
        let result = await service.importFromArc(fileURL: tempURL)

        try? FileManager.default.removeItem(at: tempURL)

        // Assert: Import should succeed with fallback to "Untitled Folder"
        switch result {
        case .success(let importResult):
            XCTAssertEqual(importResult.foldersImported, 1, "Should import folder even with null title")
            let firstNode = importResult.workspaces[0].nodes.first
            if case .folder(let folder) = firstNode {
                XCTAssertEqual(folder.name, "Untitled Folder", "Should use 'Untitled Folder' for null folder title")
                XCTAssertEqual(folder.children.count, 1, "Should import child link")
            } else {
                XCTFail("Expected folder node")
            }
        case .failure(let error):
            XCTFail("Import should succeed with null folder title, but failed with: \(error)")
        }
    }

    func testMultipleItemsWithMixedNullFields() async throws {
        // Arrange: Real-world scenario with mix of valid and null fields
        let spaces = [
            createSpace(id: "space1", title: "Valid Space", containerIDs: ["pinned", "container1"]),
            createSpace(id: "space2", title: nil, containerIDs: ["pinned", "container2"]) // NULL title
        ]

        let items = [
            // Valid link in space 1
            createLinkItem(
                id: "link1",
                parentID: "container1",
                savedTitle: "Valid Link",
                savedURL: "https://valid.com"
            ),
            // Link with null title in space 1
            createLinkItem(
                id: "link2",
                parentID: "container1",
                savedTitle: nil, // NULL
                savedURL: "https://example.com"
            ),
            // Link with null URL (should be skipped)
            createLinkItem(
                id: "link3",
                parentID: "container1",
                savedTitle: "Bad Link",
                savedURL: nil // NULL - invalid
            ),
            // Valid folder in space 2
            createFolderItem(
                id: "folder1",
                parentID: "container2",
                title: "Valid Folder",
                childrenIds: ["link4"]
            ),
            // Link in folder with null title
            createLinkItem(
                id: "link4",
                parentID: "folder1",
                savedTitle: nil, // NULL
                savedURL: "https://nested.com"
            )
        ]

        let jsonData = try createArcJSON(spaces: spaces, items: items)

        // Act
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        try jsonData.write(to: tempURL)

        let service = ArcImportService.shared
        let result = await service.importFromArc(fileURL: tempURL)

        try? FileManager.default.removeItem(at: tempURL)

        // Assert
        switch result {
        case .success(let importResult):
            XCTAssertEqual(importResult.workspacesCreated, 2, "Should import both spaces")
            XCTAssertEqual(importResult.linksImported, 3, "Should import 3 valid links (skip link3 with null URL)")
            XCTAssertEqual(importResult.foldersImported, 1, "Should import 1 folder")

            // Verify space 2 has "Untitled" name
            if importResult.workspaces.count == 2 {
                XCTAssertEqual(importResult.workspaces[1].name, "Untitled", "Space 2 should use 'Untitled'")
            }
        case .failure(let error):
            XCTFail("Import should succeed with mixed null fields, but failed with: \(error)")
        }
    }

    // MARK: - childrenIds Traversal Tests

    func testChildrenIdsTraversal_FolderChildrenFoundViaChildrenIds() async throws {
        // Arc stores parent-child relationships in childrenIds. The parentID field
        // on the child may NOT match the folder's id — it can point to the container.
        let spaces = [
            createSpace(id: "space1", title: "Test Space")
        ]

        let items: [[String: Any?]] = [
            // Folder at root of pinned container — parentID points to container
            [
                "id": "folder1",
                "title": "My Folder",
                "parentID": "container1",
                "childrenIds": ["link-inside-folder"],
                "data": nil
            ],
            // Link that folder claims as child via childrenIds,
            // BUT whose parentID points to the container (not the folder)
            [
                "id": "link-inside-folder",
                "title": nil,
                "parentID": "container1",  // Mismatched! Points to container, not folder
                "childrenIds": [],
                "data": [
                    "tab": [
                        "savedTitle": "Nested Link",
                        "savedURL": "https://nested.example.com",
                        "timeLastActiveAt": 1234567890.0
                    ]
                ]
            ],
            // A link directly under the container
            [
                "id": "root-link",
                "title": nil,
                "parentID": "container1",
                "childrenIds": [],
                "data": [
                    "tab": [
                        "savedTitle": "Root Link",
                        "savedURL": "https://root.example.com",
                        "timeLastActiveAt": 1234567890.0
                    ]
                ]
            ]
        ]

        let jsonData = try createArcJSON(spaces: spaces, items: items)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try jsonData.write(to: tempURL)

        let service = ArcImportService.shared
        let result = await service.importFromArc(fileURL: tempURL)
        try? FileManager.default.removeItem(at: tempURL)

        switch result {
        case .success(let importResult):
            XCTAssertEqual(importResult.workspacesCreated, 1)
            XCTAssertEqual(importResult.linksImported, 2, "Should find both links")
            XCTAssertEqual(importResult.foldersImported, 1)

            // The folder should contain the nested link (found via childrenIds)
            let folderNode = importResult.workspaces[0].nodes.compactMap { node -> Folder? in
                if case .folder(let f) = node { return f }
                return nil
            }.first

            XCTAssertNotNil(folderNode, "Should have a folder")
            XCTAssertEqual(folderNode?.children.count, 1, "Folder should have 1 child via childrenIds")

            if case .link(let link) = folderNode?.children.first {
                XCTAssertEqual(link.title, "Nested Link")
                XCTAssertEqual(link.url, "https://nested.example.com")
            } else {
                XCTFail("Expected link inside folder")
            }
        case .failure(let error):
            XCTFail("Import failed: \(error)")
        }
    }

    func testChildrenIdsTraversal_DeepNesting() async throws {
        // Verify childrenIds traversal works for deeply nested structures
        let spaces = [
            createSpace(id: "space1", title: "Deep Space")
        ]

        let items: [[String: Any?]] = [
            // Top-level folder
            [
                "id": "folder-top",
                "title": "Top",
                "parentID": "container1",
                "childrenIds": ["folder-mid"],
                "data": nil
            ],
            // Mid-level folder (child of top, but parentID could differ)
            [
                "id": "folder-mid",
                "title": "Middle",
                "parentID": "container1",  // parentID mismatch
                "childrenIds": ["link-deep"],
                "data": nil
            ],
            // Deep link
            [
                "id": "link-deep",
                "title": nil,
                "parentID": "container1",  // parentID mismatch
                "childrenIds": [],
                "data": [
                    "tab": [
                        "savedTitle": "Deep Link",
                        "savedURL": "https://deep.example.com",
                        "timeLastActiveAt": 1234567890.0
                    ]
                ]
            ]
        ]

        let jsonData = try createArcJSON(spaces: spaces, items: items)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try jsonData.write(to: tempURL)

        let service = ArcImportService.shared
        let result = await service.importFromArc(fileURL: tempURL)
        try? FileManager.default.removeItem(at: tempURL)

        switch result {
        case .success(let importResult):
            XCTAssertEqual(importResult.linksImported, 1)
            XCTAssertEqual(importResult.foldersImported, 2)

            // Verify the nesting: Top > Middle > Deep Link
            guard let topFolder = importResult.workspaces[0].nodes.compactMap({ node -> Folder? in
                if case .folder(let f) = node { return f }
                return nil
            }).first else {
                XCTFail("Expected top folder"); return
            }

            XCTAssertEqual(topFolder.name, "Top")
            XCTAssertEqual(topFolder.children.count, 1)

            if case .folder(let midFolder) = topFolder.children.first {
                XCTAssertEqual(midFolder.name, "Middle")
                XCTAssertEqual(midFolder.children.count, 1)

                if case .link(let link) = midFolder.children.first {
                    XCTAssertEqual(link.title, "Deep Link")
                } else {
                    XCTFail("Expected link inside middle folder")
                }
            } else {
                XCTFail("Expected middle folder inside top folder")
            }
        case .failure(let error):
            XCTFail("Import failed: \(error)")
        }
    }

    func testChildrenIdsTraversal_PreservesOrdering() async throws {
        // childrenIds defines the canonical order — verify it's preserved
        let spaces = [
            createSpace(id: "space1", title: "Ordered Space")
        ]

        let items: [[String: Any?]] = [
            // Container item that exists in the items map
            [
                "id": "container1",
                "title": nil,
                "parentID": nil as String?,
                "childrenIds": ["link-c", "link-a", "link-b"],  // Specific order
                "data": nil
            ],
            [
                "id": "link-a",
                "title": nil,
                "parentID": "container1",
                "childrenIds": [],
                "data": ["tab": ["savedTitle": "Alpha", "savedURL": "https://a.com", "timeLastActiveAt": 1.0]]
            ],
            [
                "id": "link-b",
                "title": nil,
                "parentID": "container1",
                "childrenIds": [],
                "data": ["tab": ["savedTitle": "Beta", "savedURL": "https://b.com", "timeLastActiveAt": 1.0]]
            ],
            [
                "id": "link-c",
                "title": nil,
                "parentID": "container1",
                "childrenIds": [],
                "data": ["tab": ["savedTitle": "Charlie", "savedURL": "https://c.com", "timeLastActiveAt": 1.0]]
            ]
        ]

        let jsonData = try createArcJSON(spaces: spaces, items: items)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try jsonData.write(to: tempURL)

        let service = ArcImportService.shared
        let result = await service.importFromArc(fileURL: tempURL)
        try? FileManager.default.removeItem(at: tempURL)

        switch result {
        case .success(let importResult):
            let nodes = importResult.workspaces[0].nodes
            XCTAssertEqual(nodes.count, 3)

            // Verify order matches childrenIds: C, A, B
            if case .link(let first) = nodes[0] { XCTAssertEqual(first.title, "Charlie") }
            else { XCTFail("Expected link at index 0") }

            if case .link(let second) = nodes[1] { XCTAssertEqual(second.title, "Alpha") }
            else { XCTFail("Expected link at index 1") }

            if case .link(let third) = nodes[2] { XCTAssertEqual(third.title, "Beta") }
            else { XCTFail("Expected link at index 2") }
        case .failure(let error):
            XCTFail("Import failed: \(error)")
        }
    }

    func testParentIDFallback_WhenContainerNotInItems() async throws {
        // When the pinned container ID doesn't exist as an item in the map,
        // the importer should fall back to parentID-based filtering
        let spaces = [
            createSpace(id: "space1", title: "Fallback Space")
        ]

        // No item has id == "container1", so fallback to parentID matching
        let items = [
            createLinkItem(
                id: "link1",
                parentID: "container1",
                savedTitle: "Link One",
                savedURL: "https://one.com"
            ),
            createLinkItem(
                id: "link2",
                parentID: "container1",
                savedTitle: "Link Two",
                savedURL: "https://two.com"
            )
        ]

        let jsonData = try createArcJSON(spaces: spaces, items: items)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try jsonData.write(to: tempURL)

        let service = ArcImportService.shared
        let result = await service.importFromArc(fileURL: tempURL)
        try? FileManager.default.removeItem(at: tempURL)

        switch result {
        case .success(let importResult):
            XCTAssertEqual(importResult.linksImported, 2, "Fallback should find both links via parentID")
        case .failure(let error):
            XCTFail("Import failed: \(error)")
        }
    }

    func testContainerIDs_UnpinnedBeforePinned() async throws {
        // Real Arc data puts "unpinned" BEFORE "pinned" in containerIDs
        let spaces = [
            createSpace(
                id: "space1",
                title: "Real Format",
                containerIDs: ["unpinned", "unpinned-ctr", "pinned", "pinned-ctr"]
            )
        ]

        let items: [[String: Any?]] = [
            [
                "id": "pinned-ctr",
                "title": nil,
                "parentID": nil as String?,
                "childrenIds": ["pinned-link"],
                "data": nil
            ],
            [
                "id": "pinned-link",
                "title": nil,
                "parentID": "pinned-ctr",
                "childrenIds": [],
                "data": ["tab": ["savedTitle": "Pinned", "savedURL": "https://pinned.com", "timeLastActiveAt": 1.0]]
            ],
            // Unpinned item should NOT be imported
            [
                "id": "unpinned-link",
                "title": nil,
                "parentID": "unpinned-ctr",
                "childrenIds": [],
                "data": ["tab": ["savedTitle": "Unpinned", "savedURL": "https://unpinned.com", "timeLastActiveAt": 1.0]]
            ]
        ]

        let jsonData = try createArcJSON(spaces: spaces, items: items)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try jsonData.write(to: tempURL)

        let service = ArcImportService.shared
        let result = await service.importFromArc(fileURL: tempURL)
        try? FileManager.default.removeItem(at: tempURL)

        switch result {
        case .success(let importResult):
            XCTAssertEqual(importResult.linksImported, 1, "Should only import pinned link")
            if case .link(let link) = importResult.workspaces[0].nodes.first {
                XCTAssertEqual(link.title, "Pinned")
            } else {
                XCTFail("Expected pinned link")
            }
        case .failure(let error):
            XCTFail("Import failed: \(error)")
        }
    }

    // MARK: - Integration Test with Real File

    /// Test with the actual user file if it exists
    func testRealUserFile() async throws {
        let fileURL = URL(fileURLWithPath: "/Users/ahmedsulaiman/Downloads/StorableSidebar.json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("⚠️  Skipping real file test - file not found at \(fileURL.path)")
            return
        }

        let service = ArcImportService.shared
        let result = await service.importFromArc(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            print("✅ Successfully imported user's file!")
            print("   Workspaces: \(importResult.workspacesCreated)")
            print("   Links: \(importResult.linksImported)")
            print("   Folders: \(importResult.foldersImported)")

            XCTAssertGreaterThan(importResult.workspacesCreated, 0, "Should import at least one workspace")
            XCTAssertGreaterThan(importResult.linksImported, 0, "Should import at least one link")
        case .failure(let error):
            XCTFail("Failed to import user's file: \(error)")
        }
    }

    // MARK: - Regression Test for User's File

    func testUserFileWithNullSavedTitle() async throws {
        // This test simulates the exact issue from the user's StorableSidebar.json
        // where item D5547566-F700-4C85-BB55-DEC3AD41D2A1 has savedTitle: null

        let spaces = [
            createSpace(id: "space1", title: "User Space")
        ]

        let items = [
            // Normal link before the problematic one
            createLinkItem(
                id: "link-before",
                parentID: "container1",
                savedTitle: "Normal Link",
                savedURL: "https://normal.com"
            ),
            // The problematic link from the user's file
            createLinkItem(
                id: "D5547566-F700-4C85-BB55-DEC3AD41D2A1",
                parentID: "container1",
                savedTitle: nil, // THIS caused the entire import to fail
                savedURL: "https://problematic.com"
            ),
            // Normal link after the problematic one
            createLinkItem(
                id: "link-after",
                parentID: "container1",
                savedTitle: "Another Link",
                savedURL: "https://another.com"
            )
        ]

        let jsonData = try createArcJSON(spaces: spaces, items: items)

        // Act
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        try jsonData.write(to: tempURL)

        let service = ArcImportService.shared
        let result = await service.importFromArc(fileURL: tempURL)

        try? FileManager.default.removeItem(at: tempURL)

        // Assert: BEFORE the fix, this would fail with .noDataContainer
        // AFTER the fix, it should successfully import all 3 links
        switch result {
        case .success(let importResult):
            XCTAssertEqual(importResult.workspacesCreated, 1, "Should create workspace")
            XCTAssertEqual(importResult.linksImported, 3, "Should import all 3 links despite null savedTitle")

            // Verify the problematic link uses "Untitled"
            let nodes = importResult.workspaces[0].nodes
            XCTAssertEqual(nodes.count, 3, "Should have 3 link nodes")

            // Find the problematic link by URL since order may vary
            let problematicLink = nodes.compactMap { node -> Link? in
                if case .link(let link) = node, link.url == "https://problematic.com" {
                    return link
                }
                return nil
            }.first

            XCTAssertNotNil(problematicLink, "Should find problematic link")
            XCTAssertEqual(problematicLink?.title, "Untitled", "Problematic link should use 'Untitled'")
        case .failure(let error):
            XCTFail("Import should succeed after fix, but failed with: \(error)")
        }
    }
}
