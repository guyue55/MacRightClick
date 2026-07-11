import SwiftUI
import FinderSync

struct DiagnosticsSettingsView: View {
    @State private var snapshot: RightClickMenuHealthSnapshot?
    @State private var isDebugLoggingEnabled = false
    @State private var isRepairRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label("状态", systemImage: "waveform.path.ecg")) {
                VStack(alignment: .leading, spacing: 12) {
                    if let snapshot {
                        HStack {
                            Label(healthTitle(snapshot), systemImage: healthIcon(snapshot))
                                .foregroundColor(healthColor(snapshot))
                            Spacer()
                            Button("重新检测") { refresh() }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            diagnosticRow(
                                title: "完全磁盘访问",
                                value: snapshot.fullDiskAccessState == .granted ? "已授权" : "尚未授权",
                                isHealthy: snapshot.fullDiskAccessState == .granted
                            )
                            diagnosticRow(
                                title: "Finder 扩展注册",
                                value: extensionStateTitle(snapshot.finderExtensionState),
                                isHealthy: snapshot.finderExtensionState == .enabled
                            )
                            diagnosticRow(
                                title: "扩展运行心跳",
                                value: heartbeatStateTitle(snapshot.heartbeatState),
                                isHealthy: snapshot.menuServiceLevel == .healthy
                            )
                            diagnosticRow(
                                title: "右键菜单作用范围",
                                value: snapshot.watchScope == .everywhere
                                    ? "所有目录，监听 \(snapshot.observedPathCount) 个入口"
                                    : "自定义目录，监听 \(snapshot.observedPathCount) 个入口",
                                isHealthy: snapshot.menuServiceLevel == .healthy
                            )
                            diagnosticRow(
                                title: "动作队列",
                                value: actionQueueTitle(snapshot),
                                isHealthy: snapshot.failedActionCount == 0
                                    && snapshot.oldestPendingAge.map { $0 < 60 } != false
                            )
                        }

                        repairButtons(snapshot)
                    } else {
                        ProgressView("正在检测右键菜单状态…")
                    }
                }
                .padding(.vertical, 8)
            }

            GroupBox(label: Label("日志", systemImage: "doc.text.magnifyingglass")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("启用详细调试日志", isOn: Binding(
                        get: { isDebugLoggingEnabled },
                        set: { newValue in
                            guard SharedStorageManager.shared.setBool(
                                newValue,
                                forKey: SharedStorageManager.Keys.enableDebugLogging
                            ) else {
                                showConfigurationSaveFailure("详细调试日志")
                                return
                            }
                            isDebugLoggingEnabled = newValue
                        }
                    ))
                    .toggleStyle(.checkbox)

                    Text("默认关闭。开启后会记录菜单渲染、路径监听和动作过滤细节。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Button("打开日志文件夹") {
                            NSWorkspace.shared.open(SharedStorageManager.shared.logFileURL.deletingLastPathComponent())
                        }
                        Button("导出旧日志（如有）") {
                            // 旧版 1.0.x 把日志写在 extension.log；切到 OSLog 后该文件不再追加。
                            // 这里仅做兼容：若文件还存在，定位到 Finder；若不存在，明示用户走 Console.app 看 OSLog。
                            let url = SharedStorageManager.shared.logFileURL
                            if FileManager.default.fileExists(atPath: url.path) {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } else {
                                SharedHUDManager.show(
                                    title: "无旧日志",
                                    content: "OSLog 已生效，可在 Console.app 按 subsystem=guyue.RightClickAssistant 过滤",
                                    isSuccess: true
                                )
                            }
                        }
                        Button("显示共享目录") {
                            NSWorkspace.shared.open(SharedStorageManager.shared.sharedContainerURL)
                        }
                        Button("运行快速诊断") {
                            refresh { updatedSnapshot in
                                SharedHUDManager.show(
                                    title: "诊断完成",
                                    content: healthTitle(updatedSnapshot),
                                    isSuccess: updatedSnapshot.healthLevel == .healthy
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh(completion: ((RightClickMenuHealthSnapshot) -> Void)? = nil) {
        isDebugLoggingEnabled = SharedStorageManager.shared.isDebugLoggingEnabled
        let finderSyncEnabled = FIFinderSyncController.isExtensionEnabled
        DispatchQueue.global(qos: .userInitiated).async {
            let nextSnapshot = makeRightClickMenuHealthSnapshot(
                finderSyncControllerEnabled: finderSyncEnabled
            )
            DispatchQueue.main.async {
                snapshot = nextSnapshot
                completion?(nextSnapshot)
            }
        }
    }

    @ViewBuilder
    private func diagnosticRow(title: String, value: String, isHealthy: Bool) -> some View {
        HStack {
            Label(title, systemImage: isHealthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(isHealthy ? .green : .orange)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
        .font(.callout)
    }

    @ViewBuilder
    private func repairButtons(_ snapshot: RightClickMenuHealthSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                repairButtonRow
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button("一键注册扩展") { registerExtension() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRepairRunning)

                    Button("重启 Finder") { restartFinder() }
                        .buttonStyle(.bordered)
                        .disabled(isRepairRunning)
                }
                HStack(spacing: 10) {
                    Button("重新打开并重启 Finder") { relaunchAppAndRestartFinder() }
                        .buttonStyle(.bordered)
                        .disabled(isRepairRunning)

                    Button("打开扩展设置") { openFinderExtensionSettings() }
                        .buttonStyle(.bordered)
                }
            }
        }

        if snapshot.recommendedRepairAction != .none {
            Text(repairHint(snapshot.recommendedRepairAction))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var repairButtonRow: some View {
        Group {
            Button("一键注册扩展") { registerExtension() }
                .buttonStyle(.borderedProminent)
                .disabled(isRepairRunning)

            Button("重启 Finder") { restartFinder() }
                .buttonStyle(.bordered)
                .disabled(isRepairRunning)

            Button("重新打开并重启 Finder") { relaunchAppAndRestartFinder() }
                .buttonStyle(.bordered)
                .disabled(isRepairRunning)

            Button("打开扩展设置") { openFinderExtensionSettings() }
                .buttonStyle(.bordered)
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
            if outcome.isSuccess {
                SharedHUDManager.show(title: "Finder 已重启", content: "右键菜单会按最新状态加载", isSuccess: true)
            } else {
                SharedHUDManager.show(
                    title: "Finder 重启失败",
                    content: outcome.restartFinderResult?.errorDescription ?? "请手动重启 Finder 或重新登录后再试",
                    isSuccess: false
                )
            }
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
                    content: outcome.relaunchResult?.errorDescription
                        ?? "请手动退出并重新打开右键助手",
                    isSuccess: false
                )
                return
            }
            SharedHUDManager.show(
                title: "正在重新打开",
                content: "新进程将刷新 Finder，当前进程即将退出",
                isSuccess: true
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func healthTitle(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        switch snapshot.healthLevel {
        case .healthy: return "右键菜单状态正常"
        case .warning: return "右键菜单需要刷新"
        case .critical: return "右键菜单需要修复"
        }
    }

    private func healthIcon(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        switch snapshot.healthLevel {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "arrow.clockwise.circle.fill"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    private func healthColor(_ snapshot: RightClickMenuHealthSnapshot) -> Color {
        switch snapshot.healthLevel {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func extensionStateTitle(_ state: FinderExtensionRegistrationState) -> String {
        switch state {
        case .enabled: return "已启用"
        case .registeredButNotEnabled: return "已注册但未启用"
        case .notRegistered: return "未注册"
        case .unknown: return "无法确认"
        }
    }

    private func heartbeatStateTitle(_ state: ExtensionHeartbeatState) -> String {
        switch state {
        case .recent(let count): return "最近活跃，实际监听 \(count) 个入口"
        case .stale: return "已过期"
        case .missing: return "尚未收到"
        }
    }

    private func actionQueueTitle(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        var title = "待处理 \(snapshot.pendingActionCount)，失败 \(snapshot.failedActionCount)"
        if let age = snapshot.oldestPendingAge {
            title += "，最久等待 \(Int(age)) 秒"
        }
        return title
    }

    private func repairHint(_ action: RecommendedRepairAction) -> String {
        switch action {
        case .none:
            return "当前无需修复。"
        case .openFullDiskAccessSettings:
            return "请先授予完全磁盘访问；若刚授权仍未生效，请重新打开并重启 Finder。"
        case .registerExtension:
            return "Finder 扩展未处于可用状态，建议先执行一键注册扩展。"
        case .restartFinder:
            return "扩展已注册，但 Finder 可能仍使用旧会话，建议重启 Finder。"
        case .relaunchAppAndRestartFinder:
            return "建议重新打开右键助手并重启 Finder，让主程序和扩展同时刷新。"
        }
    }
}
