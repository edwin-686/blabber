import Cocoa

class WorkflowProcessorWindowController: NSWindowController {

    private var workflowManager = WorkflowManager.shared
    private var cloudManager = CloudModelManager.shared
    private var llmProcessor = LLMProcessor()
    private var audioFeedback = AudioFeedback()
    private var pasteManager = PasteManager()

    private var inputTextView: NSTextView!
    private var outputTextView: NSTextView!
    private var pasteButton: NSButton!
    private var recordButton: NSButton!
    private var copyButton: NSButton!
    private var copyAndCloseButton: NSButton!
    private var workflowsButton: NSButton!
    private var closeButton: NSButton!
    private var workflowButtonsContainer: NSView!
    private var workflowButtonsScrollView: NSScrollView!
    private var progressIndicator: NSProgressIndicator!
    private var statusLabel: NSTextField!

    private var currentlyProcessing = false
    private var workflowsWindowController: WorkflowsWindowController?
    private var workflowShortcuts: [Int: Workflow] = [:] // Map keyboard shortcut number to workflow
    private var triggeredByHotkey = false // Track if workflow was triggered by keyboard shortcut
    private var hotkeyLabel: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1170, height: 780),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Workflow Processor"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        setupUI()
        setupKeyboardShortcuts()
    }

    private func setupKeyboardShortcuts() {
        // Add local event monitor for keyboard shortcuts
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.isKeyWindow == true else { return event }

            // Check for Cmd+1 through Cmd+9
            if event.modifierFlags.contains(.command),
               let characters = event.charactersIgnoringModifiers,
               let firstChar = characters.first,
               let digit = Int(String(firstChar)),
               digit >= 1 && digit <= 9 {

                // Check if we have a workflow for this shortcut
                if let workflow = self.workflowShortcuts[digit] {
                    self.triggeredByHotkey = true
                    self.executeWorkflow(workflow)
                    return nil // Consume the event
                }
            }

            return event
        }
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Title and Subtitle on same line
        let titleLabel = NSTextField(labelWithString: "Workflow Processor")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.frame = NSRect(x: 26, y: 720, width: 200, height: 32)
        contentView.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "Process text with your configured workflows")
        subtitleLabel.font = NSFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 230, y: 726, width: 550, height: 20)
        contentView.addSubview(subtitleLabel)

        // INPUT SECTION
        let inputLabel = NSTextField(labelWithString: "INPUT")
        inputLabel.font = NSFont.boldSystemFont(ofSize: 13)
        inputLabel.frame = NSRect(x: 26, y: 672, width: 700, height: 26)
        contentView.addSubview(inputLabel)

        // Record Button (icon)
        recordButton = NSButton(frame: NSRect(x: 772, y: 669, width: 32, height: 32))
        recordButton.title = ""
        recordButton.bezelStyle = .texturedRounded
        recordButton.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "Record")
        recordButton.target = self
        recordButton.action = #selector(recordClicked)
        recordButton.toolTip = "Record audio"
        contentView.addSubview(recordButton)

        // Paste Button (icon)
        pasteButton = NSButton(frame: NSRect(x: 810, y: 669, width: 32, height: 32))
        pasteButton.title = ""
        pasteButton.bezelStyle = .texturedRounded
        pasteButton.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paste")
        pasteButton.target = self
        pasteButton.action = #selector(pasteClicked)
        pasteButton.toolTip = "Paste from clipboard"
        contentView.addSubview(pasteButton)

        // Input Text View with Scroll View
        let inputScrollView = NSScrollView(frame: NSRect(x: 26, y: 399, width: 814, height: 268))
        inputScrollView.hasVerticalScroller = true
        inputScrollView.autohidesScrollers = true
        inputScrollView.scrollerStyle = .overlay
        inputScrollView.borderType = .bezelBorder

        inputTextView = NSTextView(frame: inputScrollView.bounds)
        inputTextView.isEditable = true
        inputTextView.isSelectable = true
        inputTextView.font = NSFont.systemFont(ofSize: 14)
        inputTextView.textContainerInset = NSSize(width: 5, height: 5)

        inputScrollView.documentView = inputTextView
        contentView.addSubview(inputScrollView)

        // OUTPUT SECTION
        let outputLabel = NSTextField(labelWithString: "OUTPUT")
        outputLabel.font = NSFont.boldSystemFont(ofSize: 13)
        outputLabel.frame = NSRect(x: 26, y: 332, width: 760, height: 26)
        contentView.addSubview(outputLabel)

        // Copy Button (icon)
        copyButton = NSButton(frame: NSRect(x: 772, y: 329, width: 32, height: 32))
        copyButton.title = ""
        copyButton.bezelStyle = .texturedRounded
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        copyButton.toolTip = "Copy to clipboard"
        contentView.addSubview(copyButton)

        // Copy and Close Button (icon)
        copyAndCloseButton = NSButton(frame: NSRect(x: 810, y: 329, width: 32, height: 32))
        copyAndCloseButton.title = ""
        copyAndCloseButton.bezelStyle = .texturedRounded
        copyAndCloseButton.image = NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: "Copy and Close")
        copyAndCloseButton.target = self
        copyAndCloseButton.action = #selector(copyAndCloseClicked)
        copyAndCloseButton.toolTip = "Copy to clipboard and close window"
        contentView.addSubview(copyAndCloseButton)

        // Output Text View with Scroll View
        let outputScrollView = NSScrollView(frame: NSRect(x: 26, y: 54, width: 814, height: 273))
        outputScrollView.hasVerticalScroller = true
        outputScrollView.autohidesScrollers = true
        outputScrollView.scrollerStyle = .overlay
        outputScrollView.borderType = .bezelBorder

        outputTextView = NSTextView(frame: outputScrollView.bounds)
        outputTextView.isEditable = true
        outputTextView.isSelectable = true
        outputTextView.font = NSFont.systemFont(ofSize: 14)
        outputTextView.textContainerInset = NSSize(width: 5, height: 5)

        outputScrollView.documentView = outputTextView
        contentView.addSubview(outputScrollView)

        // WORKFLOWS PANEL (RIGHT SIDE)
        let workflowsLabel = NSTextField(labelWithString: "WORKFLOWS")
        workflowsLabel.font = NSFont.boldSystemFont(ofSize: 13)
        workflowsLabel.frame = NSRect(x: 870, y: 672, width: 200, height: 26)
        contentView.addSubview(workflowsLabel)

        // Configure Workflows Button (gear icon only)
        workflowsButton = NSButton(frame: NSRect(x: 1102, y: 669, width: 32, height: 32))
        workflowsButton.title = ""
        workflowsButton.bezelStyle = .texturedRounded
        workflowsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Configure")
        workflowsButton.target = self
        workflowsButton.action = #selector(workflowsClicked)
        workflowsButton.toolTip = "Configure workflows"
        contentView.addSubview(workflowsButton)

        // Workflow Buttons Container with Scroll View
        workflowButtonsScrollView = NSScrollView(frame: NSRect(x: 870, y: 78, width: 270, height: 589))
        workflowButtonsScrollView.hasVerticalScroller = true
        workflowButtonsScrollView.autohidesScrollers = true
        workflowButtonsScrollView.scrollerStyle = .overlay
        workflowButtonsScrollView.borderType = .noBorder
        workflowButtonsScrollView.drawsBackground = false
        workflowButtonsScrollView.backgroundColor = .clear

        workflowButtonsContainer = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 559))
        workflowButtonsScrollView.documentView = workflowButtonsContainer
        contentView.addSubview(workflowButtonsScrollView)

        // Progress Indicator (bottom left)
        progressIndicator = NSProgressIndicator(frame: NSRect(x: 26, y: 20, width: 26, height: 26))
        progressIndicator.style = .spinning
        progressIndicator.isHidden = true
        contentView.addSubview(progressIndicator)

        // Status Label (bottom left)
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.frame = NSRect(x: 60, y: 16, width: 400, height: 32)
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        contentView.addSubview(statusLabel)

        // Copy and Close Button (bottom right, next to close)
        let copyAndCloseBottomButton = NSButton(frame: NSRect(x: 878, y: 26, width: 139, height: 42))
        copyAndCloseBottomButton.title = "Copy and Close"
        copyAndCloseBottomButton.bezelStyle = .rounded
        copyAndCloseBottomButton.target = self
        copyAndCloseBottomButton.action = #selector(copyAndCloseClicked)
        contentView.addSubview(copyAndCloseBottomButton)

        // Close Button (bottom right)
        closeButton = NSButton(frame: NSRect(x: 1027, y: 26, width: 117, height: 42))
        closeButton.title = "Close"
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        contentView.addSubview(closeButton)

        // Hotkey Label (below close button)
        hotkeyLabel = NSTextField(labelWithString: "")
        hotkeyLabel.font = NSFont.systemFont(ofSize: 10)
        hotkeyLabel.textColor = .tertiaryLabelColor
        hotkeyLabel.frame = NSRect(x: 1027, y: 8, width: 117, height: 16)
        hotkeyLabel.alignment = .center
        hotkeyLabel.isEditable = false
        hotkeyLabel.isBordered = false
        hotkeyLabel.backgroundColor = .clear
        contentView.addSubview(hotkeyLabel)

        // Update hotkey label with current configuration
        updateHotkeyLabel()

        // Load workflow buttons
        loadWorkflowButtons()
    }

    private func loadWorkflowButtons() {
        // Clear existing buttons and shortcuts
        workflowButtonsContainer.subviews.forEach { $0.removeFromSuperview() }
        workflowShortcuts.removeAll()

        let enabledWorkflows = workflowManager.getEnabledWorkflows()

        if enabledWorkflows.isEmpty {
            let noWorkflowsLabel = NSTextField(labelWithString: "No workflows configured.\n\nClick the gear icon to\ncreate your first workflow.")
            noWorkflowsLabel.font = NSFont.systemFont(ofSize: 12)
            noWorkflowsLabel.textColor = .secondaryLabelColor
            noWorkflowsLabel.alignment = .center
            noWorkflowsLabel.frame = NSRect(x: 0, y: 220, width: 250, height: 120)
            noWorkflowsLabel.isEditable = false
            noWorkflowsLabel.isBordered = false
            noWorkflowsLabel.backgroundColor = .clear
            workflowButtonsContainer.addSubview(noWorkflowsLabel)
            return
        }

        // Create card-style workflow items using NSView containers
        // Reduced dimensions: 10% narrower width, 20% shorter height
        let itemWidth: CGFloat = 245  // 272 * 0.9
        let itemHeight: CGFloat = 84  // 105 * 0.8
        let itemSpacing: CGFloat = 10
        let xOffset: CGFloat = (250 - itemWidth) / 2  // Center cards in scroll view
        let topPadding: CGFloat = 10

        // Calculate container height (minimum is scroll view height)
        let minContainerHeight: CGFloat = 589
        let totalHeight = max(minContainerHeight, CGFloat(enabledWorkflows.count) * (itemHeight + itemSpacing) + topPadding * 2)
        workflowButtonsContainer.frame = NSRect(x: 0, y: 0, width: 250, height: totalHeight)

        // Start from the top and work down
        var yPosition: CGFloat = totalHeight - topPadding - itemHeight

        for (index, workflow) in enabledWorkflows.enumerated() {
            // Store workflow for keyboard shortcuts (first 9 workflows get Cmd+1-9)
            if index < 9 {
                workflowShortcuts[index + 1] = workflow
            }

            // Create container view styled as a card with subtle tint
            let cardView = NSView(frame: NSRect(x: xOffset, y: yPosition, width: itemWidth, height: itemHeight))
            cardView.wantsLayer = true

            // Use a subtle blue/tinted background that works in both light and dark mode
            let cardColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
            cardView.layer?.backgroundColor = cardColor.cgColor
            cardView.layer?.cornerRadius = 8
            cardView.layer?.borderWidth = 1
            cardView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor

            // Add keyboard shortcut tooltip if within first 9
            let shortcutHint = index < 9 ? " (⌘\(index + 1))" : ""
            cardView.toolTip = "Prompt: \(workflow.prompt)\(shortcutHint)"

            // Add click gesture recognizer
            let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(workflowCardClicked(_:)))
            cardView.addGestureRecognizer(clickGesture)

            // Store workflow ID in the view for later retrieval
            cardView.identifier = NSUserInterfaceItemIdentifier(workflow.id.uuidString)

            // Add workflow icon
            let iconView = NSImageView(frame: NSRect(x: 12, y: 32, width: 24, height: 24))
            iconView.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Workflow")
            iconView.contentTintColor = .systemBlue
            cardView.addSubview(iconView)

            // Add workflow name label with keyboard shortcut badge
            let nameText = index < 9 ? "\(workflow.name) ⌘\(index + 1)" : workflow.name
            let nameLabel = NSTextField(labelWithString: nameText)
            nameLabel.font = NSFont.boldSystemFont(ofSize: 12)
            nameLabel.textColor = .labelColor
            nameLabel.frame = NSRect(x: 44, y: 48, width: itemWidth - 50, height: 18)
            nameLabel.isEditable = false
            nameLabel.isBordered = false
            nameLabel.drawsBackground = false
            nameLabel.alignment = .left
            nameLabel.lineBreakMode = .byTruncatingTail
            cardView.addSubview(nameLabel)

            // Add workflow description label
            let descLabel = NSTextField(labelWithString: workflow.truncatedDescription)
            descLabel.font = NSFont.systemFont(ofSize: 10)
            descLabel.textColor = .secondaryLabelColor
            descLabel.frame = NSRect(x: 44, y: 12, width: itemWidth - 50, height: 32)
            descLabel.isEditable = false
            descLabel.isBordered = false
            descLabel.drawsBackground = false
            descLabel.alignment = .left
            descLabel.lineBreakMode = .byWordWrapping
            descLabel.maximumNumberOfLines = 2
            cardView.addSubview(descLabel)

            workflowButtonsContainer.addSubview(cardView)
            yPosition -= (itemHeight + itemSpacing)
        }
    }

    @objc private func workflowCardClicked(_ sender: NSClickGestureRecognizer) {
        guard let cardView = sender.view,
              let identifier = cardView.identifier,
              let workflowId = UUID(uuidString: identifier.rawValue) else { return }

        // Find the workflow by ID
        let enabledWorkflows = workflowManager.getEnabledWorkflows()
        guard let workflow = enabledWorkflows.first(where: { $0.id == workflowId }) else {
            showError("Workflow not found")
            return
        }

        triggeredByHotkey = false  // Reset flag for manual clicks
        executeWorkflow(workflow)
    }

    @objc private func pasteClicked() {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string) {
            inputTextView.string = text
        }
    }

    @objc private func copyClicked() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(outputTextView.string, forType: .string)

        // Show confirmation
        statusLabel.stringValue = "✓ Copied to clipboard"
        statusLabel.textColor = .systemGreen

        // Clear after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.statusLabel.stringValue == "✓ Copied to clipboard" {
                self?.statusLabel.stringValue = ""
            }
        }
    }

    @objc private func copyAndCloseClicked() {
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(outputTextView.string, forType: .string)

        // Close window immediately
        window?.close()
    }


    private func executeWorkflow(_ workflow: Workflow) {
        // Prevent multiple simultaneous processing
        guard !currentlyProcessing else {
            let alert = NSAlert()
            alert.messageText = "Processing in Progress"
            alert.informativeText = "Please wait for the current workflow to complete."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Validate inputs
        let inputText = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inputText.isEmpty else {
            showError("Please enter text to process")
            return
        }

        guard let serviceId = workflow.serviceId else {
            showError("Workflow '\(workflow.name)' has no LLM service configured")
            return
        }

        // Start processing
        processWorkflow(workflow: workflow, inputText: inputText, serviceId: serviceId)
    }

    private func processWorkflow(workflow: Workflow, inputText: String, serviceId: String) {
        currentlyProcessing = true
        let wasTriggeredByHotkey = triggeredByHotkey

        if wasTriggeredByHotkey {
            // Close window and play sound for hotkey-triggered workflows
            window?.close()
            audioFeedback.startTranscribingSound()
        } else {
            // Show loading state for manual clicks
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
            statusLabel.stringValue = "Processing with \(workflow.name)..."
            statusLabel.textColor = .labelColor
            outputTextView.string = ""
        }

        // Call LLM processor
        llmProcessor.processText(text: inputText, prompt: workflow.prompt, modelId: serviceId) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.currentlyProcessing = false

                if !wasTriggeredByHotkey {
                    self?.progressIndicator.stopAnimation(nil)
                    self?.progressIndicator.isHidden = true
                }

                if let error = error {
                    if wasTriggeredByHotkey {
                        // Stop sound and show error alert for hotkey triggers
                        self?.audioFeedback.stopTranscribingSound()
                        self?.audioFeedback.playStopSound()

                        let alert = NSAlert()
                        alert.messageText = "Workflow Failed"
                        alert.informativeText = "Workflow: \(workflow.name)\n\n\(error.localizedDescription)"
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    } else {
                        self?.handleProcessingError(error, workflowName: workflow.name)
                    }
                } else if let result = result {
                    if wasTriggeredByHotkey {
                        // Stop sound and copy to clipboard (no auto-paste)
                        self?.audioFeedback.stopTranscribingSound()
                        self?.audioFeedback.playStopSound()

                        // Copy to clipboard
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(result, forType: .string)
                    } else {
                        // Show result in window for manual clicks
                        self?.outputTextView.string = result
                        self?.statusLabel.stringValue = "✓ Completed"
                        self?.statusLabel.textColor = .systemGreen

                        // Clear success message after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                            if self?.statusLabel.stringValue == "✓ Completed" {
                                self?.statusLabel.stringValue = ""
                            }
                        }
                    }
                } else {
                    if wasTriggeredByHotkey {
                        self?.audioFeedback.stopTranscribingSound()
                    }
                    self?.showError("Unknown error occurred")
                }

                // Reset the hotkey flag
                self?.triggeredByHotkey = false
            }
        }
    }

    private func handleProcessingError(_ error: Error, workflowName: String) {
        let nsError = error as NSError

        var errorMessage: String
        var helpText: String

        switch nsError.code {
        case 401:
            errorMessage = "Authentication Failed"
            helpText = "The API key may be invalid or expired. Please check your LLM service configuration in Settings."
        case 404:
            errorMessage = "Model Not Found"
            helpText = "The selected model is not available. Please select a different model."
        case 429:
            errorMessage = "Rate Limit Exceeded"
            helpText = "You've made too many requests. Please wait a moment and try again."
        case 500, 502, 503:
            errorMessage = "Server Error"
            helpText = "The LLM service is experiencing issues. Please try again later."
        default:
            errorMessage = "Processing Failed"
            helpText = error.localizedDescription
        }

        statusLabel.stringValue = "❌ Failed"
        statusLabel.textColor = .systemRed

        let alert = NSAlert()
        alert.messageText = errorMessage
        alert.informativeText = "Workflow: \(workflowName)\n\n\(helpText)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showError(_ message: String) {
        statusLabel.stringValue = "❌ Error"
        statusLabel.textColor = .systemRed

        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()

        // Clear error message after alert is dismissed
        statusLabel.stringValue = ""
    }

    private func autoPasteResult(_ text: String) {
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V to paste at cursor location
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let source = CGEventSource(stateID: .hidSystemState)

            // Press Cmd+V
            let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 'v' key
            vKeyDown?.flags = .maskCommand
            let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            vKeyUp?.flags = .maskCommand

            vKeyDown?.post(tap: .cghidEventTap)
            vKeyUp?.post(tap: .cghidEventTap)
        }
    }

    @objc private func recordClicked() {
        // Get reference to MenuBarManager from AppDelegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
           let menuBarManager = appDelegate.menuBarManager {
            // Trigger recording via menu bar manager
            if menuBarManager.isRecording {
                // Stop recording
                menuBarManager.stopRecordingAndTranscribe()
                recordButton.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "Record")
                recordButton.toolTip = "Record audio"
            } else {
                // Start recording
                menuBarManager.startRecording(toggleMode: true)
                recordButton.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop")
                recordButton.toolTip = "Stop recording"
            }
        }
    }

    @objc private func workflowsClicked() {
        // Open workflows configuration window
        workflowsWindowController = WorkflowsWindowController()

        if let workflowsWindow = workflowsWindowController?.window, let parentWindow = window {
            parentWindow.beginSheet(workflowsWindow) { [weak self] _ in
                // Reload workflow buttons when window closes
                self?.loadWorkflowButtons()
                self?.workflowsWindowController = nil
            }
        }
    }

    @objc private func closeClicked() {
        window?.close()
    }

    // MARK: - Hotkey Label Management

    private func updateHotkeyLabel() {
        let hotkey = SettingsManager.shared.workflowProcessorHotKey
        let mode = SettingsManager.shared.workflowProcessorMode

        var shortcutString = ""

        // Convert modifier flags to symbols
        if hotkey.modifierFlags.contains(.control) {
            shortcutString += "⌃"
        }
        if hotkey.modifierFlags.contains(.option) {
            shortcutString += "⌥"
        }
        if hotkey.modifierFlags.contains(.shift) {
            shortcutString += "⇧"
        }
        if hotkey.modifierFlags.contains(.command) {
            shortcutString += "⌘"
        }

        // Convert keycode to key name
        if let keyCode = hotkey.keyCode {
            let keyName = keyCodeToString(keyCode)
            shortcutString += keyName
        }

        // Add mode indicator if using double-tap
        if mode == "double-tap" {
            shortcutString += " (2x)"
        }

        hotkeyLabel.stringValue = shortcutString
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        // Map common keycodes to readable strings
        switch keyCode {
        // Letters
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"

        // Numbers
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"

        // Special keys
        case 36: return "↩"  // Return
        case 48: return "⇥"  // Tab
        case 49: return "Space"
        case 51: return "⌫"  // Delete
        case 53: return "⎋"  // Escape
        case 54: return "⌘R" // Right Command
        case 55: return "⌘L" // Left Command
        case 56: return "⇧L" // Left Shift
        case 57: return "⇪"  // Caps Lock
        case 58: return "⌥L" // Left Option
        case 59: return "⌃L" // Left Control
        case 60: return "⇧R" // Right Shift
        case 61: return "⌥R" // Right Option
        case 62: return "⌃R" // Right Control

        // Function keys
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"

        // Arrow keys
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"

        // Punctuation
        case 27: return "-"
        case 24: return "="
        case 33: return "["
        case 30: return "]"
        case 41: return ";"
        case 39: return "'"
        case 42: return "\\"
        case 43: return ","
        case 47: return "."
        case 44: return "/"
        case 50: return "`"

        default: return "?"
        }
    }

    // MARK: - Public Methods

    /// Populate input with text (e.g., from transcription)
    func setInputText(_ text: String) {
        inputTextView.string = text
    }

    /// Auto-paste from clipboard if enabled
    func autoPasteIfEnabled() {
        // This will be called from MenuBarManager when the setting is enabled
        pasteClicked()
    }
}
