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
        let dir = AppConstants.pendingDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = PendingAction(id: id, action: action, paths: paths, createdAt: Date())
        let data = try JSONEncoder().encode(payload)
        let url = dir.appendingPathComponent("\(id).json")
        try data.write(to: url, options: .atomic)
        return id
    }

    static func load(id: String) throws -> PendingAction {
        let url = AppConstants.pendingDirectory.appendingPathComponent("\(id).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PendingAction.self, from: data)
    }

    static func remove(id: String) {
        let url = AppConstants.pendingDirectory.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: url)
    }

    var launchURL: URL {
        var components = URLComponents()
        components.scheme = AppConstants.urlScheme
        components.host = "run"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url!
    }
}
