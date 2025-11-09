import Cocoa
import os.log

class LLMProviderConfigWindowController: NSWindowController {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "cloud")

    var onConfigured: ((Bool) -> Void)?

    private let provider: LLMProvider
    private let cloudManager: CloudModelManager

    private var apiKeyTextField: NSTextField!
    private var submitButton: NSButton!
    private var cancelButton: NSButton!
    private var statusLabel: NSTextField!

    init(provider: LLMProvider, cloudManager: CloudModelManager) {
        self.provider = provider
        self.cloudManager = cloudManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Configure \(provider.name)"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        var yPosition: CGFloat = 150

        // Title
        let titleLabel = NSTextField(labelWithString: "Configure \(provider.name)")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.frame = NSRect(x: 20, y: yPosition, width: 460, height: 25)
        contentView.addSubview(titleLabel)
        yPosition -= 30

        // Instructions
        let instructionText: String
        let fieldLabel: String
        let placeholder: String

        if provider.id == "ollama" {
            instructionText = "Enter the Ollama server URL (default: http://localhost:11434):"
            fieldLabel = "URL:"
            placeholder = "http://localhost:11434"
        } else {
            instructionText = "Enter your \(provider.name) API key:"
            fieldLabel = "API Key:"
            placeholder = provider.apiKeyPrefix ?? "Enter API key..."
        }

        let instructions = NSTextField(labelWithString: instructionText)
        instructions.font = NSFont.systemFont(ofSize: 11)
        instructions.textColor = .secondaryLabelColor
        instructions.frame = NSRect(x: 20, y: yPosition, width: 460, height: 15)
        contentView.addSubview(instructions)
        yPosition -= 30

        // Field Label
        let apiKeyLabel = NSTextField(labelWithString: fieldLabel)
        apiKeyLabel.font = NSFont.systemFont(ofSize: 13)
        apiKeyLabel.frame = NSRect(x: 20, y: yPosition, width: 80, height: 20)
        apiKeyLabel.isEditable = false
        apiKeyLabel.isBordered = false
        apiKeyLabel.backgroundColor = .clear
        contentView.addSubview(apiKeyLabel)

        // Input Text Field
        apiKeyTextField = NSTextField(frame: NSRect(x: 100, y: yPosition, width: 380, height: 22))
        apiKeyTextField.placeholderString = placeholder

        // Check if value already exists (check first model from provider)
        let modelsFromProvider = cloudManager.getLLMModels().filter { $0.id.hasPrefix(provider.id) }
        if let firstModel = modelsFromProvider.first,
           let existingValue = cloudManager.getAPIKey(for: firstModel.id) {
            apiKeyTextField.stringValue = existingValue
        } else if provider.id == "ollama" {
            // Set default Ollama URL
            apiKeyTextField.stringValue = "http://localhost:11434"
        }

        contentView.addSubview(apiKeyTextField)
        yPosition -= 40

        // Status Label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.frame = NSRect(x: 20, y: yPosition, width: 460, height: 20)
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        contentView.addSubview(statusLabel)

        // Buttons
        cancelButton = NSButton(frame: NSRect(x: 300, y: 15, width: 90, height: 32))
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        contentView.addSubview(cancelButton)

        submitButton = NSButton(frame: NSRect(x: 400, y: 15, width: 90, height: 32))
        submitButton.title = "Submit"
        submitButton.bezelStyle = .rounded
        submitButton.keyEquivalent = "\r" // Enter key
        submitButton.target = self
        submitButton.action = #selector(submitClicked)
        contentView.addSubview(submitButton)
    }

    @objc private func submitClicked() {
        let inputValue = apiKeyTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !inputValue.isEmpty else {
            let fieldName = provider.id == "ollama" ? "URL" : "API key"
            statusLabel.stringValue = "❌ Please enter a \(fieldName)"
            statusLabel.textColor = .systemRed
            return
        }

        // Validation based on provider
        if provider.id == "ollama" {
            // Validate URL format
            if !inputValue.lowercased().hasPrefix("http://") && !inputValue.lowercased().hasPrefix("https://") {
                statusLabel.stringValue = "⚠️ URL should start with http:// or https://"
                statusLabel.textColor = .systemOrange
                // Don't return - allow user to proceed anyway
            }
        } else if let prefix = provider.apiKeyPrefix, !inputValue.hasPrefix(prefix) {
            statusLabel.stringValue = "⚠️ \(provider.name) API keys typically start with '\(prefix)'"
            statusLabel.textColor = .systemOrange
            // Don't return - allow user to proceed anyway
        }

        // Save to keychain for all models from this provider
        let modelsFromProvider = cloudManager.getLLMModels().filter { $0.id.hasPrefix(provider.id) }

        var success = true
        for model in modelsFromProvider {
            if !cloudManager.saveAPIKey(inputValue, for: model.id) {
                success = false
                break
            }
        }

        if success {
            let fieldName = provider.id == "ollama" ? "URL" : "API key"
            os_log(.info, log: Self.logger, "%{public}s saved for %{public}s", fieldName, provider.name)
            onConfigured?(true)
            closeWindow()
        } else {
            let fieldName = provider.id == "ollama" ? "URL" : "API key"
            statusLabel.stringValue = "❌ Failed to save \(fieldName)"
            statusLabel.textColor = .systemRed
        }
    }

    @objc private func cancelClicked() {
        onConfigured?(false)
        closeWindow()
    }

    private func closeWindow() {
        // If this window is a sheet, end the sheet properly
        if let window = window, let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        } else {
            window?.close()
        }
    }
}
