import Foundation
import Security

struct SVNCachedAuth {
    var username: String
    var password: String
    var realm: String
}

enum SVNAuthCache {
    /// Loads username from `~/.subversion/auth` and password from the macOS keychain
    /// (the same store the command-line `svn` client uses).
    static func credentials(forWorkingCopy root: URL, svnBinary: String) -> SVNCachedAuth? {
        guard let identity = repositoryIdentity(forWorkingCopy: root, svnBinary: svnBinary) else {
            return credentialsMatchingHostHint(root.lastPathComponent)
        }
        if let match = credentials(matchingUUID: identity.uuid, host: identity.host) {
            return match
        }
        return credentialsMatchingHostHint(identity.host)
    }

    static func apply(to arguments: inout [String], auth: SVNCachedAuth?) {
        guard let auth else { return }
        // Insert after the subcommand (update/commit/status).
        guard !arguments.isEmpty else { return }
        arguments.insert(contentsOf: ["--username", auth.username, "--password", auth.password], at: 1)
    }

    private struct RepoIdentity {
        var url: String
        var uuid: String
        var host: String
    }

    private static func repositoryIdentity(forWorkingCopy root: URL, svnBinary: String) -> RepoIdentity? {
        let url = runShowItem(svnBinary: svnBinary, root: root, item: "url")
        let uuid = runShowItem(svnBinary: svnBinary, root: root, item: "repos-uuid")
        guard let url, let uuid, let host = URL(string: url)?.host ?? URL(string: url.replacingOccurrences(of: "svn://", with: "http://"))?.host else {
            return nil
        }
        return RepoIdentity(url: url, uuid: uuid, host: host)
    }

    private static func runShowItem(svnBinary: String, root: URL, item: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: svnBinary)
        process.arguments = ["info", "--non-interactive", "--show-item", item, "--", root.path]
        process.currentDirectoryURL = root
        process.environment = [
            "HOME": AppConstants.realHomeDirectory.path,
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/bin:/bin",
            "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    private static func credentials(matchingUUID uuid: String, host: String) -> SVNCachedAuth? {
        for entry in readSimpleAuthEntries() {
            let realm = entry.realm
            guard realm.contains(uuid) || realm.localizedCaseInsensitiveContains(host) else { continue }
            guard let password = keychainPassword(service: realm, account: entry.username) else { continue }
            return SVNCachedAuth(username: entry.username, password: password, realm: realm)
        }
        return nil
    }

    private static func credentialsMatchingHostHint(_ hint: String) -> SVNCachedAuth? {
        let needle = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        for entry in readSimpleAuthEntries() where entry.realm.localizedCaseInsensitiveContains(needle) {
            if let password = keychainPassword(service: entry.realm, account: entry.username) {
                return SVNCachedAuth(username: entry.username, password: password, realm: entry.realm)
            }
        }
        return nil
    }

    private struct SimpleAuthEntry {
        var username: String
        var realm: String
        var passtype: String
    }

    private static func readSimpleAuthEntries() -> [SimpleAuthEntry] {
        let dir = AppConstants.realHomeDirectory
            .appendingPathComponent(".subversion/auth/svn.simple", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.compactMap { parseSimpleAuthFile(at: $0) }
    }

    private static func parseSimpleAuthFile(at url: URL) -> SimpleAuthEntry? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let map = parseHashFile(text)
        guard let username = map["username"], let realm = map["svn:realmstring"] else { return nil }
        return SimpleAuthEntry(username: username, realm: realm, passtype: map["passtype"] ?? "")
    }

    /// Parses Subversion's `K <len> / key / V <len> / value` hash files.
    private static func parseHashFile(_ text: String) -> [String: String] {
        let lines = text.components(separatedBy: "\n")
        var result: [String: String] = [:]
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("K "), index + 1 < lines.count {
                let key = lines[index + 1]
                index += 2
                if index < lines.count, lines[index].hasPrefix("V ") {
                    let length = Int(lines[index].dropFirst(2).trimmingCharacters(in: .whitespaces)) ?? 0
                    index += 1
                    var value = ""
                    if length == 0 {
                        value = ""
                    } else if index < lines.count {
                        // Values are a single line for username/realm/passtype.
                        value = lines[index]
                        index += 1
                    }
                    result[key] = value
                    continue
                }
            }
            index += 1
        }
        return result
    }

    private static func keychainPassword(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
    }
}
