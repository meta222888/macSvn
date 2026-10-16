import Foundation

struct AppSettings: Codable, Equatable {
    var svnBinary: String
    var workingCopies: [String]

    static let empty = AppSettings(svnBinary: "", workingCopies: [])

    static func load() -> AppSettings {
        for url in candidateSettingsURLs() {
            if let settings = read(from: url) {
                return settings
            }
        }
        return .empty
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)

        var lastError: Error?
        var wrote = false
        for dir in AppConstants.settingsMirrorDirectories {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: dir.appendingPathComponent(AppConstants.settingsFileName), options: .atomic)
                wrote = true
            } catch {
                lastError = error
            }
        }
        if !wrote, let lastError {
            throw lastError
        }

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(AppConstants.configDidChangeName),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private static func candidateSettingsURLs() -> [URL] {
        var urls: [URL] = [
            // Inside the appex sandbox this resolves to the container copy.
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support/\(AppConstants.appSupportFolderName)/\(AppConstants.settingsFileName)"),
            AppConstants.extensionContainerSupportDirectory
                .appendingPathComponent(AppConstants.settingsFileName),
            AppConstants.settingsURL,
            AppConstants.legacySettingsURL
        ]
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }

    private static func read(from url: URL) -> AppSettings? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return nil
        }
    }
}

enum WorkingCopyResolver {
    /// Returns the working copy root (directory containing `.svn`), or nil if none under the home directory.
    static func resolveRoot(for selectedURL: URL) -> URL? {
        var current = selectedURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: current.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            current = current.deletingLastPathComponent()
        }

        let home = AppConstants.realHomeDirectory.path
        while true {
            let svnDir = current.appendingPathComponent(".svn", isDirectory: true)
            if FileManager.default.fileExists(atPath: svnDir.path) {
                return current
            }
            let path = current.path
            if path == home || path == "/" || current.pathComponents.count <= 1 {
                return nil
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    static func registeredRoot(containing path: String, in roots: [String]) -> String? {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let matches = roots.filter { root in
            let r = URL(fileURLWithPath: root).standardizedFileURL.path
            return standardized == r || standardized.hasPrefix(r + "/")
        }
        return matches.max(by: { $0.count < $1.count })
    }
}

enum SVNBinaryLocator {
    static func resolve(preferred: String) -> String? {
        var candidates: [String] = []
        if !preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(preferred)
        }
        candidates.append(contentsOf: AppConstants.knownSVNCandidates)

        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted {
            if isUsableSVN(at: path) {
                return path
            }
        }
        return nil
    }

    static func isUsableSVN(at path: String) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue, fm.isExecutableFile(atPath: path) else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version", "--quiet"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
