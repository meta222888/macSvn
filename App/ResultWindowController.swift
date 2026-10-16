import AppKit

final class ResultWindowController: NSWindowController, NSWindowDelegate {
    private let titleLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let closeButton = NSButton(title: "关闭", target: nil, action: nil)
    private var onCancel: (() -> Void)?
    var onActivate: (() -> Void)?

    var bodyText: String {
        textView.string
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppConstants.appDisplayName
        window.minSize = NSSize(width: 480, height: 280)
        self.init(window: window)
        window.delegate = self
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.lineBreakMode = .byTruncatingTail

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width, .height]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView

        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.keyEquivalent = "."
        cancelButton.keyEquivalentModifierMask = .command

        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.keyEquivalent = "\r"

        let buttonStack = NSStackView(views: [cancelButton, closeButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 12
        buttonStack.alignment = .centerY

        let root = NSStackView(views: [titleLabel, scroll, buttonStack])
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
    }

    func present(title: String, body: String, showCancel: Bool, onCancel: (() -> Void)?) {
        self.onCancel = onCancel
        titleLabel.stringValue = title
        textView.string = body
        cancelButton.isHidden = !showCancel
        cancelButton.isEnabled = showCancel
        window?.title = title
        bringToFront()
    }

    func append(_ chunk: String) {
        textView.string += chunk
        textView.scrollToEndOfDocument(nil)
    }

    func replaceBody(_ body: String) {
        textView.string = body
    }

    func finish(title: String) {
        titleLabel.stringValue = title
        window?.title = title
        cancelButton.isHidden = true
        cancelButton.isEnabled = false
        onCancel = nil
        bringToFront()
    }

    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func closeWindow() {
        window?.orderOut(nil)
    }

    @objc private func cancelClicked() {
        onCancel?()
    }

    @objc private func closeClicked() {
        // Closing hides the window; running commands continue per requirements.
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window?.orderOut(nil)
        return false
    }
}
