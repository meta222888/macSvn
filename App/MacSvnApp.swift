import SwiftUI
import UserNotifications

@main
struct MacSvnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Preferences-style scene: does not open a window on every launch.
        Settings {
            SettingsView()
                .environmentObject(AppModel.shared)
                .frame(minWidth: 620, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("设置…") {
                    AppDelegate.shared?.showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static private(set) weak var shared: AppDelegate?

    /// Set when launched/activated for a Finder action so we don't flash the settings window.
    private var launchedForAction = false
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        UNUserNotificationCenter.current().delegate = self
        NSApp.setActivationPolicy(.regular)

        let settings = AppSettings.load()
        try? settings.save()
        Task { @MainActor in
            AppModel.shared.settings = settings
            AppModel.shared.refreshSVNPath()
        }

        if consumeLaunchArguments(CommandLine.arguments) {
            launchedForAction = true
        }

        // URLs arrive via application(_:open:) shortly after launch; wait before showing settings.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.launchedForAction else { return }
            self.showSettingsWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running after result/commit windows close so Finder can invoke us again quickly.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock / app switcher click: show settings.
        showSettingsWindow()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        launchedForAction = true
        hideSettingsWindow()
        for url in urls {
            Task { @MainActor in
                AppModel.shared.handleIncomingURL(url)
            }
        }
    }

    func noteFinderActionStarting() {
        launchedForAction = true
        hideSettingsWindow()
    }

    func showSettingsWindow() {
        if settingsWindow == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environmentObject(AppModel.shared)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = AppConstants.appDisplayName
            window.identifier = NSUserInterfaceItemIdentifier("svnfindermenu.settings")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 660, height: 600))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func hideSettingsWindow() {
        settingsWindow?.orderOut(nil)
        // Also dismiss SwiftUI Settings scene windows if any were opened via the menu.
        for window in NSApp.windows {
            if window.identifier?.rawValue == "svnfindermenu.settings" {
                window.orderOut(nil)
            }
            // SwiftUI Settings windows often use this class name / title.
            let className = String(describing: type(of: window))
            if className.contains("Settings") || className.contains("Preferences") {
                window.orderOut(nil)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            AppModel.shared.revealResultWindow()
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    @discardableResult
    private func consumeLaunchArguments(_ arguments: [String]) -> Bool {
        var action: PendingActionKind?
        var paths: [String] = []
        var index = 1
        while index < arguments.count {
            let arg = arguments[index]
            if arg == "-MacSvnAction", index + 1 < arguments.count {
                action = PendingActionKind(rawValue: arguments[index + 1])
                index += 2
                continue
            }
            if arg == "-MacSvnPath", index + 1 < arguments.count {
                paths.append(arguments[index + 1])
                index += 2
                continue
            }
            if arg.hasPrefix("-MacSvnAction=") {
                action = PendingActionKind(rawValue: String(arg.dropFirst("-MacSvnAction=".count)))
                index += 1
                continue
            }
            if arg.hasPrefix("\(AppConstants.urlScheme):") {
                launchedForAction = true
                if let url = URL(string: arg) {
                    Task { @MainActor in
                        AppModel.shared.handleIncomingURL(url)
                    }
                }
                return true
            }
            index += 1
        }
        guard let action, !paths.isEmpty else { return false }
        Task { @MainActor in
            AppModel.shared.handleAction(action, paths: paths)
        }
        return true
    }
}
