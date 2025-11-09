import Cocoa

class WorkflowsWindowController: NSWindowController {

    private var workflowManager = WorkflowManager.shared
    private var cloudManager = CloudModelManager.shared
    private var tableView: NSTableView!
    private var statusLabel: NSTextField!
    private var closeButton: NSButton!
    private var addButton: NSButton!
    private var removeButton: NSButton!
    private var configButton: NSButton!

    // Workflow list
    private var displayedWorkflows: [Workflow] = []

    // Keep reference to child window controllers
    private var editWindowController: WorkflowEditWindowController?
    private var llmServicesWindowController: LLMServicesWindowController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Workflows"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        setupUI()
        loadWorkflows()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Title Label
        let titleLabel = NSTextField(labelWithString: "Post-Transcription Workflows")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.frame = NSRect(x: 20, y: 400, width: 840, height: 25)
        contentView.addSubview(titleLabel)

        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "Process your transcriptions with custom LLM prompts")
        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 20, y: 375, width: 840, height: 15)
        contentView.addSubview(subtitleLabel)

        // Table View with Scroll View
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 165, width: 840, height: 200))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .bezelBorder

        tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = NSTableHeaderView()
        tableView.autoresizingMask = [.width, .height]

        // Columns (removed Action column)
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.width = 200

        let descColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("description"))
        descColumn.title = "Description"
        descColumn.width = 420

        let serviceColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("service"))
        serviceColumn.title = "LLM Service"
        serviceColumn.width = 190

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(descColumn)
        tableView.addTableColumn(serviceColumn)

        tableView.dataSource = self
        tableView.delegate = self

        // Enable drag-and-drop reordering
        let dragType = NSPasteboard.PasteboardType("com.blabber.workflow.row")
        tableView.registerForDraggedTypes([dragType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        // macOS-style control buttons (bottom left, below table with spacing)
        // Add button (+)
        addButton = NSButton(frame: NSRect(x: 20, y: 133, width: 24, height: 24))
        addButton.bezelStyle = .smallSquare
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
        addButton.target = self
        addButton.action = #selector(addWorkflowClicked)
        addButton.toolTip = "Add workflow"
        contentView.addSubview(addButton)

        // Remove button (-)
        removeButton = NSButton(frame: NSRect(x: 44, y: 133, width: 24, height: 24))
        removeButton.bezelStyle = .smallSquare
        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")
        removeButton.target = self
        removeButton.action = #selector(removeWorkflowClicked)
        removeButton.toolTip = "Remove selected workflow"
        removeButton.isEnabled = false
        contentView.addSubview(removeButton)

        // Config button (gear)
        configButton = NSButton(frame: NSRect(x: 68, y: 133, width: 24, height: 24))
        configButton.bezelStyle = .smallSquare
        configButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Configure")
        configButton.target = self
        configButton.action = #selector(configWorkflowClicked)
        configButton.toolTip = "Configure selected workflow"
        configButton.isEnabled = false
        contentView.addSubview(configButton)

        // Configure LLM Services Button
        let configureServicesButton = NSButton(frame: NSRect(x: 20, y: 90, width: 200, height: 32))
        configureServicesButton.title = "Configure LLM Services..."
        configureServicesButton.bezelStyle = .rounded
        configureServicesButton.target = self
        configureServicesButton.action = #selector(configureServicesClicked)
        contentView.addSubview(configureServicesButton)

        // Help Text
        let helpLabel = NSTextField(labelWithString: "Configure API keys for OpenAI, Anthropic, and other LLM providers")
        helpLabel.font = NSFont.systemFont(ofSize: 10)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.frame = NSRect(x: 230, y: 98, width: 610, height: 18)
        contentView.addSubview(helpLabel)

        // Status Label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.frame = NSRect(x: 20, y: 55, width: 840, height: 25)
        contentView.addSubview(statusLabel)

        // Close Button
        closeButton = NSButton(frame: NSRect(x: 770, y: 15, width: 90, height: 32))
        closeButton.title = "Close"
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        contentView.addSubview(closeButton)
    }

    private func loadWorkflows() {
        displayedWorkflows = workflowManager.getWorkflows()
        tableView?.reloadData()
        updateButtonStates()
    }

    private func updateButtonStates() {
        let hasSelection = tableView.selectedRow >= 0
        removeButton.isEnabled = hasSelection
        configButton.isEnabled = hasSelection
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

    @objc private func addWorkflowClicked() {
        // Create a new workflow with default values
        let newWorkflow = Workflow(name: "New Workflow", description: "", prompt: "", serviceId: nil, isEnabled: true)

        // Open edit window
        openEditWindow(for: newWorkflow, isNew: true)
    }

    @objc private func configWorkflowClicked() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 && selectedRow < displayedWorkflows.count else { return }

        let workflow = displayedWorkflows[selectedRow]
        openEditWindow(for: workflow, isNew: false)
    }

    @objc private func removeWorkflowClicked() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 && selectedRow < displayedWorkflows.count else { return }

        let workflow = displayedWorkflows[selectedRow]

        // Confirm deletion
        let alert = NSAlert()
        alert.messageText = "Delete Workflow?"
        alert.informativeText = "Are you sure you want to delete '\(workflow.name)'? This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            workflowManager.deleteWorkflow(id: workflow.id)
            statusLabel.stringValue = "✓ Workflow '\(workflow.name)' deleted"
            statusLabel.textColor = .systemGreen
            loadWorkflows()

            // Clear message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.statusLabel.stringValue = ""
            }
        }
    }

    @objc private func configureServicesClicked() {
        // Open LLM services window (grouped by provider)
        llmServicesWindowController = LLMServicesWindowController()
        llmServicesWindowController?.onServicesChanged = { [weak self] in
            // Reload workflows table when services are configured
            self?.loadWorkflows()
        }

        if let configWindow = llmServicesWindowController?.window, let parentWindow = window {
            parentWindow.beginSheet(configWindow) { [weak self] _ in
                self?.llmServicesWindowController = nil
            }
        }
    }

    private func openEditWindow(for workflow: Workflow, isNew: Bool) {
        editWindowController = WorkflowEditWindowController(workflow: workflow, isNew: isNew)
        editWindowController?.onSaved = { [weak self] savedWorkflow in
            if isNew {
                self?.workflowManager.addWorkflow(savedWorkflow)
                self?.statusLabel.stringValue = "✓ Workflow '\(savedWorkflow.name)' created"
            } else {
                self?.workflowManager.updateWorkflow(savedWorkflow)
                self?.statusLabel.stringValue = "✓ Workflow '\(savedWorkflow.name)' updated"
            }
            self?.statusLabel.textColor = .systemGreen
            self?.loadWorkflows()

            // Clear message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.statusLabel.stringValue = ""
            }
        }

        if let editWindow = editWindowController?.window, let parentWindow = window {
            parentWindow.beginSheet(editWindow) { [weak self] _ in
                self?.editWindowController = nil
            }
        }
    }
}

// MARK: - NSTableViewDataSource

extension WorkflowsWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return displayedWorkflows.count
    }

    // MARK: - Drag and Drop Support

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        // Return the row index as a string for dragging
        let item = NSPasteboardItem()
        let dragType = NSPasteboard.PasteboardType("com.blabber.workflow.row")
        item.setString(String(row), forType: dragType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        // Only allow drops between rows (not on rows)
        if dropOperation == .above {
            return .move
        }
        return []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        // Get the dragged row index
        let dragType = NSPasteboard.PasteboardType("com.blabber.workflow.row")
        guard let item = info.draggingPasteboard.pasteboardItems?.first,
              let rowString = item.string(forType: dragType),
              let sourceRow = Int(rowString) else {
            return false
        }

        // Calculate destination index
        var destinationRow = row
        if sourceRow < row {
            destinationRow -= 1
        }

        // Perform the reorder
        workflowManager.reorderWorkflows(from: sourceRow, to: destinationRow)

        // Reload the table
        loadWorkflows()

        // Select the moved row
        tableView.selectRowIndexes(IndexSet(integer: destinationRow), byExtendingSelection: false)

        return true
    }
}

// MARK: - NSTableViewDelegate

extension WorkflowsWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < displayedWorkflows.count else { return nil }

        let workflow = displayedWorkflows[row]
        let identifier = tableColumn?.identifier

        // Create or reuse a cell view
        let cellIdentifier = identifier?.rawValue ?? "Cell"
        var cellView = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(cellIdentifier), owner: self) as? NSTableCellView

        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = NSUserInterfaceItemIdentifier(cellIdentifier)

            let textField = NSTextField()
            textField.isBordered = false
            textField.isEditable = false
            textField.drawsBackground = false
            textField.alignment = .left
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false

            cellView?.addSubview(textField)
            cellView?.textField = textField

            // Add constraints
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
            ])
        }

        if identifier == NSUserInterfaceItemIdentifier("name") {
            cellView?.textField?.stringValue = workflow.name
            cellView?.textField?.font = NSFont.boldSystemFont(ofSize: 11)
            cellView?.textField?.textColor = .labelColor
        } else if identifier == NSUserInterfaceItemIdentifier("description") {
            cellView?.textField?.stringValue = workflow.truncatedDescription
            cellView?.textField?.font = NSFont.systemFont(ofSize: 11)
            cellView?.textField?.textColor = .secondaryLabelColor
        } else if identifier == NSUserInterfaceItemIdentifier("service") {
            let serviceName = workflow.serviceDisplayName(manager: cloudManager)
            cellView?.textField?.stringValue = serviceName
            cellView?.textField?.font = NSFont.systemFont(ofSize: 11)
            cellView?.textField?.textColor = serviceName == "Not configured" ? .systemOrange : .labelColor
        }

        return cellView
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 24
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonStates()
    }
}
