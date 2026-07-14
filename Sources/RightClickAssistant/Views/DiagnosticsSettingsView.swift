import SwiftUI
import FinderSync

struct DiagnosticsSettingsView: View {
    private static let consoleURL = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
    private static let logQuery = "subsystem == \"guyue.RightClickAssistant\""

    @State private var snapshot: RightClickMenuHealthSnapshot?
    @State private var isDebugLoggingEnabled = false
    @State private var isRepairRunning = false

    var body: some View {
        Form {
            Section("运行状态") {
                if let snapshot {
                    SettingsStatusRow(
                        title: "右键菜单服务",
                        value: menuServiceValue(snapshot),
                        detail: menuServiceDetail(snapshot),
                        level: menuServiceLevel(snapshot)
                    )
                    SettingsStatusRow(
                        title: "文件访问",
                        value: snapshot.fullDiskAccessState == .granted ? "已授权" : "受限",
                        detail: "完全磁盘访问只影响受保护文件，不决定菜单是否出现。",
                        level: snapshot.fullDiskAccessState == .granted ? .normal : .warning
                    )
                    SettingsStatusRow(
                        title: "动作队列",
                        value: queueValue(snapshot),
                        detail: queueDetail(snapshot),
                        level: queueLevel(snapshot)
                    )
                } else {
                    ProgressView("正在检测右键菜单状态…")
                }

                Button(action: refresh) {
                    Label("重新检测", systemImage: "arrow.clockwise")
                }
                .disabled(isRepairRunning)
            }

            Section("建议修复") {
                if let snapshot {
                    if snapshot.recommendedRepairAction == .none {
                        Label("当前无需修复", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            runRecommendedAction(snapshot.recommendedRepairAction)
                        } label: {
                            if isRepairRunning {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("修复中…")
                                }
                            } else {
                                Label(
                                    repairButtonTitle(snapshot.recommendedRepairAction),
                                    systemImage: repairButtonIcon(snapshot.recommendedRepairAction)
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRepairRunning)

                        Text(repairHint(snapshot.recommendedRepairAction))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("完成检测后会显示最优先的修复动作。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("支持工具") {
                Button(action: copyDiagnosticReport) {
                    Label("复制诊断报告", systemImage: "doc.on.doc")
                }
                .disabled(snapshot == nil)

                Button(action: copyLogQuery) {
                    Label("复制 Console 查询条件", systemImage: "line.3.horizontal.decrease.circle")
                }

                Button(action: openConsole) {
                    Label("打开 Console", systemImage: "terminal")
                }

                Button(action: showSharedDirectory) {
                    Label("显示共享目录", systemImage: "folder")
                }

                Button(action: clearFailedActions) {
                    Label("清空失败动作", systemImage: "trash")
                }
                .disabled((snapshot?.failedActionCount ?? 0) == 0)
            }

            Section("日志") {
                Toggle("启用详细调试日志", isOn: Binding(
                    get: { isDebugLoggingEnabled },
                    set: saveDebugLogging
                ))

                Text("默认关闭。仅在排查问题时开启，完成后建议关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        isDebugLoggingEnabled = SharedStorageManager.shared.isDebugLoggingEnabled
        let finderSyncEnabled = FIFinderSyncController.isExtensionEnabled
        DispatchQueue.global(qos: .userInitiated).async {
            let nextSnapshot = makeRightClickMenuHealthSnapshot(
                finderSyncControllerEnabled: finderSyncEnabled
            )
            DispatchQueue.main.async {
                snapshot = nextSnapshot
            }
        }
    }

    private func runRecommendedAction(_ action: RecommendedRepairAction) {
        switch action {
        case .none:
            refresh()
        case .openFullDiskAccessSettings:
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
            ) {
                NSWorkspace.shared.open(url)
            }
        case .registerExtension:
            registerExtension()
        case .restartFinder:
            restartFinder()
        case .relaunchAppAndRestartFinder:
            relaunchAppAndRestartFinder()
        }
    }

    private func registerExtension() {
        isRepairRunning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = SystemReloader.registerFinderExtension(appBundleURL: Bundle.main.bundleURL)
            DispatchQueue.main.async {
                isRepairRunning = false
                showFinderExtensionRegistrationOutcome(outcome)
                refresh()
            }
        }
    }

    private func restartFinder() {
        isRepairRunning = true
        PermissionRefreshCoordinator.performReload(
            choice: .restartFinderOnly,
            bundleURL: Bundle.main.bundleURL
        ) { outcome in
            isRepairRunning = false
            SharedHUDManager.show(
                title: outcome.isSuccess ? "Finder 已重启" : "Finder 重启失败",
                content: outcome.isSuccess
                    ? "右键菜单会按最新状态加载"
                    : outcome.restartFinderResult?.errorDescription ?? "请手动重启 Finder 后重试",
                isSuccess: outcome.isSuccess
            )
            refresh()
        }
    }

    private func relaunchAppAndRestartFinder() {
        isRepairRunning = true
        PermissionRefreshCoordinator.performReload(
            choice: .relaunchAppAndRestartFinder,
            bundleURL: Bundle.main.bundleURL
        ) { outcome in
            isRepairRunning = false
            guard outcome.isSuccess else {
                SharedHUDManager.show(
                    title: "重新打开失败",
                    content: outcome.relaunchResult?.errorDescription ?? "请手动退出并重新打开右键助手",
                    isSuccess: false
                )
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func copyDiagnosticReport() {
        guard let snapshot else { return }
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
        copyToPasteboard(
            snapshot.diagnosticSummary(appVersion: appVersion),
            title: "诊断报告已复制"
        )
    }

    private func copyLogQuery() {
        copyToPasteboard(Self.logQuery, title: "Console 查询条件已复制")
    }

    private func copyToPasteboard(_ value: String, title: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        SharedHUDManager.show(title: title, content: "可直接粘贴使用", isSuccess: true)
    }

    private func openConsole() {
        guard FileManager.default.fileExists(atPath: Self.consoleURL.path) else {
            SharedHUDManager.show(
                title: "无法打开 Console",
                content: "系统未找到 Console.app",
                isSuccess: false
            )
            return
        }
        NSWorkspace.shared.open(Self.consoleURL)
    }

    private func showSharedDirectory() {
        NSWorkspace.shared.open(SharedStorageManager.shared.sharedContainerURL)
    }

    private func clearFailedActions() {
        do {
            try SharedStorageManager.shared.clearFailedActions()
            SharedHUDManager.show(title: "失败动作已清空", content: "动作队列状态已刷新", isSuccess: true)
            refresh()
        } catch {
            SharedHUDManager.show(
                title: "清空失败",
                content: error.localizedDescription,
                isSuccess: false
            )
        }
    }

    private func saveDebugLogging(_ enabled: Bool) {
        guard SharedStorageManager.shared.setBool(
            enabled,
            forKey: SharedStorageManager.Keys.enableDebugLogging
        ) else {
            showConfigurationSaveFailure("详细调试日志")
            return
        }
        isDebugLoggingEnabled = enabled
    }

    private func menuServiceLevel(_ snapshot: RightClickMenuHealthSnapshot) -> SettingsStatusLevel {
        switch snapshot.menuServiceLevel {
        case .healthy: return .normal
        case .unverified: return .warning
        case .unavailable: return .critical
        }
    }

    private func menuServiceValue(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        switch snapshot.menuServiceLevel {
        case .healthy: return "可用"
        case .unverified: return "待确认"
        case .unavailable: return "不可用"
        }
    }

    private func menuServiceDetail(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        let registration: String
        switch snapshot.finderExtensionState {
        case .enabled: registration = "扩展已启用"
        case .registeredButNotEnabled: registration = "扩展已注册但未启用"
        case .notRegistered: registration = "扩展未注册"
        case .unknown: registration = "扩展注册状态未知"
        }
        let scope = snapshot.watchScope == .everywhere ? "所有目录" : "自定义目录"
        let cloud = snapshot.cloudCompatibilityEnabled ? "云盘兼容已开启" : "云盘兼容已关闭"
        return "\(registration)；\(scope)，\(cloud)，实际监听 \(snapshot.observedPathCount) 个入口；File Provider 目录可使用系统服务入口。"
    }

    private func queueLevel(_ snapshot: RightClickMenuHealthSnapshot) -> SettingsStatusLevel {
        if snapshot.failedActionCount > 0 { return .critical }
        if snapshot.oldestPendingAge.map({ $0 >= 60 }) == true { return .warning }
        return .normal
    }

    private func queueValue(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        "待处理 \(snapshot.pendingActionCount)，失败 \(snapshot.failedActionCount)"
    }

    private func queueDetail(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        guard let age = snapshot.oldestPendingAge else { return "当前没有等待中的动作。" }
        return "最久等待 \(Int(age)) 秒。失败动作可在下方清理。"
    }

    private func repairButtonTitle(_ action: RecommendedRepairAction) -> String {
        switch action {
        case .none: return "重新检测"
        case .openFullDiskAccessSettings: return "打开完全磁盘访问设置"
        case .registerExtension: return "一键注册扩展"
        case .restartFinder: return "重启 Finder"
        case .relaunchAppAndRestartFinder: return "重新打开并重启 Finder"
        }
    }

    private func repairButtonIcon(_ action: RecommendedRepairAction) -> String {
        switch action {
        case .none: return "arrow.clockwise"
        case .openFullDiskAccessSettings: return "lock.open"
        case .registerExtension: return "puzzlepiece.extension"
        case .restartFinder: return "arrow.clockwise"
        case .relaunchAppAndRestartFinder: return "power"
        }
    }

    private func repairHint(_ action: RecommendedRepairAction) -> String {
        switch action {
        case .none:
            return "当前无需修复。"
        case .openFullDiskAccessSettings:
            return "完全磁盘访问影响受保护文件操作；授权后若仍未生效，请回到 Finder 页重新检测。"
        case .registerExtension:
            return "Finder 扩展未处于可用状态，将重新注册、启用并刷新 Finder。"
        case .restartFinder:
            return "扩展已注册，但当前 Finder 会话尚未报告有效心跳。"
        case .relaunchAppAndRestartFinder:
            return "主程序和 Finder 都需要重新加载，当前窗口会在新进程启动后关闭。"
        }
    }
}
