import AppKit

final class CommitWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    private var items: [SVNStatusItem] = []
    private var onSubmit: ((String, [String]) -> Void)?

    private let hintLabel = NSTextField(wrappingLabelWithString: "将提交勾选的改动。未纳入版本控制的文件不会提交。")
    private let emptyLabel = NSTextField(labelWithString: "没有可提交的改动")
    private let tableView = NSTableView()
    private let messageView = NSTextView()
    private let commitButton = NSButton(title: "提交", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "提交到 SVN"
        window.minSize = NSSize(width: 560, height: 400)
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = NSTableHeaderView()
        let checkColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        checkColumn.title = ""
        checkColumn.width = 36
        let statusColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusColumn.title = "状态"
        statusColumn.width = 140
        let pathColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        pathColumn.title = "路径"
        pathColumn.width = 480
        tableView.addTableColumn(checkColumn)
        tableView.addTableColumn(statusColumn)
        tableView.addTableColumn(pathColumn)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = true
        scroll.documentView = tableView

        let messageLabel = NSTextField(labelWithString: "提交说明（必填）")
        let messageScroll = NSScrollView()
        messageScroll.hasVerticalScroller = true
        messageScroll.borderType = .bezelBorder
        messageScroll.translatesAutoresizingMaskIntoConstraints = false
        messageView.isRichText = false
        messageView.font = NSFont.systemFont(ofSize: 13)
        messageView.delegate = self
        messageView.textContainerInset = NSSize(width: 6, height: 6)
        messageScroll.documentView = messageView

        commitButton.target = self
        commitButton.action = #selector(commitClicked)
        commitButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [cancelButton, commitButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        let root = NSStackView(views: [hintLabel, emptyLabel, scroll, messageLabel, messageScroll, buttons])
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            messageScroll.heightAnchor.constraint(equalToConstant: 120)
        ])
        updateCommitEnabled()
    }

    func present(items: [SVNStatusItem], onSubmit: @escaping (String, [String]) -> Void) {
        self.items = items
        self.onSubmit = onSubmit
        messageView.string = ""
        let hasCommittable = items.contains { $0.isCommitSelectable }
        emptyLabel.isHidden = hasCommittable
        tableView.reloadData()
        updateCommitEnabled()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        let item = items[row]
        switch tableColumn.identifier.rawValue {
        case "check":
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkToggled(_:)))
            button.state = item.isSelected ? .on : .off
            button.isEnabled = item.isCommitSelectable
            button.tag = row
            return button
        case "status":
            let text = NSTextField(labelWithString: "\(item.displayName) (\(item.item))")
            text.lineBreakMode = .byTruncatingTail
            return text
        case "path":
            let text = NSTextField(labelWithString: item.path)
            text.lineBreakMode = .byTruncatingMiddle
            text.toolTip = item.path
            return text
        default:
            return nil
        }
    }

    func textDidChange(_ notification: Notification) {
        updateCommitEnabled()
    }

    @objc private func checkToggled(_ sender: NSButton) {
        let row = sender.tag
        guard items.indices.contains(row), items[row].isCommitSelectable else { return }
        items[row].isSelected = sender.state == .on
        updateCommitEnabled()
    }

    private func updateCommitEnabled() {
        let messageOK = !messageView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let selected = items.contains { $0.isCommitSelectable && $0.isSelected }
        commitButton.isEnabled = messageOK && selected
    }

    @objc private func commitClicked() {
        let message = messageView.string
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let selectedPaths = items.filter { $0.isCommitSelectable && $0.isSelected }.map(\.path)
        guard !selectedPaths.isEmpty else { return }
        window?.orderOut(nil)
        onSubmit?(message, selectedPaths)
        onSubmit = nil
    }

    @objc private func cancelClicked() {
        window?.orderOut(nil)
        onSubmit = nil
    }
}
