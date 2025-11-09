import Cocoa
import AppKit
import os.log

class PasteManager {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "ui")

    func handleTranscription(_ text: String) {
        let settings = SettingsManager.shared

        // Always copy if auto-copy is enabled, or if auto-paste is enabled (paste requires copy)
        if settings.autoCopyEnabled || settings.autoPasteEnabled {
            copyToClipboard(text)
        }

        // Only paste if auto-paste is enabled
        if settings.autoPasteEnabled {
            simulatePaste()
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #if DEBUG
        print("PasteManager: Text copied to clipboard")
        #endif
    }

    private func simulatePaste() {
        // Check if WorkflowProcessor window is currently visible
        let isWorkflowProcessorVisible = NSApp.windows.contains { window in
            window.windowController is WorkflowProcessorWindowController && window.isVisible
        }

        // Only hide Blabber if WorkflowProcessor window is not visible
        if !isWorkflowProcessorVisible {
            NSApp.hide(nil)
            #if DEBUG
            print("PasteManager: Hiding Blabber to return focus to target app")
            #endif
        } else {
            #if DEBUG
            print("PasteManager: WorkflowProcessor window is visible, not hiding app")
            #endif
        }

        // Simulate Cmd+V to paste
        // Increased delay to 0.2s to ensure focus has returned to target app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let source = CGEventSource(stateID: .hidSystemState)

            // Press Cmd+V
            let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 'v' key
            vKeyDown?.flags = .maskCommand
            let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            vKeyUp?.flags = .maskCommand

            vKeyDown?.post(tap: .cghidEventTap)
            vKeyUp?.post(tap: .cghidEventTap)

            #if DEBUG
            print("PasteManager: Paste command (Cmd+V) sent to target app")
            #endif
        }
    }
}
