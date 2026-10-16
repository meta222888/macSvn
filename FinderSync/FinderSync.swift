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
        FinderSyncExtension.writeDebugProbe()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(defaultsObserver)
    }

    /// Watch registered working copies, their parents, and the real home directory.
    static func refreshDirectoryURLs() {
        let settings = AppSettings.load()
        var urls = Set<URL>()
        urls.insert(AppConstants.realHomeDirectory)
        for path in settings.workingCopies {
            let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            urls.insert(root)
            let parent = root.deletingLastPathComponent()
            if parent.path != root.path {
                urls.insert(parent)
            }
        }
        FIFinderSyncController.default().directoryURLs = urls
    }

    private static func writeDebugProbe() {
        let settings = AppSettings.load()
        let lines = [
            "time=\(ISO8601DateFormatter().string(from: Date()))",
            "containerHome=\(NSHomeDirectory())",
            "realHome=\(AppConstants.realHomeDirectory.path)",
            "workingCopies=\(settings.workingCopies.joined(separator: ","))",
            "directoryURLCount=\(FIFinderSyncController.default().directoryURLs?.count ?? -1)"
        ]
        let text = lines.joined(separator: "\n") + "\n"

        let candidates = [
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support/\(AppConstants.appSupportFolderName)/extension-debug.log"),
            AppConstants.applicationSupportDirectory
                .appendingPathComponent("extension-debug.log")
        ]

        for url in candidates {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                continue
            }
        }
        NSLog("SVNFinderSync probe workingCopies=%@ realHome=%@", settings.workingCopies.joined(separator: ","), AppConstants.realHomeDirectory.path)
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
        let appex = Bundle.main.bundleURL
        let appURL = appex
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return appURL.pathExtension == "app" ? appURL : nil
    }
}
