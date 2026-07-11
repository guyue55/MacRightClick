import SwiftUI

struct AdvancedSettingsView: View {
    private enum ResetKind: String, Identifiable {
        case actions
        case all

        var id: String { rawValue }
    }

    @State private var refreshID = UUID()
    @State private var pendingReset: ResetKind?

    private var advancedItems: [ActionItem] {
        ActionDispatcher.shared.allActions
            .filter { $0.settingsGroup == .advanced }
            .sorted { $0.localizedTitle < $1.localizedTitle }
            .map { ActionItem(id: $0.actionId, action: $0) }
    }

    var body: some View {
        Form {
            Section {
                ForEach(advancedItems) { item in
                    ActionRowView(action: item.action)
                }
            } header: {
                Text("高级动作")
            } footer: {
                Text("高级动作默认关闭，可能永久删除文件或改变系统状态；启用后仍会在执行前确认。")
            }
            .id(refreshID)

            Section("外部工具") {
                ExternalToolsManagerView()
            }

            Section {
                LabeledContent {
                    Button {
                        pendingReset = .actions
                    } label: {
                        Label("恢复", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("恢复动作默认状态")
                        Text("重置普通与高级动作开关，并切回精简档案。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent {
                    Button(role: .destructive) {
                        pendingReset = .all
                    } label: {
                        Label("全部恢复", systemImage: "trash")
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("恢复全部默认设置")
                        Text("同时重置收藏、菜单布局、Finder 范围、提示、调试日志与静默启动。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("恢复")
            } footer: {
                Text("恢复操作不会卸载外部工具，也不会修改登录项状态。")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            resetDialogTitle,
            isPresented: Binding(
                get: { pendingReset != nil },
                set: { if !$0 { pendingReset = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingReset {
                Button(resetConfirmationTitle(pendingReset), role: .destructive) {
                    performReset(pendingReset)
                    self.pendingReset = nil
                }
            }
            Button("取消", role: .cancel) {
                pendingReset = nil
            }
        } message: {
            Text(resetDialogMessage)
        }
    }

    private var resetDialogTitle: String {
        pendingReset == .all ? "恢复全部默认设置？" : "恢复动作默认状态？"
    }

    private var resetDialogMessage: String {
        switch pendingReset {
        case .actions:
            return "普通与高级动作的自定义开关会被清除，并恢复为精简档案；收藏和其他设置不变。"
        case .all:
            return "普通与高级动作、收藏、菜单布局、Finder 范围、提示、调试日志和静默启动都会恢复默认。此操作不可撤销。"
        case .none:
            return ""
        }
    }

    private func resetConfirmationTitle(_ kind: ResetKind) -> String {
        kind == .all ? "确认全部恢复" : "确认恢复动作"
    }

    private func performReset(_ kind: ResetKind) {
        switch kind {
        case .actions: resetActionDefaults()
        case .all: resetAllDefaults()
        }
    }

    private func resetActionDefaults() {
        let actionKeys = ActionDispatcher.shared.allActions.map { "enable_action_\($0.actionId)" }
        guard SharedStorageManager.shared.applyConfigurationChanges(
            stringArrayValues: [
                SharedStorageManager.Keys.actionProfile: [ActionProfile.essential.rawValue]
            ],
            removingKeys: actionKeys
        ) else {
            showConfigurationSaveFailure("动作默认设置")
            return
        }
        finishReset(content: "普通与高级动作已恢复为精简档案")
    }

    private func resetAllDefaults() {
        let actionKeys = ActionDispatcher.shared.allActions.map { "enable_action_\($0.actionId)" }
        let preferenceKeys = [
            "shouldEnableiCloudMenu",
            "enable_success_hud",
            SharedStorageManager.Keys.enableDebugLogging,
            SharedStorageManager.Keys.menuLayoutMode,
            SharedStorageManager.Keys.watchScope,
            LaunchPresentationPolicy.silentLaunchKey
        ]
        let defaultDirectories = SharedStorageManager.defaultWatchedDirectoryPaths(
            homePath: NSHomeDirectory()
        )
        guard SharedStorageManager.shared.applyConfigurationChanges(
            stringArrayValues: [
                SharedStorageManager.Keys.actionProfile: [ActionProfile.essential.rawValue],
                SharedStorageManager.Keys.favoriteActionIds: [],
                SharedStorageManager.Keys.watchedDirectoryPaths: defaultDirectories
            ],
            removingKeys: actionKeys + preferenceKeys
        ) else {
            showConfigurationSaveFailure("全部默认设置")
            return
        }

        finishReset(content: "动作、收藏、菜单、Finder 范围与提示设置均已重置")
    }

    private func finishReset(content: String) {
        postConfigChanged()
        refreshID = UUID()
        SharedHUDManager.show(title: "已恢复默认", content: content, isSuccess: true)
    }
}

struct ExternalToolsManagerView: View {
    @State private var brewPath: String?
    @State private var installedTools: [ManagedExternalTool: Bool] = [:]
    @State private var runningTool: ManagedExternalTool?
    @State private var runningOperation: ExternalToolOperation?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(brewPath == nil ? "未检测到 Homebrew" : "Homebrew 已就绪")
                    Text(brewPath ?? "安装 Homebrew 后可直接安装或更新可选工具。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                if brewPath == nil {
                    Button {
                        NSWorkspace.shared.open(ExternalToolManager.homebrewWebsiteURL)
                    } label: {
                        Label("Homebrew", systemImage: "safari")
                    }
                    Button(action: copyHomebrewInstallCommand) {
                        Label("复制命令", systemImage: "doc.on.doc")
                    }
                } else {
                    Button(action: refresh) {
                        Label("重新检测", systemImage: "arrow.clockwise")
                    }
                }
            }

            ForEach(ManagedExternalTool.allCases) { tool in
                Divider()
                externalToolRow(tool)
            }
        }
        .padding(.vertical, 4)
        .onAppear(perform: refresh)
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
                Text("brew \(operation == .install ? "install" : "upgrade") --cask \(tool.caskName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            Text(isInstalled ? "已安装" : "未安装")
                .font(.caption)
                .foregroundStyle(isInstalled ? Color.green : Color.secondary)

            Button(action: { run(operation, for: tool) }) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 52)
                } else {
                    Text(operation.title)
                        .frame(minWidth: 40)
                }
            }
            .disabled(brewPath == nil || runningTool != nil)
            .accessibilityLabel("\(operation.title) \(tool.displayName)")
        }
        .padding(.vertical, 2)
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

                SharedHUDManager.show(
                    title: outcome.isSuccess ? "\(operation.title)完成" : "\(operation.title)失败",
                    content: outcome.isSuccess
                        ? "\(tool.displayName) 已处理完成"
                        : operationErrorDescription(outcome),
                    isSuccess: outcome.isSuccess
                )
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
