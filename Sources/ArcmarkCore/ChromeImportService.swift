import Foundation

// MARK: - Chrome Import Result

/// Result of a Chrome bookmark import operation
struct ChromeImportResult: Sendable {
    let workspace: ImportWorkspace
    let linksImported: Int
    let foldersImported: Int
}

// MARK: - Chrome Import Errors

/// Errors that can occur during Chrome bookmark import
enum ChromeImportError: Error {
    case fileNotFound
    case invalidHTML
    case noBookmarksFound
    case parsingFailed(String)
}

extension ChromeImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "The selected file could not be found."
        case .invalidHTML:
            return "The selected file is not a valid Chrome bookmarks HTML file."
        case .noBookmarksFound:
            return "No bookmarks were found in the file."
        case .parsingFailed(let detail):
            return "Failed to parse Chrome bookmarks: \(detail)"
        }
    }
}

// MARK: - Chrome Import Service

final class ChromeImportService: Sendable {
    static let shared = ChromeImportService()

    private init() {}

    /// Import bookmarks from a Chrome bookmarks HTML file
    /// - Parameter fileURL: URL to the exported Chrome bookmarks HTML file
    /// - Returns: Result containing import statistics or error
    func importFromChrome(fileURL: URL) async -> Result<ChromeImportResult, ChromeImportError> {
        await Task.yield()

        return await Task.detached {
            do {
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    return .failure(.fileNotFound)
                }

                let content = try String(contentsOf: fileURL, encoding: .utf8)

                // Validate this is a Netscape bookmark file
                guard content.contains("NETSCAPE-Bookmark-file-1") || content.contains("<DL>") || content.contains("<dl>") else {
                    return .failure(.invalidHTML)
                }

                let nodes = try self.parseBookmarksHTML(content)

                guard !nodes.isEmpty else {
                    return .failure(.noBookmarksFound)
                }

                let stats = self.countNodes(nodes)

                let workspace = ImportWorkspace(
                    name: "Chrome Bookmarks",
                    colorId: .ember,
                    nodes: nodes
                )

                let result = ChromeImportResult(
                    workspace: workspace,
                    linksImported: stats.links,
                    foldersImported: stats.folders
                )

                return .success(result)

            } catch let error as ChromeImportError {
                return .failure(error)
            } catch {
                return .failure(.parsingFailed(error.localizedDescription))
            }
        }.value
    }

    // MARK: - Private Methods

    /// Parse Chrome bookmarks HTML using a line-by-line scanner with stack-based nesting
    private func parseBookmarksHTML(_ content: String) throws -> [Node] {
        // Regex patterns for matching bookmark elements
        let folderPattern = try NSRegularExpression(pattern: "<DT><H3[^>]*>(.*?)</H3>", options: .caseInsensitive)
        let linkPattern = try NSRegularExpression(pattern: "<DT><A\\s+HREF=\"([^\"]*)\"[^>]*>(.*?)</A>", options: .caseInsensitive)
        let dlOpenPattern = try NSRegularExpression(pattern: "<DL>", options: .caseInsensitive)
        let dlClosePattern = try NSRegularExpression(pattern: "</DL>", options: .caseInsensitive)

        // Stack-based parsing: each level is an array of nodes being built
        var stack: [[Node]] = [[]]
        // Track folder names so we can assign them when popping
        var folderNameStack: [String] = []
        // Track whether the last item was a folder header (next <DL> belongs to it)
        var pendingFolder = false
        // Track top-level folder names to flatten them
        let topLevelFolderNames: Set<String> = ["Bookmarks bar", "Other bookmarks", "Mobile bookmarks", "Bookmarks Bar"]

        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let range = NSRange(trimmed.startIndex..., in: trimmed)

            // Check for folder header: <DT><H3...>Name</H3>
            if let folderMatch = folderPattern.firstMatch(in: trimmed, range: range) {
                let nameRange = Range(folderMatch.range(at: 1), in: trimmed)!
                let folderName = decodeHTMLEntities(String(trimmed[nameRange]))
                folderNameStack.append(folderName)
                pendingFolder = true
                continue
            }

            // Check for link: <DT><A HREF="url"...>Title</A>
            if let linkMatch = linkPattern.firstMatch(in: trimmed, range: range) {
                let urlRange = Range(linkMatch.range(at: 1), in: trimmed)!
                let titleRange = Range(linkMatch.range(at: 2), in: trimmed)!
                let urlString = String(trimmed[urlRange])
                var title = decodeHTMLEntities(String(trimmed[titleRange]))

                if title.isEmpty {
                    title = "Untitled"
                }

                // Skip invalid URLs
                if urlString.isEmpty ||
                    urlString.hasPrefix("javascript:") ||
                    urlString.hasPrefix("chrome://") ||
                    URL(string: urlString) == nil {
                    continue
                }

                let link = Link(
                    id: UUID(),
                    title: title,
                    url: urlString,
                    faviconPath: nil
                )
                stack[stack.count - 1].append(.link(link))
                continue
            }

            // Check for <DL> - begin folder contents
            if dlOpenPattern.firstMatch(in: trimmed, range: range) != nil {
                if pendingFolder {
                    // This <DL> belongs to the pending folder
                    stack.append([])
                    pendingFolder = false
                }
                // If no pending folder, this is a top-level or structural <DL> - ignore
                continue
            }

            // Check for </DL> - end folder contents
            if dlClosePattern.firstMatch(in: trimmed, range: range) != nil {
                if stack.count > 1 && !folderNameStack.isEmpty {
                    let children = stack.removeLast()
                    let folderName = folderNameStack.removeLast()

                    // Check if this is a top-level Chrome folder to flatten
                    if stack.count == 1 && topLevelFolderNames.contains(folderName) {
                        // Flatten: add children directly to parent level
                        stack[stack.count - 1].append(contentsOf: children)
                    } else {
                        let folder = Folder(
                            id: UUID(),
                            name: folderName,
                            children: children,
                            isExpanded: false
                        )
                        stack[stack.count - 1].append(.folder(folder))
                    }
                }
                continue
            }
        }

        // Return the root-level nodes
        return stack.first ?? []
    }

    /// Decode common HTML entities in a string
    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        return result
    }

    /// Count links and folders in a node array
    private func countNodes(_ nodes: [Node]) -> (links: Int, folders: Int) {
        var links = 0
        var folders = 0

        for node in nodes {
            switch node {
            case .link:
                links += 1
            case .folder(let folder):
                folders += 1
                let childStats = countNodes(folder.children)
                links += childStats.links
                folders += childStats.folders
            }
        }

        return (links, folders)
    }
}
