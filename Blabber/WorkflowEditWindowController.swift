import Cocoa

class WorkflowEditWindowController: NSWindowController {

    var onSaved: ((Workflow) -> Void)?

    private let workflow: Workflow
    private let isNew: Bool
    private let cloudManager = CloudModelManager.shared

    private var nameTextField: NSTextField!
    private var descriptionTextField: NSTextField!
    private var promptTextView: NSTextView!
    private var optimizePromptButton: NSButton!
    private var providerPopup: NSPopUpButton!
    private var modelPopup: NSPopUpButton!
    private var saveButton: NSButton!
    private var cancelButton: NSButton!
    private var statusLabel: NSTextField!
    private var llmProcessor = LLMProcessor()

    init(workflow: Workflow, isNew: Bool) {
        self.workflow = workflow
        self.isNew = isNew

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = isNew ? "New Workflow" : "Edit Workflow"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupUI()
        loadWorkflowData()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        var yPosition: CGFloat = 510

        // Title
        let titleLabel = NSTextField(labelWithString: isNew ? "Create New Workflow" : "Edit Workflow")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.frame = NSRect(x: 20, y: yPosition, width: 560, height: 25)
        contentView.addSubview(titleLabel)
        yPosition -= 40

        // Name Label
        let nameLabel = NSTextField(labelWithString: "Workflow Name:")
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        nameLabel.frame = NSRect(x: 20, y: yPosition, width: 120, height: 20)
        nameLabel.isEditable = false
        nameLabel.isBordered = false
        nameLabel.backgroundColor = .clear
        contentView.addSubview(nameLabel)

        // Name Text Field
        nameTextField = NSTextField(frame: NSRect(x: 145, y: yPosition, width: 435, height: 22))
        nameTextField.placeholderString = "e.g., Formal Email"
        contentView.addSubview(nameTextField)
        yPosition -= 35

        // Description Label
        let descLabel = NSTextField(labelWithString: "Description:")
        descLabel.font = NSFont.systemFont(ofSize: 13)
        descLabel.frame = NSRect(x: 20, y: yPosition, width: 120, height: 20)
        descLabel.isEditable = false
        descLabel.isBordered = false
        descLabel.backgroundColor = .clear
        contentView.addSubview(descLabel)

        // Description Text Field
        descriptionTextField = NSTextField(frame: NSRect(x: 145, y: yPosition, width: 435, height: 22))
        descriptionTextField.placeholderString = "e.g., Professional formatting with structure"
        contentView.addSubview(descriptionTextField)
        yPosition -= 45

        // Prompt Label
        let promptLabel = NSTextField(labelWithString: "Prompt:")
        promptLabel.font = NSFont.systemFont(ofSize: 13)
        promptLabel.frame = NSRect(x: 20, y: yPosition, width: 560, height: 20)
        promptLabel.isEditable = false
        promptLabel.isBordered = false
        promptLabel.backgroundColor = .clear
        contentView.addSubview(promptLabel)
        yPosition -= 10

        let promptHint = NSTextField(labelWithString: "Instructions for the LLM. The user's text will be appended automatically.")
        promptHint.font = NSFont.systemFont(ofSize: 10)
        promptHint.textColor = .secondaryLabelColor
        promptHint.frame = NSRect(x: 20, y: yPosition, width: 560, height: 15)
        promptHint.isEditable = false
        promptHint.isBordered = false
        promptHint.backgroundColor = .clear
        contentView.addSubview(promptHint)
        yPosition -= 20

        // Prompt Text View with Scroll View
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: yPosition - 180, width: 560, height: 180))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .bezelBorder

        promptTextView = NSTextView(frame: scrollView.bounds)
        promptTextView.isEditable = true
        promptTextView.isSelectable = true
        promptTextView.font = NSFont.systemFont(ofSize: 12)
        promptTextView.textContainerInset = NSSize(width: 5, height: 5)
        promptTextView.autoresizingMask = [.width, .height]

        scrollView.documentView = promptTextView
        contentView.addSubview(scrollView)
        yPosition -= 190

        // Optimize Prompt Button (magic wand icon) - positioned on the right
        optimizePromptButton = NSButton(frame: NSRect(x: 400, y: yPosition, width: 180, height: 28))
        optimizePromptButton.title = "Optimize Prompt"
        optimizePromptButton.bezelStyle = .rounded
        optimizePromptButton.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Optimize")
        optimizePromptButton.imagePosition = .imageLeading
        optimizePromptButton.target = self
        optimizePromptButton.action = #selector(optimizePromptClicked)
        optimizePromptButton.toolTip = "Use AI to improve and optimize your prompt"
        contentView.addSubview(optimizePromptButton)
        yPosition -= 38

        // Provider Label
        let providerLabel = NSTextField(labelWithString: "Provider:")
        providerLabel.font = NSFont.systemFont(ofSize: 13)
        providerLabel.frame = NSRect(x: 20, y: yPosition, width: 120, height: 20)
        providerLabel.isEditable = false
        providerLabel.isBordered = false
        providerLabel.backgroundColor = .clear
        contentView.addSubview(providerLabel)

        // Provider Selector Popup
        providerPopup = NSPopUpButton(frame: NSRect(x: 145, y: yPosition - 2, width: 200, height: 25))
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        loadProviderOptions()
        contentView.addSubview(providerPopup)
        yPosition -= 35

        // Model Label
        let modelLabel = NSTextField(labelWithString: "Model:")
        modelLabel.font = NSFont.systemFont(ofSize: 13)
        modelLabel.frame = NSRect(x: 20, y: yPosition, width: 120, height: 20)
        modelLabel.isEditable = false
        modelLabel.isBordered = false
        modelLabel.backgroundColor = .clear
        contentView.addSubview(modelLabel)

        // Model Selector Popup
        modelPopup = NSPopUpButton(frame: NSRect(x: 145, y: yPosition - 2, width: 300, height: 25))
        contentView.addSubview(modelPopup)
        yPosition -= 50

        // Status Label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.frame = NSRect(x: 20, y: yPosition, width: 560, height: 20)
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        contentView.addSubview(statusLabel)

        // Buttons
        cancelButton = NSButton(frame: NSRect(x: 400, y: 15, width: 90, height: 32))
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        contentView.addSubview(cancelButton)

        saveButton = NSButton(frame: NSRect(x: 500, y: 15, width: 90, height: 32))
        saveButton.title = "Save"
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r" // Enter key
        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        contentView.addSubview(saveButton)
    }

    private func loadProviderOptions() {
        providerPopup.removeAllItems()

        // Add only configured providers
        let providers = ["OpenAI", "Anthropic", "Google", "xAI", "Ollama"]
        let allLLMs = cloudManager.getLLMModels()

        var configuredProviders: [String] = []

        // Check which providers are configured
        for providerName in providers {
            let modelsForProvider = allLLMs.filter { $0.provider == providerName }

            if !modelsForProvider.isEmpty {
                // Check if any model from this provider has an API key
                var isConfigured = false
                for model in modelsForProvider {
                    if let _ = cloudManager.getAPIKey(for: model.id) {
                        isConfigured = true
                        break
                    }
                }

                // Ollama is always "configured" (doesn't need API key check)
                if providerName == "Ollama" {
                    isConfigured = true
                }

                if isConfigured {
                    configuredProviders.append(providerName)
                }
            }
        }

        if configuredProviders.isEmpty {
            providerPopup.addItem(withTitle: "No providers configured")
            providerPopup.isEnabled = false
            modelPopup.isEnabled = false
            statusLabel.stringValue = "⚠️ Please configure LLM providers first"
            statusLabel.textColor = .systemOrange
            return
        }

        providerPopup.isEnabled = true

        // Add placeholder
        providerPopup.addItem(withTitle: "Select provider...")

        // Add each configured provider
        for providerName in configuredProviders {
            providerPopup.addItem(withTitle: providerName)
        }
    }

    @objc private func providerChanged() {
        let selectedProvider = providerPopup.titleOfSelectedItem ?? ""
        loadModelOptions(for: selectedProvider)
    }

    private func loadModelOptions(for provider: String) {
        modelPopup.removeAllItems()

        if provider == "Select provider..." || provider.isEmpty {
            modelPopup.addItem(withTitle: "Select provider first")
            modelPopup.isEnabled = false
            return
        }

        let modelsForProvider = cloudManager.getLLMModels().filter { $0.provider == provider }

        if modelsForProvider.isEmpty {
            modelPopup.addItem(withTitle: "No models available")
            modelPopup.isEnabled = false
            return
        }

        // Check if provider has API key configured
        var hasAPIKey = false
        for model in modelsForProvider {
            if let _ = cloudManager.getAPIKey(for: model.id) {
                hasAPIKey = true
                break
            }
        }

        if !hasAPIKey {
            modelPopup.addItem(withTitle: "Provider not configured - configure API key first")
            modelPopup.isEnabled = false
            statusLabel.stringValue = "⚠️ Please configure API key for \(provider) in 'Configure LLM Services'"
            statusLabel.textColor = .systemOrange
            return
        }

        modelPopup.isEnabled = true
        statusLabel.stringValue = ""

        for model in modelsForProvider {
            modelPopup.addItem(withTitle: model.name)
        }
    }

    private func loadWorkflowData() {
        nameTextField.stringValue = workflow.name
        descriptionTextField.stringValue = workflow.description
        promptTextView.string = workflow.prompt

        // Select the provider and model if configured
        if let serviceId = workflow.serviceId,
           let model = cloudManager.availableModels.first(where: { $0.id == serviceId }) {
            providerPopup.selectItem(withTitle: model.provider)
            loadModelOptions(for: model.provider)
            modelPopup.selectItem(withTitle: model.name)
        } else {
            // No service configured, load default models
            if let firstProvider = providerPopup.itemTitles.dropFirst().first {
                providerPopup.selectItem(withTitle: firstProvider)
                loadModelOptions(for: firstProvider)
            }
        }
    }

    @objc private func saveClicked() {
        // Validate inputs
        let name = nameTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = descriptionTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = promptTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            statusLabel.stringValue = "❌ Workflow name is required"
            statusLabel.textColor = .systemRed
            return
        }

        guard !prompt.isEmpty else {
            statusLabel.stringValue = "❌ Prompt is required"
            statusLabel.textColor = .systemRed
            return
        }

        // Get selected service ID from provider + model
        var selectedServiceId: String? = nil
        if modelPopup.isEnabled {
            let selectedModelName = modelPopup.titleOfSelectedItem ?? ""
            let selectedProvider = providerPopup.titleOfSelectedItem ?? ""

            if !selectedModelName.isEmpty && selectedProvider != "Select provider..." {
                // Find the model by provider and name
                let models = cloudManager.getConfiguredLLMModels().filter { $0.provider == selectedProvider }
                if let model = models.first(where: { $0.name == selectedModelName }) {
                    selectedServiceId = model.id
                }
            }
        }

        // Update workflow properties
        workflow.name = name
        workflow.description = description
        workflow.prompt = prompt
        workflow.serviceId = selectedServiceId

        // Callback with saved workflow
        onSaved?(workflow)
        closeWindow()
    }

    @objc private func cancelClicked() {
        closeWindow()
    }

    @objc private func optimizePromptClicked() {
        // Get current prompt
        let currentPrompt = promptTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !currentPrompt.isEmpty else {
            statusLabel.stringValue = "⚠️ Please enter a prompt first"
            statusLabel.textColor = .systemOrange
            return
        }

        // Get selected model
        guard modelPopup.isEnabled,
              let selectedModelName = modelPopup.titleOfSelectedItem,
              let selectedProvider = providerPopup.titleOfSelectedItem,
              selectedProvider != "Select provider..." else {
            statusLabel.stringValue = "⚠️ Please select a provider and model first"
            statusLabel.textColor = .systemOrange
            return
        }

        // Find the model
        let models = cloudManager.getConfiguredLLMModels().filter { $0.provider == selectedProvider }
        guard let model = models.first(where: { $0.name == selectedModelName }) else {
            statusLabel.stringValue = "❌ Could not find selected model"
            statusLabel.textColor = .systemRed
            return
        }

        // Disable button during processing
        optimizePromptButton.isEnabled = false
        optimizePromptButton.title = "Optimizing..."
        statusLabel.stringValue = "Processing with \(model.name)..."
        statusLabel.textColor = .labelColor

        // Create optimization request prompt
        let optimizationPrompt = """
        You are a prompt engineering expert. Your task is to improve and optimize the following prompt for use with a language model.

        The improved prompt should be:
        - Clear and specific
        - Well-structured
        - Effective for achieving the intended goal
        - Concise but comprehensive

        Original prompt:
        \(currentPrompt)

        Please provide ONLY the improved prompt without any explanation or commentary.
        """

        // Call LLM processor
        llmProcessor.processText(text: "", prompt: optimizationPrompt, modelId: model.id) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                // Re-enable button
                self.optimizePromptButton.isEnabled = true
                self.optimizePromptButton.title = "Optimize Prompt"

                if let error = error {
                    self.statusLabel.stringValue = "❌ Optimization failed: \(error.localizedDescription)"
                    self.statusLabel.textColor = .systemRed

                    // Clear error after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                        if self?.statusLabel.stringValue.starts(with: "❌") == true {
                            self?.statusLabel.stringValue = ""
                        }
                    }
                } else if let result = result {
                    // Update prompt with optimized version
                    self.promptTextView.string = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.statusLabel.stringValue = "✓ Prompt optimized successfully"
                    self.statusLabel.textColor = .systemGreen

                    // Clear success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        if self?.statusLabel.stringValue == "✓ Prompt optimized successfully" {
                            self?.statusLabel.stringValue = ""
                        }
                    }
                }
            }
        }
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
