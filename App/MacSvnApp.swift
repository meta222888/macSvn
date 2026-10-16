import SwiftUI
import UserNotifications

@main
struct MacSvnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            SettingsView()
                .environmentObject(AppModel.shared)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // Migrate legacy settings and mirror them into App Group + extension container.
        let settings = AppSettings.load()
        try? settings.save()
        Task { @MainActor in
            AppModel.shared.settings = settings
            AppModel.shared.refreshSVNPath()
        }
        consumeLaunchArguments(CommandLine.arguments)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { @MainActor in
                AppModel.shared.handleIncomingURL(url)
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

    private func consumeLaunchArguments(_ arguments: [String]) {
        // Support: -MacSvnAction update|commit -MacSvnPath <path> ...
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
            index += 1
        }
        guard let action, !paths.isEmpty else { return }
        Task { @MainActor in
            AppModel.shared.handleAction(action, paths: paths)
        }
    }
}
