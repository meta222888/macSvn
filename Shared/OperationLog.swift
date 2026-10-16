import AppKit
import Foundation

struct OperationLogEntry: Codable, Equatable {
    var time: Date
    var action: String
    var exitCode: Int?
    var paths: [String]
    var message: String?
    var outputHead: [String]
    var outputTail: [String]
}

enum OperationLog {
    static func append(action: String, exitCode: Int?, paths: [String], output: String, message: String? = nil) {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let head = Array(lines.prefix(20))
        let tail: [String]
        if lines.count > 40 {
            tail = Array(lines.suffix(20))
        } else if lines.count > 20 {
            tail = Array(lines.dropFirst(20))
        } else {
            tail = []
        }

        var entries = loadAll()
        entries.append(
            OperationLogEntry(
                time: Date(),
                action: action,
                exitCode: exitCode,
                paths: paths,
                message: message,
                outputHead: head,
                outputTail: tail
            )
        )
        if entries.count > AppConstants.maxOperationLogEntries {
            entries = Array(entries.suffix(AppConstants.maxOperationLogEntries))
        }
        saveAll(entries)
    }

    static func loadAll() -> [OperationLogEntry] {
        let url = AppConstants.operationsLogURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([OperationLogEntry].self, from: data)) ?? []
    }

    private static func saveAll(_ entries: [OperationLogEntry]) {
        do {
            try FileManager.default.createDirectory(
                at: AppConstants.applicationSupportDirectory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: AppConstants.operationsLogURL, options: .atomic)
        } catch {
            // Best-effort logging only.
        }
    }

    static func openInFinder() {
        let url = AppConstants.operationsLogURL
        if !FileManager.default.fileExists(atPath: url.path) {
            saveAll([])
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
