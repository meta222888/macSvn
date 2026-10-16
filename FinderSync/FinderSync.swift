import Cocoa
import FinderSync

final class FinderSyncExtension: FIFinderSync {
    private let defaultsObserver: NSObjectProtocol

    override init() {
        defaultsObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(AppConstants.configDidChangeName),
            object: nil,
            queue: .main
        ) { _ in
            FinderSyncExtension.refreshDirectoryURLs()
        }
        super.init()
        FinderSyncExtension.refreshDirectoryURLs()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(defaultsObserver)
    }

    static func refreshDirectoryURLs() {
        let settings = AppSettings.load()
        let urls = Set(settings.workingCopies.map { URL(fileURLWithPath: $0, isDirectory: true) })
        FIFinderSyncController.default().directoryURLs = urls
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer:
            break
        default:
            return nil
        }

        let targets = targetURLs()
        guard !targets.isEmpty else { return nil }

        let settings = AppSettings.load()
        guard !settings.workingCopies.isEmpty else { return nil }

        guard targets.allSatisfy({
            WorkingCopyResolver.registeredRoot(containing: $0.path, in: settings.workingCopies) != nil
        }) else {
            return nil
        }

        let menu = NSMenu(title: "")
        menu.addItem(withTitle: "SVN 更新", action: #selector(updateSelected(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "SVN 提交", action: #selector(commitSelected(_:)), keyEquivalent: "")
        return menu
    }

    @objc private func updateSelected(_ sender: AnyObject?) {
        launchHost(action: .update)
    }

    @objc private func commitSelected(_ sender: AnyObject?) {
        launchHost(action: .commit)
    }

    private func targetURLs() -> [URL] {
        let controller = FIFinderSyncController.default()
        if let selected = controller.selectedItemURLs(), !selected.isEmpty {
            return selected
        }
        if let targeted = controller.targetedURL() {
            return [targeted]
        }
        return []
    }

    private func launchHost(action: PendingActionKind) {
        let paths = targetURLs().map(\.path)
        guard !paths.isEmpty else { return }

        do {
            let id = try PendingAction.store(action: action, paths: paths)
            let url = URL(string: "\(AppConstants.urlScheme)://run?id=\(id)")!
            let conf = NSWorkspace.OpenConfiguration()
            conf.activates = true

            if let host = hostAppURL() {
                NSWorkspace.shared.open([url], withApplicationAt: host, configuration: conf) { _, error in
                    if error != nil {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                NSWorkspace.shared.open(url)
            }
        } catch {
            if let host = hostAppURL() {
                NSWorkspace.shared.openApplication(at: host, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    private func hostAppURL() -> URL? {
        // …/SVN访达菜单.app/Contents/PlugIns/SVNFinderSync.appex
        let appex = Bundle.main.bundleURL
        let appURL = appex
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return appURL.pathExtension == "app" ? appURL : nil
    }
}
