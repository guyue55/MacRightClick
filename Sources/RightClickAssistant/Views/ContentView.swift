import SwiftUI
import FinderSync


/// 侧边栏导航条目
enum SidebarItem: String, CaseIterable, Identifiable {
    case overview = "overview"
    case actions = "actions"
    case permissions = "permissions"
    case diagnostics = "diagnostics"
    case advanced = "advanced"
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .overview: return "概览"
        case .actions: return "动作"
        case .permissions: return "权限"
        case .diagnostics: return "诊断"
        case .advanced: return "高级"
        }
    }
    
    var iconName: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .actions: return "list.bullet.rectangle"
        case .permissions: return "lock.shield"
        case .diagnostics: return "waveform.path.ecg"
        case .advanced: return "exclamationmark.triangle"
        }
    }
}

public struct ContentView: View {
    @State private var selectedTab: SidebarItem = .overview
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            // 1. 侧边栏
            List(SidebarItem.allCases, selection: $selectedTab) { item in
                NavigationLink(value: item) {
                    Label(item.title, systemImage: item.iconName)
                        .font(.headline)
                        .padding(.vertical, 4)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("导航")
            .frame(minWidth: 200)
            
        } detail: {
            // 2. 细节主面板
            VStack(alignment: .leading, spacing: 0) {
                // 顶部毛玻璃标题栏
                HStack {
                    Text(selectedTab.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Spacer()
                    Text("免费开源")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().stroke(Color.secondary, lineWidth: 1))
                }
                .padding()
                .background(.thinMaterial)
                
                Divider()
                
                // 根据当前选项卡，动态渲染内容
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .overview:
                            OverviewSettingsView()
                        case .actions:
                            ActionsHubView()
                        case .permissions:
                            PermissionsSettingsView()
                        case .diagnostics:
                            DiagnosticsSettingsView()
                        case .advanced:
                            AdvancedSettingsView()
                        }
                    }
                    .padding()
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 850, minHeight: 600)
    }
}

// MARK: - A. 新信息架构页面
struct OverviewSettingsView: View {
    @State private var isLaunchEnabled = false

    private var launchEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.isLaunchEnabled },
            set: { newValue in
                self.isLaunchEnabled = newValue
                let success = LaunchServiceManager.shared.setEnabled(newValue)
                if success {
                    SharedStorageManager.shared.setBool(newValue, forKey: "shouldStartOnLaunch")
                    SharedHUDManager.show(
                        title: newValue ? "开机自启已启用" : "开机自启已禁用",
                        content: newValue ? "右键助手会随登录启动" : "已从登录项移除",
                        iconName: newValue ? "bolt.fill" : "bolt.slash.fill",
                        isSuccess: true
                    )
                } else {
                    self.isLaunchEnabled = LaunchServiceManager.shared.isEnabled
                    SharedHUDManager.show(
                        title: "自启设置失败",
                        content: "请前往系统设置检查登录项权限",
                        isSuccess: false
                    )
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ExtensionStatusBanner()
                .padding(.horizontal, -16)
                .padding(.top, -16)

            // 扩展注册入口——始终可见，不受 isExtensionEnabled 检测影响
            ExtensionRegistrationBox()

            GroupBox(label: Label("常用", systemImage: "slider.horizontal.3")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("登录时启动右键助手", isOn: launchEnabledBinding)
                        .toggleStyle(.checkbox)

                    Text("保持后台服务可用，Finder 右键动作可以随时由宿主 App 处理。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    Toggle("显示成功提示", isOn: Binding(
                        get: { SharedStorageManager.shared.getBool(forKey: "enable_success_hud", defaultValue: true) },
                        set: { SharedStorageManager.shared.setBool($0, forKey: "enable_success_hud") }
                    ))
                    .toggleStyle(.checkbox)

                    Text("关闭后，成功动作保持静默；失败和权限问题仍会提示。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(label: Label("项目", systemImage: "info.circle")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("开源右键助手 (RightClickAssistant) v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                        .font(.headline)
                    Text("免费开源，采用 MIT 协议。项目不包含广告，也不会主动收集使用数据。")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Button("访问 GitHub 源码仓库") {
                        if let url = URL(string: "https://github.com/guyue55/MacRightClick") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 5)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            isLaunchEnabled = LaunchServiceManager.shared.isEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            isLaunchEnabled = LaunchServiceManager.shared.isEnabled
        }
    }
}

struct PermissionsSettingsView: View {
    @State private var hasFullDiskAccess = false
    @State private var shouldEnableiCloudMenu = false
    @State private var watchedDirectoryPaths: [String] = []
    let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

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
                            shouldEnableiCloudMenu = newValue
                            SharedStorageManager.shared.setBool(newValue, forKey: "shouldEnableiCloudMenu")
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
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        shouldEnableiCloudMenu = SharedStorageManager.shared.getBool(forKey: "shouldEnableiCloudMenu", defaultValue: false)
        watchedDirectoryPaths = SharedStorageManager.shared.watchedDirectoryURLs.map(\.path)
        checkFullDiskAccess()
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
        SharedStorageManager.shared.removeValue(forKey: SharedStorageManager.Keys.watchedDirectoryPaths)
        refresh()
        postConfigChanged()
    }

    private func saveWatchedDirectories(_ paths: [String]) {
        watchedDirectoryPaths = paths
        SharedStorageManager.shared.setStringArray(paths, forKey: SharedStorageManager.Keys.watchedDirectoryPaths)
        postConfigChanged()
    }

    private func checkFullDiskAccess() {
        // 通过尝试访问用户 Safari 目录来检测完全磁盘访问权限。
        // /Library/Application Support/com.apple.TCC 受 SIP 保护，即使授予 FDA 也无法读取。
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testPath = home.appendingPathComponent("Library/Safari").path
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: testPath)
            hasFullDiskAccess = true
        } catch {
            hasFullDiskAccess = false
        }
    }
}

struct DiagnosticsSettingsView: View {
    @State private var isExtensionEnabled = false
    @State private var isDebugLoggingEnabled = false
    @State private var pendingCount = 0
    @State private var failedCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label("状态", systemImage: "waveform.path.ecg")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(isExtensionEnabled ? "Finder 扩展已启用" : "Finder 扩展未启用", systemImage: isExtensionEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(isExtensionEnabled ? .green : .orange)
                        Spacer()
                        Button("重新检测") {
                            refresh()
                        }
                    }

                    HStack(spacing: 16) {
                        Label("待处理: \(pendingCount)", systemImage: "tray")
                            .foregroundColor(pendingCount > 0 ? .accentColor : .secondary)
                        Label("失败: \(failedCount)", systemImage: "tray.and.arrow.down")
                            .foregroundColor(failedCount > 0 ? .red : .secondary)
                    }
                    .font(.callout)

                    Button("打开扩展设置") {
                        if #available(macOS 13.0, *),
                           let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
                            NSWorkspace.shared.open(url)
                        } else {
                            FIFinderSyncController.showExtensionManagementInterface()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 8)
            }

            GroupBox(label: Label("日志", systemImage: "doc.text.magnifyingglass")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("启用详细调试日志", isOn: Binding(
                        get: { isDebugLoggingEnabled },
                        set: { newValue in
                            isDebugLoggingEnabled = newValue
                            SharedStorageManager.shared.setBool(newValue, forKey: SharedStorageManager.Keys.enableDebugLogging)
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
                        Button("显示共享目录") {
                            NSWorkspace.shared.open(SharedStorageManager.shared.sharedContainerURL)
                        }
                        Button("运行快速诊断") {
                            refresh()
                            SharedHUDManager.show(
                                title: "诊断完成",
                                content: isExtensionEnabled ? "Finder 扩展已启用" : "Finder 扩展未启用",
                                isSuccess: isExtensionEnabled
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        isExtensionEnabled = FIFinderSyncController.isExtensionEnabled
        isDebugLoggingEnabled = SharedStorageManager.shared.isDebugLoggingEnabled
        pendingCount = SharedStorageManager.shared.pendingActionCount
        failedCount = SharedStorageManager.shared.failedActionCount
    }
}

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

            GroupBox(label: Label("恢复", systemImage: "arrow.counterclockwise")) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("恢复动作默认设置")
                            .font(.body)
                        Text("移除所有动作启用状态配置，重新使用内置默认值。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("恢复默认") {
                        resetActionDefaults()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func resetActionDefaults() {
        for action in ActionDispatcher.shared.allActions {
            SharedStorageManager.shared.removeValue(forKey: "enable_action_\(action.actionId)")
        }
        postConfigChanged()
        refreshID = UUID()
        SharedHUDManager.show(title: "已恢复默认", content: "右键动作将按内置默认值显示", isSuccess: true)
    }
}

private func postConfigChanged() {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("guyue.RightClickAssistant.configChanged"),
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
}

// MARK: - B. 动作管理统一面板（根据不同分类渲染）
struct ActionsHubView: View {
    @State private var selectedCategory: ActionCategory = .newFile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择要显示在 Finder 右键菜单中的动作。星标动作会出现在右键菜单的“常用”分组中。")
                .font(.body)
                .foregroundColor(.secondary)

            Picker("动作分类", selection: $selectedCategory) {
                ForEach(ActionCategory.allCases) { category in
                    Text(category.localizedName).tag(category)
                }
            }
            .pickerStyle(.segmented)

            ActionsManagerView(category: selectedCategory, includeAdvanced: false)
        }
    }
}

struct ActionsManagerView: View {
    let category: ActionCategory
    var includeAdvanced: Bool = true
    var showsIdentifiers: Bool = false
    
    private var items: [ActionItem] {
        let actions = ActionDispatcher.shared.actions(in: category)
        return actions.map { ActionItem(id: $0.actionId, action: $0) }
    }

    private var standardItems: [ActionItem] {
        items.filter { $0.action.settingsGroup == .standard }
    }

    private var advancedItems: [ActionItem] {
        items.filter { $0.action.settingsGroup == .advanced }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("您可以在下方自由勾选启用或禁用具体的右键菜单项。禁用的条目将不会出现在您的访达右键中。")
                .font(.body)
                .foregroundColor(.secondary)
            
            ActionListGroupView(
                title: "\(category.localizedName)列表",
                iconName: "list.bullet.indent",
                items: standardItems,
                showsIdentifiers: showsIdentifiers
            )

            if includeAdvanced && !advancedItems.isEmpty {
                ActionListGroupView(
                    title: "高级功能（默认关闭）",
                    iconName: "exclamationmark.triangle",
                    items: advancedItems,
                    showsIdentifiers: showsIdentifiers,
                    footer: "这些动作可能永久删除文件、重启 Finder 或跨目录复制/移动项目。请确认自己理解影响后再启用。"
                )
            }
        }
    }
}

struct ActionListGroupView: View {
    let title: String
    let iconName: String
    let items: [ActionItem]
    var showsIdentifiers: Bool = false
    var footer: String? = nil

    var body: some View {
        GroupBox(label: Label(title, systemImage: iconName)) {
            VStack(alignment: .leading, spacing: 4) {
                if items.isEmpty {
                    Text("暂无可用动作")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(items) { item in
                        ActionRowView(action: item.action, showsIdentifier: showsIdentifiers)
                        if item.id != items.last?.id {
                            Divider()
                        }
                    }
                }

                if let footer = footer {
                    Divider()
                        .padding(.vertical, 4)
                    Text(footer)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

/// 单个动作的 Toggle 封装组件
struct ActionRowView: View {
    let action: MenuAction
    var showsIdentifier: Bool = false
    
    // 通过 actionId 绑定到 AppGroup 共享的 UserDefaults 中，让 Extension 动态读取是否渲染
    @State private var isEnabled = true
    @State private var isFavorite = false
    
    var body: some View {
        HStack(spacing: 12) {
            if let icon = action.iconName {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(6)
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(action.localizedTitle)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if let bundleId = action.associatedBundleIdentifier {
                        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) == nil {
                            Text("未检测到应用")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        }
                    }

                    if action.isHighRisk {
                        Text("高级")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.orange.opacity(0.14)))
                    }
                }
                if showsIdentifier {
                    Text("动作 ID: \(action.actionId)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                if let riskDescription = action.riskDescription {
                    Text(riskDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "从常用分组移除" : "加入常用分组")
            
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: isEnabled) { newValue in
                    saveStateToSharedDefaults(newValue)
                }
        }
        .padding(.vertical, 6)
        .onAppear {
            loadStateFromSharedDefaults()
            loadFavoriteState()
        }
    }
    
    private func saveStateToSharedDefaults(_ enabled: Bool) {
        SharedStorageManager.shared.setBool(enabled, forKey: "enable_action_\(action.actionId)")
        // 发送分布式通知让 FinderSync 插件知道配置已经发生变动，即时刷新菜单内容
        postConfigChanged()
    }
    
    private func loadStateFromSharedDefaults() {
        isEnabled = SharedStorageManager.shared.getBool(
            forKey: "enable_action_\(action.actionId)",
            defaultValue: action.isEnabledByDefault
        )
    }

    private func loadFavoriteState() {
        isFavorite = SharedStorageManager.shared.isFavoriteAction(action)
    }

    private func toggleFavorite() {
        isFavorite.toggle()
        SharedStorageManager.shared.setAction(action, favorite: isFavorite)
        postConfigChanged()
    }
}

/// 专为规避 Swift 6 协议 existential 动态类型推导编译挂起设计的具体实体结构
struct ActionItem: Identifiable {
    let id: String
    let action: MenuAction
}

// MARK: - C2. 扩展注册入口（始终可见，不依赖检测状态）
/// 始终显示的扩展注册组件，不受 isExtensionEnabled 检测结果影响。
/// 即使用户看到"已启用"绿色横幅，下方仍可主动重新注册扩展。
struct ExtensionRegistrationBox: View {
    @State private var isRegistering = false

    var body: some View {
        GroupBox(label: Label("扩展注册", systemImage: "bolt.shield")) {
            VStack(alignment: .leading, spacing: 10) {
                Text("若右键菜单未出现，点击下方按钮自动注册 Finder 扩展。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Button(action: {
                        isRegistering = true
                        autoRegisterExtension()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isRegistering = false
                        }
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
                        if #available(macOS 13.0, *),
                           let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
                            NSWorkspace.shared.open(url)
                        } else {
                            FIFinderSyncController.showExtensionManagementInterface()
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 12))
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func autoRegisterExtension() {
        guard let appPath = Bundle.main.bundleURL.path as String? else {
            SharedHUDManager.show(title: "注册失败", content: "无法定位 App 路径", isSuccess: false)
            return
        }
        let extPath = (appPath as NSString).appendingPathComponent("Contents/PlugIns/RightClickAssistantExtension.appex")

        guard FileManager.default.fileExists(atPath: extPath) else {
            SharedHUDManager.show(title: "注册失败", content: "未找到扩展组件", isSuccess: false)
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        proc.arguments = ["-a", extPath]

        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                SharedHUDManager.show(title: "注册成功", content: "扩展已注册，重启 Finder 后生效", isSuccess: true)
            } else {
                SharedHUDManager.show(title: "注册失败", content: "pluginkit 返回码: \(proc.terminationStatus)", isSuccess: false)
            }
        } catch {
            SharedHUDManager.show(title: "注册失败", content: error.localizedDescription, isSuccess: false)
        }
    }
}

// MARK: - C. 访达右键扩展集成状态自检 Banner
struct ExtensionStatusBanner: View {
    @State private var isEnabled = false
    @State private var isPulsing = false
    
    // 1.5 秒定时器进行保底状态查询 (以防部分平铺多窗口操作时未触发 willBecomeActive)
    let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Group {
            if isEnabled {
                // 已激活 Banner
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.green)
                        .frame(width: 32, height: 32)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("右键助手扩展服务已启用")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                            Text("Finder 扩展正在运行。您可以在下方管理右键动作。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Pulsing Dot 动态呼吸灯
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [Color.green.opacity(0.08), Color.teal.opacity(0.03)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
                .padding(.top, 16)
            } else {
                // 未激活 Banner + 步骤引导
                VStack(alignment: .leading, spacing: 14) {
                    // 1. 顶部的紧凑式提醒 Row
                    HStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.orange)
                            .frame(width: 32, height: 32)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("访达右键扩展尚未启用")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("右键助手需要系统扩展授权才能正常运行，请按下方指引开启服务。")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            openExtensionSettings()
                        }) {
                            HStack(spacing: 5) {
                                Text("打开扩展设置")
                                Image(systemName: "arrow.up.forward.app.fill")
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }

                    // 一键注册扩展独立成行，避免与上方按钮挤在同一 HStack 中被截断
                    HStack {
                        Spacer()
                        Button(action: {
                            autoRegisterExtension()
                        }) {
                            HStack(spacing: 5) {
                                Text("一键注册扩展")
                                Image(systemName: "bolt.fill")
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    
                    Divider()
                        .background(Color.orange.opacity(0.15))
                    
                    // 2. 动态检测并呈现对应的系统版本引导
                    OnboardingStepsView()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [Color.orange.opacity(0.06), Color.orange.opacity(0.01)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
                .padding(.horizontal)
                .padding(.top, 16)
            }
        }
        .onAppear {
            checkStatus()
        }
        .onReceive(timer) { _ in
            checkStatus()
        }
        // 监听系统 willBecomeActive 通知：用户在系统设置中勾选后，切回 App 时刷新状态。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            checkStatus()
        }
    }
    
    private func checkStatus() {
        isEnabled = FIFinderSyncController.isExtensionEnabled
    }

    /// 智能打开扩展管理面板：优先用 URL Scheme 直达，失败回退到系统 API。
    private func openExtensionSettings() {
        // macOS 13+ 推荐使用 URL Scheme 定位扩展面板，避免跳转到通用设置页。
        if #available(macOS 13.0, *) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
                NSWorkspace.shared.open(url)
                return
            }
        }
        FIFinderSyncController.showExtensionManagementInterface()
    }

    /// 通过 pluginkit 命令行自动注册 Finder 扩展，无需用户手动在系统设置中翻找。
    private func autoRegisterExtension() {
        guard let appBundle = Bundle.main.bundleURL.path as String? else {
            SharedHUDManager.show(title: "注册失败", content: "无法定位 App Bundle 路径", isSuccess: false)
            return
        }
        let extPath = (appBundle as NSString).appendingPathComponent("Contents/PlugIns/RightClickAssistantExtension.appex")
        
        guard FileManager.default.fileExists(atPath: extPath) else {
            SharedHUDManager.show(
                title: "注册失败",
                content: "未找到扩展组件，请确认 App 未被移动或损坏",
                isSuccess: false
            )
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-a", extPath]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                SharedHUDManager.show(
                    title: "注册成功",
                    content: "扩展已注册，请重启 Finder 或稍候生效",
                    isSuccess: true
                )
                // 注册后延迟刷新状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.checkStatus()
                }
            } else {
                SharedHUDManager.show(
                    title: "注册失败",
                    content: "pluginkit 返回错误码 \(process.terminationStatus)",
                    isSuccess: false
                )
            }
        } catch {
            SharedHUDManager.show(
                title: "注册失败",
                content: "无法执行 pluginkit: \(error.localizedDescription)",
                isSuccess: false
            )
        }
    }
}

// MARK: - Onboarding Walkthrough Views

/// 智能适配 macOS 系统版本的扩展激活步骤面板
struct OnboardingStepsView: View {
    // 识别当前操作系统大/小版本号
    private var systemVersion: (major: Int, minor: Int) {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return (os.majorVersion, os.minorVersion)
    }
    
    // 是否为 macOS 13 (Ventura) 及更高版本（该版本后苹果全面改版为“系统设置”单列样式）
    private var isVenturaOrNewer: Bool {
        systemVersion.major >= 13
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
            
            if isVenturaOrNewer {
                // macOS 13+ 新版"系统设置"引导路径
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
            } else {
                // macOS 12 及以下旧版"系统偏好设置"引导路径
                VStack(alignment: .leading, spacing: 10) {
                    StepRow(
                        step: 1,
                        iconName: "bolt.fill",
                        title: "推荐：点击「一键注册扩展」",
                        desc: "应用将自动执行 pluginkit 注册，无需手动操作系统偏好设置。"
                    )

                    StepRow(
                        step: 2,
                        iconName: "macwindow.and.cursorarrow",
                        title: "或手动：打开扩展管理面板",
                        desc: "点击「打开扩展设置」按钮，系统将打开「系统偏好设置 -> 扩展」，在左侧选择「访达」后勾选「右键助手扩展」。"
                    )
                    
                    StepRow(
                        step: 3,
                        iconName: "checkmark.square.fill",
                        title: "确认扩展已启用",
                        desc: "勾选后回到本页面确认状态变绿。"
                    )
                }
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
