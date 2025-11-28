import Cocoa
import os.log

class AboutViewController: NSViewController {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "updates")

    private var updateStatusLabel: NSTextField!
    private var updateSpinner: NSProgressIndicator!
    private var updateActionButton: NSButton!
    private var latestVersion: String?
    private var downloadURL: String?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        checkForUpdates()
    }

    private func setupUI() {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stackView)

        // App Icon
        let iconImageView = NSImageView()
        if let appIcon = NSImage(named: "AppIcon") {
            iconImageView.image = appIcon
        } else {
            // Fallback to system waveform icon if AppIcon not found
            iconImageView.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Blabber")
        }
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(iconImageView)

        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 128),
            iconImageView.heightAnchor.constraint(equalToConstant: 128)
        ])

        // App Name
        let appNameLabel = NSTextField(labelWithString: "Blabber")
        appNameLabel.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        appNameLabel.alignment = .center
        stackView.addArrangedSubview(appNameLabel)

        // Version
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.font = NSFont.systemFont(ofSize: 14)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        stackView.addArrangedSubview(versionLabel)

        // Add some spacing
        stackView.addArrangedSubview(NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 8)))

        // Links section - Row 1: Website | GitHub | License
        let linksRow1 = NSStackView()
        linksRow1.orientation = .horizontal
        linksRow1.spacing = 4
        linksRow1.addArrangedSubview(createLinkButton(title: "Website", url: "https://blabbernotes.com"))
        linksRow1.addArrangedSubview(createPipeLabel())
        linksRow1.addArrangedSubview(createLinkButton(title: "GitHub", url: "https://github.com/edwin-686/blabber"))
        linksRow1.addArrangedSubview(createPipeLabel())
        linksRow1.addArrangedSubview(createLinkButton(title: "License", url: "https://github.com/edwin-686/blabber/blob/master/LICENSE"))
        stackView.addArrangedSubview(linksRow1)

        // Row 2: Support & Feature Requests
        let supportButton = createLinkButton(title: "Support & Feature Requests", url: "mailto:edwinsauerman@gmail.com")
        stackView.addArrangedSubview(supportButton)

        // Add some spacing
        stackView.addArrangedSubview(NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 8)))

        // Update check section
        let updateStackView = NSStackView()
        updateStackView.orientation = .vertical
        updateStackView.alignment = .centerX
        updateStackView.spacing = 8
        stackView.addArrangedSubview(updateStackView)

        // Update spinner
        updateSpinner = NSProgressIndicator()
        updateSpinner.style = .spinning
        updateSpinner.controlSize = .small
        updateSpinner.translatesAutoresizingMaskIntoConstraints = false
        updateStackView.addArrangedSubview(updateSpinner)

        // Update status label
        updateStatusLabel = NSTextField(labelWithString: "")
        updateStatusLabel.font = NSFont.systemFont(ofSize: 12)
        updateStatusLabel.textColor = .secondaryLabelColor
        updateStatusLabel.alignment = .center
        updateStatusLabel.isHidden = true
        updateStackView.addArrangedSubview(updateStatusLabel)

        // Update action button (Download Update or Try Again)
        updateActionButton = NSButton()
        updateActionButton.bezelStyle = .rounded
        updateActionButton.target = self
        updateActionButton.action = #selector(updateActionClicked)
        updateActionButton.isHidden = true
        updateStackView.addArrangedSubview(updateActionButton)

        // Add some spacing
        stackView.addArrangedSubview(NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 8)))

        // Buy Me A Coffee button
        let buyMeCoffeeButton = NSButton()
        buyMeCoffeeButton.title = " Buy Me A Coffee"
        buyMeCoffeeButton.bezelStyle = .rounded
        buyMeCoffeeButton.target = self
        buyMeCoffeeButton.action = #selector(openBuyMeCoffee)

        // Add coffee icon to button
        if let coffeeIcon = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Coffee") {
            buyMeCoffeeButton.image = coffeeIcon
            buyMeCoffeeButton.imagePosition = .imageLeading
        }

        stackView.addArrangedSubview(buyMeCoffeeButton)

        // Copyright
        let copyrightLabel = NSTextField(labelWithString: "© 2025 Blabber")
        copyrightLabel.font = NSFont.systemFont(ofSize: 11)
        copyrightLabel.textColor = .tertiaryLabelColor
        copyrightLabel.alignment = .center
        stackView.addArrangedSubview(copyrightLabel)

        // Center stackView in view
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
    }

    private func createPipeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "|")
        label.textColor = .tertiaryLabelColor
        label.font = NSFont.systemFont(ofSize: 13)
        return label
    }

    private func createLinkButton(title: String, url: String) -> NSButton {
        let button = NSButton()
        button.title = title
        button.bezelStyle = .inline
        button.isBordered = false

        // Create attributed string with blue color and underline
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: NSFont.systemFont(ofSize: 13)
        ]
        button.attributedTitle = NSAttributedString(string: title, attributes: attributes)

        button.target = self
        button.action = #selector(linkClicked(_:))
        button.tag = url.hashValue

        // Store URL in button's represented object
        button.identifier = NSUserInterfaceItemIdentifier(url)

        return button
    }

    @objc private func linkClicked(_ sender: NSButton) {
        guard let urlString = sender.identifier?.rawValue,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openBuyMeCoffee() {
        if let url = URL(string: "https://buymeacoffee.com/blabbernotes") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Update Checking

    private func checkForUpdates() {
        #if DEBUG
        print("[AboutViewController] Starting update check")
        #endif

        updateSpinner.startAnimation(nil)
        updateStatusLabel.stringValue = "Checking for updates..."
        updateStatusLabel.isHidden = false
        updateActionButton.isHidden = true

        guard let url = URL(string: "https://api.github.com/repos/edwin-686/blabber/releases/latest") else {
            os_log(.error, log: Self.logger, "Invalid GitHub API URL")
            showError()
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleUpdateResponse(data: data, response: response, error: error)
            }
        }
        task.resume()
    }

    private func handleUpdateResponse(data: Data?, response: URLResponse?, error: Error?) {
        updateSpinner.stopAnimation(nil)

        if let error = error {
            os_log(.error, log: Self.logger, "Update check failed: %{public}@", error.localizedDescription)
            #if DEBUG
            print("[AboutViewController] Update check error: \(error)")
            #endif
            showError()
            return
        }

        guard let data = data else {
            os_log(.error, log: Self.logger, "Update check returned no data")
            showError()
            return
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                os_log(.error, log: Self.logger, "Failed to parse update response as JSON")
                showError()
                return
            }

            guard let tagName = json["tag_name"] as? String else {
                os_log(.error, log: Self.logger, "Missing required fields in update response")
                showError()
                return
            }

            // Strip "v" prefix from tag name (e.g., "v1.0.1" -> "1.0.1")
            let latestVersionString = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            latestVersion = latestVersionString
            downloadURL = "https://blabbernotes.com/download"

            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

            #if DEBUG
            print("[AboutViewController] Current version: \(currentVersion), Latest version: \(latestVersionString)")
            #endif

            if isNewerVersion(latestVersionString, than: currentVersion) {
                os_log(.info, log: Self.logger, "Update available: %{public}@", latestVersionString)
                showUpdateAvailable(version: latestVersionString)
            } else {
                os_log(.info, log: Self.logger, "App is up to date (current: %{public}@, latest: %{public}@)", currentVersion, latestVersionString)
                showUpToDate()
            }

        } catch {
            os_log(.error, log: Self.logger, "Failed to parse update response: %{public}@", error.localizedDescription)
            #if DEBUG
            print("[AboutViewController] JSON parsing error: \(error)")
            #endif
            showError()
        }
    }

    private func isNewerVersion(_ version1: String, than version2: String) -> Bool {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }

        // Pad arrays to same length with zeros
        let maxLength = max(v1Components.count, v2Components.count)
        let v1 = v1Components + Array(repeating: 0, count: maxLength - v1Components.count)
        let v2 = v2Components + Array(repeating: 0, count: maxLength - v2Components.count)

        // Compare component by component
        for i in 0..<maxLength {
            if v1[i] > v2[i] {
                return true
            } else if v1[i] < v2[i] {
                return false
            }
        }

        return false // versions are equal
    }

    private func showUpToDate() {
        updateSpinner.isHidden = true
        updateStatusLabel.stringValue = "✓ You're running the latest version"
        updateStatusLabel.textColor = .secondaryLabelColor
        updateStatusLabel.isHidden = false
        updateActionButton.isHidden = true
    }

    private func showUpdateAvailable(version: String) {
        updateSpinner.isHidden = true
        updateStatusLabel.stringValue = "Version \(version) is available"
        updateStatusLabel.textColor = .controlAccentColor
        updateStatusLabel.isHidden = false

        updateActionButton.title = "Download Update"
        updateActionButton.isHidden = false
    }

    private func showError() {
        updateSpinner.isHidden = true
        updateStatusLabel.stringValue = "Unable to check for updates"
        updateStatusLabel.textColor = .secondaryLabelColor
        updateStatusLabel.isHidden = false

        updateActionButton.title = "Try Again"
        updateActionButton.isHidden = false
    }

    @objc private func updateActionClicked() {
        if updateActionButton.title == "Try Again" {
            // Retry update check
            checkForUpdates()
        } else {
            // Open download page
            if let urlString = downloadURL, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
