import Cocoa
import os.log

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "application")

    var menuBarManager: MenuBarManager?
    var onboardingWindowController: OnboardingWindowController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        #if DEBUG
        print("========================================")
        print("Blabber is launching...")
        print("hasCompletedOnboarding = \(SettingsManager.shared.hasCompletedOnboarding)")
        print("========================================")
        #endif

        // Check if first launch (onboarding not completed)
        if !SettingsManager.shared.hasCompletedOnboarding {
            os_log(.info, log: Self.logger, "First launch detected - showing onboarding")
            showOnboarding()
        } else {
            os_log(.info, log: Self.logger, "Onboarding already complete - initializing MenuBarManager")
            initializeMenuBarManager()
        }

        os_log(.info, log: Self.logger, "Application did finish launching")
    }

    private func showOnboarding() {
        onboardingWindowController = OnboardingWindowController()
        onboardingWindowController?.onComplete = { [weak self] in
            // Initialize menu bar manager after onboarding completes
            self?.initializeMenuBarManager()
        }

        // Ensure window appears on top of all other windows
        if let window = onboardingWindowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func initializeMenuBarManager() {
        os_log(.info, log: Self.logger, "Initializing menu bar manager")
        menuBarManager = MenuBarManager()
        os_log(.info, log: Self.logger, "Blabber is now running in the menu bar")

        // Auto-show menu after onboarding completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.menuBarManager?.showMenu()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        os_log(.info, log: Self.logger, "Blabber is terminating")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Hotkey Management

    /// Temporarily disable hotkeys (used when configuring hotkeys in settings)
    func disableHotKeys() {
        menuBarManager?.hotKeyManager = nil
        #if DEBUG
        print("Hotkeys disabled")
        #endif
    }

    /// Re-enable hotkeys after configuration
    func enableHotKeys() {
        menuBarManager?.setupHotKeys()
        #if DEBUG
        print("Hotkeys re-enabled")
        #endif
    }
}
