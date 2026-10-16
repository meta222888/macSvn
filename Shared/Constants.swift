import Foundation

enum AppConstants {
    static let appDisplayName = "SVN 访达菜单"
    static let bundleIdentifier = "com.local.svnfindermenu"
    static let extensionBundleIdentifier = "com.local.svnfindermenu.FinderSync"
    static let urlScheme = "svnfindermenu"
    /// ASCII-only folder name so sandboxed Finder Sync temporary exceptions work reliably.
    static let appSupportFolderName = "com.local.svnfindermenu"
    static let legacyAppSupportFolderName = "SVN访达菜单"
    static let settingsFileName = "settings.json"
    static let operationsLogFileName = "operations.log"
    static let pendingFolderName = "pending"
    static let configDidChangeName = "com.local.svnfindermenu.configDidChange"
    static let maxOperationLogEntries = 200

    static let knownSVNCandidates = [
        "/opt/homebrew/bin/svn",
        "/usr/local/bin/svn",
        "/opt/local/bin/svn"
    ]

    /// Real user home (`/Users/...`), not the Finder Sync sandbox container home.
    static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// Host-visible Application Support (always under the real home).
    static var applicationSupportDirectory: URL {
        realHomeDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appSupportFolderName, isDirectory: true)
    }

    /// Extension-visible Application Support via its sandboxed home (`NSHomeDirectory()` inside the appex).
    static var extensionContainerSupportDirectory: URL {
        realHomeDirectory
            .appendingPathComponent(
                "Library/Containers/\(extensionBundleIdentifier)/Data/Library/Application Support/\(appSupportFolderName)",
                isDirectory: true
            )
    }

    /// Paths the host app mirrors settings into so the sandboxed extension can always read them.
    static var settingsMirrorDirectories: [URL] {
        [
            applicationSupportDirectory,
            extensionContainerSupportDirectory
        ]
    }

    static var settingsURL: URL {
        applicationSupportDirectory.appendingPathComponent(settingsFileName)
    }

    static var operationsLogURL: URL {
        applicationSupportDirectory.appendingPathComponent(operationsLogFileName)
    }

    static var pendingDirectory: URL {
        // Prefer the extension container so the sandboxed appex can write pending requests.
        extensionContainerSupportDirectory.appendingPathComponent(pendingFolderName, isDirectory: true)
    }

    static var hostPendingDirectory: URL {
        applicationSupportDirectory.appendingPathComponent(pendingFolderName, isDirectory: true)
    }

    static var legacySettingsURL: URL {
        realHomeDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(legacyAppSupportFolderName, isDirectory: true)
            .appendingPathComponent(settingsFileName)
    }
}
