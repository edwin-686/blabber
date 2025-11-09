import Cocoa

class CloudModelsWindowController: NSWindowController {

    // Callback when models are configured/unconfigured
    var onModelsChanged: (() -> Void)?

    private var cloudManager = CloudModelManager.shared
    private var tableView: NSTableView!
    private var statusLabel: NSTextField!
    private var closeButton: NSButton!

    // Model list
    private var displayedModels: [CloudModel] = []

    // Keep reference to config window controller
    private var configWindowController: CloudModelConfigWindowController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 878, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cloud Transcription Models"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        setupUI()
        loadModels()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Title Label
        let titleLabel = NSTextField(labelWithString: "Available Cloud Models")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.frame = NSRect(x: 20, y: 300, width: 838, height: 25)
        contentView.addSubview(titleLabel)

        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "Configure cloud transcription providers by adding your API keys")
        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 20, y: 280, width: 838, height: 15)
        contentView.addSubview(subtitleLabel)

        // Table View with Scroll View
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 90, width: 838, height: 180))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .bezelBorder

        tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = NSTableHeaderView()
        tableView.autoresizingMask = [.width, .height]

        // Columns
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Provider"
        nameColumn.width = 152

        let descColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("description"))
        descColumn.title = "Description"
        descColumn.width = 359

        let statusColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusColumn.title = "Status"
        statusColumn.width = 108

        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionColumn.title = "Action"
        actionColumn.width = 192

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(descColumn)
        tableView.addTableColumn(statusColumn)
        tableView.addTableColumn(actionColumn)

        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        // Status Label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.frame = NSRect(x: 20, y: 50, width: 838, height: 25)
        contentView.addSubview(statusLabel)

        // Close Button
        closeButton = NSButton(frame: NSRect(x: 768, y: 15, width: 90, height: 32))
        closeButton.title = "Close"
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        contentView.addSubview(closeButton)
    }

    private func loadModels() {
        // Only show transcription models, not LLM models
        displayedModels = cloudManager.getTranscriptionModels()
        tableView.reloadData()
    }

    @objc private func closeClicked() {
        // If this window is a sheet, end the sheet properly
        if let window = window, let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        } else {
            // Otherwise just close normally
            window?.close()
        }
    }

    @objc private func configureButtonClicked(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0 && row < displayedModels.count else { return }

        let model = displayedModels[row]

        // Check if this is a coming soon model
        if model.comingSoon {
            let alert = NSAlert()
            alert.messageText = "Coming Soon"
            alert.informativeText = "\(model.name) integration is coming soon! This provider will be available in a future update."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Open configuration window
        configWindowController = CloudModelConfigWindowController(model: model)
        configWindowController?.onConfigured = { [weak self] success in
            if success {
                self?.statusLabel.stringValue = "✓ \(model.name) configured successfully"
                self?.statusLabel.textColor = .systemGreen
                self?.tableView.reloadData()
                self?.onModelsChanged?()

                // Clear message after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    self?.statusLabel.stringValue = ""
                }
            }
        }

        if let configWindow = configWindowController?.window, let parentWindow = window {
            parentWindow.beginSheet(configWindow)
        }
    }

    @objc private func unconfigureButtonClicked(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0 && row < displayedModels.count else { return }

        let model = displayedModels[row]

        // Confirm unconfiguration
        let alert = NSAlert()
        alert.messageText = "Remove API Key?"
        alert.informativeText = "Are you sure you want to remove the API key for \(model.name)? You will need to re-enter it to use this provider again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if cloudManager.deleteAPIKey(for: model.id) {
                statusLabel.stringValue = "✓ \(model.name) unconfigured"
                statusLabel.textColor = .systemGreen
                tableView.reloadData()
                onModelsChanged?()

                // Clear message after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    self?.statusLabel.stringValue = ""
                }
            } else {
                statusLabel.stringValue = "❌ Failed to remove API key"
                statusLabel.textColor = .systemRed
            }
        }
    }
}

// MARK: - NSTableViewDataSource

extension CloudModelsWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return displayedModels.count
    }
}

// MARK: - NSTableViewDelegate

extension CloudModelsWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < displayedModels.count else { return nil }

        let model = displayedModels[row]
        let isConfigured = cloudManager.isModelConfigured(model)

        let identifier = tableColumn?.identifier

        if identifier == NSUserInterfaceItemIdentifier("name") {
            let cellView = NSTextField()
            cellView.stringValue = model.name
            cellView.font = NSFont.boldSystemFont(ofSize: 11)
            cellView.isBordered = false
            cellView.isEditable = false
            cellView.drawsBackground = false
            cellView.alignment = .left
            cellView.lineBreakMode = .byTruncatingTail
            return cellView
        } else if identifier == NSUserInterfaceItemIdentifier("description") {
            let cellView = NSTextField()
            cellView.stringValue = model.description
            cellView.font = NSFont.systemFont(ofSize: 11)
            cellView.textColor = .secondaryLabelColor
            cellView.isBordered = false
            cellView.isEditable = false
            cellView.drawsBackground = false
            cellView.alignment = .left
            cellView.lineBreakMode = .byTruncatingTail
            return cellView
        } else if identifier == NSUserInterfaceItemIdentifier("status") {
            let status: String
            let color: NSColor

            if model.comingSoon {
                status = "Coming soon"
                color = .systemOrange
            } else if isConfigured {
                status = "✓ Configured"
                color = .systemGreen
            } else {
                status = "Not configured"
                color = .secondaryLabelColor
            }

            let cellView = NSTextField()
            cellView.stringValue = status
            cellView.font = NSFont.systemFont(ofSize: 11)
            cellView.textColor = color
            cellView.isBordered = false
            cellView.isEditable = false
            cellView.drawsBackground = false
            cellView.alignment = .left
            cellView.lineBreakMode = .byTruncatingTail
            return cellView
        } else if identifier == NSUserInterfaceItemIdentifier("action") {
            let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 192, height: 24))

            if isConfigured && !model.comingSoon {
                // Show Unconfigure button
                let unconfigureButton = NSButton(frame: NSRect(x: 0, y: 2, width: 100, height: 20))
                unconfigureButton.title = "Remove"
                unconfigureButton.bezelStyle = .rounded
                unconfigureButton.target = self
                unconfigureButton.action = #selector(unconfigureButtonClicked(_:))
                containerView.addSubview(unconfigureButton)
            } else {
                // Show Configure button
                let configureButton = NSButton(frame: NSRect(x: 0, y: 2, width: 100, height: 20))
                configureButton.title = model.comingSoon ? "Learn More" : "Configure"
                configureButton.bezelStyle = .rounded
                configureButton.target = self
                configureButton.action = #selector(configureButtonClicked(_:))
                containerView.addSubview(configureButton)
            }

            return containerView
        }

        return nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 24
    }
}
