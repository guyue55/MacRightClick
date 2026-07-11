import SwiftUI
import FinderSync

struct PermissionsSettingsView: View {
    @State private var hasFullDiskAccess = false
    @State private var hasLoadedInitialFullDiskAccess = false
    @State private var didPromptAfterFullDiskAccessGrant = false
    @State private var shouldShowManualRelaunchFallback = false
    @State private var shouldEnableiCloudMenu = false
    @State private var watchedDirectoryPaths: [String] = []
    @State private var watchScope: WatchScope = .everywhere
    // 改事件驱动：不再用 2s 轮询，避免 App 在后台空跑 timer。
    // 状态刷新由三处事件触发：onAppear、willBecomeActive（用户从系统设置切回时）、
    // 以及 FDA HStack 内的「重新检测」按钮（用户已知刚授权完想立刻确认）。

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label("完全磁盘访问权限", systemImage: "lock.shield")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: hasFullDiskAccess ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(hasFullDiskAccess ? .green : .orange)
                            .frame(width: 30, height: 30)
                            .background((hasFullDiskAccess ? Color.green : Color.orange).opacity(0.15))
                            .cornerRadius(7)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(hasFullDiskAccess ? "已授权" : "尚未授权")
                                .font(.system(size: 13, weight: .semibold))
                            Text(hasFullDiskAccess ? "部分受保护目录的文件操作会更稳定。" : "部分深层文件和系统目录操作可能受限。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("打开系统设置") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("重新检测") {
                            refresh(promptOnFullDiskAccessGrant: true)
                            SharedHUDManager.show(
                                title: hasFullDiskAccess ? "已授权" : "尚未授权",
                                content: hasFullDiskAccess
                                    ? "完全磁盘访问权限已生效。如右键菜单仍未刷新，请重新打开应用并重启 Finder。"
                                    : "如果刚刚已授权但尚未生效，请使用下方修复按钮重新打开并重启 Finder",
                                isSuccess: hasFullDiskAccess
                            )
                        }
                        .buttonStyle(.bordered)
                    }

                    if shouldShowManualRelaunchFallback {
                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Label(
                                "如果刚刚已在系统设置授权，请重新打开右键助手并重启 Finder",
                                systemImage: "arrow.clockwise.circle.fill"
                            )
                            .font(.caption)
                            .foregroundColor(.orange)

                            HStack(spacing: 10) {
                                Button("重新打开并重启 Finder") {
                                    relaunchAppAndRestartFinderAfterPermissionChange()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("仅重启 Finder") {
                                    restartFinderAfterPermissionChange()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(label: Label("云同步盘兼容", systemImage: "icloud")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("额外监听 iCloud、OneDrive 与 CloudStorage", isOn: Binding(
                        get: { shouldEnableiCloudMenu },
                        set: { newValue in
                            guard SharedStorageManager.shared.setBool(
                                newValue,
                                forKey: "shouldEnableiCloudMenu"
                            ) else {
                                showConfigurationSaveFailure("云同步盘兼容")
                                return
                            }
                            shouldEnableiCloudMenu = newValue
                            postConfigChanged()
                        }
                    ))
                    .toggleStyle(.checkbox)

                    Text("某些云同步目录由系统 File Provider 托管，开启后会额外注册常见云盘位置。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(label: Label("右键菜单作用范围", systemImage: "scope")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("作用范围", selection: Binding(
                        get: { watchScope },
                        set: { newValue in
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
                    )) {
                        Text("所有目录").tag(WatchScope.everywhere)
                        Text("仅自定义目录").tag(WatchScope.custom)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(watchScope == .everywhere
                         ? "默认在 Finder 任意目录显示右键菜单（推荐）。"
                         : "仅在下方自定义列表中的目录显示右键菜单，适合隐私敏感或希望降低 FinderSync 注册面的场景。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(label: Label("Finder 菜单监听目录", systemImage: "folder.badge.gearshape")) {
                VStack(alignment: .leading, spacing: 10) {
                    if watchedDirectoryPaths.isEmpty {
                        Text("暂无监听目录")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(watchedDirectoryPaths, id: \.self) { path in
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(.accentColor)
                                Text(path)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("移除") {
                                    removeWatchedDirectory(path)
                                }
                            }
                        }
                    }

                    HStack {
                        Button("添加目录") {
                            addWatchedDirectory()
                        }
                        Button("恢复默认目录") {
                            resetWatchedDirectories()
                        }
                    }
                    if watchScope == .everywhere {
                        Text("当前作用范围为「所有目录」，自定义列表暂不生效。切回「仅自定义目录」即可启用此处配置。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(watchScope == .everywhere)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { refresh(promptOnFullDiskAccessGrant: false) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            refresh(promptOnFullDiskAccessGrant: true)
        }
    }

    private func refresh(promptOnFullDiskAccessGrant: Bool) {
        shouldEnableiCloudMenu = SharedStorageManager.shared.getBool(forKey: "shouldEnableiCloudMenu", defaultValue: false)
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
