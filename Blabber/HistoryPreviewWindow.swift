import Cocoa

class HistoryPreviewWindow: NSWindow {

    private let maxWidth: CGFloat = 400
    private let maxHeight: CGFloat = 500
    private var contentStack: NSStackView!

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: maxWidth, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .popUpMenu
        self.hasShadow = true

        setupUI()
    }

    private func setupUI() {
        // Use NSVisualEffectView to match menu appearance exactly
        let visualEffectView = NSVisualEffectView(frame: contentView!.bounds)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.material = .menu
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 8
        visualEffectView.layer?.borderWidth = 0.5
        visualEffectView.layer?.borderColor = NSColor.separatorColor.cgColor

        // Create vertical stack view to hold all content
        contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 6  // Add spacing between elements
        contentStack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        visualEffectView.addSubview(contentStack)

        // Pin stack view to edges with reduced padding
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 6),
            contentStack.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 8),
            contentStack.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -8),
            contentStack.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -6)
        ])

        contentView?.addSubview(visualEffectView)
    }

    /// Show preview with given text, positioned next to the menu item
    func showPreview(text: String, item: HistoryItem, nearMenuItem menuItemFrame: NSRect) {
        // Clear existing content
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Main transcription text
        let mainLabel = createLabel(text: text, fontSize: 13, color: .labelColor)
        contentStack.addArrangedSubview(mainLabel)

        // Separator line (like menu bar)
        let separator1 = createSeparator()
        contentStack.addArrangedSubview(separator1)

        // Metadata section
        let metadataStack = NSStackView()
        metadataStack.orientation = .vertical
        metadataStack.alignment = .leading
        metadataStack.spacing = 2

        let timestampLabel = createLabel(text: "Timestamp: \(item.formattedTimestamp)", fontSize: 10, color: .secondaryLabelColor)
        let durationLabel = createLabel(text: "Duration: \(item.formattedDuration)", fontSize: 10, color: .secondaryLabelColor)
        let modelLabel = createLabel(text: "Model: \(item.formattedModel)", fontSize: 10, color: .secondaryLabelColor)
        metadataStack.addArrangedSubview(timestampLabel)
        metadataStack.addArrangedSubview(durationLabel)
        metadataStack.addArrangedSubview(modelLabel)

        contentStack.addArrangedSubview(metadataStack)

        // Separator line
        let separator2 = createSeparator()
        contentStack.addArrangedSubview(separator2)

        // Hints section
        let hintsStack = NSStackView()
        hintsStack.orientation = .vertical
        hintsStack.alignment = .leading
        hintsStack.spacing = 2

        let clickHint = createLabel(text: "Click to copy", fontSize: 10, color: .secondaryLabelColor)
        let rightClickHint = createLabel(text: "Right-click to process with workflow", fontSize: 10, color: .secondaryLabelColor)
        let pinHint = createLabel(text: "⌥P to pin/unpin", fontSize: 10, color: .secondaryLabelColor)
        let deleteHint = createLabel(text: "⌥D to delete", fontSize: 10, color: .secondaryLabelColor)
        hintsStack.addArrangedSubview(clickHint)
        hintsStack.addArrangedSubview(rightClickHint)
        hintsStack.addArrangedSubview(pinHint)
        hintsStack.addArrangedSubview(deleteHint)

        contentStack.addArrangedSubview(hintsStack)

        // Calculate size based on content (with reduced padding)
        contentStack.layoutSubtreeIfNeeded()
        let fittingSize = contentStack.fittingSize
        let contentWidth = min(fittingSize.width + 16, maxWidth)  // 8px padding on each side
        let contentHeight = min(fittingSize.height + 12, maxHeight)  // 6px padding top/bottom

        // Get screen frame
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero

        // Position to the LEFT of menu by default (Maccy-style)
        var xPos = menuItemFrame.minX - contentWidth - 20

        // If too close to left edge, position on right side
        if xPos < screenFrame.minX {
            xPos = menuItemFrame.maxX + 20
        }

        // Vertically align with menu item
        var yPos = menuItemFrame.midY - contentHeight / 2
        yPos = max(screenFrame.minY + 10, min(yPos, screenFrame.maxY - contentHeight - 10))

        let frame = NSRect(x: xPos, y: yPos, width: contentWidth, height: contentHeight)
        setFrame(frame, display: true, animate: false)

        // Show window
        orderFront(nil)
    }

    /// Hide the preview window
    func hidePreview() {
        orderOut(nil)
    }

    // MARK: - Helper Methods

    private func createLabel(text: String, fontSize: CGFloat, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: fontSize)
        label.textColor = color
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = maxWidth - 16  // Match new padding (8px each side)
        return label
    }

    private func createSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // Set height and width constraints (match new reduced padding)
        NSLayoutConstraint.activate([
            separator.heightAnchor.constraint(equalToConstant: 1),
            separator.widthAnchor.constraint(equalToConstant: maxWidth - 16)  // 8px padding on each side
        ])

        return separator
    }
}
