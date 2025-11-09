import Cocoa

// Structure to hold find-replace pairs
struct FindReplacePair {
    var find: String
    var replace: String
    var caseSensitive: Bool

    var isEmpty: Bool {
        return find.isEmpty && replace.isEmpty
    }
}

class FindReplaceWindowController: NSWindowController {

    private var settingsManager = SettingsManager.shared
    private var tableView: NSTableView!
    private var saveButton: NSButton!

    // Data model
    private var pairs: [FindReplacePair] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Find & Replace"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        setupUI()
        loadData()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Title Label
        let titleLabel = NSTextField(labelWithString: "Transcription Corrections")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.frame = NSRect(x: 20, y: 400, width: 840, height: 25)
        contentView.addSubview(titleLabel)

        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "Automatically fix common transcription errors")
        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 20, y: 375, width: 840, height: 15)
        contentView.addSubview(subtitleLabel)

        // Table View with Scroll View
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 80, width: 840, height: 285))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .bezelBorder

        tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = NSTableHeaderView()
        tableView.autoresizingMask = [.width, .height]
        tableView.allowsEmptySelection = true
        tableView.allowsColumnResizing = false

        // Column 1: Find
        let findColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("find"))
        findColumn.title = "Find"
        findColumn.width = 300

        // Column 2: Replace
        let replaceColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("replace"))
        replaceColumn.title = "Replace"
        replaceColumn.width = 300

        // Column 3: Case Sensitive
        let caseColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("caseSensitive"))
        caseColumn.title = "Case Sensitive"
        caseColumn.width = 110

        // Column 4: Delete
        let deleteColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("delete"))
        deleteColumn.title = ""
        deleteColumn.width = 60

        tableView.addTableColumn(findColumn)
        tableView.addTableColumn(replaceColumn)
        tableView.addTableColumn(caseColumn)
        tableView.addTableColumn(deleteColumn)

        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        // Help Text
        let helpLabel = NSTextField(labelWithString: "Changes apply automatically after transcription. Start typing in a blank row to add a new entry.\nLeaving the Replace field blank will remove the found text.")
        helpLabel.font = NSFont.systemFont(ofSize: 10)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.frame = NSRect(x: 20, y: 38, width: 840, height: 28)
        helpLabel.maximumNumberOfLines = 2
        helpLabel.lineBreakMode = .byWordWrapping
        contentView.addSubview(helpLabel)

        // Save and Close Button
        saveButton = NSButton(frame: NSRect(x: 720, y: 15, width: 140, height: 32))
        saveButton.title = "Save and Close"
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"  // Make it the default button (Enter key)
        saveButton.target = self
        saveButton.action = #selector(saveAndCloseClicked)
        contentView.addSubview(saveButton)
    }

    private func loadData() {
        // Load find-replace pairs from settings
        pairs = settingsManager.findReplacePairs.map { FindReplacePair(find: $0.find, replace: $0.replace, caseSensitive: $0.caseSensitive) }

        let hadExistingEntries = !pairs.isEmpty

        // Always ensure there's at least one empty row at the end
        if pairs.isEmpty || !pairs.last!.isEmpty {
            pairs.append(FindReplacePair(find: "", replace: "", caseSensitive: false))
        }

        tableView?.reloadData()

        // Focus on the empty row (last row if there were existing entries, first row otherwise)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let rowToEdit = hadExistingEntries ? self.pairs.count - 1 : 0
            self.tableView.editColumn(0, row: rowToEdit, with: nil, select: true)
        }
    }

    private func ensureEmptyRowExists() {
        // Check if last row is empty
        if pairs.isEmpty || !pairs.last!.isEmpty {
            let newRowIndex = pairs.count
            pairs.append(FindReplacePair(find: "", replace: "", caseSensitive: false))

            // Insert the new row without disrupting the current editing session
            tableView.insertRows(at: IndexSet(integer: newRowIndex), withAnimation: .effectFade)

            // Auto-scroll to make the newly added row visible
            tableView.scrollRowToVisible(newRowIndex)
        }
    }

    @objc private func saveAndCloseClicked() {
        // Filter out empty rows before saving
        let validPairs = pairs.filter { !$0.isEmpty }

        // Save to settings
        settingsManager.findReplacePairs = validPairs.map { (find: $0.find, replace: $0.replace, caseSensitive: $0.caseSensitive) }

        // Close the window
        if let window = window, let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        } else {
            window?.close()
        }
    }

    @objc private func deleteButtonClicked(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0 && row < pairs.count else { return }

        pairs.remove(at: row)
        tableView.removeRows(at: IndexSet(integer: row), withAnimation: .effectFade)

        // Ensure there's always at least one empty row
        ensureEmptyRowExists()
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0 && row < pairs.count else { return }

        pairs[row].caseSensitive = (sender.state == .on)
    }
}

// MARK: - NSTableViewDataSource

extension FindReplaceWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return pairs.count
    }
}

// MARK: - NSTableViewDelegate

extension FindReplaceWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < pairs.count else { return nil }

        let pair = pairs[row]
        let identifier = tableColumn?.identifier

        if identifier == NSUserInterfaceItemIdentifier("find") || identifier == NSUserInterfaceItemIdentifier("replace") {
            // Text field for Find and Replace columns
            let cellIdentifier = identifier?.rawValue ?? "Cell"
            var cellView = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(cellIdentifier), owner: self) as? NSTableCellView

            if cellView == nil {
                cellView = NSTableCellView()
                cellView?.identifier = NSUserInterfaceItemIdentifier(cellIdentifier)

                let textField = NSTextField()
                textField.isBordered = false
                textField.isEditable = true
                textField.drawsBackground = false
                textField.alignment = .left
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.delegate = self
                textField.tag = row  // Store row in tag

                cellView?.addSubview(textField)
                cellView?.textField = textField

                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                ])
            }

            if identifier == NSUserInterfaceItemIdentifier("find") {
                cellView?.textField?.stringValue = pair.find
                cellView?.textField?.placeholderString = "Search text..."
            } else {
                cellView?.textField?.stringValue = pair.replace
                cellView?.textField?.placeholderString = "Replace with..."
            }

            return cellView

        } else if identifier == NSUserInterfaceItemIdentifier("caseSensitive") {
            // Checkbox for Case Sensitive column
            let cellIdentifier = "CaseCheckbox"
            var cellView = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(cellIdentifier), owner: self) as? NSTableCellView

            if cellView == nil {
                cellView = NSTableCellView()
                cellView?.identifier = NSUserInterfaceItemIdentifier(cellIdentifier)

                let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkboxChanged(_:)))
                checkbox.translatesAutoresizingMaskIntoConstraints = false

                cellView?.addSubview(checkbox)

                NSLayoutConstraint.activate([
                    checkbox.centerXAnchor.constraint(equalTo: cellView!.centerXAnchor),
                    checkbox.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                ])
            }

            if let checkbox = cellView?.subviews.first as? NSButton {
                checkbox.state = pair.caseSensitive ? .on : .off
            }

            return cellView

        } else if identifier == NSUserInterfaceItemIdentifier("delete") {
            // Delete button column
            let cellIdentifier = "DeleteButton"
            var cellView = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(cellIdentifier), owner: self) as? NSTableCellView

            if cellView == nil {
                cellView = NSTableCellView()
                cellView?.identifier = NSUserInterfaceItemIdentifier(cellIdentifier)

                let deleteButton = NSButton()
                deleteButton.bezelStyle = .roundRect
                deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
                deleteButton.imagePosition = .imageOnly
                deleteButton.isBordered = false
                deleteButton.target = self
                deleteButton.action = #selector(deleteButtonClicked(_:))
                deleteButton.translatesAutoresizingMaskIntoConstraints = false

                cellView?.addSubview(deleteButton)

                NSLayoutConstraint.activate([
                    deleteButton.centerXAnchor.constraint(equalTo: cellView!.centerXAnchor),
                    deleteButton.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                    deleteButton.widthAnchor.constraint(equalToConstant: 20),
                    deleteButton.heightAnchor.constraint(equalToConstant: 20)
                ])
            }

            return cellView
        }

        return nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 28
    }
}

// MARK: - NSTextFieldDelegate

extension FindReplaceWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }

        // Find the row this text field belongs to
        let row = tableView.row(for: textField)
        guard row >= 0 && row < pairs.count else { return }

        // Find which column (find or replace)
        let column = tableView.column(for: textField)
        guard column >= 0 else { return }

        let columnIdentifier = tableView.tableColumns[column].identifier

        if columnIdentifier == NSUserInterfaceItemIdentifier("find") {
            pairs[row].find = textField.stringValue
        } else if columnIdentifier == NSUserInterfaceItemIdentifier("replace") {
            pairs[row].replace = textField.stringValue
        }

        // If editing the last row and it's no longer empty, add a new empty row
        if row == pairs.count - 1 && !pairs[row].isEmpty {
            ensureEmptyRowExists()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            // Tab key pressed - move to next field
            let row = tableView.row(for: control)
            let column = tableView.column(for: control)

            if column == 0 {
                // From Find to Replace
                tableView.editColumn(1, row: row, with: nil, select: true)
                return true
            } else if column == 1 {
                // From Replace to next row's Find
                let nextRow = row + 1
                if nextRow < pairs.count {
                    tableView.editColumn(0, row: nextRow, with: nil, select: true)
                    return true
                }
            }
        }

        return false
    }
}
