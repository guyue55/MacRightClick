import SwiftUI
import FinderSync

private let rightClickFinderExtensionBundleIdentifier = "guyue.RightClickAssistant.Extension"

func openFinderExtensionSettings() {
    if #available(macOS 13.0, *),
       let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
        NSWorkspace.shared.open(url)
    } else {
        FIFinderSyncController.showExtensionManagementInterface()
    }
}

func makeRightClickMenuHealthSnapshot(
    finderSyncControllerEnabled: Bool = FIFinderSyncController.isExtensionEnabled
) -> RightClickMenuHealthSnapshot {
    let query = SystemReloader.queryFinderExtension(bundleIdentifier: rightClickFinderExtensionBundleIdentifier)
    let pluginKitState = FinderExtensionDiagnostics.registrationState(
        pluginKitOutput: query.standardOutput,
        commandSucceeded: query.isSuccess,
        bundleIdentifier: rightClickFinderExtensionBundleIdentifier
    )
    let storage = SharedStorageManager.shared
    let heartbeatState = ExtensionHeartbeatStore(
        fileURL: storage.extensionHeartbeatURL
    ).state()

    return FinderExtensionDiagnostics.makeSnapshot(
        fullDiskAccessGranted: FullDiskAccessChecker.hasFullDiskAccess(),
        finderSyncControllerEnabled: finderSyncControllerEnabled,
        pluginKitState: pluginKitState,
        heartbeatState: heartbeatState,
        watchScope: storage.watchScope,
        cloudCompatibilityEnabled: storage.isCloudCompatibilityEnabled,
        pendingActionCount: storage.pendingActionCount,
        oldestPendingAge: storage.oldestPendingActionAge(),
        failedActionCount: storage.failedActionCount
    )
}

func showFinderExtensionRegistrationOutcome(_ outcome: FinderExtensionRegistrationOutcome) {
    if outcome.isSuccess {
        SharedHUDManager.show(
            title: "注册成功",
            content: "Finder 已重启，右键菜单会按最新扩展状态加载",
            isSuccess: true
        )
    } else {
        SharedHUDManager.show(
            title: "注册失败",
            content: outcome.errorDescription ?? "请打开扩展设置手动启用右键助手扩展",
            isSuccess: false
        )
    }
}

func showConfigurationSaveFailure(_ settingName: String) {
    SharedHUDManager.show(
        title: "设置保存失败",
        content: "无法写入“\(settingName)”，原设置已保留。请检查共享目录权限后重试。",
        iconName: "exclamationmark.triangle.fill",
        isSuccess: false
    )
}

func postConfigChanged() {
    SystemReloader.postConfigChanged()
}

enum SettingsStatusLevel {
    case normal
    case warning
    case critical

    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    var iconName: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .critical: return "xmark.circle.fill"
        }
    }
}

struct SettingsStatusRow: View {
    let title: String
    let value: String
    let detail: String?
    let level: SettingsStatusLevel

    init(
        title: String,
        value: String,
        detail: String? = nil,
        level: SettingsStatusLevel
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.level = level
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: level.iconName)
                .foregroundStyle(level.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Finder extension management
struct ExtensionRegistrationBox: View {
    @State private var isRegistering = false
    @State private var isExtensionEnabled = FIFinderSyncController.isExtensionEnabled

    var body: some View {
        HStack(spacing: 12) {
            Label(
                isExtensionEnabled ? "扩展已启用" : "扩展尚未启用",
                systemImage: isExtensionEnabled
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill"
            )
            .foregroundStyle(isExtensionEnabled ? Color.green : Color.orange)

            Spacer()

            if isExtensionEnabled {
                registrationButton
                    .buttonStyle(.bordered)
            } else {
                registrationButton
                    .buttonStyle(.borderedProminent)
            }

            Button {
                openFinderExtensionSettings()
            } label: {
                Label("扩展设置", systemImage: "gearshape")
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        isExtensionEnabled = FIFinderSyncController.isExtensionEnabled
    }

    private var registrationButton: some View {
        Button(action: autoRegisterExtension) {
            if isRegistering {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("注册中")
                }
            } else {
                Label(
                    isExtensionEnabled ? "重新注册" : "注册扩展",
                    systemImage: "arrow.clockwise"
                )
            }
        }
        .frame(minWidth: 92)
        .disabled(isRegistering)
    }

    private func autoRegisterExtension() {
        isRegistering = true
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = SystemReloader.registerFinderExtension(appBundleURL: Bundle.main.bundleURL)
            DispatchQueue.main.async {
                isRegistering = false
                showFinderExtensionRegistrationOutcome(outcome)
                refresh()
            }
        }
    }
}

// MARK: - Extension readiness
struct ExtensionStatusBanner: View {
    @State private var snapshot: RightClickMenuHealthSnapshot?
    @State private var isRepairRunning = false

    var body: some View {
        Group {
            if let snapshot {
                HStack(spacing: 12) {
                    Image(systemName: bannerIcon(snapshot))
                        .foregroundStyle(bannerColor(snapshot))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(bannerTitle(snapshot))
                            .font(.body.weight(.medium))
                        Text(bannerSubtitle(snapshot))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    if snapshot.recommendedRepairAction == .none {
                        Label("正常", systemImage: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button(action: { runRecommendedAction(snapshot) }) {
                            if isRepairRunning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label(
                                    bannerButtonTitle(snapshot),
                                    systemImage: "arrow.clockwise"
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(bannerColor(snapshot))
                        .disabled(isRepairRunning)
                        .accessibilityLabel(
                            isRepairRunning ? "修复中" : bannerButtonTitle(snapshot)
                        )
                    }
                }
                .padding(.vertical, 4)
            } else {
                ProgressView("正在检测右键菜单状态…")
                    .controlSize(.small)
            }
        }
        .onAppear(perform: checkStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            checkStatus()
        }
    }

    private func checkStatus() {
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

    private func runRecommendedAction(_ snapshot: RightClickMenuHealthSnapshot) {
        switch snapshot.recommendedRepairAction {
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
        case .none:
            checkStatus()
        }
    }

    private func registerExtension() {
        isRepairRunning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = SystemReloader.registerFinderExtension(appBundleURL: Bundle.main.bundleURL)
            DispatchQueue.main.async {
                isRepairRunning = false
                showFinderExtensionRegistrationOutcome(outcome)
                checkStatus()
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
                    : outcome.restartFinderResult?.errorDescription ?? "请手动重启 Finder",
                isSuccess: outcome.isSuccess
            )
            checkStatus()
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
                    content: outcome.relaunchResult?.errorDescription ?? "请手动重新打开右键助手",
                    isSuccess: false
                )
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func bannerTitle(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        switch snapshot.healthLevel {
        case .healthy: return "Finder 右键菜单可用"
        case .warning: return "Finder 右键菜单需要检查"
        case .critical: return "Finder 右键菜单不可用"
        }
    }

    private func bannerSubtitle(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        switch snapshot.recommendedRepairAction {
        case .none:
            return "扩展心跳与动作队列状态正常"
        case .openFullDiskAccessSettings:
            return "受保护目录的文件操作可能受限"
        case .registerExtension:
            return "扩展未注册或尚未启用"
        case .restartFinder:
            return "扩展状态尚未刷新"
        case .relaunchAppAndRestartFinder:
            return "主程序与 Finder 需要重新加载"
        }
    }

    private func bannerButtonTitle(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        switch snapshot.recommendedRepairAction {
        case .none: return "重新检测"
        case .openFullDiskAccessSettings: return "权限设置"
        case .registerExtension: return "注册扩展"
        case .restartFinder: return "重启 Finder"
        case .relaunchAppAndRestartFinder: return "重新打开"
        }
    }

    private func bannerIcon(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        switch snapshot.healthLevel {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .critical: return "xmark.circle.fill"
        }
    }

    private func bannerColor(_ snapshot: RightClickMenuHealthSnapshot) -> Color {
        switch snapshot.healthLevel {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
