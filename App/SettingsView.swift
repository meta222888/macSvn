import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(AppConstants.appDisplayName)
                .font(.title2.bold())

            GroupBox("svn 命令") {
                VStack(alignment: .leading, spacing: 10) {
                    if let path = model.resolvedSVNPath {
                        Label("当前使用：\(path)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    } else {
                        Label("未找到可用的 svn。请先安装官方客户端，或手动选择可执行文件。", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Button("选择 svn 可执行文件…") { model.chooseSVNBinary() }
                        if !model.settings.svnBinary.isEmpty {
                            Button("恢复自动查找") { model.clearCustomSVNBinary() }
                        }
                        Spacer()
                        Button("重新检测") { model.refreshSVNPath() }
                    }

                    Text("查找顺序：设置中的路径 → /opt/homebrew/bin/svn → /usr/local/bin/svn → /opt/local/bin/svn")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox("工作副本") {
                VStack(alignment: .leading, spacing: 10) {
                    if model.settings.workingCopies.isEmpty {
                        Text("尚未登记工作副本。登记后，访达右键才会出现 SVN 菜单。")
                            .foregroundStyle(.secondary)
                    } else {
                        List {
                            ForEach(Array(model.settings.workingCopies.enumerated()), id: \.offset) { _, path in
                                Text(path)
                                    .textSelection(.enabled)
                            }
                            .onDelete(perform: model.removeWorkingCopies)
                        }
                        .frame(minHeight: 140, maxHeight: 220)
                    }

                    HStack {
                        Button("添加…") { model.addWorkingCopy() }
                        Spacer()
                    }

                    Text("移除只从本产品列表中去掉，不会删除磁盘上的工作副本。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox("访达扩展") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("请打开：系统设置 → 通用 → 登录项与扩展 → 访达扩展 → 打开「SVN 访达菜单」。")
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button("重新启动访达") { model.relaunchFinder() }
                        Button("打开操作记录") { model.openOperationsLog() }
                        Spacer()
                    }

                    Text("更换登记目录后若菜单未出现，可手动重新启动访达。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 560)
    }
}
