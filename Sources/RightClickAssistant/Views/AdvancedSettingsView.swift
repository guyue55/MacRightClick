import SwiftUI

struct AdvancedSettingsView: View {
    @State private var refreshID = UUID()

    private var advancedItems: [ActionItem] {
        ActionDispatcher.shared.allActions
            .filter { $0.settingsGroup == .advanced }
            .sorted { $0.localizedTitle < $1.localizedTitle }
            .map { ActionItem(id: $0.actionId, action: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("高级动作默认关闭，开启后仍会在执行前确认。")
                .font(.body)
                .foregroundColor(.secondary)

            ActionListGroupView(
                title: "高级功能",
                iconName: "exclamationmark.triangle",
                items: advancedItems,
                footer: "包含永久删除、跨目录复制/移动、重启 Finder 等动作。"
            )
            .id(refreshID)

            ExternalToolsManagerView()

            GroupBox(label: Label("恢复", systemImage: "arrow.counterclockwise")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("仅恢复动作启用状态")
                                .font(.body)
                            Text("移除所有动作启用状态配置，恢复为内置默认值。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("恢复") { resetActionDefaults() }
                            .buttonStyle(.bordered)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("恢复全部默认设置")
                                .font(.body)
                            Text("除动作启用状态外，同时清空收藏、监听目录、提示开关与调试日志开关。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("全部恢复") { resetAllDefaults() }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func resetActionDefaults() {
        let actionKeys = ActionDispatcher.shared.allActions.map { "enable_action_\($0.actionId)" }
        guard SharedStorageManager.shared.applyConfigurationChanges(removingKeys: actionKeys) else {
            showConfigurationSaveFailure("动作默认设置")
            return
        }
        postConfigChanged()
        refreshID = UUID()
        SharedHUDManager.show(title: "已恢复默认", content: "右键动作将按内置默认值显示", isSuccess: true)
    }

    /// 全量恢复：在 resetActionDefaults 基础上，再清空收藏、提示开关、监听目录、调试日志开关。
    /// 与 resetActionDefaults 分两档的原因：用户最常见诉求是"我把某个动作关错了，给我退回默认"，
    /// 不该顺带把收藏列表和监听目录一起清掉。
    private func resetAllDefaults() {
        let actionKeys = ActionDispatcher.shared.allActions.map { "enable_action_\($0.actionId)" }
        let preferenceKeys = [
            "shouldEnableiCloudMenu",
            "enable_success_hud",
            SharedStorageManager.Keys.enableDebugLogging,
            SharedStorageManager.Keys.menuLayoutMode
        ]
        let defaultDirectories = SharedStorageManager.defaultWatchedDirectoryPaths(
            homePath: NSHomeDirectory()
        )
        guard SharedStorageManager.shared.applyConfigurationChanges(
            stringArrayValues: [
                SharedStorageManager.Keys.favoriteActionIds: [],
                SharedStorageManager.Keys.watchedDirectoryPaths: defaultDirectories
            ],
            removingKeys: actionKeys + preferenceKeys
        ) else {
            showConfigurationSaveFailure("全部默认设置")
            return
        }

        postConfigChanged()
        refreshID = UUID()
        SharedHUDManager.show(
            title: "已恢复全部默认",
            content: "动作、收藏、监听目录、提示开关均已重置",
            isSuccess: true
        )
    }
}

struct ExternalToolsManagerView: View {
    @State private var brewPath: String?
    @State private var installedTools: [ManagedExternalTool: Bool] = [:]
    @State private var runningTool: ManagedExternalTool?
    @State private var runningOperation: ExternalToolOperation?

    var body: some View {
        GroupBox(label: Label("外部工具", systemImage: "hammer")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("终端与编辑器依赖")
                            .font(.body)
                        Text(brewPath == nil
                             ? "未检测到 Homebrew。安装 Homebrew 后，可在这里直接安装或更新可选工具。"
                             : "已检测到 Homebrew：\(brewPath ?? "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if brewPath == nil {
                        Button("打开 Homebrew") {
                            NSWorkspace.shared.open(ExternalToolManager.homebrewWebsiteURL)
                        }
                        .buttonStyle(.bordered)

                        Button("复制安装命令") {
                            copyHomebrewInstallCommand()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("重新检测") { refresh() }
                            .buttonStyle(.bordered)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ManagedExternalTool.allCases) { tool in
                        externalToolRow(tool)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func externalToolRow(_ tool: ManagedExternalTool) -> some View {
        let isInstalled = installedTools[tool] ?? false
        let operation: ExternalToolOperation = isInstalled ? .update : .install
        let isRunning = runningTool == tool

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.displayName)
                    .font(.callout)
                    .fontWeight(.medium)
                Text("brew \(operation == .install ? "install" : "upgrade") --cask \(tool.caskName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Text(isInstalled ? "已安装" : "未安装")
                .font(.caption)
                .foregroundColor(isInstalled ? .green : .secondary)

            Button(action: { run(operation, for: tool) }) {
                HStack(spacing: 6) {
                    if isRunning {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    }
                    Text(isRunning ? "\(runningOperation?.title ?? operation.title)中…" : operation.title)
                }
                .frame(minWidth: 72)
            }
            .buttonStyle(.bordered)
            .disabled(brewPath == nil || runningTool != nil)
        }
        .padding(.vertical, 5)
    }

    private func refresh() {
        brewPath = ExternalToolManager.homebrewExecutablePath()
        InstalledAppRegistry.shared.invalidateAll()
        installedTools = Dictionary(
            uniqueKeysWithValues: ManagedExternalTool.allCases.map { tool in
                (tool, ExternalToolManager.isInstalled(tool))
            }
        )
    }

    private func copyHomebrewInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ExternalToolManager.homebrewInstallCommand, forType: .string)
        SharedHUDManager.show(
            title: "已复制 Homebrew 安装命令",
            content: "请在终端中确认后执行",
            isSuccess: true
        )
    }

    private func run(_ operation: ExternalToolOperation, for tool: ManagedExternalTool) {
        guard let brewPath else {
            SharedHUDManager.show(
                title: "未检测到 Homebrew",
                content: "请先安装 Homebrew 后再安装或更新工具",
                isSuccess: false
            )
            return
        }

        runningTool = tool
        runningOperation = operation
        SharedHUDManager.show(
            title: "\(operation.title)\(tool.displayName)",
            content: "Homebrew 正在后台执行，请稍候",
            isSuccess: true
        )

        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = ExternalToolManager.perform(
                operation: operation,
                tool: tool,
                brewExecutablePath: brewPath
            )

            DispatchQueue.main.async {
                runningTool = nil
                runningOperation = nil
                refresh()

                if outcome.isSuccess {
                    SharedHUDManager.show(
                        title: "\(operation.title)完成",
                        content: "\(tool.displayName) 已处理完成",
                        isSuccess: true
                    )
                } else {
                    SharedHUDManager.show(
                        title: "\(operation.title)失败",
                        content: operationErrorDescription(outcome),
                        isSuccess: false
                    )
                }
            }
        }
    }

    private func operationErrorDescription(_ outcome: ExternalToolOperationOutcome) -> String {
        let stderr = outcome.commandResult.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return String(stderr.prefix(240))
        }
        return outcome.commandResult.errorDescription
            ?? "brew 返回码：\(outcome.commandResult.terminationStatus.map { String($0) } ?? "unknown")"
    }
}
