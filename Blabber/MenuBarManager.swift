import Cocoa
import AVFoundation
import os.log

class MenuBarManager: NSObject {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "ui")

    private var statusItem: NSStatusItem?
    private var menu: NSMenu!

    // Menu items that need to be updated dynamically
    private var recordingMenuItem: NSMenuItem!
    private var searchField: HistorySearchField?
    private var previewWindow: HistoryPreviewWindow?
    private var currentSearchQuery: String = ""
    private var historyStartIndex: Int = 2 // Index where history items start (after Start Recording + Search)
    private var keyMonitor: Any? // Local event monitor for keyboard shortcuts in menu
    private var currentHighlightedItem: HistoryItem? // Currently highlighted history item

    // Recording components
    var audioRecorder: AudioRecorder?
    var transcriber: WhisperTranscriber?
    var cloudTranscriber: CloudTranscriber?
    var pasteManager: PasteManager?
    var hotKeyManager: HotKeyManager?
    var audioFeedback: AudioFeedback?
    var audioLevelMonitor: AudioLevelMonitor?

    var isRecording = false
    var isTranscribing = false
    var recordingStartTime: Date?
    let minimumRecordingDuration: TimeInterval = 2.0 // 2 seconds minimum
    var isToggleMode = false // Track if started by double-tap vs hold
    var currentAudioLevel: AudioLevelMonitor.AudioLevel = .silence
    var maxDurationTimer: Timer? // Timer to enforce maximum recording duration
    var iconUpdateTimer: Timer? // Timer to update the menu bar icon with elapsed time
    var currentTranscriptionModel: String? // Track which model is being used for current transcription

    // Optional debug window
    var debugWindowController: NSWindowController?
    var settingsWindowController: NSWindowController?
    var workflowProcessorWindowController: WorkflowProcessorWindowController?
    var aboutWindowController: NSWindowController?

    override init() {
        #if DEBUG
        print("MenuBarManager: Starting initialization")
        #endif
        super.init()
        setupMenuBar()
        setupComponents()
        setupHotKeys()
        requestPermissions()
        os_log(.info, log: Self.logger, "MenuBarManager initialized")
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Blabber")
            button.image?.isTemplate = true // Makes it adapt to light/dark mode
        }

        // Create menu
        menu = NSMenu()
        menu.delegate = self

        // Start/Stop Recording (context-aware)
        recordingMenuItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        recordingMenuItem.target = self
        if let icon = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Start Recording") {
            recordingMenuItem.image = tintImage(icon, with: .systemRed)
        }
        menu.addItem(recordingMenuItem)

        // Search field (custom view) - full menu width with minimal padding
        let searchFieldItem = NSMenuItem()
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 30))

        searchField = HistorySearchField(frame: NSRect(x: 1, y: 4, width: 498, height: 22))
        searchField?.placeholderString = "Type to search..."
        searchField?.target = self
        searchField?.action = #selector(searchFieldChanged)
        searchField?.refusesFirstResponder = false

        // Set up keyboard shortcut callbacks
        searchField?.onPinUnpin = { [weak self] in
            self?.handlePinUnpinShortcut()
        }
        searchField?.onDelete = { [weak self] in
            self?.handleDeleteShortcut()
        }

        // Make search field send action continuously as text changes
        if let searchFieldCell = searchField?.cell as? NSSearchFieldCell {
            searchFieldCell.sendsWholeSearchString = false
            searchFieldCell.sendsSearchStringImmediately = true
        }

        containerView.addSubview(searchField!)
        searchFieldItem.view = containerView
        menu.addItem(searchFieldItem)

        // Observe text changes for continuous search updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(searchFieldTextChanged(_:)),
            name: NSControl.textDidChangeNotification,
            object: searchField
        )

        // Observe history changes (for clearing, deletion, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(historyChanged),
            name: NSNotification.Name("HistoryChanged"),
            object: nil
        )

        // History items will be populated here dynamically
        // (index 2 onwards, until we hit the separator)

        menu.addItem(NSMenuItem.separator())

        // Clear History
        let clearHistoryItem = NSMenuItem(
            title: "Clear History",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearHistoryItem.target = self
        menu.addItem(clearHistoryItem)

        // Preferences
        let settingsItem = NSMenuItem(
            title: "Preferences",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Open Workflow Processor
        let workflowProcessorItem = NSMenuItem(
            title: "Open Workflow Processor",
            action: #selector(openWorkflowProcessorAction),
            keyEquivalent: "w"
        )
        workflowProcessorItem.target = self
        menu.addItem(workflowProcessorItem)

        // About
        let aboutItem = NSMenuItem(
            title: "About",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu

        os_log(.info, log: Self.logger, "Menu bar setup complete")
    }

    // MARK: - Public Methods

    /// Programmatically show the menu bar menu
    func showMenu() {
        statusItem?.button?.performClick(nil)
    }

    // MARK: - Component Setup

    private func setupComponents() {
        audioRecorder = AudioRecorder()
        transcriber = WhisperTranscriber()
        cloudTranscriber = CloudTranscriber()
        pasteManager = PasteManager()
        audioFeedback = AudioFeedback()
        audioLevelMonitor = AudioLevelMonitor()

        // Setup audio level callback
        audioLevelMonitor?.onLevelChanged = { [weak self] level in
            self?.handleAudioLevelChanged(level)
        }

        // Setup prolonged silence callback (notification at 10s)
        audioLevelMonitor?.onProlongedSilence = { [weak self] in
            self?.handleProlongedSilence()
        }

        // Setup sound warning callback (every 5s)
        audioLevelMonitor?.onSilenceSoundWarning = { [weak self] in
            self?.handleSilenceSoundWarning()
        }

        os_log(.info, log: Self.logger, "Components initialized")
    }

    func setupHotKeys() {
        hotKeyManager = HotKeyManager()

        // Press and hold Right Command (hold mode)
        hotKeyManager?.onRightCommandPressed = { [weak self] in
            guard let self = self else { return }

            // Don't start if transcription is in progress
            if self.isTranscribing {
                self.log("⚠️ Transcription in progress - ignoring hotkey")
                return
            }

            // Don't start if already recording in toggle mode
            if self.isRecording && self.isToggleMode {
                self.log("⚠️ In toggle mode - ignoring press-and-hold (double-tap to stop)")
                return
            }

            self.log("Right Command held (1+ second)")
            self.startRecording(toggleMode: false)
        }

        hotKeyManager?.onRightCommandReleased = { [weak self] in
            guard let self = self else { return }
            self.log("Right Command released")

            // Don't stop if transcription is in progress
            if self.isTranscribing {
                self.log("⚠️ Transcription in progress - ignoring hotkey")
                return
            }

            // Only stop if NOT in toggle mode (to prevent conflicts)
            if !self.isToggleMode {
                self.stopRecordingAndTranscribe()
            } else {
                self.log("⚠️ In toggle mode - ignoring release (use double-tap to stop)")
            }
        }

        // Double-tap Right Command (toggle mode)
        hotKeyManager?.onRightCommandDoubleTap = { [weak self] in
            guard let self = self else { return }
            self.log("Right Command double-tapped")

            // Don't handle if transcription is in progress
            if self.isTranscribing {
                self.log("⚠️ Transcription in progress - ignoring hotkey")
                return
            }

            self.handleDoubleTap()
        }

        // Option + Right Command double-tap (workflow processor)
        hotKeyManager?.onWorkflowProcessorRequested = { [weak self] in
            guard let self = self else { return }
            self.log("Workflow processor hotkey triggered - Toggling window")

            // Don't toggle if transcription is in progress
            if self.isTranscribing {
                self.log("⚠️ Transcription in progress - ignoring hotkey")
                return
            }

            self.openWorkflowProcessor(shouldToggle: true)
        }

        log("Hotkeys configured (Hold or Double-tap)")
    }

    private func requestPermissions() {
        log("Checking permissions...")

        // Check accessibility permissions (no prompt - onboarding handles this)
        let accessEnabled = AXIsProcessTrusted()

        if accessEnabled {
            log("✓ Accessibility permissions granted")
        } else {
            log("⚠️ Accessibility permissions not granted - app may not work properly")
        }

        // Check microphone permissions (no prompt - onboarding handles this)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .authorized {
            log("✓ Microphone permissions granted")
        } else {
            log("⚠️ Microphone permissions not granted - recording will not work")
        }
    }

    // MARK: - Recording Actions

    @objc private func toggleRecording() {
        if isTranscribing {
            abortTranscription()
        } else if isRecording {
            stopRecordingAndTranscribe()
        } else {
            startRecording(toggleMode: false)
        }
    }

    private func handleDoubleTap() {
        if isRecording {
            // Already recording, stop it (works regardless of how recording was started)
            stopRecordingAndTranscribe()
        } else {
            // Not recording, start in toggle mode
            startRecording(toggleMode: true)
        }
    }

    func startRecording(toggleMode: Bool) {
        guard !isRecording else {
            if isToggleMode {
                log("⚠️ Already recording in toggle mode - double-tap to stop")
            } else {
                log("⚠️ Already recording in hold mode - release to stop")
            }
            return
        }
        isRecording = true
        isToggleMode = toggleMode
        recordingStartTime = Date()

        if toggleMode {
            log("🔴 Recording started (toggle mode - double-tap, menu, or release to stop)")
        } else {
            log("🔴 Recording started (hold mode - release, double-tap, or menu to stop)")
        }

        updateMenuBarIcon(recording: true)
        recordingMenuItem.title = "Stop Recording"
        if let icon = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: "Stop Recording") {
            recordingMenuItem.image = tintImage(icon, with: .systemRed)
        }

        // Start icon update timer to refresh the elapsed time every second
        startIconUpdateTimer()

        // Play start sound first
        audioFeedback?.playStartSound()

        // Delay starting the recorder to allow sound to play
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.audioRecorder?.startRecording()

            // Start monitoring audio levels
            self?.audioLevelMonitor?.startMonitoring(audioRecorder: self?.audioRecorder?.recorder)

            // Start max duration timer
            self?.startMaxDurationTimer()
        }
    }

    func stopRecordingAndTranscribe() {
        guard isRecording else { return }
        isRecording = false
        isToggleMode = false // Reset toggle mode flag

        // Cancel max duration timer
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        // Cancel icon update timer
        iconUpdateTimer?.invalidate()
        iconUpdateTimer = nil

        // Stop monitoring audio levels
        audioLevelMonitor?.stopMonitoring()
        currentAudioLevel = .silence

        // Check recording duration
        let recordingDuration: TimeInterval
        if let startTime = recordingStartTime {
            recordingDuration = Date().timeIntervalSince(startTime)
        } else {
            recordingDuration = 0
        }

        log("⏸ Recording stopped (duration: \(String(format: "%.1f", recordingDuration))s)")
        updateMenuBarIcon(recording: false)
        recordingMenuItem.title = "Start Recording"
        if let icon = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Start Recording") {
            recordingMenuItem.image = tintImage(icon, with: .systemRed)
        }

        // Play stop sound
        audioFeedback?.playStopSound()

        guard let audioFile = audioRecorder?.stopRecording() else {
            log("❌ Failed to stop recording")
            return
        }

        // Check if recording is too short
        if recordingDuration < minimumRecordingDuration {
            log("⚠️ Recording too short (\(String(format: "%.1f", recordingDuration))s), ignoring...")
            // Cleanup audio file
            try? FileManager.default.removeItem(at: audioFile)
            return
        }

        log("Transcribing audio file...")
        isTranscribing = true
        updateMenuBarIcon(transcribing: true)
        recordingMenuItem.title = "Abort Transcription"
        if let icon = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Abort Transcription") {
            recordingMenuItem.image = tintImage(icon, with: .systemRed)
        }
        audioFeedback?.startTranscribingSound()

        // Check if we're using a cloud model or local model
        let modelPath = SettingsManager.shared.whisperModelPath
        currentTranscriptionModel = modelPath

        if modelPath.hasPrefix("cloud:") {
            // Cloud model - extract model ID
            let modelId = String(modelPath.dropFirst(6)) // Remove "cloud:" prefix
            log("Using cloud model: \(modelId)")

            // Transcribe using cloud API
            cloudTranscriber?.transcribe(audioFile: audioFile, modelId: modelId) { [weak self] text in
                self?.handleTranscriptionResult(text: text, recordingDuration: self?.recordingStartTime.map({ Date().timeIntervalSince($0) }))
            }
        } else {
            // Local model - use WhisperTranscriber
            log("Using local model: \(modelPath)")

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let text = self?.transcriber?.transcribe(audioFile: audioFile) else {
                    DispatchQueue.main.async {
                        self?.handleTranscriptionResult(text: nil, recordingDuration: nil)
                    }
                    return
                }

                DispatchQueue.main.async {
                    self?.handleTranscriptionResult(text: text, recordingDuration: self?.recordingStartTime.map({ Date().timeIntervalSince($0) }))
                }
            }
        }
    }

    private func handleTranscriptionResult(text: String?, recordingDuration: TimeInterval?) {
        guard let text = text else {
            log("❌ Transcription failed or aborted")
            isTranscribing = false
            updateMenuBarIcon(transcribing: false)
            recordingMenuItem.title = "Start Recording"
            if let icon = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Start Recording") {
                recordingMenuItem.image = tintImage(icon, with: .systemRed)
            }
            audioFeedback?.stopTranscribingSound()
            return
        }

        // Clean up newlines from transcription for terminal-safe pasting
        let cleanedText = cleanTranscriptionText(text)

        // Apply find-and-replace corrections
        let correctedText = applyFindReplace(cleanedText)

        log("✓ Transcription: \"\(correctedText)\"")
        isTranscribing = false
        updateMenuBarIcon(transcribing: false)
        recordingMenuItem.title = "Start Recording"
        if let icon = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Start Recording") {
            recordingMenuItem.image = tintImage(icon, with: .systemRed)
        }
        audioFeedback?.stopTranscribingSound()
        audioFeedback?.playStopSound()

        // Save to history
        if let duration = recordingDuration {
            HistoryManager.shared.addItem(text: correctedText, duration: duration, model: currentTranscriptionModel)
            log("✓ Added to history")
        }

        // Clear current transcription model
        currentTranscriptionModel = nil

        // Handle transcription according to settings
        pasteManager?.handleTranscription(correctedText)

        let settings = SettingsManager.shared
        if settings.autoPasteEnabled {
            log("✓ Text copied and pasted")
        } else if settings.autoCopyEnabled {
            log("✓ Text copied to clipboard")
        } else {
            log("✓ Transcription complete (not copied or pasted)")
        }
    }

    private func abortTranscription() {
        guard isTranscribing else {
            log("⚠️ No transcription in progress")
            return
        }

        log("⚠️ Aborting transcription...")

        // Tell transcriber to abort the process
        transcriber?.abort()

        // Stop transcribing sound
        audioFeedback?.stopTranscribingSound()

        // Reset state
        isTranscribing = false
        updateMenuBarIcon(transcribing: false)
        recordingMenuItem.title = "Start Recording"
        if let icon = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Start Recording") {
            recordingMenuItem.image = tintImage(icon, with: .systemRed)
        }

        log("✓ Transcription aborted")
    }

    /// Clean transcription text by removing newlines and joining intelligently
    /// This makes the output safe for terminal pasting where newlines trigger command execution
    private func cleanTranscriptionText(_ text: String) -> String {
        // Split on newlines and trim whitespace
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return "" }

        var result = ""
        for (index, line) in lines.enumerated() {
            result += line

            // Don't add separator after last line
            if index < lines.count - 1 {
                // If line ends with sentence-ending punctuation, just add space
                if line.hasSuffix(".") || line.hasSuffix("!") || line.hasSuffix("?") {
                    result += " "
                } else {
                    // No punctuation - add period and space for proper sentence structure
                    result += ". "
                }
            }
        }

        return result
    }

    /// Apply find-and-replace corrections to transcription text
    /// Replacements are applied in order (top to bottom), single pass
    private func applyFindReplace(_ text: String) -> String {
        let pairs = SettingsManager.shared.findReplacePairs
        guard !pairs.isEmpty else { return text }

        var result = text

        for pair in pairs {
            if pair.caseSensitive {
                // Case-sensitive replacement
                result = result.replacingOccurrences(of: pair.find, with: pair.replace)
            } else {
                // Case-insensitive replacement
                result = result.replacingOccurrences(of: pair.find, with: pair.replace, options: .caseInsensitive)
            }
        }

        return result
    }

    // MARK: - Max Duration Timer

    private func startMaxDurationTimer() {
        // Get max duration from settings
        let maxDuration = SettingsManager.shared.maxRecordingDuration

        log("Max recording duration set to \(Int(maxDuration / 60)) minutes")

        // Start timer
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) { [weak self] _ in
            self?.maxDurationReached()
        }
    }

    private func maxDurationReached() {
        log("⏱ Maximum recording duration reached - stopping automatically")

        // Show notification
        let notification = NSUserNotification()
        notification.title = "Blabber"
        notification.informativeText = "Maximum recording duration reached. Recording stopped automatically."
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)

        // Stop recording
        stopRecordingAndTranscribe()
    }

    // MARK: - Icon Update Timer

    private func startIconUpdateTimer() {
        // Update icon every second to refresh the timer display
        iconUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateIconWithElapsedTime()
        }

        // Add timer to common run loop modes so it continues to fire even when menu is tracking
        if let timer = iconUpdateTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func updateIconWithElapsedTime() {
        guard isRecording else { return }

        // Update the menu bar icon with current elapsed time
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateMenuBarIcon(recording: true, audioActive: self.currentAudioLevel == .active)

            // Also update the menu item title with full timer
            if let startTime = self.recordingStartTime {
                let elapsedSeconds = Date().timeIntervalSince(startTime)
                let timerText = self.formatElapsedTimeFull(elapsedSeconds)
                self.recordingMenuItem.title = "Stop Recording (\(timerText))"
            }

            // Force menu to update (ensures the timer updates even when menu is open)
            self.menu.update()
        }
    }

    // MARK: - Audio Level Handling

    private func handleAudioLevelChanged(_ level: AudioLevelMonitor.AudioLevel) {
        // Only update if still recording
        guard isRecording else { return }

        // Update current level
        currentAudioLevel = level

        // Update icon to reflect audio activity
        DispatchQueue.main.async { [weak self] in
            self?.updateMenuBarIcon(recording: true, audioActive: level == .active)
        }
    }

    private func handleProlongedSilence() {
        // Only warn if still recording
        guard isRecording else { return }

        log("⚠️ No audio detected for 20 seconds - check microphone")

        // Show notification (only once at 20 seconds)
        // The notification plays its own sound, so we don't play submarine here
        let notification = NSUserNotification()
        notification.title = "Blabber"
        notification.informativeText = "No audio detected for 20 seconds. Please check your microphone."
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    private func handleSilenceSoundWarning() {
        // Only warn if still recording
        guard isRecording else { return }

        // Play submarine warning sound every 5 seconds (no notification)
        if SettingsManager.shared.audioFeedbackEnabled {
            if let sound = NSSound(named: "Submarine") {
                sound.play()
            } else {
                NSSound.beep()  // Fallback to beep if Submarine sound not available
            }
        }
    }

    // MARK: - Menu Bar Icon Updates

    private func updateMenuBarIcon(recording: Bool = false, transcribing: Bool = false, audioActive: Bool = false) {
        guard let button = statusItem?.button else { return }

        if recording {
            // Calculate elapsed time
            let elapsedSeconds = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
            let timerText = formatElapsedTimeCompact(elapsedSeconds)

            if let waveformImage = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Recording") {
                if audioActive {
                    // Audio is being detected - show red waveform icon with timer
                    let compositeImage = createIconWithTimer(waveformImage: waveformImage, timerText: timerText, tintColor: .systemRed)
                    button.image = compositeImage
                } else {
                    // Recording but no audio detected - show waveform in default color with timer
                    let compositeImage = createIconWithTimer(waveformImage: waveformImage, timerText: timerText, tintColor: nil)
                    button.image = compositeImage
                }
            }
        } else if transcribing {
            button.image = NSImage(systemSymbolName: "waveform.badge.magnifyingglass", accessibilityDescription: "Transcribing")
            button.image?.isTemplate = true
        } else {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Blabber")
            button.image?.isTemplate = true
        }
    }

    /// Tint an image with a specific color
    private func tintImage(_ image: NSImage, with color: NSColor) -> NSImage {
        let tintedImage = image.copy() as! NSImage
        tintedImage.lockFocus()

        color.set()
        let imageRect = NSRect(origin: .zero, size: tintedImage.size)
        imageRect.fill(using: .sourceAtop)

        tintedImage.unlockFocus()
        tintedImage.isTemplate = false

        return tintedImage
    }

    /// Format elapsed time for menu bar display (seconds during first minute, then minutes)
    private func formatElapsedTimeCompact(_ elapsedSeconds: TimeInterval) -> String {
        let totalSeconds = Int(elapsedSeconds)
        let minutes = totalSeconds / 60

        if minutes == 0 {
            // First minute: show seconds
            return "\(totalSeconds)s"
        } else {
            // After first minute: show minutes
            return "\(minutes)m"
        }
    }

    /// Format elapsed time for menu item display (full minutes:seconds)
    private func formatElapsedTimeFull(_ elapsedSeconds: TimeInterval) -> String {
        let minutes = Int(elapsedSeconds) / 60
        let seconds = Int(elapsedSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Create composite image with waveform icon and timer text
    private func createIconWithTimer(waveformImage: NSImage, timerText: String, tintColor: NSColor? = nil) -> NSImage {
        // Create attributed string for the timer text
        let fontSize: CGFloat = 13
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: tintColor ?? NSColor.labelColor
        ]
        let attributedText = NSAttributedString(string: " " + timerText, attributes: attributes)
        let textSize = attributedText.size()

        // Calculate total size for composite image
        let iconSize = waveformImage.size
        let totalWidth = iconSize.width + textSize.width + 2 // Add small spacing
        let totalHeight = max(iconSize.height, textSize.height)

        // Create new image with combined size
        let compositeImage = NSImage(size: NSSize(width: totalWidth, height: totalHeight))

        compositeImage.lockFocus()

        // Draw the waveform icon on the left
        let iconRect = NSRect(x: 0, y: (totalHeight - iconSize.height) / 2, width: iconSize.width, height: iconSize.height)
        if let tintColor = tintColor {
            let tintedWaveform = tintImage(waveformImage, with: tintColor)
            tintedWaveform.draw(in: iconRect)
        } else {
            waveformImage.draw(in: iconRect)
        }

        // Draw the timer text on the right
        let textRect = NSRect(x: iconSize.width + 2, y: (totalHeight - textSize.height) / 2, width: textSize.width, height: textSize.height)
        attributedText.draw(in: textRect)

        compositeImage.unlockFocus()
        compositeImage.isTemplate = (tintColor == nil)

        return compositeImage
    }

    // MARK: - Menu Actions

    // Debug window removed - no longer needed (app operates via menu bar + hotkeys only)
    /*
    @objc private func showDebugWindow() {
        if debugWindowController == nil {
            // Create debug window with ViewController
            let storyboard = NSStoryboard(name: "Main", bundle: nil)
            if let viewController = storyboard.instantiateController(withIdentifier: "ViewController") as? ViewController {
                // Share components with ViewController BEFORE creating window
                // This prevents viewDidLoad from creating duplicate instances
                viewController.audioRecorder = self.audioRecorder
                viewController.transcriber = self.transcriber
                viewController.pasteManager = self.pasteManager
                viewController.hotKeyManager = self.hotKeyManager

                // Now create window with the configured view controller
                let window = NSWindow(contentViewController: viewController)
                window.title = "Blabber Debug"
                window.setContentSize(NSSize(width: 500, height: 400))
                window.styleMask = [.titled, .closable, .miniaturizable]

                debugWindowController = NSWindowController(window: window)
            }
        }

        debugWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    */

    @objc private func clearHistory() {
        // Create alert with checkbox
        let alert = NSAlert()
        alert.messageText = "Clear History?"
        alert.informativeText = "This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        // Create checkbox for "Also clear pinned items"
        let clearPinnedCheckbox = NSButton(checkboxWithTitle: "Also clear pinned items", target: nil, action: nil)
        clearPinnedCheckbox.state = .off
        alert.accessoryView = clearPinnedCheckbox

        // Show alert
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // User clicked "Clear"
            let includingPinned = (clearPinnedCheckbox.state == .on)
            HistoryManager.shared.clearHistory(includingPinned: includingPinned)
            log("History cleared (including pinned: \(includingPinned))")

            // Rebuild menu to show empty state
            rebuildHistoryItems()
        }
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            let settingsVC = SettingsViewController()
            let window = NSWindow(contentViewController: settingsVC)
            window.title = "Blabber Settings"
            window.setContentSize(NSSize(width: 450, height: 810))
            window.styleMask = [.titled, .closable]
            window.level = .floating

            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        if aboutWindowController == nil {
            let aboutVC = AboutViewController()
            let window = NSWindow(contentViewController: aboutVC)
            window.title = "About Blabber"
            window.setContentSize(NSSize(width: 400, height: 450))
            window.styleMask = [.titled, .closable]
            window.level = .floating

            aboutWindowController = NSWindowController(window: window)
        }

        aboutWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openWorkflowProcessorAction() {
        openWorkflowProcessor(shouldToggle: true)
    }

    private func openWorkflowProcessor(shouldToggle: Bool) {
        // Check if window is already visible
        let isWindowVisible = workflowProcessorWindowController?.window?.isVisible == true

        if isWindowVisible && shouldToggle {
            // Window is visible - check if it's also focused
            let isWindowFocused = workflowProcessorWindowController?.window?.isKeyWindow == true && NSApp.isActive

            if isWindowFocused {
                // Window is visible AND focused - close it
                workflowProcessorWindowController?.window?.close()
                return
            }
            // Window is visible but not focused - fall through to bring it to front
        }

        // Create or reuse workflow processor window
        if workflowProcessorWindowController == nil {
            workflowProcessorWindowController = WorkflowProcessorWindowController()
        }

        // Auto-paste if enabled (only when first opening, not when bringing to front)
        if !isWindowVisible && SettingsManager.shared.workflowAutoPasteEnabled {
            workflowProcessorWindowController?.autoPasteIfEnabled()
        }

        // Show window and bring it to front
        workflowProcessorWindowController?.showWindow(nil)
        workflowProcessorWindowController?.window?.makeKeyAndOrderFront(nil)
        workflowProcessorWindowController?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        log("Quitting Blabber...")
        NSApplication.shared.terminate(self)
    }

    // MARK: - Utilities

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[\(timestamp)] \(message)")
    }

    // MARK: - History Management

    /// Rebuild history items in the menu based on current search query
    private func rebuildHistoryItems() {
        // Remove existing history items (between search field and separator)
        // Find separator index
        var separatorIndex = -1
        for i in historyStartIndex..<menu.items.count {
            if menu.items[i].isSeparatorItem {
                separatorIndex = i
                break
            }
        }

        // Remove all items between historyStartIndex and separator
        if separatorIndex > historyStartIndex {
            for _ in historyStartIndex..<separatorIndex {
                menu.removeItem(at: historyStartIndex)
            }
        }

        // Get history items (filtered by search query)
        let historyManager = HistoryManager.shared
        let items = currentSearchQuery.isEmpty
            ? historyManager.getItems()
            : historyManager.searchItems(query: currentSearchQuery)

        // Add history items to menu
        if items.isEmpty {
            let emptyItem = NSMenuItem(title: "No history yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.insertItem(emptyItem, at: historyStartIndex)
        } else {
            for (index, item) in items.enumerated() {
                let menuItem = createHistoryMenuItem(for: item, searchQuery: currentSearchQuery)
                menu.insertItem(menuItem, at: historyStartIndex + index)
            }
        }
    }

    /// Create a menu item for a history item
    private func createHistoryMenuItem(for item: HistoryItem, searchQuery: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: "", // Will be replaced by attributedTitle
            action: #selector(historyItemClicked(_:)),
            keyEquivalent: ""
        )

        // Show pinned status with simple star prefix, no emoji
        let prefix = item.isPinned ? "★ " : ""

        // Get attributed string with bold matched text
        let itemAttributedText = item.attributedDisplayText(searchQuery: searchQuery)

        // Create final attributed string with prefix
        let finalAttributedString = NSMutableAttributedString()

        if !prefix.isEmpty {
            let normalFont = NSFont.menuFont(ofSize: 0)
            let prefixAttributedString = NSAttributedString(
                string: prefix,
                attributes: [.font: normalFont]
            )
            finalAttributedString.append(prefixAttributedString)
        }

        finalAttributedString.append(itemAttributedText)

        menuItem.attributedTitle = finalAttributedString
        menuItem.target = self
        menuItem.representedObject = item

        return menuItem
    }

    @objc private func searchFieldChanged() {
        currentSearchQuery = searchField?.stringValue ?? ""
        log("Search query: \"\(currentSearchQuery)\"")
        rebuildHistoryItems()
    }

    @objc private func searchFieldTextChanged(_ notification: Notification) {
        currentSearchQuery = searchField?.stringValue ?? ""
        log("Search text changed: \"\(currentSearchQuery)\"")
        rebuildHistoryItems()
    }

    @objc private func historyChanged() {
        log("History changed - rebuilding menu items")
        rebuildHistoryItems()
    }

    @objc private func historyItemClicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? HistoryItem else { return }

        // Check for right-click (secondary click) using current event
        if let currentEvent = NSApp.currentEvent {
            // Right-click can be detected by button number 1 (right button) on mouse
            // Or by Control+Click on trackpad/mouse (which macOS treats as right-click)
            let isRightClick = (currentEvent.type == .rightMouseDown) ||
                               (currentEvent.type == .rightMouseUp) ||
                               (currentEvent.buttonNumber == 1)

            if isRightClick {
                // Right-click: Open workflow processor with this text (don't toggle if already open)
                openWorkflowProcessor(shouldToggle: false)
                workflowProcessorWindowController?.setInputText(item.text)
                log("Right-clicked history item - opened workflow processor: \"\(item.truncatedText)\"")
                return
            }
        }

        // Check for modifier keys
        let modifiers = NSEvent.modifierFlags

        if modifiers.contains(.control) || modifiers.contains(.command) {
            // Control+Click or Command+Click: Open workflow processor with this text (don't toggle if already open)
            openWorkflowProcessor(shouldToggle: false)
            workflowProcessorWindowController?.setInputText(item.text)
            log("Opened workflow processor with history item: \"\(item.truncatedText)\"")
            return
        }

        if modifiers.contains(.option) {
            // Check if Delete/Backspace key was pressed
            if let currentEvent = NSApp.currentEvent,
               currentEvent.type == .keyDown,
               (currentEvent.keyCode == 51 || currentEvent.keyCode == 117) { // Delete or Forward Delete
                // Delete item
                HistoryManager.shared.deleteItem(itemId: item.id)
                rebuildHistoryItems()
                log("Deleted history item")
                return
            } else {
                // Option+Click or Option+P: Toggle pin
                HistoryManager.shared.togglePin(itemId: item.id)
                rebuildHistoryItems()
                log(item.isPinned ? "Unpinned history item" : "Pinned history item")
                return
            }
        }

        // Normal click: Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)

        log("✓ Copied history item to clipboard: \"\(item.truncatedText)\"")
    }
}

// MARK: - NSMenuDelegate

extension MenuBarManager: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Check if workflow processor window is open and bring it forward
        if let windowController = workflowProcessorWindowController,
           let window = windowController.window,
           window.isVisible {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }

        // Rebuild history items when menu opens
        rebuildHistoryItems()

        // Initialize preview window if needed
        if previewWindow == nil {
            previewWindow = HistoryPreviewWindow()
        }

        // Install keyboard event monitor for CMD-P and Delete
        installKeyboardMonitor()

        // Focus search field - with helper window, this should work consistently
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.focusSearchField()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.focusSearchField()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.focusSearchField()
        }
    }

    private func focusSearchField() {
        guard let searchField = searchField else {
            return
        }

        // Make search field the first responder so keyboard input goes to it
        if let menuWindow = searchField.window {
            menuWindow.makeFirstResponder(searchField)

            // Try to position cursor at start
            if let fieldEditor = menuWindow.fieldEditor(true, for: searchField) as? NSTextView {
                fieldEditor.selectedRange = NSRange(location: 0, length: 0)
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        // Hide preview window when menu closes
        previewWindow?.hidePreview()

        // Remove keyboard event monitor
        removeKeyboardMonitor()

        // Clear search field
        searchField?.stringValue = ""
        currentSearchQuery = ""
        currentHighlightedItem = nil
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        // Hide preview if no item or item is not a history item
        guard let item = item,
              let historyItem = item.representedObject as? HistoryItem,
              let menuFrame = getMenuFrame() else {
            previewWindow?.hidePreview()
            currentHighlightedItem = nil
            return
        }

        // Track currently highlighted item for keyboard shortcuts
        currentHighlightedItem = historyItem

        // Show preview for this history item
        previewWindow?.showPreview(text: historyItem.text, item: historyItem, nearMenuItem: menuFrame)
    }

    /// Get the approximate frame of the menu on screen
    private func getMenuFrame() -> NSRect? {
        guard let statusButton = statusItem?.button else { return nil }

        // Get button's window and frame
        let buttonFrame = statusButton.window?.convertToScreen(statusButton.frame) ?? NSRect.zero

        // Menu appears below the button, approximate position
        return NSRect(
            x: buttonFrame.minX,
            y: buttonFrame.minY - 50, // Approximate offset
            width: 250,
            height: 400
        )
    }

    // MARK: - Keyboard Shortcuts

    private func installKeyboardMonitor() {
        // Remove existing monitor if any
        removeKeyboardMonitor()

        // Install local event monitor for key down events with higher priority
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }

            // Only process keyDown events
            guard event.type == .keyDown else { return event }

            // Get clean modifier flags (remove function key, numeric pad, etc.)
            let relevantModifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])

            // Check for Option-P (keyCode 35 is 'p', only Option pressed, no Command)
            if event.keyCode == 35 && relevantModifiers == .option {
                self.handlePinUnpinShortcut()
                return nil // Consume the event
            }

            // Check for Option-D (keyCode 2 is 'd', only Option pressed, no Command)
            if event.keyCode == 2 && relevantModifiers == .option {
                self.handleDeleteShortcut()
                return nil // Consume the event
            }

            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handlePinUnpinShortcut() {
        guard let item = currentHighlightedItem else { return }

        log("⌥P pressed - toggling pin for item")
        HistoryManager.shared.togglePin(itemId: item.id)
        rebuildHistoryItems()

        // Post notification so history changes are reflected
        NotificationCenter.default.post(name: NSNotification.Name("HistoryChanged"), object: nil)
    }

    private func handleDeleteShortcut() {
        guard let item = currentHighlightedItem else { return }

        log("⌥D pressed - deleting item")
        HistoryManager.shared.deleteItem(itemId: item.id)
        rebuildHistoryItems()

        // Hide preview since item is deleted
        previewWindow?.hidePreview()
        currentHighlightedItem = nil

        // Post notification so history changes are reflected
        NotificationCenter.default.post(name: NSNotification.Name("HistoryChanged"), object: nil)
    }
}
