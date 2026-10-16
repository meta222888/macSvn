import Foundation

final class SVNRunner {
    private(set) var isRunning = false
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private let lock = NSLock()

    struct Result {
        var exitCode: Int32
        var output: String
        var cancelled: Bool
    }

    func run(
        svnBinary: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        onOutput: @escaping (String) -> Void,
        completion: @escaping (Result) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else {
            DispatchQueue.main.async {
                completion(Result(exitCode: -1, output: "已有操作正在进行", cancelled: false))
            }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: svnBinary)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        var environment = ProcessInfo.processInfo.environment
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existing = environment["PATH"], !existing.isEmpty {
            environment["PATH"] = extraPath + ":" + existing
        } else {
            environment["PATH"] = extraPath
        }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        self.outputPipe = stdout
        self.errorPipe = stderr
        self.process = process
        self.isRunning = true

        let collected = NSMutableString()
        let collectedLock = NSLock()

        let handleChunk: (FileHandle) -> Void = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return
            }
            collectedLock.lock()
            collected.append(chunk)
            collectedLock.unlock()
            DispatchQueue.main.async {
                onOutput(chunk)
            }
        }

        stdout.fileHandleForReading.readabilityHandler = handleChunk
        stderr.fileHandleForReading.readabilityHandler = handleChunk

        process.terminationHandler = { [weak self] proc in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            let remainingOut = stdout.fileHandleForReading.readDataToEndOfFile()
            let remainingErr = stderr.fileHandleForReading.readDataToEndOfFile()
            for data in [remainingOut, remainingErr] {
                if !data.isEmpty, let chunk = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                    collectedLock.lock()
                    collected.append(chunk)
                    collectedLock.unlock()
                    DispatchQueue.main.async {
                        onOutput(chunk)
                    }
                }
            }

            collectedLock.lock()
            let full = collected as String
            collectedLock.unlock()

            let cancelled = proc.terminationReason == .uncaughtSignal
            let code = proc.terminationStatus
            DispatchQueue.main.async {
                self?.lock.lock()
                self?.isRunning = false
                self?.process = nil
                self?.outputPipe = nil
                self?.errorPipe = nil
                self?.lock.unlock()
                completion(Result(exitCode: code, output: full, cancelled: cancelled))
            }
        }

        do {
            try process.run()
        } catch {
            isRunning = false
            self.process = nil
            DispatchQueue.main.async {
                completion(Result(exitCode: -1, output: error.localizedDescription, cancelled: false))
            }
        }
    }

    func cancel() {
        lock.lock()
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }
        let pid = process.processIdentifier
        // Terminate the process group when possible.
        kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }
}
