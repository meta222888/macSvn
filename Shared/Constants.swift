import Foundation

enum AppConstants {
    static let appDisplayName = "SVN 访达菜单"
    static let bundleIdentifier = "com.local.svnfindermenu"
    static let urlScheme = "svnfindermenu"
    static let appSupportFolderName = "SVN访达菜单"
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

    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appSupportFolderName, isDirectory: true)
    }

    static var settingsURL: URL {
        applicationSupportDirectory.appendingPathComponent(settingsFileName)
    }

    static var operationsLogURL: URL {
        applicationSupportDirectory.appendingPathComponent(operationsLogFileName)
    }

    static var pendingDirectory: URL {
        applicationSupportDirectory.appendingPathComponent(pendingFolderName, isDirectory: true)
    }
}
