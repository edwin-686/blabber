import Cocoa

// Represents an LLM provider (grouping multiple models)
struct LLMProvider {
    let id: String
    let name: String
    let description: String
    let apiKeyPrefix: String? // e.g., "sk-" for OpenAI, "sk-ant-" for Anthropic
}

class LLMServicesWindowController: NSWindowController {

    // Callback when services are configured/unconfigured
    var onServicesChanged: (() -> Void)?

    private var cloudManager = CloudModelManager.shared
    private var tableView: NSTableView!
    private var statusLabel: NSTextField!
    private var closeButton: NSButton!
    private var removeButton: NSButton!
    private var configButton: NSButton!

    // Provider list
    private let providers: [LLMProvider] = [
        LLMProvider(
            id: "openai",
            name: "OpenAI",
            description: "GPT-4, GPT-4 Turbo, GPT-3.5 Turbo models",
            apiKeyPrefix: "sk-"
        ),
        LLMProvider(
            id: "anthropic",
            name: "Anthropic",
            description: "Claude 3 Opus, Sonnet, and Haiku models",
            apiKeyPrefix: "sk-ant-"
        ),
        LLMProvider(
            id: "google",
            name: "Google",
            description: "Gemini Pro model",
            apiKeyPrefix: nil
        ),
        LLMProvider(
            id: "xai",
            name: "xAI",
            description: "Grok model",
            apiKeyPrefix: nil
        ),
        LLMProvider(
            id: "ollama",
            name: "Ollama",
            description: "Local LLMs (Llama 2, Mistral, Code Llama) - no API key required",
            apiKeyPrefix: nil
        )
    ]

    // Keep reference to config window controller
    private var configWindowController: LLMProviderConfigWindowController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LLM Services"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Title Label
        let titleLabel = NSTextField(labelWithString: "Available LLM Providers")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.frame = NSRect(x: 20, y: 300, width: 660, height: 25)
        contentView.addSubview(titleLabel)

        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "Configure API keys for text generation providers")
        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 20, y: 280, width: 660, height: 15)
        contentView.addSubview(subtitleLabel)

        // Table View with Scroll View
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 115, width: 660, height: 155))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .bezelBorder

        tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = NSTableHeaderView()
        tableView.autoresizingMask = [.width, .height]

        // Columns (removed Action column)
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Provider"
        nameColumn.width = 110

        let descColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("description"))
        descColumn.title = "Description"
        descColumn.width = 380

        let statusColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusColumn.title = "Status"
        statusColumn.width = 150

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(descColumn)
        tableView.addTableColumn(statusColumn)

        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        // macOS-style control buttons (bottom left, below table with spacing)
        // Remove button (-)
        removeButton = NSButton(frame: NSRect(x: 20, y: 83, width: 24, height: 24))
        removeButton.bezelStyle = .smallSquare
        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")
        removeButton.target = self
        removeButton.action = #selector(removeButtonClicked)
        removeButton.toolTip = "Remove API key for selected provider"
        removeButton.isEnabled = false
        contentView.addSubview(removeButton)

        // Config button (gear)
        configButton = NSButton(frame: NSRect(x: 44, y: 83, width: 24, height: 24))
        configButton.bezelStyle = .smallSquare
        configButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Configure")
        configButton.target = self
        configButton.action = #selector(configButtonClicked)
        configButton.toolTip = "Configure API key for selected provider"
        configButton.isEnabled = false
        contentView.addSubview(configButton)

        // Status Label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.frame = NSRect(x: 20, y: 50, width: 660, height: 25)
        contentView.addSubview(statusLabel)

        // Close Button
        closeButton = NSButton(frame: NSRect(x: 590, y: 15, width: 90, height: 32))
        closeButton.title = "Close"
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        contentView.addSubview(closeButton)
    }

    private func updateButtonStates() {
        let selectedRow = tableView.selectedRow
        let hasSelection = selectedRow >= 0 && selectedRow < providers.count

        if hasSelection {
            let provider = providers[selectedRow]
            let isConfigured = isProviderConfigured(provider)

            // Enable/disable buttons based on provider state
            configButton.isEnabled = true
            removeButton.isEnabled = isConfigured && provider.id != "ollama"
        } else {
            configButton.isEnabled = false
            removeButton.isEnabled = false
        }
    }

    @objc private func closeClicked() {
        // If this window is a sheet, end the sheet properly
        if let window = window, let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        } else {
            window?.close()
        }
    }

    @objc private func configButtonClicked() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 && selectedRow < providers.count else { return }

        let provider = providers[selectedRow]

        // Open configuration window (now supports Ollama URL configuration)
        configWindowController = LLMProviderConfigWindowController(provider: provider, cloudManager: cloudManager)
        configWindowController?.onConfigured = { [weak self] success in
            if success {
                self?.statusLabel.stringValue = "✓ \(provider.name) configured successfully"
                self?.statusLabel.textColor = .systemGreen
                self?.tableView.reloadData()
                self?.updateButtonStates()
                self?.onServicesChanged?()

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

    @objc private func removeButtonClicked() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 && selectedRow < providers.count else { return }

        let provider = providers[selectedRow]

        // Confirm deletion
        let alert = NSAlert()
        alert.messageText = "Remove API Key?"
        alert.informativeText = "Are you sure you want to remove the API key for \(provider.name)? You will need to re-enter it to use this provider again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Remove API keys for all models from this provider
            let modelsFromProvider = cloudManager.getLLMModels().filter { model in
                model.id.hasPrefix(provider.id)
            }

            var success = true
            for model in modelsFromProvider {
                if !cloudManager.deleteAPIKey(for: model.id) {
                    success = false
                }
            }

            if success {
                statusLabel.stringValue = "✓ \(provider.name) API key removed"
                statusLabel.textColor = .systemGreen
                tableView.reloadData()
                updateButtonStates()
                onServicesChanged?()

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

    private func isProviderConfigured(_ provider: LLMProvider) -> Bool {
        if provider.id == "ollama" {
            return true // Ollama is always "configured"
        }

        // Check if any model from this provider has an API key
        let modelsFromProvider = cloudManager.getLLMModels().filter { model in
            model.id.hasPrefix(provider.id)
        }

        return modelsFromProvider.contains { cloudManager.isModelConfigured($0) }
    }
}

// MARK: - NSTableViewDataSource

extension LLMServicesWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return providers.count
    }
}

// MARK: - NSTableViewDelegate

extension LLMServicesWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < providers.count else { return nil }

        let provider = providers[row]
        let isConfigured = isProviderConfigured(provider)

        let identifier = tableColumn?.identifier

        if identifier == NSUserInterfaceItemIdentifier("name") {
            let cellView = NSTextField()
            cellView.stringValue = provider.name
            cellView.font = NSFont.boldSystemFont(ofSize: 11)
            cellView.isBordered = false
            cellView.isEditable = false
            cellView.drawsBackground = false
            cellView.alignment = .left
            cellView.lineBreakMode = .byTruncatingTail
            return cellView
        } else if identifier == NSUserInterfaceItemIdentifier("description") {
            let cellView = NSTextField()
            cellView.stringValue = provider.description
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

            if isConfigured {
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
        }

        return nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 24
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonStates()
    }
}
