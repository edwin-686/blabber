import Foundation
import Cocoa

class HistoryItem: Codable {
    var id: UUID
    var text: String
    var timestamp: Date
    var duration: TimeInterval
    var isPinned: Bool
    var model: String? // Optional for backward compatibility with existing history

    init(text: String, timestamp: Date, duration: TimeInterval, isPinned: Bool = false, model: String? = nil) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
        self.isPinned = isPinned
        self.model = model
    }

    /// Returns truncated text for menu display (first 70 characters)
    var truncatedText: String {
        if text.count <= 70 {
            return text
        }
        return String(text.prefix(70)) + "..."
    }

    /// Returns smart truncated text with context around search match
    /// - Parameter searchQuery: The search query to find and show context for
    /// - Returns: Truncated text showing context around the match, or standard truncation if no match beyond position 60
    func smartTruncatedText(searchQuery: String) -> String {
        // If no search query or text is short enough, use standard truncation
        guard !searchQuery.isEmpty, text.count > 70 else {
            return truncatedText
        }

        // Find match position (case-insensitive)
        let lowercaseText = text.lowercased()
        let lowercaseQuery = searchQuery.lowercased()

        guard let matchRange = lowercaseText.range(of: lowercaseQuery) else {
            // No match found, use standard truncation
            return truncatedText
        }

        let matchPosition = text.distance(from: text.startIndex, to: matchRange.lowerBound)

        // If match is in first 60 characters, use standard truncation
        if matchPosition <= 60 {
            return truncatedText
        }

        // Match is beyond position 60, show context around it
        let matchLength = searchQuery.count

        // Get prefix (first 10 characters)
        let prefixEnd = text.index(text.startIndex, offsetBy: min(10, text.count))
        let prefix = String(text[text.startIndex..<prefixEnd])

        // Calculate context window around match
        let contextStart = max(0, matchPosition - 10)
        let contextEnd = min(text.count, matchPosition + matchLength + 40)

        let contextStartIndex = text.index(text.startIndex, offsetBy: contextStart)
        let contextEndIndex = text.index(text.startIndex, offsetBy: min(contextEnd, text.count))

        let context = String(text[contextStartIndex..<contextEndIndex])

        // Build display string
        let display = "\(prefix)...\(context)"

        // Ensure we don't exceed 70 characters total (plus ellipsis)
        if display.count > 70 {
            return String(display.prefix(70)) + "..."
        } else if contextEnd < text.count {
            return display + "..."
        } else {
            return display
        }
    }

    /// Returns attributed string with bold matched text for menu display
    /// - Parameter searchQuery: The search query to bold in the display
    /// - Returns: NSAttributedString with matched text in bold
    func attributedDisplayText(searchQuery: String) -> NSAttributedString {
        let displayText: String
        let isSmartTruncated: Bool

        if searchQuery.isEmpty || text.count <= 70 {
            displayText = truncatedText
            isSmartTruncated = false
        } else {
            // Check if we need smart truncation
            let lowercaseText = text.lowercased()
            let lowercaseQuery = searchQuery.lowercased()

            if let matchRange = lowercaseText.range(of: lowercaseQuery) {
                let matchPosition = text.distance(from: text.startIndex, to: matchRange.lowerBound)
                if matchPosition > 60 {
                    displayText = smartTruncatedText(searchQuery: searchQuery)
                    isSmartTruncated = true
                } else {
                    displayText = truncatedText
                    isSmartTruncated = false
                }
            } else {
                displayText = truncatedText
                isSmartTruncated = false
            }
        }

        // Create attributed string
        let normalFont = NSFont.menuFont(ofSize: 0) // 0 means use default menu font size
        let boldFont = NSFont.boldSystemFont(ofSize: normalFont.pointSize)

        let attributedString = NSMutableAttributedString(
            string: displayText,
            attributes: [.font: normalFont]
        )

        // Find and bold the matched text (case-insensitive)
        if !searchQuery.isEmpty {
            let displayLowercase = displayText.lowercased()
            let queryLowercase = searchQuery.lowercased()

            if let range = displayLowercase.range(of: queryLowercase) {
                let nsRange = NSRange(range, in: displayText)
                attributedString.addAttribute(.font, value: boldFont, range: nsRange)
            }
        }

        return attributedString
    }

    /// Returns formatted timestamp string
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    /// Returns formatted duration string
    var formattedDuration: String {
        return String(format: "%.1fs", duration)
    }

    /// Returns formatted model string for display
    var formattedModel: String {
        guard let model = model else {
            return "Unknown"
        }

        // Check if it's a cloud model
        if model.hasPrefix("cloud:") {
            let modelId = String(model.dropFirst(6))
            return modelId.capitalized
        }

        // For local models, extract a readable name from the path
        // Example: /path/to/ggml-large-v3-turbo-q5_0.bin -> Large V3 Turbo Q5
        let filename = (model as NSString).lastPathComponent
        let withoutExtension = (filename as NSString).deletingPathExtension

        // Remove "ggml-" prefix if present
        var displayName = withoutExtension
        if displayName.hasPrefix("ggml-") {
            displayName = String(displayName.dropFirst(5))
        }

        // Capitalize and clean up
        return displayName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
