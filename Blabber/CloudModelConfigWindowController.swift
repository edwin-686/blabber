import Cocoa
import os.log

class CloudModelConfigWindowController: NSWindowController {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "cloud")

    var onConfigured: ((Bool) -> Void)?

    private let model: CloudModel
    private let cloudManager = CloudModelManager.shared

    private var apiKeyTextField: NSTextField!
    private var submitButton: NSButton!
    private var cancelButton: NSButton!
    private var statusLabel: NSTextField!

    init(model: CloudModel) {
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Configure \(model.name)"
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
        let titleLabel = NSTextField(labelWithString: "Configure \(model.name)")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.frame = NSRect(x: 20, y: yPosition, width: 460, height: 25)
        contentView.addSubview(titleLabel)
        yPosition -= 30

        // Instructions
        let instructions = NSTextField(labelWithString: "Enter your API key to enable transcription with \(model.name):")
        instructions.font = NSFont.systemFont(ofSize: 11)
        instructions.textColor = .secondaryLabelColor
        instructions.frame = NSRect(x: 20, y: yPosition, width: 460, height: 15)
        contentView.addSubview(instructions)
        yPosition -= 30

        // API Key Label
        let apiKeyLabel = NSTextField(labelWithString: "API Key:")
        apiKeyLabel.font = NSFont.systemFont(ofSize: 13)
        apiKeyLabel.frame = NSRect(x: 20, y: yPosition, width: 80, height: 20)
        apiKeyLabel.isEditable = false
        apiKeyLabel.isBordered = false
        apiKeyLabel.backgroundColor = .clear
        contentView.addSubview(apiKeyLabel)

        // API Key Text Field
        apiKeyTextField = NSTextField(frame: NSRect(x: 100, y: yPosition, width: 380, height: 22))
        apiKeyTextField.placeholderString = "sk-..."

        // Check if API key already exists
        if let existingKey = cloudManager.getAPIKey(for: model.id) {
            apiKeyTextField.stringValue = existingKey
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
        let apiKey = apiKeyTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !apiKey.isEmpty else {
            statusLabel.stringValue = "❌ Please enter an API key"
            statusLabel.textColor = .systemRed
            return
        }

        // Basic validation based on provider
        if model.provider == "OpenAI" && !apiKey.hasPrefix("sk-") {
            statusLabel.stringValue = "⚠️ OpenAI API keys typically start with 'sk-'"
            statusLabel.textColor = .systemOrange
            // Don't return - allow user to proceed anyway
        } else if model.provider == "Anthropic" && !apiKey.hasPrefix("sk-ant-") {
            statusLabel.stringValue = "⚠️ Anthropic API keys typically start with 'sk-ant-'"
            statusLabel.textColor = .systemOrange
            // Don't return - allow user to proceed anyway
        }

        // Save to keychain
        if cloudManager.saveAPIKey(apiKey, for: model.id) {
            os_log(.info, log: Self.logger, "API key saved for model: %{public}s", model.id)
            onConfigured?(true)
            closeWindow()
        } else {
            statusLabel.stringValue = "❌ Failed to save API key"
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
