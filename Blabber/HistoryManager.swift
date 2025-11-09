import Foundation
import os.log

class HistoryManager {
    static let shared = HistoryManager()

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "history")

    private var items: [HistoryItem] = []
    private let historyFileURL: URL

    private init() {
        // Get app support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let blabberDir = appSupport.appendingPathComponent("Blabber", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: blabberDir, withIntermediateDirectories: true)

        historyFileURL = blabberDir.appendingPathComponent("history.json")

        // Load existing history
        loadHistory()
    }

    // MARK: - Public Methods

    /// Add a new transcription to history
    func addItem(text: String, duration: TimeInterval, model: String? = nil) {
        let item = HistoryItem(text: text, timestamp: Date(), duration: duration, model: model)
        items.insert(item, at: 0) // Add at beginning

        // Enforce history size limit (but don't remove pinned items)
        trimHistory()

        saveHistory()
    }

    /// Get all items, sorted with pinned items first
    func getItems() -> [HistoryItem] {
        return items.sorted { item1, item2 in
            // Pinned items always come first
            if item1.isPinned != item2.isPinned {
                return item1.isPinned
            }
            // Otherwise sort by timestamp (newest first)
            return item1.timestamp > item2.timestamp
        }
    }

    /// Search history items by text
    func searchItems(query: String) -> [HistoryItem] {
        if query.isEmpty {
            return getItems()
        }

        let lowercaseQuery = query.lowercased()
        return getItems().filter { item in
            item.text.lowercased().contains(lowercaseQuery)
        }
    }

    /// Toggle pin status of an item
    func togglePin(itemId: UUID) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].isPinned.toggle()
            saveHistory()
        }
    }

    /// Delete an item
    func deleteItem(itemId: UUID) {
        items.removeAll { $0.id == itemId }
        saveHistory()
    }

    /// Clear all history (except pinned items)
    func clearHistory(includingPinned: Bool = false) {
        if includingPinned {
            items.removeAll()
        } else {
            items.removeAll { !$0.isPinned }
        }
        saveHistory()
    }

    // MARK: - Private Methods

    private func trimHistory() {
        let maxSize = SettingsManager.shared.historySize

        // Separate pinned and unpinned items
        let pinnedItems = items.filter { $0.isPinned }
        let unpinnedItems = items.filter { !$0.isPinned }

        // Keep only the most recent unpinned items (up to maxSize)
        let trimmedUnpinned = Array(unpinnedItems.prefix(maxSize))

        // Combine pinned + trimmed unpinned
        items = pinnedItems + trimmedUnpinned
    }

    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: historyFileURL)
            os_log(.info, log: Self.logger, "Saved %{public}d items to disk", items.count)
        } catch {
            os_log(.error, log: Self.logger, "Failed to save history: %{public}s", error.localizedDescription)
        }
    }

    private func loadHistory() {
        do {
            let data = try Data(contentsOf: historyFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([HistoryItem].self, from: data)
            os_log(.info, log: Self.logger, "Loaded %{public}d items from disk", items.count)
        } catch {
            #if DEBUG
            print("HistoryManager: No existing history or failed to load: \(error)")
            #endif
            items = []
        }
    }
}
