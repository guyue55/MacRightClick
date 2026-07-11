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

// MARK: - C2. 扩展注册入口（始终可见，不依赖检测状态）
/// 仅在扩展已启用时显示的「修复入口」。未启用时由 ExtensionStatusBanner 内部承担引导职责，
/// 此组件保持隐藏，避免双入口冲淡新用户的引导路径。
struct ExtensionRegistrationBox: View {
    @State private var isRegistering = false
    @State private var isExtensionEnabled = FIFinderSyncController.isExtensionEnabled

    var body: some View {
        // 仅在扩展已启用时作为「修复入口」出现：
        // - 未启用：上方 ExtensionStatusBanner 已经承担引导职责，再叠加一个 GroupBox 会让用户被双入口分心
        // - 已启用：右键菜单偶发失灵时（比如重装 macOS、冷启动 Finder 异常），用户在这里点一下即可重注册
        Group {
            if isExtensionEnabled {
                registrationGroupBox
            } else {
                EmptyView()
            }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        isExtensionEnabled = FIFinderSyncController.isExtensionEnabled
    }

    private var registrationGroupBox: some View {
        GroupBox(label: Label("扩展修复", systemImage: "bolt.shield")) {
            VStack(alignment: .leading, spacing: 10) {
                Text("如果右键菜单出现异常，可点击下方按钮重新注册 Finder 扩展。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Button(action: {
                        isRegistering = true
                        autoRegisterExtension()
                    }) {
                        HStack(spacing: 6) {
                            if isRegistering {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            }
                            Text(isRegistering ? "注册中…" : "一键注册扩展")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isRegistering)

                    Button("打开系统设置") {
                        openFinderExtensionSettings()
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 12))
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func autoRegisterExtension() {
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

// MARK: - C. 访达右键扩展集成状态自检 Banner
struct ExtensionStatusBanner: View {
    @State private var snapshot: RightClickMenuHealthSnapshot?
    @State private var isPulsing = false
    @State private var isRepairRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot {
                HStack(spacing: 14) {
                    Image(systemName: bannerIcon(snapshot))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(bannerColor(snapshot))
                        .frame(width: 32, height: 32)
                        .background(bannerColor(snapshot).opacity(0.15))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(bannerTitle(snapshot))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Text(bannerSubtitle(snapshot))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if snapshot.healthLevel == .healthy {
                        HStack(spacing: 6) {
                            Text("运行中")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.green)

                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .scaleEffect(isPulsing ? 1.3 : 0.8)
                                .opacity(isPulsing ? 1.0 : 0.4)
                                .onAppear {
                                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                                        isPulsing = true
                                    }
                                }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                    } else {
                        Button(action: { runRecommendedAction(snapshot) }) {
                            HStack(spacing: 5) {
                                Text(bannerButtonTitle(snapshot))
                                Image(systemName: "arrow.clockwise")
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(bannerColor(snapshot))
                        .disabled(isRepairRunning)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [bannerColor(snapshot).opacity(0.08), bannerColor(snapshot).opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(bannerColor(snapshot).opacity(0.22), lineWidth: 1)
                )

                if snapshot.recommendedRepairAction == .registerExtension {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider()
                            .background(Color.orange.opacity(0.15))
                        OnboardingStepsView()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.orange.opacity(0.04))
                    .cornerRadius(12)
                }
            } else {
                ProgressView("正在检测右键菜单状态…")
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .onAppear { checkStatus() }
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
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
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
            if outcome.isSuccess {
                SharedHUDManager.show(title: "Finder 已重启", content: "右键菜单会按最新状态加载", isSuccess: true)
            } else {
                SharedHUDManager.show(
                    title: "Finder 重启失败",
                    content: outcome.restartFinderResult?.errorDescription ?? "请手动重启 Finder 或重新登录后再试",
                    isSuccess: false
                )
            }
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

    private func bannerTitle(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        switch snapshot.healthLevel {
        case .healthy: return "右键助手扩展服务已启用"
        case .warning: return "右键菜单需要刷新"
        case .critical: return "右键菜单需要修复"
        }
    }

    private func bannerSubtitle(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        switch snapshot.recommendedRepairAction {
        case .none:
            return "Finder 扩展正在运行。您可以在下方管理右键动作。"
        case .openFullDiskAccessSettings:
            return "完全磁盘访问尚未生效，部分受保护路径的文件操作可能受限。"
        case .registerExtension:
            return "Finder 扩展未处于可用状态，请一键注册或打开系统扩展设置。"
        case .restartFinder:
            return "扩展已注册，但 Finder 可能仍在使用旧会话，建议重启 Finder。"
        case .relaunchAppAndRestartFinder:
            return "建议重新打开右键助手并重启 Finder，让主程序和扩展同时刷新。"
        }
    }

    private func bannerButtonTitle(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        switch snapshot.recommendedRepairAction {
        case .none: return "重新检测"
        case .openFullDiskAccessSettings: return "打开权限设置"
        case .registerExtension: return isRepairRunning ? "注册中…" : "一键注册扩展"
        case .restartFinder: return "重启 Finder"
        case .relaunchAppAndRestartFinder: return "重新打开"
        }
    }

    private func bannerIcon(_ snapshot: RightClickMenuHealthSnapshot) -> String {
        switch snapshot.healthLevel {
        case .healthy: return "checkmark.shield.fill"
        case .warning: return "arrow.clockwise.circle.fill"
        case .critical: return "exclamationmark.triangle.fill"
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

// MARK: - Onboarding Walkthrough Views

/// 智能适配 macOS 系统版本的扩展激活步骤面板
struct OnboardingStepsView: View {
    // 项目最低 deployment target = macOS 13.0 (build.sh: arm64-apple-macosx13.0)，
    // 因此引导文案统一指向 Ventura+ 的「系统设置」单列样式，不再保留 macOS 12 兜底分支。
    private var systemVersion: (major: Int, minor: Int) {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return (os.majorVersion, os.minorVersion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 系统版本提示条
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text("已识别当前系统为 macOS \(systemVersion.major).\(systemVersion.minor)，请按以下步骤操作：")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.orange.opacity(0.9))
                Spacer()
            }
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 10) {
                StepRow(
                    step: 1,
                    iconName: "bolt.fill",
                    title: "推荐：点击「一键注册扩展」",
                    desc: "点击上方橙色的「一键注册扩展」按钮，应用将通过 pluginkit 自动注册扩展，无需手动翻找系统设置。注册后可能需要重启 Finder。"
                )

                StepRow(
                    step: 2,
                    iconName: "macwindow.and.cursorarrow",
                    title: "或手动：打开扩展管理面板",
                    desc: "点击「打开扩展设置」按钮，在系统设置中找到「扩展」→「访达扩展」，勾选「右键助手扩展」。"
                )

                StepRow(
                    step: 3,
                    iconName: "checkmark.square.fill",
                    title: "确认扩展已启用",
                    desc: "勾选后回到本页面，上方状态应变为「已启用」绿色标识。如仍未显示，请尝试重启 Finder。"
                )
            }
        }
    }
}
/// 每一行步骤卡片，集成 SF Symbols 与醒目数字徽章
struct StepRow: View {
    let step: Int
    let iconName: String
    let title: String
    let desc: String
    var isCrucial: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 数字步骤圆圈徽章
            Text("\(step)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(isCrucial ? Color.red : Color.orange)
                )
                .shadow(color: (isCrucial ? Color.red : Color.orange).opacity(0.3), radius: 2, x: 0, y: 1)
                .padding(.top, 2)

            // SF Symbols 辅助拟真图标
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isCrucial ? .red : .orange)
                .frame(width: 24, height: 24)
                .background((isCrucial ? Color.red : Color.orange).opacity(0.1))
                .cornerRadius(6)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(isCrucial ? .red : .primary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCrucial ? Color.red.opacity(0.04) : Color.primary.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCrucial ? Color.red.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
}
