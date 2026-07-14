import SwiftUI
import FinderSync

struct PermissionsSettingsView: View {
    @State private var hasFullDiskAccess = false
    @State private var hasLoadedInitialFullDiskAccess = false
    @State private var didPromptAfterFullDiskAccessGrant = false
    @State private var shouldShowManualRelaunchFallback = false
    @State private var shouldEnableiCloudMenu = true
    @State private var watchedDirectoryPaths: [String] = []
    @State private var watchScope: WatchScope = .everywhere
    // 改事件驱动：不再用 2s 轮询，避免 App 在后台空跑 timer。
    // 状态刷新由三处事件触发：onAppear、willBecomeActive（用户从系统设置切回时）、
    // 以及 FDA HStack 内的「重新检测」按钮（用户已知刚授权完想立刻确认）。

    var body: some View {
        Form {
            Section("Finder 扩展") {
                ExtensionRegistrationBox()
            }

            Section("右键菜单范围") {
                Picker("作用范围", selection: Binding(
                    get: { watchScope },
                    set: saveWatchScope
                )) {
                    Text("所有目录").tag(WatchScope.everywhere)
                    Text("仅自定义目录").tag(WatchScope.custom)
                }
                .pickerStyle(.segmented)

                Toggle("兼容 iCloud、OneDrive 与 CloudStorage", isOn: Binding(
                    get: { shouldEnableiCloudMenu },
                    set: saveCloudCompatibility
                ))

                LabeledContent("File Provider 降级入口") {
                    Text("服务 > 右键助手…")
                        .foregroundStyle(.secondary)
                }
            }

            Section("自定义目录") {
                if watchedDirectoryPaths.isEmpty {
                    Text("暂无目录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(watchedDirectoryPaths, id: \.self) { path in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(path)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                removeWatchedDirectory(path)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .help("移除目录")
                            .accessibilityLabel("移除目录 \(path)")
                        }
                    }
                }

                HStack {
                    Button(action: addWatchedDirectory) {
                        Label("添加目录", systemImage: "plus")
                    }
                    Button(action: resetWatchedDirectories) {
                        Label("恢复默认", systemImage: "arrow.counterclockwise")
                    }
                }

                if watchScope == .everywhere {
                    Text("当前使用所有目录，自定义目录列表未启用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(watchScope == .everywhere)

            Section("文件访问") {
                HStack(spacing: 10) {
                    Label(
                        hasFullDiskAccess ? "完全磁盘访问已授权" : "完全磁盘访问尚未授权",
                        systemImage: hasFullDiskAccess
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle.fill"
                    )
                    .foregroundStyle(hasFullDiskAccess ? Color.green : Color.orange)

                    Spacer()

                    Button {
                        if let url = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("系统设置", systemImage: "gearshape")
                    }

                    Button {
                        refresh(promptOnFullDiskAccessGrant: true)
                    } label: {
                        Label("重新检测", systemImage: "arrow.clockwise")
                    }
                }

                if shouldShowManualRelaunchFallback {
                    HStack {
                        Button("重新打开并重启 Finder") {
                            relaunchAppAndRestartFinderAfterPermissionChange()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("仅重启 Finder") {
                            restartFinderAfterPermissionChange()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refresh(promptOnFullDiskAccessGrant: false) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            refresh(promptOnFullDiskAccessGrant: true)
        }
    }

    private func saveWatchScope(_ newValue: WatchScope) {
        guard SharedStorageManager.shared.setStringArray(
            [newValue.rawValue],
            forKey: SharedStorageManager.Keys.watchScope
        ) else {
            showConfigurationSaveFailure("右键菜单作用范围")
            return
        }
        watchScope = newValue
        postConfigChanged()
    }

    private func saveCloudCompatibility(_ enabled: Bool) {
        guard SharedStorageManager.shared.setBool(
            enabled,
            forKey: SharedStorageManager.Keys.cloudCompatibility
        ) else {
            showConfigurationSaveFailure("云同步盘兼容")
            return
        }
        shouldEnableiCloudMenu = enabled
        postConfigChanged()
    }

    private func refresh(promptOnFullDiskAccessGrant: Bool) {
        shouldEnableiCloudMenu = SharedStorageManager.shared.isCloudCompatibilityEnabled
        watchScope = SharedStorageManager.shared.watchScope
        // UI 永远展示用户的「自定义目录」原始列表（即使当前作用范围是 .everywhere，
        // 切回 .custom 时仍保留之前的自定义配置，避免来回切换丢数据）。
        watchedDirectoryPaths = SharedStorageManager.shared.customWatchedDirectoryPathsForUI
        checkFullDiskAccess(promptOnGrant: promptOnFullDiskAccessGrant)
    }

    private func addWatchedDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "添加"

        if panel.runModal() == .OK, let url = panel.url {
            var paths = watchedDirectoryPaths
            if !paths.contains(url.path) {
                paths.append(url.path)
                saveWatchedDirectories(paths)
            }
        }
    }

    private func removeWatchedDirectory(_ path: String) {
        saveWatchedDirectories(watchedDirectoryPaths.filter { $0 != path })
    }

    private func resetWatchedDirectories() {
        guard SharedStorageManager.shared.removeValue(
            forKey: SharedStorageManager.Keys.watchedDirectoryPaths
        ) else {
            showConfigurationSaveFailure("监听目录")
            return
        }
        refresh(promptOnFullDiskAccessGrant: false)
        postConfigChanged()
    }

    private func saveWatchedDirectories(_ paths: [String]) {
        guard SharedStorageManager.shared.setStringArray(
            paths,
            forKey: SharedStorageManager.Keys.watchedDirectoryPaths
        ) else {
            showConfigurationSaveFailure("监听目录")
            return
        }
        watchedDirectoryPaths = paths
        postConfigChanged()
    }

    private func checkFullDiskAccess(promptOnGrant: Bool) {
        let previous = hasFullDiskAccess
        let current = FullDiskAccessChecker.hasFullDiskAccess()
        hasFullDiskAccess = current

        if current {
            shouldShowManualRelaunchFallback = false
        } else if promptOnGrant && hasLoadedInitialFullDiskAccess {
            shouldShowManualRelaunchFallback = PermissionRefreshCoordinator
                .shouldOfferManualRelaunchFallback(currentFullDiskAccess: current)
        }

        let shouldPrompt = PermissionRefreshCoordinator.shouldPromptAfterGrant(
            previous: previous,
            current: current,
            hasLoadedInitialState: hasLoadedInitialFullDiskAccess,
            didPrompt: didPromptAfterFullDiskAccessGrant
        )

        defer { hasLoadedInitialFullDiskAccess = true }

        guard promptOnGrant, shouldPrompt else {
            return
        }

        didPromptAfterFullDiskAccessGrant = true
        promptRestartFinderAfterFullDiskAccessGrant()
    }

    private func promptRestartFinderAfterFullDiskAccessGrant() {
        let alert = NSAlert()
        alert.messageText = "完全磁盘访问权限已生效"
        alert.informativeText = "macOS 可能不会把新权限热更新给已运行的主程序和 Finder 扩展。建议重新打开右键助手并重启 Finder，让右键菜单和文件操作按新权限加载。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "重新打开并重启 Finder")
        alert.addButton(withTitle: "仅重启 Finder")
        alert.addButton(withTitle: "稍后")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            relaunchAppAndRestartFinderAfterPermissionChange()
        case .alertSecondButtonReturn:
            restartFinderAfterPermissionChange()
        default:
            break
        }
    }

    private func relaunchAppAndRestartFinderAfterPermissionChange() {
        SharedHUDManager.show(
            title: "正在重新打开",
            content: "正在启动新进程，随后会让 Finder 按新权限刷新",
            isSuccess: true
        )

        PermissionRefreshCoordinator.performReload(
            choice: .relaunchAppAndRestartFinder,
            bundleURL: Bundle.main.bundleURL
        ) { outcome in
            guard outcome.isSuccess else {
                SharedHUDManager.show(
                    title: "重新打开失败",
                    content: outcome.relaunchResult?.errorDescription
                        ?? "请手动退出并重新打开右键助手，然后重启 Finder",
                    isSuccess: false
                )
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func restartFinderAfterPermissionChange() {
        SharedHUDManager.show(
            title: "正在重启 Finder",
            content: "右键菜单会在 Finder 重新打开后按新权限刷新",
            isSuccess: true
        )

        PermissionRefreshCoordinator.performReload(
            choice: .restartFinderOnly,
            bundleURL: Bundle.main.bundleURL
        ) { outcome in
            if !outcome.isSuccess {
                SharedHUDManager.show(
                    title: "Finder 重启失败",
                    content: outcome.restartFinderResult?.errorDescription
                        ?? "请手动重启 Finder 或重新登录后再试",
                    isSuccess: false
                )
            }
        }
    }
}
