import Foundation
import Security

/// Ensures Subversion can authenticate non-interactively when launched from this GUI app.
///
/// Terminal-saved credentials often use `passtype=keychain`. Ad-hoc signed apps cannot keep
/// “Always Allow” on that keychain item, so every launch prompts again.
/// After a one-time keychain read (user may enter the login password once), we rewrite the
/// matching `~/.subversion/auth/svn.simple` entry to `passtype=simple` so later `svn` calls
/// need no keychain access from this app.
enum SVNAuthCache {
    /// Prepare auth cache for this working copy. Safe to call before every svn invocation.
    static func prepare(forWorkingCopy root: URL, svnBinary: String) {
        let identity = repositoryIdentity(forWorkingCopy: root, svnBinary: svnBinary)
        let entries = readSimpleAuthEntries()
        let matches: [SimpleAuthEntry]
        if let identity {
            matches = entries.filter {
                $0.realm.contains(identity.uuid) || $0.realm.localizedCaseInsensitiveContains(identity.host)
            }
        } else {
            let hint = root.lastPathComponent
            matches = entries.filter { $0.realm.localizedCaseInsensitiveContains(hint) }
        }
        for entry in matches {
            migrateKeychainEntryIfNeeded(entry)
        }
    }

    // MARK: - Migration

    private static func migrateKeychainEntryIfNeeded(_ entry: SimpleAuthEntry) {
        if entry.passtype != "keychain", entry.password != nil {
            return
        }
        guard let password = keychainPassword(service: entry.realm, account: entry.username),
              !password.isEmpty else {
            return
        }
        writeSimpleAuthFile(
            at: entry.fileURL,
            username: entry.username,
            realm: entry.realm,
            password: password
        )
    }

    private static func writeSimpleAuthFile(at url: URL, username: String, realm: String, password: String) {
        func field(_ key: String, _ value: String) -> String {
            "K \(key.utf8.count)\n\(key)\nV \(value.utf8.count)\n\(value)\n"
        }
        let body =
            field("passtype", "simple")
            + field("svn:realmstring", realm)
            + field("username", username)
            + field("password", password)
            + "END\n"
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            // Best effort; svn may still fail and surface auth errors.
        }
    }

    // MARK: - Repository identity

    private struct RepoIdentity {
        var uuid: String
        var host: String
    }

    private static func repositoryIdentity(forWorkingCopy root: URL, svnBinary: String) -> RepoIdentity? {
        let url = runShowItem(svnBinary: svnBinary, root: root, item: "url")
        let uuid = runShowItem(svnBinary: svnBinary, root: root, item: "repos-uuid")
        guard let url, let uuid else { return nil }
        let host = URL(string: url)?.host
            ?? URL(string: url.replacingOccurrences(of: "svn://", with: "http://"))?.host
        guard let host else { return nil }
        return RepoIdentity(uuid: uuid, host: host)
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

    // MARK: - Auth file parsing

    private struct SimpleAuthEntry {
        var fileURL: URL
        var username: String
        var realm: String
        var passtype: String
        var password: String?
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
        return SimpleAuthEntry(
            fileURL: url,
            username: username,
            realm: realm,
            passtype: map["passtype"] ?? "",
            password: map["password"]
        )
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
