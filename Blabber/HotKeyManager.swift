import Cocoa
import Carbon

class HotKeyManager {

    var onRightCommandPressed: (() -> Void)?
    var onRightCommandReleased: (() -> Void)?
    var onRightCommandDoubleTap: (() -> Void)?
    var onWorkflowProcessorRequested: (() -> Void)?

    private var eventMonitor: Any?
    private var localEventMonitor: Any?
    private let settings = SettingsManager.shared

    // Timer for minimum hold duration
    private var holdTimer: Timer?
    private let minimumHoldDuration: TimeInterval = 0.5 // 0.5 second minimum hold
    private var holdRecordingStarted = false
    private var holdWorkflowStarted = false  // Track workflow hold mode separately

    // Double-tap detection
    private var lastTapTime: Date?
    private let doubleTapWindow: TimeInterval = 0.4 // 400ms window for double-tap

    // Track current key state
    private var currentPressedKey: UInt16?
    private var currentModifiers: NSEvent.ModifierFlags = []
    private var previousModifiers: NSEvent.ModifierFlags = []

    init() {
        setupEventMonitor()
    }

    // Helper to get modifier flag for a modifier key code
    private func modifierFlagForKeyCode(_ keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: return .command  // Right/Left Command
        case 58, 61: return .option   // Left/Right Option
        case 59, 62: return .control  // Left/Right Control
        case 56, 60: return .shift    // Left/Right Shift
        default: return nil
        }
    }

    private func setupEventMonitor() {
        // Monitor flag changes (for modifier keys)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            self?.handleEvent(event)
        }

        // Also monitor local events (within app)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
    }

    private func handleEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            handleFlagsChanged(event)
        } else if event.type == .keyDown {
            handleKeyDown(event)
        } else if event.type == .keyUp {
            handleKeyUp(event)
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // Get configured hotkeys
        let holdToRecord = settings.holdToRecordHotKey
        let toggleRecording = settings.toggleRecordingHotKey
        let workflowProcessor = settings.workflowProcessorHotKey

        // Detect which modifier key was pressed or released
        if let modifierFlag = modifierFlagForKeyCode(keyCode) {
            let wasPressed = previousModifiers.contains(modifierFlag)
            let isPressed = flags.contains(modifierFlag)

            if !wasPressed && isPressed {
                // Modifier key was PRESSED
                currentModifiers = flags

                // Check if this matches any configured hotkey
                var matchesHold = false
                var matchesToggle = false
                var matchesWorkflow = false

                // Check hold-to-record
                if let holdKeyCode = holdToRecord.keyCode, keyCode == holdKeyCode {
                    if holdToRecord.modifierFlags.isEmpty || flags.contains(holdToRecord.modifierFlags) {
                        matchesHold = true
                    }
                }

                // Check toggle-recording
                if let toggleKeyCode = toggleRecording.keyCode, keyCode == toggleKeyCode {
                    if toggleRecording.modifierFlags.isEmpty || flags.contains(toggleRecording.modifierFlags) {
                        matchesToggle = true
                    }
                }

                // Check workflow processor
                if let workflowKeyCode = workflowProcessor.keyCode, keyCode == workflowKeyCode {
                    if workflowProcessor.modifierFlags.isEmpty || flags.contains(workflowProcessor.modifierFlags) {
                        matchesWorkflow = true
                    }
                }

                // Handle matches
                if matchesHold || matchesToggle || matchesWorkflow {
                    currentPressedKey = keyCode

                    // Always start hold timer if hold-to-record matches
                    // (even if toggle also matches - we'll decide on release)
                    if matchesHold {
                        startHoldTimer()
                    }

                    // Start hold timer for workflow if in hold mode
                    if matchesWorkflow && settings.workflowProcessorMode == "hold" {
                        startWorkflowHoldTimer()
                    }
                }
            } else if wasPressed && !isPressed {
                // Modifier key was RELEASED
                if currentPressedKey == keyCode {
                    handleHotKeyRelease()
                }
            }
        } else {
            // Non-modifier key combination
            currentModifiers = flags

            // Check if this key+modifier combination matches any hotkey
            var matchesHold = false
            var matchesToggle = false
            var matchesWorkflow = false

            // Check hold-to-record (with modifiers)
            if let holdKeyCode = holdToRecord.keyCode,
               keyCode == holdKeyCode,
               !holdToRecord.modifierFlags.isEmpty,
               flags == holdToRecord.modifierFlags {
                matchesHold = true
            }

            // Check toggle-recording (with modifiers)
            if let toggleKeyCode = toggleRecording.keyCode,
               keyCode == toggleKeyCode,
               !toggleRecording.modifierFlags.isEmpty,
               flags == toggleRecording.modifierFlags {
                matchesToggle = true
            }

            // Check workflow processor (with modifiers)
            if let workflowKeyCode = workflowProcessor.keyCode,
               keyCode == workflowKeyCode,
               !workflowProcessor.modifierFlags.isEmpty,
               flags == workflowProcessor.modifierFlags {
                matchesWorkflow = true
            }

            // Handle matches
            if matchesHold || matchesToggle || matchesWorkflow {
                currentPressedKey = keyCode

                // Always start hold timer if hold-to-record matches
                if matchesHold {
                    startHoldTimer()
                }
            }
        }

        previousModifiers = flags
    }

    private func handleKeyDown(_ event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // Get configured hotkeys
        let holdToRecord = settings.holdToRecordHotKey
        let toggleRecording = settings.toggleRecordingHotKey
        let workflowProcessor = settings.workflowProcessorHotKey

        currentModifiers = flags

        // Check if this key press matches any configured hotkey
        var matchesHold = false
        var matchesToggle = false
        var matchesWorkflow = false

        // Check hold-to-record
        if let holdKeyCode = holdToRecord.keyCode,
           keyCode == holdKeyCode,
           flags == holdToRecord.modifierFlags {
            matchesHold = true
        }

        // Check toggle-recording
        if let toggleKeyCode = toggleRecording.keyCode,
           keyCode == toggleKeyCode,
           flags == toggleRecording.modifierFlags {
            matchesToggle = true
        }

        // Check workflow processor
        if let workflowKeyCode = workflowProcessor.keyCode,
           keyCode == workflowKeyCode,
           flags == workflowProcessor.modifierFlags {
            matchesWorkflow = true
        }

        // Handle matches
        if matchesHold || matchesToggle || matchesWorkflow {
            currentPressedKey = keyCode

            // Always start hold timer if hold-to-record matches
            if matchesHold {
                startHoldTimer()
            }

            // Start hold timer for workflow if in hold mode
            if matchesWorkflow && settings.workflowProcessorMode == "hold" {
                startWorkflowHoldTimer()
            }
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // Get configured hotkeys
        let holdToRecord = settings.holdToRecordHotKey
        let toggleRecording = settings.toggleRecordingHotKey
        let workflowProcessor = settings.workflowProcessorHotKey

        // Check if this is the release of a pressed hotkey
        if currentPressedKey == keyCode {
            // Check if the same key is configured for both hold-to-record and toggle-recording
            let isHoldKey = holdToRecord.keyCode == keyCode && flags == holdToRecord.modifierFlags
            let isToggleKey = toggleRecording.keyCode == keyCode && flags == toggleRecording.modifierFlags
            let isSameKey = isHoldKey && isToggleKey

            if isSameKey {
                // Same key for both modes - decide based on whether hold timer fired
                if holdRecordingStarted {
                    // Long press - handle as hold-to-record
                    handleHoldToRecordRelease()
                } else {
                    // Quick press - handle as toggle-recording (double-tap)
                    handleToggleRecordingRelease()
                }
            }
            else if isHoldKey {
                // Only hold-to-record configured for this key
                handleHoldToRecordRelease()
            }
            else if isToggleKey {
                // Only toggle-recording configured for this key
                handleToggleRecordingRelease()
            }
            else if let workflowKeyCode = workflowProcessor.keyCode,
                    keyCode == workflowKeyCode,
                    flags == workflowProcessor.modifierFlags {
                // Workflow processor
                handleWorkflowProcessorRelease()
            }

            currentPressedKey = nil
            currentModifiers = []
        }
    }

    private func startHoldTimer() {
        // Cancel any existing timer
        holdTimer?.invalidate()
        holdRecordingStarted = false

        // Create timer that fires after minimum hold duration
        holdTimer = Timer.scheduledTimer(withTimeInterval: minimumHoldDuration, repeats: false) { [weak self] _ in
            // Timer completed - user held long enough, start recording
            self?.holdRecordingStarted = true
            self?.onRightCommandPressed?()
        }
    }

    private func startWorkflowHoldTimer() {
        // Cancel any existing timer
        holdTimer?.invalidate()
        holdWorkflowStarted = false

        // Create timer that fires after minimum hold duration
        holdTimer = Timer.scheduledTimer(withTimeInterval: minimumHoldDuration, repeats: false) { [weak self] _ in
            // Timer completed - user held long enough, open workflow processor
            self?.holdWorkflowStarted = true
            self?.onWorkflowProcessorRequested?()
        }
    }

    private func handleHoldToRecordRelease() {
        // Cancel timer if it hasn't fired yet
        holdTimer?.invalidate()
        holdTimer = nil

        // Check if recording was started via hold
        if holdRecordingStarted {
            // This was a hold-and-release action
            onRightCommandReleased?()
            holdRecordingStarted = false
        }
    }

    private func handleToggleRecordingRelease() {
        // Cancel any hold timer
        holdTimer?.invalidate()
        holdTimer = nil

        // This wasn't a hold action, check for double-tap
        let now = Date()

        if let lastTap = lastTapTime {
            let timeSinceLastTap = now.timeIntervalSince(lastTap)

            if timeSinceLastTap <= doubleTapWindow {
                // Double-tap detected!
                onRightCommandDoubleTap?()
                lastTapTime = nil // Reset after detecting double-tap
            } else {
                // Too slow, record as first tap
                lastTapTime = now
            }
        } else {
            // First tap, record timestamp
            lastTapTime = now
        }
    }

    private func handleWorkflowProcessorRelease() {
        // Cancel any hold timer
        holdTimer?.invalidate()
        holdTimer = nil

        // Check the workflow processor mode
        let mode = settings.workflowProcessorMode

        if mode == "hold" {
            // Hold mode: check if the timer fired (workflow already started)
            // If not, do nothing (user released too quickly)
            holdWorkflowStarted = false
        } else {
            // Double-tap mode: check for double-tap
            let now = Date()

            if let lastTap = lastTapTime {
                let timeSinceLastTap = now.timeIntervalSince(lastTap)

                if timeSinceLastTap <= doubleTapWindow {
                    // Double-tap detected!
                    onWorkflowProcessorRequested?()
                    lastTapTime = nil // Reset after detecting double-tap
                } else {
                    // Too slow, record as first tap
                    lastTapTime = now
                }
            } else {
                // First tap, record timestamp
                lastTapTime = now
            }
        }
    }

    private func handleHotKeyRelease() {
        guard currentPressedKey != nil else { return }

        // Get configured hotkeys
        let holdToRecord = settings.holdToRecordHotKey
        let toggleRecording = settings.toggleRecordingHotKey
        let workflowProcessor = settings.workflowProcessorHotKey

        // Check if the same key is configured for both hold-to-record and toggle-recording
        let isHoldKey = currentPressedKey == holdToRecord.keyCode
        let isToggleKey = currentPressedKey == toggleRecording.keyCode
        let isSameKey = isHoldKey && isToggleKey

        if isSameKey {
            // Same key for both modes - decide based on whether hold timer fired
            if holdRecordingStarted {
                // Long press - handle as hold-to-record
                handleHoldToRecordRelease()
            } else {
                // Quick press - handle as toggle-recording (double-tap)
                handleToggleRecordingRelease()
            }
        }
        else if isHoldKey {
            handleHoldToRecordRelease()
        }
        else if isToggleKey {
            handleToggleRecordingRelease()
        }
        else if currentPressedKey == workflowProcessor.keyCode {
            handleWorkflowProcessorRelease()
        }

        currentPressedKey = nil
        currentModifiers = []
    }

    deinit {
        holdTimer?.invalidate()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
