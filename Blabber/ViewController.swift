import Cocoa
import AVFoundation
import os.log

class ViewController: NSViewController {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "ui")

    var recordButton: NSButton!
    var statusLabel: NSTextField!
    var logTextView: NSTextView!
    var scrollView: NSScrollView!

    var audioRecorder: AudioRecorder?
    var transcriber: WhisperTranscriber?
    var pasteManager: PasteManager?
    var hotKeyManager: HotKeyManager?

    var isRecording = false

    override func viewDidLoad() {
        super.viewDidLoad()

        os_log(.info, log: Self.logger, "ViewController loaded - hiding debug window")

        // Don't set up UI or components - we don't need this window
        // setupUI()
        // setupComponents()
        // requestPermissions()
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        // IMPORTANT: Hide this window immediately - we don't use it anymore
        // App operates entirely through menu bar + hotkeys
        log("ViewController viewWillAppear - closing window")
        view.window?.orderOut(nil)
        view.window?.close()
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        // Extra safety: hide window even if it somehow appears
        log("ViewController viewDidAppear - forcing window closed")
        view.window?.orderOut(nil)
        view.window?.setIsVisible(false)
        view.window?.close()
    }

    func setupUI() {
        view.setFrameSize(NSSize(width: 500, height: 400))

        // Record Button
        recordButton = NSButton(frame: NSRect(x: 150, y: 320, width: 200, height: 50))
        recordButton.title = "🎤 Start Recording"
        recordButton.bezelStyle = .rounded
        recordButton.target = self
        recordButton.action = #selector(recordButtonClicked)
        view.addSubview(recordButton)

        // Status Label
        statusLabel = NSTextField(frame: NSRect(x: 50, y: 280, width: 400, height: 30))
        statusLabel.stringValue = "Debug Mode - Use menu bar or hotkeys to record"
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.alignment = .center
        view.addSubview(statusLabel)

        // Disable button if in debug mode (components will be shared)
        // We'll enable it later in setupComponents if this is standalone mode
        recordButton.isEnabled = false

        // Log ScrollView and TextView
        scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: 460, height: 240))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false

        logTextView = NSTextView(frame: scrollView.contentView.bounds)
        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        scrollView.documentView = logTextView
        view.addSubview(scrollView)

        log("UI setup complete")
    }

    func setupComponents() {
        // Determine if we're in standalone mode or debug mode
        let isStandaloneMode = (audioRecorder == nil)

        // Only initialize components if they weren't already provided (e.g., by MenuBarManager)
        if audioRecorder == nil {
            audioRecorder = AudioRecorder()
            log("Created new AudioRecorder (standalone mode)")
        } else {
            log("Using shared AudioRecorder from MenuBarManager (debug mode)")
        }

        if transcriber == nil {
            transcriber = WhisperTranscriber()
            log("Created new WhisperTranscriber")
        } else {
            log("Using shared WhisperTranscriber from MenuBarManager")
        }

        if pasteManager == nil {
            pasteManager = PasteManager()
            log("Created new PasteManager")
        } else {
            log("Using shared PasteManager from MenuBarManager")
        }

        // DISABLED: Don't create HotKeyManager in ViewController to prevent conflicts
        // Hotkeys should only be managed by MenuBarManager
        if hotKeyManager != nil {
            log("Using shared HotKeyManager from MenuBarManager")
        } else {
            log("No HotKeyManager (hotkeys managed by MenuBarManager only)")
        }

        // Enable record button only in standalone mode
        if isStandaloneMode {
            recordButton?.isEnabled = true
            statusLabel?.stringValue = "Ready. Press button or Right Command key."
            log("Standalone mode - Record button enabled")
        } else {
            recordButton?.isEnabled = false
            statusLabel?.stringValue = "Debug Mode - Use menu bar or hotkeys to record"
            log("Debug mode - Record button disabled (use menu bar controls)")
        }

        log("Components setup complete")
    }

    func requestPermissions() {
        log("Requesting permissions...")

        // Request accessibility permissions
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if accessEnabled {
            log("✓ Accessibility permissions granted")
        } else {
            log("⚠️ Accessibility permissions needed for hotkey")
        }

        // Request microphone permissions
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.log("✓ Microphone permissions granted")
                } else {
                    self?.log("⚠️ Microphone permissions denied")
                }
            }
        }
    }

    @objc func recordButtonClicked() {
        if isRecording {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true

        log("🔴 Recording started...")
        statusLabel.stringValue = "Recording... (Release Right Command or click button to stop)"
        recordButton.title = "⏹ Stop Recording"

        audioRecorder?.startRecording()
    }

    func stopRecordingAndTranscribe() {
        guard isRecording else { return }
        isRecording = false

        log("⏸ Recording stopped")
        statusLabel.stringValue = "Transcribing..."
        recordButton.title = "🎤 Start Recording"

        guard let audioFile = audioRecorder?.stopRecording() else {
            log("❌ Failed to stop recording")
            statusLabel.stringValue = "Error: Failed to stop recording"
            return
        }

        log("Transcribing audio file...")

        // Transcribe in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let text = self?.transcriber?.transcribe(audioFile: audioFile) else {
                DispatchQueue.main.async {
                    self?.log("❌ Transcription failed")
                    self?.statusLabel.stringValue = "Transcription failed"
                }
                return
            }

            DispatchQueue.main.async {
                self?.log("✓ Transcription: \"\(text)\"")
                self?.statusLabel.stringValue = "Processing..."
                self?.pasteManager?.handleTranscription(text)
                self?.statusLabel.stringValue = "Ready. Press button or Right Command key."
                self?.log("✓ Transcription complete")
            }
        }
    }

    func log(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let textView = self.logTextView else { return }

            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let logMessage = "[\(timestamp)] \(message)\n"

            let currentText = textView.string
            textView.string = currentText + logMessage

            // Auto-scroll to bottom
            textView.scrollToEndOfDocument(nil)

            // Also print to console
            print(logMessage.trimmingCharacters(in: .newlines))
        }
    }
}
