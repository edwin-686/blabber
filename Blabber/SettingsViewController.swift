import Cocoa
import os.log

class SettingsViewController: NSViewController, NSWindowDelegate, NSTextFieldDelegate {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "ui")

    // UI Elements
    private var audioFeedbackCheckbox: NSButton!
    private var autoPasteCheckbox: NSButton!
    private var autoCopyCheckbox: NSButton!
    private var workflowAutoPasteCheckbox: NSButton!
    private var maxRecordingDurationTextField: NSTextField!
    private var historySizeTextField: NSTextField!
    private var modelSelectorPopup: NSPopUpButton!
    private var languageSelectorPopup: NSPopUpButton!
    private var downloadModelsButton: NSButton!

    // Hotkey Recorders
    private var holdToRecordRecorder: HotKeyRecorderControl!
    private var toggleRecordingRecorder: HotKeyRecorderControl!
    private var workflowProcessorRecorder: HotKeyRecorderControl!

    // Pending hotkey changes (saved only when window closes)
    private var pendingHoldToRecordHotKey: (keyCode: UInt16?, modifierFlags: NSEvent.ModifierFlags)?
    private var pendingToggleRecordingHotKey: (keyCode: UInt16?, modifierFlags: NSEvent.ModifierFlags)?
    private var pendingWorkflowProcessorHotKey: (keyCode: UInt16?, modifierFlags: NSEvent.ModifierFlags)?
    private var pendingWorkflowProcessorMode: String?

    private let settings = SettingsManager.shared
    private let modelManager = ModelManager.shared
    private let cloudManager = CloudModelManager.shared

    // Reference to AppDelegate to disable hotkeys while configuring
    private weak var appDelegate: AppDelegate?

    // Keep reference to window controllers so they don't get deallocated
    private var modelDownloadWindowController: ModelDownloadWindowController?
    private var cloudModelsWindowController: CloudModelsWindowController?
    private var workflowsWindowController: WorkflowsWindowController?
    private var findReplaceWindowController: FindReplaceWindowController?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 810))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Get reference to AppDelegate
        if let app = NSApplication.shared.delegate as? AppDelegate {
            appDelegate = app
        }

        setupUI()
        loadSettings()
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        // Disable hotkeys while configuring to avoid conflicts
        appDelegate?.disableHotKeys()

        // Set self as window delegate to intercept close attempts
        view.window?.delegate = self

        // Prevent auto-focus on any recorder
        view.window?.makeFirstResponder(nil)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()

        // Save pending hotkey changes
        savePendingHotKeyChanges()

        // Re-enable hotkeys
        appDelegate?.enableHotKeys()
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Check for hotkey conflicts before allowing window to close
        if hasHotKeyConflicts() {
            showConflictPreventionAlert()
            return false  // Prevent window from closing
        }
        return true  // Allow window to close
    }

    private func setupUI() {
        var yPosition: CGFloat = 770

        // General Section
        let generalLabel = createLabel(text: "General", fontSize: 13, bold: true)
        generalLabel.frame = NSRect(x: 20, y: yPosition, width: 410, height: 20)
        view.addSubview(generalLabel)
        yPosition -= 35

        // Audio Feedback
        audioFeedbackCheckbox = createCheckbox(title: "Play sounds when recording starts/stops")
        audioFeedbackCheckbox.frame = NSRect(x: 30, y: yPosition, width: 400, height: 20)
        audioFeedbackCheckbox.target = self
        audioFeedbackCheckbox.action = #selector(audioFeedbackChanged)
        view.addSubview(audioFeedbackCheckbox)
        yPosition -= 30

        // Auto Paste
        autoPasteCheckbox = createCheckbox(title: "Automatically paste transcription")
        autoPasteCheckbox.frame = NSRect(x: 30, y: yPosition, width: 400, height: 20)
        autoPasteCheckbox.target = self
        autoPasteCheckbox.action = #selector(autoPasteChanged)
        view.addSubview(autoPasteCheckbox)
        yPosition -= 30

        // Auto Copy
        autoCopyCheckbox = createCheckbox(title: "Always copy to clipboard (even without paste)")
        autoCopyCheckbox.frame = NSRect(x: 30, y: yPosition, width: 400, height: 20)
        autoCopyCheckbox.target = self
        autoCopyCheckbox.action = #selector(autoCopyChanged)
        view.addSubview(autoCopyCheckbox)
        yPosition -= 35

        // Max Recording Duration Label
        let maxDurationLabel = createLabel(text: "Max recording duration (minutes):", fontSize: 13, bold: false)
        maxDurationLabel.frame = NSRect(x: 30, y: yPosition, width: 320, height: 20)
        view.addSubview(maxDurationLabel)

        // Max Recording Duration Text Field
        maxRecordingDurationTextField = NSTextField(frame: NSRect(x: 360, y: yPosition - 2, width: 60, height: 22))
        maxRecordingDurationTextField.placeholderString = "10"
        maxRecordingDurationTextField.target = self
        maxRecordingDurationTextField.action = #selector(maxRecordingDurationChanged)
        maxRecordingDurationTextField.delegate = self
        view.addSubview(maxRecordingDurationTextField)
        yPosition -= 35

        // History Size Label (moved to General section)
        let historySizeLabel = createLabel(text: "History items to keep:", fontSize: 13, bold: false)
        historySizeLabel.frame = NSRect(x: 30, y: yPosition, width: 320, height: 20)
        view.addSubview(historySizeLabel)

        // History Size Text Field
        historySizeTextField = NSTextField(frame: NSRect(x: 360, y: yPosition - 2, width: 60, height: 22))
        historySizeTextField.placeholderString = "5"
        historySizeTextField.target = self
        historySizeTextField.action = #selector(historySizeChanged)
        historySizeTextField.delegate = self
        view.addSubview(historySizeTextField)
        yPosition -= 45

        // Hotkeys Section
        let hotkeysLabel = createLabel(text: "Hotkeys", fontSize: 13, bold: true)
        hotkeysLabel.frame = NSRect(x: 20, y: yPosition, width: 80, height: 20)
        view.addSubview(hotkeysLabel)

        // Info icon next to Hotkeys label
        let infoIcon = NSImageView(frame: NSRect(x: 95, y: yPosition + 3, width: 14, height: 14))
        if let infoImage = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Hotkey configuration guide") {
            infoIcon.image = infoImage
            infoIcon.contentTintColor = .secondaryLabelColor
            infoIcon.toolTip = createHotkeyGuideTooltip()
        }

        // Add click gesture recognizer to show popover immediately
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(infoIconClicked(_:)))
        infoIcon.addGestureRecognizer(clickGesture)

        view.addSubview(infoIcon)
        yPosition -= 35

        // Hold to Record Label
        let holdToRecordLabel = createLabel(text: "Press and hold to record:", fontSize: 13, bold: false)
        holdToRecordLabel.frame = NSRect(x: 30, y: yPosition, width: 200, height: 20)
        view.addSubview(holdToRecordLabel)

        // Hold to Record Recorder
        holdToRecordRecorder = HotKeyRecorderControl(frame: NSRect(x: 240, y: yPosition - 2, width: 180, height: 26))
        holdToRecordRecorder.allowModifierKeys = true  // Allow single/multiple modifier keys
        holdToRecordRecorder.onHotKeyChanged = { [weak self] keyCode, modifierFlags in
            self?.holdToRecordHotKeyChanged(keyCode: keyCode, modifierFlags: modifierFlags)
        }
        view.addSubview(holdToRecordRecorder)
        yPosition -= 35

        // Toggle Recording Label
        let toggleRecordingLabel = createLabel(text: "Start/stop recording:", fontSize: 13, bold: false)
        toggleRecordingLabel.frame = NSRect(x: 30, y: yPosition, width: 200, height: 20)
        view.addSubview(toggleRecordingLabel)

        // Toggle Recording Recorder
        toggleRecordingRecorder = HotKeyRecorderControl(frame: NSRect(x: 240, y: yPosition - 2, width: 180, height: 26))
        toggleRecordingRecorder.allowSingleKey = true  // Allow single key with double-tap
        toggleRecordingRecorder.singleKeyOnly = true  // Restrict to single keys only
        toggleRecordingRecorder.onHotKeyChanged = { [weak self] keyCode, modifierFlags in
            self?.toggleRecordingHotKeyChanged(keyCode: keyCode, modifierFlags: modifierFlags)
        }
        view.addSubview(toggleRecordingRecorder)
        yPosition -= 35

        // Workflow Processor Label
        let workflowProcessorLabel = createLabel(text: "Open workflow processor:", fontSize: 13, bold: false)
        workflowProcessorLabel.frame = NSRect(x: 30, y: yPosition, width: 200, height: 20)
        view.addSubview(workflowProcessorLabel)

        // Workflow Processor Recorder
        workflowProcessorRecorder = HotKeyRecorderControl(frame: NSRect(x: 240, y: yPosition - 2, width: 180, height: 26))
        workflowProcessorRecorder.singleKeyOnly = true  // Single key only
        workflowProcessorRecorder.detectHoldMode = true  // Detect hold vs quick press
        workflowProcessorRecorder.onHotKeyChanged = { [weak self] keyCode, modifierFlags in
            self?.workflowProcessorHotKeyChanged(keyCode: keyCode, modifierFlags: modifierFlags)
        }
        workflowProcessorRecorder.onModeDetected = { [weak self] mode in
            self?.pendingWorkflowProcessorMode = mode
        }
        view.addSubview(workflowProcessorRecorder)
        yPosition -= 45

        // Models Section
        let modelsLabel = createLabel(text: "Transcription Model", fontSize: 13, bold: true)
        modelsLabel.frame = NSRect(x: 20, y: yPosition, width: 410, height: 20)
        view.addSubview(modelsLabel)
        yPosition -= 35

        // Language Selector Label
        let languageLabel = createLabel(text: "Language:", fontSize: 13, bold: false)
        languageLabel.frame = NSRect(x: 30, y: yPosition, width: 80, height: 20)
        view.addSubview(languageLabel)

        // Language Selector Popup
        languageSelectorPopup = NSPopUpButton(frame: NSRect(x: 115, y: yPosition - 2, width: 295, height: 25))
        languageSelectorPopup.target = self
        languageSelectorPopup.action = #selector(languageSelectionChanged)
        view.addSubview(languageSelectorPopup)
        yPosition -= 35

        // Current Model Label
        let currentModelLabel = createLabel(text: "Model:", fontSize: 13, bold: false)
        currentModelLabel.frame = NSRect(x: 30, y: yPosition, width: 80, height: 20)
        view.addSubview(currentModelLabel)

        // Model Selector Popup
        modelSelectorPopup = NSPopUpButton(frame: NSRect(x: 115, y: yPosition - 2, width: 295, height: 25))
        modelSelectorPopup.target = self
        modelSelectorPopup.action = #selector(modelSelectionChanged)
        view.addSubview(modelSelectorPopup)
        yPosition -= 55

        // Local Models Button
        downloadModelsButton = NSButton(frame: NSRect(x: 30, y: yPosition, width: 175, height: 32))
        downloadModelsButton.title = "Configure Local Model"
        downloadModelsButton.bezelStyle = .rounded
        downloadModelsButton.target = self
        downloadModelsButton.action = #selector(downloadModelsClicked)
        view.addSubview(downloadModelsButton)

        // Cloud Models Button
        let cloudModelsButton = NSButton(frame: NSRect(x: 215, y: yPosition, width: 175, height: 32))
        cloudModelsButton.title = "Configure Cloud Model"
        cloudModelsButton.bezelStyle = .rounded
        cloudModelsButton.target = self
        cloudModelsButton.action = #selector(cloudModelsClicked)
        view.addSubview(cloudModelsButton)
        yPosition -= 45

        // Find & Replace Button
        let findReplaceButton = NSButton(frame: NSRect(x: 30, y: yPosition, width: 150, height: 32))
        findReplaceButton.title = "Find & Replace..."
        findReplaceButton.bezelStyle = .rounded
        findReplaceButton.target = self
        findReplaceButton.action = #selector(findReplaceClicked)
        view.addSubview(findReplaceButton)
        yPosition -= 45

        // Workflows Section
        let workflowsLabel = createLabel(text: "Workflows", fontSize: 13, bold: true)
        workflowsLabel.frame = NSRect(x: 20, y: yPosition, width: 410, height: 20)
        view.addSubview(workflowsLabel)
        yPosition -= 30

        let workflowsDescLabel = createLabel(text: "Post-transcription text processing with LLMs", fontSize: 11, bold: false)
        workflowsDescLabel.frame = NSRect(x: 30, y: yPosition, width: 400, height: 18)
        workflowsDescLabel.textColor = .secondaryLabelColor
        view.addSubview(workflowsDescLabel)
        yPosition -= 35

        // Workflows Button
        let workflowsButton = NSButton(frame: NSRect(x: 30, y: yPosition, width: 150, height: 32))
        workflowsButton.title = "Workflows..."
        workflowsButton.bezelStyle = .rounded
        workflowsButton.target = self
        workflowsButton.action = #selector(workflowsClicked)
        view.addSubview(workflowsButton)
        yPosition -= 30

        // Auto-paste for Workflow Processor
        workflowAutoPasteCheckbox = createCheckbox(title: "Auto-paste clipboard when opening Workflow Processor")
        workflowAutoPasteCheckbox.frame = NSRect(x: 30, y: yPosition, width: 400, height: 20)
        workflowAutoPasteCheckbox.target = self
        workflowAutoPasteCheckbox.action = #selector(workflowAutoPasteChanged)
        view.addSubview(workflowAutoPasteCheckbox)
        yPosition -= 50

        // Reset Buttons
        let resetButton = NSButton(frame: NSRect(x: 30, y: 20, width: 150, height: 28))
        resetButton.title = "Reset to Defaults"
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetToDefaults)
        view.addSubview(resetButton)

        let resetHotkeysButton = NSButton(frame: NSRect(x: 190, y: 20, width: 140, height: 28))
        resetHotkeysButton.title = "Reset Hotkeys"
        resetHotkeysButton.bezelStyle = .rounded
        resetHotkeysButton.target = self
        resetHotkeysButton.action = #selector(resetHotkeys)
        view.addSubview(resetHotkeysButton)

        // Buy Me a Coffee text with icon
        let coffeeButton = NSButton(frame: NSRect(x: 340, y: 20, width: 100, height: 28))
        coffeeButton.bezelStyle = .inline
        coffeeButton.isBordered = false
        coffeeButton.target = self
        coffeeButton.action = #selector(buyMeCoffeeClicked)
        coffeeButton.toolTip = "Buy me a coffee"

        // Create attributed string with text and coffee icon
        let attributedTitle = NSMutableAttributedString()

        // Add "BuyMeA" text
        let textAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.systemFont(ofSize: 13)
        ]
        attributedTitle.append(NSAttributedString(string: "BuyMeA", attributes: textAttributes))

        // Add coffee icon
        if let coffeeIcon = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Coffee") {
            let iconSize = NSSize(width: 16, height: 16)
            coffeeIcon.size = iconSize

            let imageAttachment = NSTextAttachment()
            imageAttachment.image = coffeeIcon
            imageAttachment.bounds = NSRect(x: 0, y: -2, width: iconSize.width, height: iconSize.height)

            attributedTitle.append(NSAttributedString(attachment: imageAttachment))
        }

        coffeeButton.attributedTitle = attributedTitle

        view.addSubview(coffeeButton)
    }

    private func createLabel(text: String, fontSize: CGFloat, bold: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        return label
    }

    private func createCheckbox(title: String) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        return checkbox
    }

    private func createHotkeyGuideTooltip() -> String {
        return """
        Hotkey Configuration Guide

        Press-and-Hold to Record:
        • Use 1-2 modifier keys (⌘⌥⌃⇧)
        • Example: ⌘R (right command)

        Double-Tap to Start/Stop:
        • Single modifier key only
        • Example: ⌥R (double tap)

        Workflow Processor:
        • Single modifier key only
        • Can be configured as "hold" or "double tap" mode
        • Examples: ⌥R (press and hold) or ⌥R (double tap)
        """
    }

    @objc private func infoIconClicked(_ sender: NSClickGestureRecognizer) {
        guard let iconView = sender.view else { return }

        // Create popover with the guide content
        let popover = NSPopover()
        let viewController = NSViewController()
        viewController.view = NSView(frame: NSRect(x: 0, y: 0, width: 325, height: 200))

        // Create text view with the guide content
        let textView = NSTextView(frame: NSRect(x: 10, y: 10, width: 305, height: 180))
        textView.string = createHotkeyGuideTooltip()
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 11)
        viewController.view.addSubview(textView)

        popover.contentViewController = viewController
        popover.behavior = .transient
        popover.show(relativeTo: iconView.bounds, of: iconView, preferredEdge: .maxY)
    }

    private func loadSettings() {
        audioFeedbackCheckbox.state = settings.audioFeedbackEnabled ? .on : .off
        autoPasteCheckbox.state = settings.autoPasteEnabled ? .on : .off
        autoCopyCheckbox.state = settings.autoCopyEnabled ? .on : .off
        workflowAutoPasteCheckbox.state = settings.workflowAutoPasteEnabled ? .on : .off
        maxRecordingDurationTextField.stringValue = String(Int(settings.maxRecordingDuration / 60))
        historySizeTextField.stringValue = String(settings.historySize)

        // Load hotkeys
        let holdToRecord = settings.holdToRecordHotKey
        holdToRecordRecorder.setHotKey(keyCode: holdToRecord.keyCode, modifierFlags: holdToRecord.modifierFlags)

        let toggleRecording = settings.toggleRecordingHotKey
        toggleRecordingRecorder.setHotKey(keyCode: toggleRecording.keyCode, modifierFlags: toggleRecording.modifierFlags)

        let workflowProcessor = settings.workflowProcessorHotKey
        let workflowMode = settings.workflowProcessorMode
        workflowProcessorRecorder.setHotKey(keyCode: workflowProcessor.keyCode, modifierFlags: workflowProcessor.modifierFlags, mode: workflowMode)

        // Load installed models and language selector
        loadModelSelector()
        loadLanguageSelector()
    }

    private func loadModelSelector() {
        modelSelectorPopup.removeAllItems()

        let installedModels = modelManager.getInstalledModels()
        let configuredCloudModels = cloudManager.getConfiguredTranscriptionModels()

        if installedModels.isEmpty && configuredCloudModels.isEmpty {
            modelSelectorPopup.addItem(withTitle: "No models available - download or configure one")
            modelSelectorPopup.isEnabled = false
            return
        }

        modelSelectorPopup.isEnabled = true

        // Get current model path/ID
        let currentSelection = settings.whisperModelPath

        var selectedIndex = 0
        var currentIndex = 0
        var foundValidSelection = false

        // Add local models
        if !installedModels.isEmpty {
            // Add separator label (not selectable)
            modelSelectorPopup.addItem(withTitle: "Local Models")
            if let menuItem = modelSelectorPopup.item(at: currentIndex) {
                menuItem.isEnabled = false
            }
            currentIndex += 1

            for model in installedModels {
                modelSelectorPopup.addItem(withTitle: "  " + model.dropdownDisplayName)

                // Check if this is the currently selected model
                if modelManager.modelPath(for: model).path == currentSelection {
                    selectedIndex = currentIndex
                    foundValidSelection = true
                }
                currentIndex += 1
            }
        }

        // Add cloud models
        if !configuredCloudModels.isEmpty {
            // Add separator label
            modelSelectorPopup.addItem(withTitle: "Cloud Models")
            if let menuItem = modelSelectorPopup.item(at: currentIndex) {
                menuItem.isEnabled = false
            }
            currentIndex += 1

            for model in configuredCloudModels {
                modelSelectorPopup.addItem(withTitle: "  " + model.dropdownDisplayName)

                // Check if this is the currently selected model (store cloud model IDs with "cloud:" prefix)
                if currentSelection == "cloud:\(model.id)" {
                    selectedIndex = currentIndex
                    foundValidSelection = true
                }
                currentIndex += 1
            }
        }

        // If the configured model doesn't exist, select the first valid model
        if !foundValidSelection {
            if !installedModels.isEmpty {
                // Select first local model (index 1, after "Local Models" separator)
                selectedIndex = 1
                let firstModel = installedModels[0]
                let newPath = modelManager.modelPath(for: firstModel).path
                settings.whisperModelPath = newPath
                os_log(.info, log: Self.logger, "Configured model not found, auto-selected first local model: %{public}s", firstModel.name)
            } else if !configuredCloudModels.isEmpty {
                // Select first cloud model (after "Cloud Models" separator)
                selectedIndex = 1
                let firstCloudModel = configuredCloudModels[0]
                settings.whisperModelPath = "cloud:\(firstCloudModel.id)"
                os_log(.info, log: Self.logger, "Configured model not found, auto-selected first cloud model: %{public}s", firstCloudModel.displayName)
            }
        }

        modelSelectorPopup.selectItem(at: selectedIndex)
    }

    private func loadLanguageSelector() {
        languageSelectorPopup.removeAllItems()

        // Top 20 languages + Auto Detect (sorted alphabetically after Auto)
        let languages: [(name: String, code: String)] = [
            ("Auto Detect", "auto"),
            ("Afrikaans", "af"),
            ("Arabic", "ar"),
            ("Chinese", "zh"),
            ("Danish", "da"),
            ("Dutch", "nl"),
            ("English", "en"),
            ("French", "fr"),
            ("German", "de"),
            ("Hindi", "hi"),
            ("Italian", "it"),
            ("Japanese", "ja"),
            ("Korean", "ko"),
            ("Norwegian", "no"),
            ("Polish", "pl"),
            ("Portuguese", "pt"),
            ("Russian", "ru"),
            ("Spanish", "es"),
            ("Swedish", "sv"),
            ("Turkish", "tr"),
            ("Vietnamese", "vi")
        ]

        // Add languages to dropdown
        for (name, _) in languages {
            languageSelectorPopup.addItem(withTitle: name)
        }

        // Select current language
        let currentLanguage = settings.transcriptionLanguage
        for (index, (_, code)) in languages.enumerated() {
            if code == currentLanguage {
                languageSelectorPopup.selectItem(at: index)
                break
            }
        }
    }

    @objc private func languageSelectionChanged() {
        // Map display names back to language codes
        let languages: [(name: String, code: String)] = [
            ("Auto Detect", "auto"),
            ("Afrikaans", "af"),
            ("Arabic", "ar"),
            ("Chinese", "zh"),
            ("Danish", "da"),
            ("Dutch", "nl"),
            ("English", "en"),
            ("French", "fr"),
            ("German", "de"),
            ("Hindi", "hi"),
            ("Italian", "it"),
            ("Japanese", "ja"),
            ("Korean", "ko"),
            ("Norwegian", "no"),
            ("Polish", "pl"),
            ("Portuguese", "pt"),
            ("Russian", "ru"),
            ("Spanish", "es"),
            ("Swedish", "sv"),
            ("Turkish", "tr"),
            ("Vietnamese", "vi")
        ]

        let selectedTitle = languageSelectorPopup.titleOfSelectedItem ?? "Auto Detect"
        for (name, code) in languages {
            if name == selectedTitle {
                settings.transcriptionLanguage = code
                #if DEBUG
                print("SettingsViewController: Transcription language changed to: \(code)")
                #endif
                break
            }
        }
    }

    @objc private func audioFeedbackChanged() {
        settings.audioFeedbackEnabled = (audioFeedbackCheckbox.state == .on)
        #if DEBUG
        print("SettingsViewController: Audio feedback: \(settings.audioFeedbackEnabled)")
        #endif
    }

    @objc private func autoPasteChanged() {
        settings.autoPasteEnabled = (autoPasteCheckbox.state == .on)
        #if DEBUG
        print("SettingsViewController: Auto paste: \(settings.autoPasteEnabled)")
        #endif
    }

    @objc private func autoCopyChanged() {
        settings.autoCopyEnabled = (autoCopyCheckbox.state == .on)
        #if DEBUG
        print("SettingsViewController: Auto copy: \(settings.autoCopyEnabled)")
        #endif
    }

    @objc private func workflowAutoPasteChanged() {
        settings.workflowAutoPasteEnabled = (workflowAutoPasteCheckbox.state == .on)
        #if DEBUG
        print("SettingsViewController: Workflow auto paste: \(settings.workflowAutoPasteEnabled)")
        #endif
    }

    @objc private func maxRecordingDurationChanged() {
        // Parse minutes from text field and convert to seconds
        if let minutes = Double(maxRecordingDurationTextField.stringValue) {
            settings.maxRecordingDuration = minutes * 60
            #if DEBUG
            print("SettingsViewController: Max recording duration: \(minutes) minutes (\(settings.maxRecordingDuration) seconds)")
            #endif
        } else {
            // Invalid input, reset to current setting
            maxRecordingDurationTextField.stringValue = String(Int(settings.maxRecordingDuration / 60))
        }
    }

    @objc private func historySizeChanged() {
        // Parse number from text field (5-50 range)
        if let value = Int(historySizeTextField.stringValue), value >= 5, value <= 50 {
            settings.historySize = value
            #if DEBUG
            print("SettingsViewController: History size: \(value)")
            #endif
        } else {
            // Invalid input, reset to current setting
            historySizeTextField.stringValue = String(settings.historySize)
        }
    }

    private func holdToRecordHotKeyChanged(keyCode: UInt16?, modifierFlags: NSEvent.ModifierFlags) {
        // Store as pending change
        pendingHoldToRecordHotKey = (keyCode, modifierFlags)
        #if DEBUG
        print("SettingsViewController: Hold to record hotkey changed (pending): keyCode=\(String(describing: keyCode)), flags=\(modifierFlags)")
        #endif

        // Check for conflicts
        checkHotKeyConflicts()
    }

    private func toggleRecordingHotKeyChanged(keyCode: UInt16?, modifierFlags: NSEvent.ModifierFlags) {
        // Store as pending change
        pendingToggleRecordingHotKey = (keyCode, modifierFlags)
        #if DEBUG
        print("SettingsViewController: Toggle recording hotkey changed (pending): keyCode=\(String(describing: keyCode)), flags=\(modifierFlags)")
        #endif

        // Check for conflicts
        checkHotKeyConflicts()
    }

    private func workflowProcessorHotKeyChanged(keyCode: UInt16?, modifierFlags: NSEvent.ModifierFlags) {
        // Store as pending change
        pendingWorkflowProcessorHotKey = (keyCode, modifierFlags)
        #if DEBUG
        print("SettingsViewController: Workflow processor hotkey changed (pending): keyCode=\(String(describing: keyCode)), flags=\(modifierFlags)")
        #endif

        // Check for conflicts
        checkHotKeyConflicts()
    }

    private func savePendingHotKeyChanges() {
        // Save pending hotkey changes when window closes
        if let pending = pendingHoldToRecordHotKey {
            settings.holdToRecordHotKey = pending
            #if DEBUG
            print("SettingsViewController: Saved hold to record hotkey: keyCode=\(String(describing: pending.keyCode)), flags=\(pending.modifierFlags)")
            #endif
        }

        if let pending = pendingToggleRecordingHotKey {
            settings.toggleRecordingHotKey = pending
            #if DEBUG
            print("SettingsViewController: Saved toggle recording hotkey: keyCode=\(String(describing: pending.keyCode)), flags=\(pending.modifierFlags)")
            #endif
        }

        if let pending = pendingWorkflowProcessorHotKey {
            settings.workflowProcessorHotKey = pending
            #if DEBUG
            print("SettingsViewController: Saved workflow processor hotkey: keyCode=\(String(describing: pending.keyCode)), flags=\(pending.modifierFlags)")
            #endif
        }

        if let mode = pendingWorkflowProcessorMode {
            settings.workflowProcessorMode = mode
            #if DEBUG
            print("SettingsViewController: Saved workflow processor mode: \(mode)")
            #endif
        }

        // Clear pending changes
        pendingHoldToRecordHotKey = nil
        pendingToggleRecordingHotKey = nil
        pendingWorkflowProcessorHotKey = nil
        pendingWorkflowProcessorMode = nil
    }

    private func checkHotKeyConflicts() {
        // Get current pending or saved hotkeys
        let holdToRecord = pendingHoldToRecordHotKey ?? settings.holdToRecordHotKey
        let toggleRecording = pendingToggleRecordingHotKey ?? settings.toggleRecordingHotKey
        let workflowProcessor = pendingWorkflowProcessorHotKey ?? settings.workflowProcessorHotKey
        let workflowMode = pendingWorkflowProcessorMode ?? settings.workflowProcessorMode

        // NOTE: Press-and-hold and start/stop CAN use the same key (this is intentional)
        // The app already has logic to prevent double-recording

        // Mode-aware conflict detection:
        // - Only conflict if same key AND same mode
        // - Different modes on same key are allowed

        // Check for conflicts between press-and-hold (hold mode) and workflow processor in hold mode
        if workflowMode == "hold" {
            if let hold = holdToRecord.keyCode, let workflow = workflowProcessor.keyCode,
               hold == workflow && holdToRecord.modifierFlags == workflowProcessor.modifierFlags {
                showConflictAlert(hotkey1: "Press and hold to record", hotkey2: "Workflow processor (hold mode)")
            }
        }

        // Check for conflicts between start/stop (double-tap mode) and workflow processor in double-tap mode
        if workflowMode == "double-tap" {
            if let toggle = toggleRecording.keyCode, let workflow = workflowProcessor.keyCode,
               toggle == workflow && toggleRecording.modifierFlags == workflowProcessor.modifierFlags {
                showConflictAlert(hotkey1: "Start/stop recording (double-tap)", hotkey2: "Workflow processor (double-tap mode)")
            }
        }
    }

    private func showConflictAlert(hotkey1: String, hotkey2: String) {
        let alert = NSAlert()
        alert.messageText = "Hotkey Conflict"
        alert.informativeText = "'\(hotkey1)' and '\(hotkey2)' have the same hotkey. This may cause unexpected behavior."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func hasHotKeyConflicts() -> Bool {
        // Get current pending or saved hotkeys
        let holdToRecord = pendingHoldToRecordHotKey ?? settings.holdToRecordHotKey
        let toggleRecording = pendingToggleRecordingHotKey ?? settings.toggleRecordingHotKey
        let workflowProcessor = pendingWorkflowProcessorHotKey ?? settings.workflowProcessorHotKey
        let workflowMode = pendingWorkflowProcessorMode ?? settings.workflowProcessorMode

        // Check for conflicts between press-and-hold (hold mode) and workflow processor in hold mode
        if workflowMode == "hold" {
            if let hold = holdToRecord.keyCode, let workflow = workflowProcessor.keyCode,
               hold == workflow && holdToRecord.modifierFlags == workflowProcessor.modifierFlags {
                return true
            }
        }

        // Check for conflicts between start/stop (double-tap mode) and workflow processor in double-tap mode
        if workflowMode == "double-tap" {
            if let toggle = toggleRecording.keyCode, let workflow = workflowProcessor.keyCode,
               toggle == workflow && toggleRecording.modifierFlags == workflowProcessor.modifierFlags {
                return true
            }
        }

        return false
    }

    private func showConflictPreventionAlert() {
        let alert = NSAlert()
        alert.messageText = "Cannot Close Settings"
        alert.informativeText = "You have unresolved hotkey conflicts. Please change one of the conflicting hotkeys or click \"Reset Hotkeys\" to resolve the issue before closing."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func modelSelectionChanged() {
        let selectedTitle = modelSelectorPopup.titleOfSelectedItem ?? ""

        // Skip if it's a separator
        if selectedTitle == "Local Models" || selectedTitle == "Cloud Models" {
            return
        }

        // Check if it's a cloud model
        if selectedTitle.contains("(Cloud)") {
            // Find the cloud model
            let configuredCloudModels = cloudManager.getConfiguredModels()
            for cloudModel in configuredCloudModels {
                let modelTitle = "  " + cloudModel.dropdownDisplayName
                if selectedTitle == modelTitle {
                    // Store cloud model with "cloud:" prefix
                    settings.whisperModelPath = "cloud:\(cloudModel.id)"
                    #if DEBUG
                    print("SettingsViewController: Selected cloud model: \(cloudModel.name) (ID: \(cloudModel.id))")
                    #endif
                    return
                }
            }
        } else {
            // It's a local model
            let installedModels = modelManager.getInstalledModels()
            for model in installedModels {
                let modelTitle = "  " + model.dropdownDisplayName
                if selectedTitle == modelTitle {
                    let modelPath = modelManager.modelPath(for: model).path
                    settings.whisperModelPath = modelPath
                    #if DEBUG
                    print("SettingsViewController: Selected local model: \(model.name) at \(modelPath)")
                    #endif
                    return
                }
            }
        }
    }

    @objc private func downloadModelsClicked() {
        // Show model download/management window as a sheet
        modelDownloadWindowController = ModelDownloadWindowController()
        modelDownloadWindowController?.onModelsChanged = { [weak self] in
            // Reload model selector when models are downloaded or deleted
            self?.loadModelSelector()
        }

        if let window = modelDownloadWindowController?.window {
            view.window?.beginSheet(window) { [weak self] _ in
                // Clear reference when sheet is dismissed
                self?.modelDownloadWindowController = nil
            }
        }
    }

    @objc private func cloudModelsClicked() {
        // Show cloud models management window as a sheet
        cloudModelsWindowController = CloudModelsWindowController()
        cloudModelsWindowController?.onModelsChanged = { [weak self] in
            // Reload model selector when cloud models are configured or removed
            self?.loadModelSelector()
        }

        if let window = cloudModelsWindowController?.window {
            view.window?.beginSheet(window) { [weak self] _ in
                // Clear reference when sheet is dismissed
                self?.cloudModelsWindowController = nil
            }
        }
    }

    @objc private func workflowsClicked() {
        // Show workflows management window as a sheet
        workflowsWindowController = WorkflowsWindowController()

        if let window = workflowsWindowController?.window {
            view.window?.beginSheet(window) { [weak self] _ in
                // Clear reference when sheet is dismissed
                self?.workflowsWindowController = nil
            }
        }
    }

    @objc private func findReplaceClicked() {
        // Show find & replace management window as a sheet
        findReplaceWindowController = FindReplaceWindowController()

        if let window = findReplaceWindowController?.window {
            view.window?.beginSheet(window) { [weak self] _ in
                // Clear reference when sheet is dismissed
                self?.findReplaceWindowController = nil
            }
        }
    }

    @objc private func resetToDefaults() {
        settings.resetToDefaults()
        loadSettings()
        os_log(.info, log: Self.logger, "Settings reset to defaults")

        // Show alert
        let alert = NSAlert()
        alert.messageText = "Settings Reset"
        alert.informativeText = "All settings have been reset to their default values."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func resetHotkeys() {
        // Reset only hotkeys to defaults
        settings.resetHotkeysToDefaults()

        // Clear pending changes
        pendingHoldToRecordHotKey = nil
        pendingToggleRecordingHotKey = nil
        pendingWorkflowProcessorHotKey = nil
        pendingWorkflowProcessorMode = nil

        // Update UI to show default hotkeys
        let holdToRecord = settings.holdToRecordHotKey
        holdToRecordRecorder.setHotKey(keyCode: holdToRecord.keyCode, modifierFlags: holdToRecord.modifierFlags)

        let toggleRecording = settings.toggleRecordingHotKey
        toggleRecordingRecorder.setHotKey(keyCode: toggleRecording.keyCode, modifierFlags: toggleRecording.modifierFlags)

        let workflowProcessor = settings.workflowProcessorHotKey
        let workflowMode = settings.workflowProcessorMode
        workflowProcessorRecorder.setHotKey(keyCode: workflowProcessor.keyCode, modifierFlags: workflowProcessor.modifierFlags, mode: workflowMode)

        os_log(.info, log: Self.logger, "Hotkeys reset to defaults")

        // Show alert
        let alert = NSAlert()
        alert.messageText = "Hotkeys Reset"
        alert.informativeText = "All hotkey configurations have been reset to their default values."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func buyMeCoffeeClicked() {
        if let url = URL(string: "https://buymeacoffee.com/blabbernotes") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Allow default behavior for Return/Enter and Tab
        return false
    }

    func controlTextDidChange(_ notification: Notification) {
        // Validate input as it's typed - only allow numeric characters
        guard let textField = notification.object as? NSTextField else { return }

        // Only validate our numeric fields
        if textField !== maxRecordingDurationTextField && textField !== historySizeTextField {
            return
        }

        let currentValue = textField.stringValue
        let numericOnly = currentValue.filter { $0.isNumber }

        // If the filtered string is different, update the text field to remove non-numeric characters
        if currentValue != numericOnly {
            textField.stringValue = numericOnly
        }
    }
}
