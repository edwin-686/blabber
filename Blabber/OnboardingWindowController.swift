import Cocoa
import AVFoundation
import os.log

class OnboardingWindowController: NSWindowController, NSWindowDelegate {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "onboarding")

    // Completion callback
    var onComplete: (() -> Void)?

    // UI Elements
    private var iconImageView: NSImageView!
    private var titleLabel: NSTextField!
    private var messageLabel: NSTextField!
    private var nextButton: NSButton!
    private var skipButton: NSButton!
    private var websiteButton: NSButton!
    private var statusLabel: NSTextField!
    private var progressBar: NSProgressIndicator!
    private var modelSelectorPopup: NSPopUpButton!

    // Onboarding steps
    private enum Step {
        case welcome
        case accessibility
        case microphone
        case modelDownload
        case complete
    }

    private var currentStep: Step = .welcome

    // Model download state
    private var modelManager = ModelManager.shared
    private var selectedModel: WhisperModel?
    private var isDownloading = false

    // MARK: - Initialization

    convenience init() {
        #if DEBUG
        print("🟢 OnboardingWindowController.init() - Creating onboarding window")
        #endif
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Blabber"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        window.delegate = self
        setupUI()
        showStep(.welcome)
        #if DEBUG
        print("🟢 OnboardingWindowController.init() - Ready to show welcome screen")
        #endif
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Icon/Logo ImageView at top
        iconImageView = NSImageView(frame: NSRect(x: 260, y: 320, width: 80, height: 80))
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(iconImageView)

        // Title Label
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 20)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 50, y: 270, width: 500, height: 30)
        contentView.addSubview(titleLabel)

        // Message Label
        messageLabel = NSTextField(labelWithString: "")
        messageLabel.font = NSFont.systemFont(ofSize: 14)
        messageLabel.alignment = .left
        messageLabel.isEditable = false
        messageLabel.isBordered = false
        messageLabel.backgroundColor = .clear
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.frame = NSRect(x: 50, y: 100, width: 500, height: 150)
        contentView.addSubview(messageLabel)

        // Status Label (for showing permission check results)
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.alignment = .center
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.frame = NSRect(x: 50, y: 65, width: 500, height: 20)
        contentView.addSubview(statusLabel)

        // Next Button
        nextButton = NSButton(frame: NSRect(x: 450, y: 30, width: 100, height: 32))
        nextButton.title = "Next"
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"  // Enter key
        nextButton.target = self
        nextButton.action = #selector(nextButtonClicked)
        contentView.addSubview(nextButton)

        // Skip Button (hidden by default)
        skipButton = NSButton(frame: NSRect(x: 330, y: 30, width: 100, height: 32))
        skipButton.title = "Skip"
        skipButton.bezelStyle = .rounded
        skipButton.target = self
        skipButton.action = #selector(skipButtonClicked)
        skipButton.isHidden = true
        contentView.addSubview(skipButton)

        // Website/Donate Button (hidden by default)
        websiteButton = NSButton(frame: NSRect(x: 50, y: 30, width: 160, height: 32))
        websiteButton.title = "Buy Me a Coffee ☕"
        websiteButton.bezelStyle = .rounded
        websiteButton.target = self
        websiteButton.action = #selector(websiteButtonClicked)
        websiteButton.isHidden = true
        contentView.addSubview(websiteButton)

        // Progress Bar (hidden by default)
        progressBar = NSProgressIndicator(frame: NSRect(x: 50, y: 45, width: 360, height: 20))
        progressBar.style = .bar  // Make sure it's a bar, not spinning
        progressBar.isIndeterminate = false  // Make it determinate
        progressBar.isHidden = true
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.doubleValue = 0
        contentView.addSubview(progressBar)

        // Model Selector Popup (hidden by default)
        modelSelectorPopup = NSPopUpButton(frame: NSRect(x: 50, y: 100, width: 500, height: 25))
        modelSelectorPopup.isHidden = true
        contentView.addSubview(modelSelectorPopup)
    }

    // MARK: - Step Management

    private func showStep(_ step: Step) {
        currentStep = step
        statusLabel.stringValue = ""
        skipButton.isHidden = true  // Hide by default, show in specific steps
        websiteButton.isHidden = true  // Hide by default, show in complete step

        switch step {
        case .welcome:
            showWelcomeStep()
        case .accessibility:
            showAccessibilityStep()
        case .microphone:
            showMicrophoneStep()
        case .modelDownload:
            showModelDownloadStep()
        case .complete:
            showCompleteStep()
        }
    }

    private func showWelcomeStep() {
        // Show app icon
        if let appIcon = NSApplication.shared.applicationIconImage {
            iconImageView.image = appIcon
        }

        titleLabel.stringValue = "Welcome to Blabber!"
        messageLabel.stringValue = """
        Blabber brings powerful voice transcription to your Mac with privacy-first local AI.

        Key Features:
        • Private & Local - Your voice data stays on your Mac
        • Cloud Options - Optional cloud models for enhanced accuracy
        • Hotkey Control - Stay focused: hold or double-tap to record
        • Workflow Processor - AI-powered text transformations
        • Flexible Input - Transcribe speech or process any copied text

        Let's set up a few optional permissions to get you started.
        """
        nextButton.title = "Get Started"
    }

    private func showAccessibilityStep() {
        // Show accessibility/privacy icon
        if let privacyIcon = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "Accessibility") {
            let config = NSImage.SymbolConfiguration(pointSize: 60, weight: .regular)
            iconImageView.image = privacyIcon.withSymbolConfiguration(config)
            iconImageView.contentTintColor = .systemBlue
        }

        titleLabel.stringValue = "Accessibility Permission (Recommended)"
        messageLabel.stringValue = """
        Accessibility permission enables convenient features:
        • Global hotkey detection (hold or double-tap Right Command)
        • Auto-paste transcriptions directly where your cursor is

        Without this permission, you can still use Blabber through the menu bar.

        Click "Request Permission" to enable these features, or "Skip" to continue.
        """
        nextButton.title = "Request Permission"
        skipButton.isHidden = false  // Show skip button

        // Check if already granted
        if checkAccessibilityPermission() {
            statusLabel.stringValue = "✓ Accessibility permission already granted"
            statusLabel.textColor = .systemGreen
            nextButton.title = "Next"
            skipButton.isHidden = true  // Hide skip if already granted
        }
    }

    private func showMicrophoneStep() {
        // Show microphone icon
        if let micIcon = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Microphone") {
            let config = NSImage.SymbolConfiguration(pointSize: 60, weight: .regular)
            iconImageView.image = micIcon.withSymbolConfiguration(config)
            iconImageView.contentTintColor = .systemRed
        }

        titleLabel.stringValue = "Microphone Permission"
        messageLabel.stringValue = """
        Microphone permission is required for voice transcription.

        When you click "Request Permission", macOS will prompt you to grant access.

        Note: Without microphone access, you can still use the workflow processor with copied text, but voice transcription won't work.

        Click "Request Permission" to continue, or "Skip" if you only want to use text workflows.
        """
        nextButton.title = "Request Permission"
        skipButton.isHidden = false  // Show skip button

        // Check if already granted
        if checkMicrophonePermission() {
            statusLabel.stringValue = "✓ Microphone permission already granted"
            statusLabel.textColor = .systemGreen
            nextButton.title = "Next"
            skipButton.isHidden = true  // Hide skip if already granted
        }
    }

    private func showModelDownloadStep() {
        // Show download icon
        if let downloadIcon = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Download") {
            let config = NSImage.SymbolConfiguration(pointSize: 60, weight: .regular)
            iconImageView.image = downloadIcon.withSymbolConfiguration(config)
            iconImageView.contentTintColor = .systemGreen
        }

        titleLabel.stringValue = "Download Whisper Models"
        messageLabel.stringValue = """
        Choose a Whisper AI model for local transcription:

        • Large V3 Turbo Full (Recommended) - Best accuracy (1.6 GB)
        • Large V3 Turbo Q5 - Smaller file, great quality (574 MB)
        • Large V3 Turbo Q8 - Balanced option

        Select a model and click Download. This may take a few minutes.

        Note: You can download additional models later in Settings.
        """

        // Hide progress bar initially
        progressBar.isHidden = true
        progressBar.doubleValue = 0

        // Show model selector
        modelSelectorPopup.isHidden = false
        modelSelectorPopup.removeAllItems()

        // Add recommended models to popup (show all turbo variants)
        let recommendedModels = [
            modelManager.availableModels.first(where: { $0.recommended })!,
            modelManager.availableModels.first(where: { $0.fileName == "ggml-large-v3-turbo-q5_0.bin" })!,
            modelManager.availableModels.first(where: { $0.fileName == "ggml-large-v3-turbo-q8_0.bin" })!
        ]

        for model in recommendedModels {
            let title = model.recommended ? "\(model.name) ⭐ - \(model.sizeInMB) MB" : "\(model.name) - \(model.sizeInMB) MB"
            modelSelectorPopup.addItem(withTitle: title)
        }

        // Select the recommended model by default
        modelSelectorPopup.selectItem(at: 0)
        selectedModel = recommendedModels[0]

        // Add action handler for dropdown changes
        modelSelectorPopup.target = self
        modelSelectorPopup.action = #selector(modelDropdownChanged)

        // Set button state based on whether selected model is downloaded
        updateDownloadButtonState()
    }

    @objc private func modelDropdownChanged() {
        // Update selected model when user changes dropdown
        let selectedIndex = modelSelectorPopup.indexOfSelectedItem
        let recommendedModels = [
            modelManager.availableModels.first(where: { $0.recommended })!,
            modelManager.availableModels.first(where: { $0.fileName == "ggml-large-v3-turbo-q5_0.bin" })!,
            modelManager.availableModels.first(where: { $0.fileName == "ggml-large-v3-turbo-q8_0.bin" })!
        ]

        if selectedIndex < recommendedModels.count {
            selectedModel = recommendedModels[selectedIndex]
            updateDownloadButtonState()
        }
    }

    private func updateDownloadButtonState() {
        // Check if selected model is already downloaded
        if let model = selectedModel, modelManager.isModelDownloaded(model) {
            statusLabel.stringValue = "✓ This model is already downloaded"
            statusLabel.textColor = .systemGreen
            nextButton.title = "Next"
        } else {
            statusLabel.stringValue = ""
            nextButton.title = "Download"
        }
    }

    private func showCompleteStep() {
        // Hide model UI elements
        modelSelectorPopup.isHidden = true
        progressBar.isHidden = true

        // Show app icon again
        if let appIcon = NSApplication.shared.applicationIconImage {
            iconImageView.image = appIcon
            iconImageView.contentTintColor = nil  // Remove any tint
        }

        titleLabel.stringValue = "You're All Set!"
        messageLabel.stringValue = """
        Thank you for choosing Blabber!

        Quick Start Guide:
        • ⌘ Hold Right Command (0.5s+) to record, release to transcribe
        • ⌘ Double-tap Right Command to toggle recording on/off
        • Access history, settings, and workflows from the menu bar
        • Transcriptions auto-paste at your cursor (if accessibility enabled)

        Optional: If you configure cloud models or LLM providers later, macOS may prompt you to allow keychain access for securely storing API keys.

        Enjoy your privacy-focused transcription experience!
        """
        nextButton.title = "Start Using Blabber"
        websiteButton.isHidden = false  // Show donate button
        statusLabel.stringValue = ""
    }

    // MARK: - Button Actions

    @objc private func skipButtonClicked() {
        switch currentStep {
        case .accessibility:
            showAccessibilitySkipConfirmation()
        case .microphone:
            showMicrophoneSkipConfirmation()
        default:
            break
        }
    }

    @objc private func websiteButtonClicked() {
        if let url = URL(string: "https://blabbernotes.com") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func nextButtonClicked() {
        switch currentStep {
        case .welcome:
            showStep(.accessibility)

        case .accessibility:
            // Check current permission status
            if checkAccessibilityPermission() {
                // Already granted, move to next step
                statusLabel.stringValue = "✓ Permission granted!"
                statusLabel.textColor = .systemGreen

                // Auto-advance after short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.showStep(.microphone)
                }
            } else {
                // Check if button says "Request Permission" (first click) or "Retry" (after failed attempt)
                if nextButton.title == "Request Permission" {
                    // First click - open System Settings
                    requestAccessibilityPermission()
                } else if nextButton.title == "Retry" {
                    // User is retrying - re-open System Settings (will re-add to list if removed)
                    requestAccessibilityPermission()
                } else {
                    // User clicked "Next" after opening settings - check again
                    if checkAccessibilityPermission() {
                        // Success!
                        statusLabel.stringValue = "✓ Permission granted!"
                        statusLabel.textColor = .systemGreen

                        // Auto-advance after short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            self?.showStep(.microphone)
                        }
                    } else {
                        // Still not enabled - change button to "Retry" and show warning
                        statusLabel.stringValue = "⚠️ Blabber is not enabled yet. Please toggle it ON in System Settings."
                        statusLabel.textColor = .systemOrange
                        nextButton.title = "Retry"
                    }
                }
            }

        case .microphone:
            if checkMicrophonePermission() {
                // Already granted, move to next step
                showStep(.modelDownload)
            } else {
                // Request permission
                requestMicrophonePermission { [weak self] granted in
                    DispatchQueue.main.async {
                        if granted {
                            self?.statusLabel.stringValue = "✓ Permission granted!"
                            self?.statusLabel.textColor = .systemGreen
                            self?.nextButton.title = "Next"

                            // Auto-advance after short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self?.showStep(.modelDownload)
                            }
                        } else {
                            self?.statusLabel.stringValue = "⚠️ Permission denied. Please enable in System Preferences > Privacy & Security > Microphone"
                            self?.statusLabel.textColor = .systemRed
                            self?.nextButton.title = "Try Again"
                        }
                    }
                }
            }

        case .modelDownload:
            // Update selected model based on popup selection
            let selectedIndex = modelSelectorPopup.indexOfSelectedItem
            let recommendedModels = [
                modelManager.availableModels.first(where: { $0.recommended })!,
                modelManager.availableModels.first(where: { $0.fileName == "ggml-large-v3-turbo.bin" })!
            ]
            selectedModel = recommendedModels[selectedIndex]

            guard let model = selectedModel else { return }

            // Check if already downloaded
            if modelManager.isModelDownloaded(model) {
                // Save model path to settings
                let modelPath = modelManager.modelPath(for: model).path
                SettingsManager.shared.whisperModelPath = modelPath
                os_log(.info, log: Self.logger, "Model already downloaded, proceeding to complete")
                showStep(.complete)
                return
            }

            // Prevent multiple simultaneous downloads
            guard !isDownloading else { return }
            isDownloading = true

            // Disable button and show progress
            nextButton.isEnabled = false
            progressBar.isHidden = false
            progressBar.doubleValue = 0
            statusLabel.stringValue = "Downloading model..."
            statusLabel.textColor = .systemBlue

            os_log(.info, log: Self.logger, "Starting download of %{public}s", model.name)

            // Start download
            modelManager.downloadModel(model, progressHandler: { [weak self] progress, downloaded, total in
                DispatchQueue.main.async {
                    self?.progressBar.doubleValue = progress * 100
                    self?.statusLabel.stringValue = String(format: "Downloading... %.0f%%", progress * 100)
                }
            }, completion: { [weak self] result in
                DispatchQueue.main.async {
                    self?.isDownloading = false
                    self?.nextButton.isEnabled = true

                    switch result {
                    case .success(let path):
                        os_log(.info, log: Self.logger, "Download complete: %{public}s", path.path)
                        self?.statusLabel.stringValue = "✓ Download complete!"
                        self?.statusLabel.textColor = .systemGreen

                        // Save model path to settings
                        SettingsManager.shared.whisperModelPath = path.path

                        // Auto-advance after short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self?.showStep(.complete)
                        }

                    case .failure(let error):
                        os_log(.error, log: Self.logger, "Download failed: %{public}s", error.localizedDescription)
                        self?.statusLabel.stringValue = "❌ Download failed: \(error.localizedDescription)"
                        self?.statusLabel.textColor = .systemRed
                        self?.nextButton.title = "Try Again"
                        self?.progressBar.isHidden = true
                    }
                }
            })


        case .complete:
            // Mark onboarding as complete
            SettingsManager.shared.hasCompletedOnboarding = true
            // Close window
            window?.close()
            // Notify completion
            onComplete?()
        }
    }

    // MARK: - Skip Confirmation Dialogs

    private func showAccessibilitySkipConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Skip Accessibility Permission?"
        alert.informativeText = """
        Without Accessibility permission, the following features won't work:

        • Global hotkey detection (Right Command hold/double-tap)
        • Auto-paste transcriptions at cursor position

        You'll need to use the menu bar icon to control all recording and access transcriptions manually.

        Are you sure you want to continue without these features?
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Go Back")
        alert.addButton(withTitle: "Skip Anyway")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            // User confirmed skip
            showStep(.microphone)
        }
        // If first button (Go Back), do nothing - stay on current screen
    }

    private func showMicrophoneSkipConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Skip Microphone Permission?"
        alert.informativeText = """
        Without Microphone permission, voice transcription won't work.

        Blabber's main feature is recording and transcribing audio. You can still use the workflow processor with copied text, but you won't be able to:

        • Record audio
        • Transcribe speech to text

        Are you sure you want to continue without microphone access?
        """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Go Back")
        alert.addButton(withTitle: "Skip Anyway")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            // User confirmed skip
            showStep(.modelDownload)
        }
        // If first button (Go Back), do nothing - stay on current screen
    }

    // MARK: - Permission Checking

    private func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    private func checkMicrophonePermission() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        default:
            return false
        }
    }

    // MARK: - Permission Requesting

    private func requestAccessibilityPermission() {
        os_log(.info, log: Self.logger, "Opening System Settings for Accessibility")

        // IMPORTANT: Trigger accessibility check with prompt option to ensure app is added to the list
        // This will cause macOS to add Blabber to the accessibility list (if not already there)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let _ = AXIsProcessTrustedWithOptions(options)

        // Note: For LSUIElement (menu bar) apps, the system prompt may not show properly
        // So we also open System Settings directly to the Accessibility page

        // Small delay to let the system process the accessibility check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Try modern macOS 13+ URL scheme first
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                // Fallback to older macOS URL scheme
                NSWorkspace.shared.open(url)
            }
        }

        // Update button text to guide user
        statusLabel.stringValue = "→ Please enable Blabber in System Settings, then click 'Next'"
        statusLabel.textColor = .systemBlue
        nextButton.title = "Next"
    }

    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        os_log(.info, log: Self.logger, "Requesting Microphone Permission (user clicked Next)")
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            completion(granted)
        }
    }

    // MARK: - Window Delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // If download is in progress, show warning
        if isDownloading {
            let alert = NSAlert()
            alert.messageText = "Download in Progress"
            alert.informativeText = """
            A model is currently downloading. If you close this window now, the download will be aborted and you'll need to start over.

            Are you sure you want to cancel the download and close the setup?
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Keep Downloading")
            alert.addButton(withTitle: "Cancel Download")

            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                // User chose to cancel download
                os_log(.default, log: Self.logger, "WARNING - User cancelled download by closing window")
                // The download will be interrupted when window closes
                // Next time they open onboarding, they can retry
                return true  // Allow close
            } else {
                // User chose to keep downloading
                return false  // Prevent close
            }
        }

        // No download in progress, allow close
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Clean up state when window closes
        if isDownloading {
            os_log(.default, log: Self.logger, "WARNING - Window closing during download - resetting state")
            isDownloading = false
        }
    }
}
