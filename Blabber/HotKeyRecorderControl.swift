import Cocoa
import Carbon

/// A custom control for recording keyboard shortcuts, inspired by Maccy
class HotKeyRecorderControl: NSView {

    // MARK: - Properties

    private var borderView: NSBox!
    private var labelField: NSTextField!
    private var clearButton: NSButton!

    private var isRecording = false
    private var localMonitor: Any?
    private var recordedModifiers: NSEvent.ModifierFlags = []
    private var recordedKeyCode: UInt16?
    private var hasRecordedNonModifier = false
    private var pressedModifierKeyCodes: Set<UInt16> = []

    var keyCode: UInt16?
    var modifierFlags: NSEvent.ModifierFlags = []

    var onHotKeyChanged: ((UInt16?, NSEvent.ModifierFlags) -> Void)?

    private let placeholderText = "Click to record shortcut"
    var allowSingleKey: Bool = false  // If true, shows "(double tap)" for single keys
    var allowModifierKeys: Bool = false  // If true, allows single/multiple modifier keys without "(double tap)"
    var singleKeyOnly: Bool = false  // If true, restricts to single keys only (for toggle/workflow)
    var detectHoldMode: Bool = false  // If true, detect whether user holds or quick-presses (for workflow)

    // Hold mode detection
    private var holdModeTimer: Timer?
    private var detectedMode: String?  // "hold" or "double-tap"
    var currentMode: String?  // Store current mode for display ("hold" or "double-tap")
    var onModeDetected: ((String) -> Void)?

    // Modifier key codes
    private let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62] // Cmd, Shift, Option, Control (L&R)

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - UI Setup

    private func setupUI() {
        wantsLayer = true

        // Border/background
        borderView = NSBox()
        borderView.boxType = .custom
        borderView.borderType = .lineBorder
        borderView.cornerRadius = 4
        borderView.borderColor = .separatorColor
        borderView.borderWidth = 1
        borderView.fillColor = .controlBackgroundColor
        addSubview(borderView)

        // Label to display the shortcut
        labelField = NSTextField(labelWithString: placeholderText)
        labelField.font = .systemFont(ofSize: 13)
        labelField.textColor = .secondaryLabelColor
        labelField.alignment = .center
        labelField.lineBreakMode = .byTruncatingTail
        addSubview(labelField)

        // Clear button
        clearButton = NSButton()
        clearButton.title = "✕"
        clearButton.bezelStyle = .roundRect
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 12)
        clearButton.target = self
        clearButton.action = #selector(clearHotKey)
        clearButton.isHidden = true
        addSubview(clearButton)

        // Click gesture
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(clickGesture)

        layoutSubviews()
    }

    private func layoutSubviews() {
        borderView.frame = bounds

        let clearButtonWidth: CGFloat = 20
        let padding: CGFloat = 8

        clearButton.frame = NSRect(
            x: bounds.width - clearButtonWidth - padding,
            y: (bounds.height - clearButtonWidth) / 2,
            width: clearButtonWidth,
            height: clearButtonWidth
        )

        let labelX = padding
        let labelWidth = clearButton.isHidden ? bounds.width - padding * 2 : bounds.width - clearButtonWidth - padding * 3

        labelField.frame = NSRect(
            x: labelX,
            y: (bounds.height - 20) / 2,
            width: labelWidth,
            height: 20
        )
    }

    override func layout() {
        super.layout()
        layoutSubviews()
    }

    // MARK: - Recording

    @objc private func handleClick() {
        if !isRecording {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        labelField.stringValue = "Press keys..."
        labelField.textColor = .labelColor
        borderView.borderColor = .controlAccentColor
        borderView.borderWidth = 2

        // Reset tracking
        recordedModifiers = []
        recordedKeyCode = nil
        hasRecordedNonModifier = false
        pressedModifierKeyCodes = []

        // Become first responder to receive key events
        window?.makeFirstResponder(self)

        // Monitor key events
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil // Consume the event
        }
    }

    private func stopRecording() {
        isRecording = false
        borderView.borderColor = .separatorColor
        borderView.borderWidth = 1

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        // Clean up hold mode timer
        holdModeTimer?.invalidate()
        holdModeTimer = nil

        updateDisplay()
        onHotKeyChanged?(keyCode, modifierFlags)
    }

    private func cancelRecording() {
        isRecording = false
        borderView.borderColor = .separatorColor
        borderView.borderWidth = 1

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        // Clean up hold mode timer
        holdModeTimer?.invalidate()
        holdModeTimer = nil
        detectedMode = nil

        recordedModifiers = []
        recordedKeyCode = nil
        hasRecordedNonModifier = false
        pressedModifierKeyCodes = []
        updateDisplay()
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let eventKeyCode = event.keyCode
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if event.type == .flagsChanged {
            // Track which modifier keys are pressed/released
            if modifierKeyCodes.contains(eventKeyCode) {
                // Detect if THIS key was pressed or released
                let wasPressed = pressedModifierKeyCodes.contains(eventKeyCode)

                // Check if THIS specific key's modifier flag is present
                let thisKeyModifierFlag = modifierFlagForKeyCode(eventKeyCode)
                let isNowPressed = thisKeyModifierFlag != nil && flags.contains(thisKeyModifierFlag!)

                if !wasPressed && isNowPressed {
                    // This key was just PRESSED
                    pressedModifierKeyCodes.insert(eventKeyCode)
                    recordedModifiers = flags

                    if allowModifierKeys {
                        // Press-and-hold mode: only allow 1-2 modifier keys
                        if pressedModifierKeyCodes.count == 1 {
                            labelField.stringValue = modifierFlagsToString(flags)
                        } else if pressedModifierKeyCodes.count == 2 {
                            // Two modifiers pressed - record immediately
                            let sortedKeys = Array(pressedModifierKeyCodes).sorted()
                            keyCode = sortedKeys[0]
                            var remainingFlags: NSEvent.ModifierFlags = []
                            for modKey in sortedKeys.dropFirst() {
                                if [54, 55].contains(modKey) { remainingFlags.insert(.command) }
                                else if [58, 61].contains(modKey) { remainingFlags.insert(.option) }
                                else if [59, 62].contains(modKey) { remainingFlags.insert(.control) }
                                else if [56, 60].contains(modKey) { remainingFlags.insert(.shift) }
                            }
                            modifierFlags = remainingFlags
                            stopRecording()
                        } else {
                            // More than 2 keys - too many
                            labelField.stringValue = "Too many keys!"
                        }
                    } else {
                        // Toggle/workflow mode
                        if singleKeyOnly {
                            // Single key only mode: silently show current state
                            // Don't show any messages about multiple keys, just wait for last release
                            if pressedModifierKeyCodes.count >= 1 {
                                labelField.stringValue = modifierFlagsToString(flags)

                                // Handle hold timer for workflow processor
                                if detectHoldMode {
                                    if pressedModifierKeyCodes.count == 1 {
                                        // Exactly 1 key - start/restart timer
                                        startHoldModeTimer()
                                    } else {
                                        // Multiple keys - cancel timer to prevent false "hold" detection
                                        holdModeTimer?.invalidate()
                                        holdModeTimer = nil
                                        detectedMode = nil
                                    }
                                }
                            }
                        } else {
                            // Allow multiple modifiers
                            labelField.stringValue = modifierFlagsToString(flags) + "..."
                        }
                    }
                } else if wasPressed {
                    // This key was just RELEASED
                    let wasCount = pressedModifierKeyCodes.count
                    pressedModifierKeyCodes.remove(eventKeyCode)

                    // Check if all modifiers have been released
                    if pressedModifierKeyCodes.isEmpty && !recordedModifiers.isEmpty && !hasRecordedNonModifier {
                        if allowModifierKeys {
                            // Press-and-hold: only record single modifier on release
                            if wasCount == 1 {
                                keyCode = eventKeyCode
                                modifierFlags = []
                                stopRecording()
                            }
                        } else if allowSingleKey || (singleKeyOnly && detectHoldMode) {
                            // Toggle/workflow: check if single-key-only restriction
                            if singleKeyOnly {
                                // Single key only mode: always use last released key
                                if pressedModifierKeyCodes.isEmpty {
                                    // Check if timer already fired and recorded (workflow processor)
                                    if detectHoldMode && wasCount == 1 {
                                        // Check if we're still recording (timer might have already fired)
                                        if !isRecording {
                                            // Timer already fired and recorded as "hold" - do nothing
                                            return
                                        }

                                        // Quick release - cancel timer and record as double-tap
                                        holdModeTimer?.invalidate()
                                        holdModeTimer = nil

                                        detectedMode = "double-tap"
                                        currentMode = "double-tap"
                                        keyCode = eventKeyCode
                                        modifierFlags = []
                                        onModeDetected?("double-tap")
                                        stopRecording()
                                    } else {
                                        // Not in detectHoldMode - record normally
                                        keyCode = eventKeyCode
                                        modifierFlags = []
                                        stopRecording()
                                    }
                                }
                                // If some keys still pressed, do nothing - wait for last release
                            } else {
                                // Allow multi-modifier combos
                                if recordedModifiers.rawValue.nonzeroBitCount == 1 {
                                    keyCode = eventKeyCode
                                    modifierFlags = []
                                } else {
                                    keyCode = eventKeyCode
                                    var remainingFlags = recordedModifiers
                                    if let releasedMod = modifierFlagForKeyCode(eventKeyCode) {
                                        remainingFlags.remove(releasedMod)
                                    }
                                    modifierFlags = remainingFlags
                                }
                                stopRecording()
                            }
                        }
                    } else if !pressedModifierKeyCodes.isEmpty {
                        // Some modifiers still pressed
                        recordedModifiers = flags
                        labelField.stringValue = modifierFlagsToString(flags) + "..."
                    } else {
                        // All released but nothing to record
                        recordedModifiers = []
                    }
                }
            }

        } else if event.type == .keyDown {
            // Escape cancels recording
            if eventKeyCode == 53 {
                cancelRecording()
                return
            }

            if modifierKeyCodes.contains(eventKeyCode) {
                // Already handled in flagsChanged
                return
            } else {
                // Non-modifier key pressed
                // Special keys that can be recorded
                let specialKeys: Set<UInt16> = [
                    49,  // Space
                    36,  // Return
                    48,  // Tab
                    51,  // Delete
                    123, 124, 125, 126, // Arrow keys
                ]

                // Determine if this combination is valid
                let hasModifiers = !pressedModifierKeyCodes.isEmpty || !recordedModifiers.isEmpty
                let isSpecialKey = specialKeys.contains(eventKeyCode)

                if allowModifierKeys {
                    // Press-and-hold mode: ONLY modifier keys allowed, reject all others
                    labelField.stringValue = "Only modifier keys allowed"
                    return
                } else if singleKeyOnly {
                    // Single-key-only mode: reject non-modifier keys
                    labelField.stringValue = "Single modifier key only"
                    return
                } else if allowSingleKey {
                    // Toggle/workflow mode: allow any key
                    keyCode = eventKeyCode
                    modifierFlags = recordedModifiers
                    hasRecordedNonModifier = true
                    stopRecording()
                } else {
                    // Default mode: require modifiers
                    if hasModifiers || isSpecialKey {
                        keyCode = eventKeyCode
                        modifierFlags = recordedModifiers
                        hasRecordedNonModifier = true
                        stopRecording()
                    }
                }
            }
        }
    }

    // MARK: - Display

    private func updateDisplay() {
        if let keyCode = keyCode {
            let modifierString = modifierFlagsToString(modifierFlags)
            let keyString = keyCodeToString(keyCode)
            let isModifierKey = modifierKeyCodes.contains(keyCode)

            if modifierString.isEmpty {
                // Single key - check display mode
                if allowSingleKey && !isModifierKey {
                    // Single regular key with double-tap
                    labelField.stringValue = keyString + " (double tap)"
                } else if (detectHoldMode && singleKeyOnly && isModifierKey) || (allowSingleKey && isModifierKey && !allowModifierKeys) {
                    // Single modifier key for toggle/workflow - show L/R with mode
                    let modeIndicator: String
                    if detectHoldMode {
                        // Workflow processor: show detected mode
                        modeIndicator = currentMode == "hold" ? " (press and hold)" : " (double tap)"
                    } else {
                        // Toggle recording: always double tap
                        modeIndicator = " (double tap)"
                    }
                    labelField.stringValue = keyCodeToString(keyCode) + modeIndicator
                } else if allowModifierKeys && isModifierKey {
                    // Single modifier key for press-and-hold (show L/R)
                    labelField.stringValue = keyString  // Uses keyCodeToString which shows L/R
                } else {
                    labelField.stringValue = keyString
                }
            } else {
                // Multiple keys
                if isModifierKey && allowModifierKeys {
                    // Multi-modifier combo for press-and-hold: show with L/R
                    let triggerKeyString = keyCodeToString(keyCode)
                    let otherModsString = modifierFlagsToString(modifierFlags)
                    labelField.stringValue = otherModsString + triggerKeyString
                } else if isModifierKey {
                    // Multi-modifier combo for toggle/workflow: show symbols only
                    var allModifiers = modifierFlags
                    if let keyModifier = modifierFlagForKeyCode(keyCode) {
                        allModifiers.insert(keyModifier)
                    }
                    labelField.stringValue = modifierFlagsToString(allModifiers)
                } else {
                    // Modifier + regular key
                    labelField.stringValue = modifierString + keyString
                }
            }

            labelField.textColor = .labelColor
            clearButton.isHidden = false
        } else {
            labelField.stringValue = placeholderText
            labelField.textColor = .secondaryLabelColor
            clearButton.isHidden = true
        }

        layoutSubviews()
    }

    // Get modifier flag for a key code
    private func modifierFlagForKeyCode(_ keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: return .command
        case 58, 61: return .option
        case 59, 62: return .control
        case 56, 60: return .shift
        default: return nil
        }
    }

    // Get just the symbol for a modifier key (without L/R)
    private func modifierKeySymbol(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 54, 55: return "⌘"
        case 58, 61: return "⌥"
        case 59, 62: return "⌃"
        case 56, 60: return "⇧"
        default: return keyCodeToString(keyCode)
        }
    }

    private func modifierFlagsToString(_ flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        // Map common key codes to readable strings
        switch keyCode {
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
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 54: return "⌘R" // Right Command
        case 55: return "⌘L" // Left Command
        case 56: return "⇧L" // Left Shift
        case 58: return "⌥L" // Left Option
        case 59: return "⌃L" // Left Control
        case 60: return "⇧R" // Right Shift
        case 61: return "⌥R" // Right Option
        case 62: return "⌃R" // Right Control
        case 63: return "Fn" // Function key
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
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
        default:
            // Try to get the character
            if let character = keyCodeToCharacter(keyCode) {
                return character
            }
            return "Key \(keyCode)"
        }
    }

    private func keyCodeToCharacter(_ keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)

        guard let data = layoutData else { return nil }

        let keyboardLayout = unsafeBitCast(data, to: CFData.self)
        let layout = unsafeBitCast(CFDataGetBytePtr(keyboardLayout), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let error = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard error == noErr, length > 0 else { return nil }

        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    // MARK: - Hold Mode Detection

    private func startHoldModeTimer() {
        // Cancel any existing timer
        holdModeTimer?.invalidate()
        detectedMode = nil

        // Store the current key being held
        guard let currentKey = pressedModifierKeyCodes.first else { return }

        // Create timer that fires after 0.5s to immediately record as hold mode
        holdModeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            // Timer fired - user held long enough, immediately record and exit
            self.detectedMode = "hold"
            self.currentMode = "hold"
            self.keyCode = currentKey
            self.modifierFlags = []
            self.onModeDetected?("hold")

            // Immediately stop recording (exit blue/focused state)
            self.stopRecording()
        }
    }

    // MARK: - Actions

    @objc private func clearHotKey() {
        keyCode = nil
        modifierFlags = []
        currentMode = nil
        updateDisplay()
        onHotKeyChanged?(nil, [])
    }

    // MARK: - Public Methods

    func setHotKey(keyCode: UInt16?, modifierFlags: NSEvent.ModifierFlags, mode: String? = nil) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.currentMode = mode
        updateDisplay()
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            stopRecording()
        }
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        // Prevent event propagation when clicked
        handleClick()
    }
}
