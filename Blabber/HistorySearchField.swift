import Cocoa

/// Custom search field that intercepts special keyboard shortcuts for history management
class HistorySearchField: NSSearchField, NSTextViewDelegate {

    // Callback closures for special key handling
    var onPinUnpin: (() -> Void)?
    var onDelete: (() -> Void)?

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)

        // Set ourselves as the text view's delegate to intercept key events
        if let textView = notification.object as? NSTextView {
            textView.delegate = self
        }
    }

    // NSTextViewDelegate method - called when text view interprets key events
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        // Check the current event to see what key was pressed
        guard let event = NSApp.currentEvent, event.type == .keyDown else {
            return true
        }

        let relevantModifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])

        // Check for Option-P (pin/unpin) - always intercept this
        if event.keyCode == 35 && relevantModifiers == .option {
            onPinUnpin?()
            return false // Don't insert the π character
        }

        // Check for Option-D (delete) - keyCode 2 is 'd'
        if event.keyCode == 2 && relevantModifiers == .option {
            onDelete?()
            return false // Don't insert the ∂ character
        }

        return true // Allow the text change
    }
}
