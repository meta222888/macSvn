import AppKit
import Combine
import Foundation
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: AppSettings
    @Published var resolvedSVNPath: String?
    @Published var statusMessage: String = ""
    @Published private(set) var busyReason: String?

    let runner = SVNRunner()
    private var resultController: ResultWindowController?
    private var commitController: CommitWindowController?
    private var authHint = """
    请先在终端对这个版本库成功操作一次，让 Subversion 记住凭据；本版本不保管密码。
    若弹出「钥匙串访问」：输入登录密码并点「允许」即可（只需一次）。本应用会把该版本库凭据改存为 Subversion 本地缓存，之后不再访问钥匙串。因本机使用临时签名，「始终允许」通常无法记住。
    """

    private init() {
        settings = AppSettings.load()
        refreshSVNPath()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var isBusy: Bool { busyReason != nil || runner.isRunning }

    func refreshSVNPath() {
        resolvedSVNPath = SVNBinaryLocator.resolve(preferred: settings.svnBinary)
    }

    func saveSettings() {
        do {
            try settings.save()
            refreshSVNPath()
            statusMessage = "已保存"
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    func addWorkingCopy() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "添加"
        panel.message = "选择 Subversion 工作副本中的文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let root = WorkingCopyResolver.resolveRoot(for: url) else {
            statusMessage = "这不是工作副本：在所选路径到用户主目录之间找不到 .svn"
            return
        }

        let path = root.path
        if settings.workingCopies.contains(where: { URL(fileURLWithPath: $0).standardizedFileURL.path == root.standardizedFileURL.path }) {
            statusMessage = "该工作副本已登记：\(path)"
            return
        }

        settings.workingCopies.append(path)
        saveSettings()
        if url.standardizedFileURL.path != root.standardizedFileURL.path {
            statusMessage = "已登记实际根目录：\(path)"
        } else {
            statusMessage = "已添加：\(path)"
        }
    }

    func removeWorkingCopies(at offsets: IndexSet) {
        settings.workingCopies.remove(atOffsets: offsets)
        saveSettings()
        statusMessage = "已移除登记（磁盘上的工作副本未删除）"
    }

    func chooseSVNBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择 svn 可执行文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if SVNBinaryLocator.isUsableSVN(at: url.path) {
            settings.svnBinary = url.path
            saveSettings()
            statusMessage = "已使用：\(url.path)"
        } else {
            statusMessage = "所选文件无法通过 svn --version 检查"
        }
    }

    func clearCustomSVNBinary() {
        settings.svnBinary = ""
        saveSettings()
        statusMessage = "已恢复自动查找"
    }

    func relaunchFinder() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        try? process.run()
        statusMessage = "已请求重新启动访达"
    }

    func openOperationsLog() {
        OperationLog.openInFinder()
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == AppConstants.urlScheme else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value else {
            showResult(title: "无法处理请求", body: "缺少请求编号", showCancel: false)
            return
        }
        do {
            let pending = try PendingAction.load(id: id)
            PendingAction.remove(id: id)
            handleAction(pending.action, paths: pending.paths)
        } catch {
            showResult(title: "无法处理请求", body: error.localizedDescription, showCancel: false)
        }
    }

    func handleAction(_ action: PendingActionKind, paths: [String]) {
        NSApp.activate(ignoringOtherApps: true)

        guard let svn = resolvedSVNPath ?? SVNBinaryLocator.resolve(preferred: settings.svnBinary) else {
            showResult(
                title: "找不到可用的 svn",
                body: "请在设置窗口中指定 svn 可执行文件。\n常见位置：\n/opt/homebrew/bin/svn\n/usr/local/bin/svn\n/opt/local/bin/svn",
                showCancel: false
            )
            return
        }
        resolvedSVNPath = svn

        let cleaned = paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            showResult(title: "没有可操作的文件", body: "没有目标路径", showCancel: false)
            return
        }

        let matchedRoots = cleaned.compactMap { WorkingCopyResolver.registeredRoot(containing: $0, in: settings.workingCopies) }
        let uniqueRoots = Array(Set(matchedRoots))
        guard uniqueRoots.count == 1, let rootPath = uniqueRoots.first else {
            showResult(title: "无法执行", body: "一次只能操作同一个工作副本", showCancel: false)
            return
        }

        if runner.isRunning || busyReason != nil {
            showResult(title: "已有操作正在进行", body: "请等待当前更新或提交结束后再试。", showCancel: false)
            return
        }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)

        switch action {
        case .update:
            startUpdate(svn: svn, paths: cleaned, workingDirectory: rootURL)
        case .commit:
            startCommitFlow(svn: svn, paths: cleaned, workingDirectory: rootURL)
        }
    }

    private func prepareAuthThenRun(
        svn: String,
        workingDirectory: URL,
        prepareTitle: String,
        work: @escaping () -> Void
    ) {
        // Keychain prompt (if any) must run off the main thread so the dialog can appear.
        DispatchQueue.global(qos: .userInitiated).async {
            SVNAuthCache.prepare(forWorkingCopy: workingDirectory, svnBinary: svn)
            DispatchQueue.main.async(execute: work)
        }
    }

    private func startUpdate(svn: String, paths: [String], workingDirectory: URL) {
        let controller = ensureResultController()
        controller.present(title: "正在更新", body: "", showCancel: true, onCancel: { [weak self] in
            self?.runner.cancel()
        })
        busyReason = "update"

        prepareAuthThenRun(svn: svn, workingDirectory: workingDirectory, prepareTitle: "正在更新") { [weak self] in
            guard let self else { return }
            let args = ["update", "--non-interactive", "--"] + paths
            self.runner.run(svnBinary: svn, arguments: args, workingDirectory: workingDirectory, onOutput: { [weak controller] chunk in
                controller?.append(chunk)
            }, completion: { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.busyReason = nil
                    let title: String
                    if result.cancelled {
                        title = "更新已取消"
                    } else if result.exitCode == 0 {
                        title = "更新完成"
                    } else {
                        title = "更新失败"
                    }
                    if result.exitCode != 0 && !result.cancelled {
                        let body = self.appendAuthHintIfNeeded(to: controller.bodyText)
                        controller.replaceBody(body)
                    }
                    controller.finish(title: title)
                    OperationLog.append(action: "更新", exitCode: Int(result.exitCode), paths: paths, output: result.output)
                    self.notify(title: title)
                }
            })
        }
    }

    private func startCommitFlow(svn: String, paths: [String], workingDirectory: URL) {
        let controller = ensureResultController()
        controller.present(title: "正在读取改动", body: "", showCancel: true, onCancel: { [weak self] in
            self?.runner.cancel()
        })
        busyReason = "status"

        prepareAuthThenRun(svn: svn, workingDirectory: workingDirectory, prepareTitle: "正在读取改动") { [weak self] in
            guard let self else { return }
            let args = ["status", "--xml", "--non-interactive", "--"] + paths
            self.runner.run(svnBinary: svn, arguments: args, workingDirectory: workingDirectory, onOutput: { _ in }, completion: { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.busyReason = nil
                    OperationLog.append(
                        action: "获取状态",
                        exitCode: Int(result.exitCode),
                        paths: paths,
                        output: result.output
                    )

                    if result.cancelled {
                        controller.finish(title: "已取消")
                        self.notify(title: "已取消")
                        return
                    }
                    if result.exitCode != 0 {
                        let body = self.appendAuthHintIfNeeded(to: result.output)
                        controller.present(title: "无法获取改动", body: body, showCancel: false, onCancel: nil)
                        self.notify(title: "无法获取改动")
                        return
                    }

                    controller.closeWindow()
                    do {
                        let items = try SVNStatusParser.parse(xml: Data(result.output.utf8))
                            .map { self.absolutizeStatusItem($0, workingDirectory: workingDirectory) }
                        self.showCommitWindow(svn: svn, items: items, workingDirectory: workingDirectory)
                    } catch {
                        self.showResult(title: "无法获取改动", body: error.localizedDescription, showCancel: false)
                    }
                }
            })
        }
    }

    private func absolutizeStatusItem(_ item: SVNStatusItem, workingDirectory: URL) -> SVNStatusItem {
        let url = URL(fileURLWithPath: item.path, relativeTo: workingDirectory).standardizedFileURL
        var copy = item
        copy.path = url.path
        return copy
    }

    private func showCommitWindow(svn: String, items: [SVNStatusItem], workingDirectory: URL) {
        if commitController == nil {
            commitController = CommitWindowController()
        }
        commitController?.present(items: items) { [weak self] message, selectedPaths in
            self?.performCommit(svn: svn, message: message, paths: selectedPaths, workingDirectory: workingDirectory)
        }
    }

    private func performCommit(svn: String, message: String, paths: [String], workingDirectory: URL) {
        let controller = ensureResultController()
        controller.present(title: "正在提交", body: "", showCancel: true, onCancel: { [weak self] in
            self?.runner.cancel()
        })
        busyReason = "commit"

        prepareAuthThenRun(svn: svn, workingDirectory: workingDirectory, prepareTitle: "正在提交") { [weak self] in
            guard let self else { return }
            let args = ["commit", "--non-interactive", "-m", message, "--"] + paths
            self.runner.run(svnBinary: svn, arguments: args, workingDirectory: workingDirectory, onOutput: { [weak controller] chunk in
                controller?.append(chunk)
            }, completion: { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.busyReason = nil
                    let title: String
                    if result.cancelled {
                        title = "提交已取消"
                    } else if result.exitCode == 0 {
                        title = "提交完成"
                    } else {
                        title = "提交失败"
                    }
                    if result.exitCode != 0 && !result.cancelled {
                        let body = self.appendAuthHintIfNeeded(to: controller.bodyText)
                        controller.replaceBody(body)
                    }
                    controller.finish(title: title)
                    OperationLog.append(
                        action: "提交",
                        exitCode: Int(result.exitCode),
                        paths: paths,
                        output: result.output,
                        message: message
                    )
                    self.notify(title: title)
                }
            })
        }
    }

    private func appendAuthHintIfNeeded(to body: String) -> String {
        let lower = body.lowercased()
        let looksLikeAuth =
            lower.contains("authorization")
            || lower.contains("authentication")
            || lower.contains("credentials")
            || lower.contains("E170001".lowercased())
            || lower.contains("E230001".lowercased())
            || body.contains("认证")
            || body.contains("密码")
            || body.contains("证书")
        if looksLikeAuth || body.contains("non-interactive") || body.contains("--non-interactive") {
            if body.contains(authHint) { return body }
            return body + (body.hasSuffix("\n") || body.isEmpty ? "" : "\n\n") + authHint
        }
        // Always append for non-zero failures that mention server/ssl as a soft hint? Spec says attach when cert/account rejected.
        if lower.contains("ssl") || lower.contains("certificate") || lower.contains("server") {
            if body.contains(authHint) { return body }
            return body + (body.hasSuffix("\n") || body.isEmpty ? "" : "\n\n") + authHint
        }
        return body
    }

    private func ensureResultController() -> ResultWindowController {
        if let resultController {
            return resultController
        }
        let controller = ResultWindowController()
        resultController = controller
        controller.onActivate = { [weak self] in
            self?.resultController?.bringToFront()
        }
        return controller
    }

    func showResult(title: String, body: String, showCancel: Bool) {
        let controller = ensureResultController()
        controller.present(title: title, body: body, showCancel: showCancel, onCancel: showCancel ? { [weak self] in
            self?.runner.cancel()
        } : nil)
    }

    func revealResultWindow() {
        resultController?.bringToFront()
    }

    private func notify(title: String) {
        let content = UNMutableNotificationContent()
        content.title = AppConstants.appDisplayName
        content.body = title
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
