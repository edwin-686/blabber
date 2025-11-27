import Foundation
import Cocoa

class SettingsManager {

    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    // Keys
    private enum Keys {
        static let audioFeedbackEnabled = "audioFeedbackEnabled"
        static let autoPasteEnabled = "autoPasteEnabled"
        static let autoCopyEnabled = "autoCopyEnabled"
        static let historySize = "historySize"
        static let whisperModelPath = "whisperModelPath"
        static let maxRecordingDuration = "maxRecordingDuration"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let workflowAutoPasteEnabled = "workflowAutoPasteEnabled"

        // Hotkeys
        static let holdToRecordHotKey = "holdToRecordHotKey"
        static let toggleRecordingHotKey = "toggleRecordingHotKey"
        static let workflowProcessorHotKey = "workflowProcessorHotKey"
        static let workflowProcessorMode = "workflowProcessorMode"

        // Find & Replace
        static let findReplacePairs = "findReplacePairs"

        // Transcription
        static let transcriptionLanguage = "transcriptionLanguage"
    }

    // MARK: - Properties with Defaults

    var audioFeedbackEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.audioFeedbackEnabled) == nil {
                return true // Default enabled
            }
            return defaults.bool(forKey: Keys.audioFeedbackEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.audioFeedbackEnabled)
        }
    }

    var autoPasteEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.autoPasteEnabled) == nil {
                return true // Default enabled
            }
            return defaults.bool(forKey: Keys.autoPasteEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.autoPasteEnabled)
        }
    }

    var autoCopyEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.autoCopyEnabled) == nil {
                return false // Default disabled (paste does copy anyway)
            }
            return defaults.bool(forKey: Keys.autoCopyEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.autoCopyEnabled)
        }
    }

    var historySize: Int {
        get {
            if defaults.object(forKey: Keys.historySize) == nil {
                return 5 // Default 5 items
            }
            return defaults.integer(forKey: Keys.historySize)
        }
        set {
            // Clamp to valid range
            let clamped = min(max(newValue, 5), 50)
            defaults.set(clamped, forKey: Keys.historySize)
        }
    }

    var whisperModelPath: String {
        get {
            if let path = defaults.string(forKey: Keys.whisperModelPath) {
                return path
            }
            // Default path
            return NSHomeDirectory() + "/Models/ggml-large-v3-turbo.bin"
        }
        set {
            defaults.set(newValue, forKey: Keys.whisperModelPath)
        }
    }

    var maxRecordingDuration: TimeInterval {
        get {
            if defaults.object(forKey: Keys.maxRecordingDuration) == nil {
                return 600 // Default 10 minutes (600 seconds)
            }
            return defaults.double(forKey: Keys.maxRecordingDuration)
        }
        set {
            // Clamp to valid range: 60 seconds (1 minute) to 1800 seconds (30 minutes)
            let clamped = min(max(newValue, 60), 1800)
            defaults.set(clamped, forKey: Keys.maxRecordingDuration)
        }
    }

    var hasCompletedOnboarding: Bool {
        get {
            return defaults.bool(forKey: Keys.hasCompletedOnboarding)
        }
        set {
            defaults.set(newValue, forKey: Keys.hasCompletedOnboarding)
        }
    }

    var workflowAutoPasteEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.workflowAutoPasteEnabled) == nil {
                return true // Default enabled
            }
            return defaults.bool(forKey: Keys.workflowAutoPasteEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.workflowAutoPasteEnabled)
        }
    }

    // MARK: - Hotkeys

    /// Hotkey for press-and-hold to record (default: Right Command key)
    var holdToRecordHotKey: (keyCode: UInt16?, modifierFlags: NSEvent.ModifierFlags) {
        get {
            if let dict = defaults.dictionary(forKey: Keys.holdToRecordHotKey),
               let keyCode = dict["keyCode"] as? UInt16,
               let rawFlags = dict["modifierFlags"] as? UInt {
                return (keyCode, NSEvent.ModifierFlags(rawValue: rawFlags))
            }
            // Default: Right Command key (keycode 54)
            return (54, [])
        }
        set {
            if let keyCode = newValue.keyCode {
                defaults.set([
                    "keyCode": keyCode,
                    "modifierFlags": newValue.modifierFlags.rawValue
                ], forKey: Keys.holdToRecordHotKey)
            } else {
                defaults.removeObject(forKey: Keys.holdToRecordHotKey)
            }
        }
    }

    /// Hotkey for toggle recording (default: Right Command double-tap)
    var toggleRecordingHotKey: (keyCode: UInt16?, modifierFlags: NSEvent.ModifierFlags) {
        get {
            if let dict = defaults.dictionary(forKey: Keys.toggleRecordingHotKey),
               let keyCode = dict["keyCode"] as? UInt16,
               let rawFlags = dict["modifierFlags"] as? UInt {
                return (keyCode, NSEvent.ModifierFlags(rawValue: rawFlags))
            }
            // Default: Right Command key (keycode 54) - will be handled as double-tap
            return (54, [])
        }
        set {
            if let keyCode = newValue.keyCode {
                defaults.set([
                    "keyCode": keyCode,
                    "modifierFlags": newValue.modifierFlags.rawValue
                ], forKey: Keys.toggleRecordingHotKey)
            } else {
                defaults.removeObject(forKey: Keys.toggleRecordingHotKey)
            }
        }
    }

    /// Hotkey for opening workflow processor (default: Right Option key double-tap)
    var workflowProcessorHotKey: (keyCode: UInt16?, modifierFlags: NSEvent.ModifierFlags) {
        get {
            if let dict = defaults.dictionary(forKey: Keys.workflowProcessorHotKey),
               let keyCode = dict["keyCode"] as? UInt16,
               let rawFlags = dict["modifierFlags"] as? UInt {
                return (keyCode, NSEvent.ModifierFlags(rawValue: rawFlags))
            }
            // Default: Right Option key (keycode 61)
            return (61, [])
        }
        set {
            if let keyCode = newValue.keyCode {
                defaults.set([
                    "keyCode": keyCode,
                    "modifierFlags": newValue.modifierFlags.rawValue
                ], forKey: Keys.workflowProcessorHotKey)
            } else {
                defaults.removeObject(forKey: Keys.workflowProcessorHotKey)
            }
        }
    }

    var workflowProcessorMode: String {
        get {
            if let mode = defaults.string(forKey: Keys.workflowProcessorMode) {
                return mode
            }
            // Default: double-tap mode (for Right Option key)
            return "double-tap"
        }
        set {
            defaults.set(newValue, forKey: Keys.workflowProcessorMode)
        }
    }

    // MARK: - Find & Replace

    /// Find and replace pairs for transcription corrections
    var findReplacePairs: [(find: String, replace: String, caseSensitive: Bool)] {
        get {
            if let array = defaults.array(forKey: Keys.findReplacePairs) as? [[String: Any]] {
                return array.compactMap { dict in
                    guard let find = dict["find"] as? String,
                          let replace = dict["replace"] as? String else {
                        return nil
                    }
                    let caseSensitive = dict["caseSensitive"] as? Bool ?? false
                    return (find: find, replace: replace, caseSensitive: caseSensitive)
                }
            }
            return []
        }
        set {
            let array = newValue.map { ["find": $0.find, "replace": $0.replace, "caseSensitive": $0.caseSensitive] }
            defaults.set(array, forKey: Keys.findReplacePairs)
        }
    }

    // MARK: - Transcription Settings

    /// Language for transcription (ISO 639-1 code, or "auto" for auto-detect)
    var transcriptionLanguage: String {
        get {
            return defaults.string(forKey: Keys.transcriptionLanguage) ?? "auto"
        }
        set {
            defaults.set(newValue, forKey: Keys.transcriptionLanguage)
        }
    }

    // MARK: - Initialization

    private init() {
        // Private initializer for singleton
    }

    // MARK: - Reset

    func resetToDefaults() {
        audioFeedbackEnabled = true
        autoPasteEnabled = true
        autoCopyEnabled = false
        historySize = 5
        whisperModelPath = NSHomeDirectory() + "/Models/ggml-large-v3-turbo.bin"
        maxRecordingDuration = 600 // 10 minutes
        workflowAutoPasteEnabled = true
        transcriptionLanguage = "auto"

        // Reset hotkeys to defaults
        holdToRecordHotKey = (54, [])  // Right Command
        toggleRecordingHotKey = (54, [])  // Right Command double-tap
        workflowProcessorHotKey = (61, [])  // Right Option key
        workflowProcessorMode = "double-tap"  // Default: double-tap mode
    }

    func resetHotkeysToDefaults() {
        // Reset only hotkeys to defaults (does not affect other settings)
        holdToRecordHotKey = (54, [])  // Right Command
        toggleRecordingHotKey = (54, [])  // Right Command double-tap
        workflowProcessorHotKey = (61, [])  // Right Option key
        workflowProcessorMode = "double-tap"  // Default: double-tap mode
    }
}
