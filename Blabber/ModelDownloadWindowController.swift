import Cocoa
import os.log

class ModelDownloadWindowController: NSWindowController {

    private static let logger = OSLog(subsystem: "com.blabber.app", category: "models")

    // Callback when models are downloaded
    var onModelsChanged: (() -> Void)?

    private var modelManager = ModelManager.shared
    private var tableView: NSTableView!
    private var progressBar: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var closeButton: NSButton!
    private var currentlyDownloading: WhisperModel?

    // Model list
    private var displayedModels: [WhisperModel] = []
    // Track which models have updates available
    private var modelsWithUpdates: Set<String> = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Download Whisper Models"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        setupUI()
        loadModels()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Title Label
        let titleLabel = NSTextField(labelWithString: "Available Whisper Models")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.frame = NSRect(x: 20, y: 400, width: 840, height: 25)
        contentView.addSubview(titleLabel)

        // Table View with Scroll View - extend to right edge
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 120, width: 840, height: 270))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .bezelBorder

        tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = NSTableHeaderView()
        tableView.autoresizingMask = [.width, .height]

        // Columns - adjusted to show full buttons
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Model"
        nameColumn.width = 270

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "Size"
        sizeColumn.width = 100

        let statusColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusColumn.title = "Status"
        statusColumn.width = 140

        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionColumn.title = "Action"
        actionColumn.width = 300

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(sizeColumn)
        tableView.addTableColumn(statusColumn)
        tableView.addTableColumn(actionColumn)

        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        // Progress Bar
        progressBar = NSProgressIndicator(frame: NSRect(x: 20, y: 85, width: 840, height: 20))
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.isHidden = true
        progressBar.minValue = 0
        progressBar.maxValue = 100
        contentView.addSubview(progressBar)

        // Status Label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.frame = NSRect(x: 20, y: 50, width: 840, height: 25)
        contentView.addSubview(statusLabel)

        // Close Button
        closeButton = NSButton(frame: NSRect(x: 770, y: 15, width: 90, height: 32))
        closeButton.title = "Close"
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        contentView.addSubview(closeButton)
    }

    private func loadModels() {
        displayedModels = modelManager.availableModels
        tableView.reloadData()

        // Check for updates for installed models
        checkForUpdates()
    }

    private func checkForUpdates() {
        for model in displayedModels where modelManager.isModelDownloaded(model) {
            modelManager.checkForUpdate(model) { [weak self] hasUpdate in
                if hasUpdate {
                    self?.modelsWithUpdates.insert(model.fileName)
                    self?.tableView.reloadData()
                }
            }
        }
    }

    @objc private func closeClicked() {
        // If this window is a sheet, end the sheet properly
        if let window = window, let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        } else {
            // Otherwise just close normally
            window?.close()
        }
    }

    @objc private func downloadButtonClicked(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0 && row < displayedModels.count else { return }

        let model = displayedModels[row]

        // Check if already downloaded
        if modelManager.isModelDownloaded(model) {
            let alert = NSAlert()
            alert.messageText = "Already Downloaded"
            alert.informativeText = "\(model.name) is already downloaded."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Prevent downloading multiple models simultaneously
        guard currentlyDownloading == nil else {
            let alert = NSAlert()
            alert.messageText = "Download in Progress"
            alert.informativeText = "Please wait for the current download to complete."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        currentlyDownloading = model

        // Update UI
        progressBar.isHidden = false
        progressBar.doubleValue = 0
        statusLabel.stringValue = "Downloading \(model.name)..."
        closeButton.isEnabled = false

        // Disable download buttons
        tableView.reloadData()

        os_log(.info, log: Self.logger, "Starting download of %{public}s", model.name)

        // Start download
        modelManager.downloadModel(model, progressHandler: { [weak self] progress, downloaded, total in
            DispatchQueue.main.async {
                self?.progressBar.doubleValue = progress * 100

                let downloadedMB = Double(downloaded) / 1024 / 1024
                let totalMB = Double(total) / 1024 / 1024
                self?.statusLabel.stringValue = String(format: "Downloading \(model.name)... %.1f / %.1f MB (%.0f%%)", downloadedMB, totalMB, progress * 100)
            }
        }, completion: { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.currentlyDownloading = nil
                self.closeButton.isEnabled = true

                switch result {
                case .success(let path):
                    os_log(.info, log: Self.logger, "Download complete: %{public}s", path.path)
                    self.statusLabel.stringValue = "✓ \(model.name) downloaded successfully!"
                    self.progressBar.isHidden = true

                    // Clear update flag for this model
                    self.modelsWithUpdates.remove(model.fileName)

                    // Reload table to update status
                    self.tableView.reloadData()

                    // Notify parent that models changed
                    self.onModelsChanged?()

                    // Show success alert
                    let alert = NSAlert()
                    alert.messageText = "Download Complete"
                    alert.informativeText = "\(model.name) has been downloaded and is ready to use."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()

                case .failure(let error):
                    os_log(.error, log: Self.logger, "Download failed: %{public}s", error.localizedDescription)
                    self.statusLabel.stringValue = "❌ Download failed: \(error.localizedDescription)"
                    self.progressBar.isHidden = true

                    // Reload table
                    self.tableView.reloadData()

                    // Show error alert
                    let alert = NSAlert()
                    alert.messageText = "Download Failed"
                    alert.informativeText = "Failed to download \(model.name): \(error.localizedDescription)"
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        })
    }

    @objc private func deleteButtonClicked(_ sender: NSButton) {
        // Find which row this button is in by traversing up the view hierarchy
        var view: NSView? = sender
        while view != nil && view!.superview != tableView {
            view = view?.superview
        }

        guard let rowView = view,
              let row = tableView.row(for: rowView) as Int?,
              row >= 0 && row < displayedModels.count else { return }

        let model = displayedModels[row]

        // Check if this is the last installed model
        let installedModels = modelManager.getInstalledModels()
        if installedModels.count == 1 {
            let alert = NSAlert()
            alert.messageText = "Cannot Delete Last Model"
            alert.informativeText = "Blabber requires at least one model to function. Please download another model before deleting this one."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Confirm deletion
        let alert = NSAlert()
        alert.messageText = "Delete Model?"
        alert.informativeText = "Are you sure you want to delete \(model.name)? This will free up approximately \(model.sizeInMB) MB of disk space."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Check if this model is currently selected
            let modelPath = modelManager.modelPath(for: model).path
            let currentPath = SettingsManager.shared.whisperModelPath
            let isDeletingCurrentModel = (modelPath == currentPath)

            if modelManager.deleteModel(model) {
                os_log(.info, log: Self.logger, "Model deleted: %{public}s", model.name)

                // If we deleted the currently selected model, auto-select the first available model
                if isDeletingCurrentModel {
                    let remainingModels = modelManager.getInstalledModels()
                    if let firstModel = remainingModels.first {
                        let newPath = modelManager.modelPath(for: firstModel).path
                        SettingsManager.shared.whisperModelPath = newPath
                        os_log(.info, log: Self.logger, "Auto-selected new model: %{public}s", firstModel.name)
                    }
                }

                // Reload table to update UI
                tableView.reloadData()

                // Notify parent that models changed
                onModelsChanged?()

                // Show success message
                statusLabel.stringValue = "✓ \(model.name) deleted successfully"
                statusLabel.textColor = .systemGreen

                // Clear message after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    self?.statusLabel.stringValue = ""
                }
            } else {
                // Show error
                statusLabel.stringValue = "❌ Failed to delete model"
                statusLabel.textColor = .systemRed
            }
        }
    }
}

// MARK: - NSTableViewDataSource

extension ModelDownloadWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return displayedModels.count
    }
}

// MARK: - NSTableViewDelegate

extension ModelDownloadWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < displayedModels.count else { return nil }

        let model = displayedModels[row]
        let isDownloaded = modelManager.isModelDownloaded(model)

        let identifier = tableColumn?.identifier

        if identifier == NSUserInterfaceItemIdentifier("name") {
            let cellView = NSTextField()
            cellView.stringValue = model.name
            if model.recommended {
                cellView.stringValue += " ⭐"
            }
            cellView.font = model.recommended ? NSFont.boldSystemFont(ofSize: 11) : NSFont.systemFont(ofSize: 11)
            cellView.isBordered = false
            cellView.isEditable = false
            cellView.drawsBackground = false
            cellView.alignment = .left
            cellView.lineBreakMode = .byTruncatingTail
            return cellView
        } else if identifier == NSUserInterfaceItemIdentifier("size") {
            let cellView = NSTextField()
            cellView.stringValue = "\(model.sizeInMB) MB"
            cellView.font = NSFont.systemFont(ofSize: 11)
            cellView.isBordered = false
            cellView.isEditable = false
            cellView.drawsBackground = false
            cellView.alignment = .left
            cellView.lineBreakMode = .byTruncatingTail
            return cellView
        } else if identifier == NSUserInterfaceItemIdentifier("status") {
            let hasUpdate = modelsWithUpdates.contains(model.fileName)
            let status: String
            let color: NSColor

            if hasUpdate {
                status = "⚠️ Update available"
                color = .systemOrange
            } else if isDownloaded {
                status = "✓ Downloaded"
                color = .systemGreen
            } else {
                status = "Not downloaded"
                color = .secondaryLabelColor
            }

            let cellView = NSTextField()
            cellView.stringValue = status
            cellView.font = NSFont.systemFont(ofSize: 11)
            cellView.textColor = color
            cellView.isBordered = false
            cellView.isEditable = false
            cellView.drawsBackground = false
            cellView.alignment = .left
            cellView.lineBreakMode = .byTruncatingTail
            return cellView
        } else if identifier == NSUserInterfaceItemIdentifier("action") {
            // Create a container view to hold both buttons
            let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 24))

            // Download button
            let hasUpdate = modelsWithUpdates.contains(model.fileName)
            let downloadButton = NSButton(frame: NSRect(x: 0, y: 2, width: 130, height: 20))
            downloadButton.title = isDownloaded ? "Re-download" : "Download"
            downloadButton.bezelStyle = .rounded
            downloadButton.isEnabled = (currentlyDownloading == nil)
            downloadButton.target = self
            downloadButton.action = #selector(downloadButtonClicked(_:))

            // Highlight button if update is available
            if hasUpdate {
                downloadButton.contentTintColor = .systemOrange
            }

            containerView.addSubview(downloadButton)

            // Delete button (only show if downloaded)
            if isDownloaded {
                let deleteButton = NSButton(frame: NSRect(x: 140, y: 2, width: 100, height: 20))
                deleteButton.title = "Delete"
                deleteButton.bezelStyle = .rounded
                deleteButton.isEnabled = true
                deleteButton.target = self
                deleteButton.action = #selector(deleteButtonClicked(_:))
                containerView.addSubview(deleteButton)
            }

            return containerView
        }

        return nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 24
    }
}
