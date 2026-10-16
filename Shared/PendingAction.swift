import Foundation

enum PendingActionKind: String, Codable {
    case update
    case commit
}

struct PendingAction: Codable, Equatable {
    var id: String
    var action: PendingActionKind
    var paths: [String]
    var createdAt: Date

    static func store(action: PendingActionKind, paths: [String]) throws -> String {
        let id = UUID().uuidString
        let payload = PendingAction(id: id, action: action, paths: paths, createdAt: Date())
        let data = try JSONEncoder().encode(payload)

        var wrote = false
        var lastError: Error?
        for dir in [
            AppConstants.pendingDirectory,
            AppConstants.hostPendingDirectory
        ] {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: dir.appendingPathComponent("\(id).json"), options: .atomic)
                wrote = true
            } catch {
                lastError = error
            }
        }
        if !wrote {
            throw lastError ?? NSError(domain: "PendingAction", code: 1)
        }
        return id
    }

    static func load(id: String) throws -> PendingAction {
        let candidates = [
            AppConstants.hostPendingDirectory.appendingPathComponent("\(id).json"),
            AppConstants.pendingDirectory.appendingPathComponent("\(id).json"),
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support/\(AppConstants.appSupportFolderName)/pending/\(id).json")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PendingAction.self, from: data)
        }
        throw NSError(domain: "PendingAction", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "找不到请求 \(id)"
        ])
    }

    static func remove(id: String) {
        let candidates = [
            AppConstants.hostPendingDirectory.appendingPathComponent("\(id).json"),
            AppConstants.pendingDirectory.appendingPathComponent("\(id).json"),
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support/\(AppConstants.appSupportFolderName)/pending/\(id).json")
        ]
        for url in candidates {
            try? FileManager.default.removeItem(at: url)
        }
    }

    var launchURL: URL {
        var components = URLComponents()
        components.scheme = AppConstants.urlScheme
        components.host = "run"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url!
    }
}
