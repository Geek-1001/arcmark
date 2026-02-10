//
//  SearchCoordinator.swift
//  Arcmark
//

import AppKit

/// Manages search and filtering logic for nodes
@MainActor
final class SearchCoordinator {

    // MARK: - Properties

    /// Current search query
    private(set) var currentQuery: String = ""

    /// Callback triggered when the query changes
    var onQueryChanged: ((String) -> Void)?

    // MARK: - Public Methods

    /// Updates the current search query
    /// - Parameter query: The new search query
    func updateQuery(_ query: String) {
        currentQuery = query
        onQueryChanged?(query)
    }

    /// Clears the current search query
    func clearQuery() {
        updateQuery("")
    }

    /// Filters nodes based on the current query
    /// - Parameters:
    ///   - nodes: The nodes to filter
    ///   - query: Optional query override. If nil, uses currentQuery
    /// - Returns: Filtered nodes matching the query
    func filter(nodes: [Node], query: String? = nil) -> [Node] {
        let searchQuery = query ?? currentQuery
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedQuery.isEmpty {
            return nodes
        }

        return NodeFiltering.filter(nodes: nodes, query: trimmedQuery)
    }

    /// Checks if search is currently active
    var isSearchActive: Bool {
        !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Gets the trimmed query string
    var trimmedQuery: String {
        currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
