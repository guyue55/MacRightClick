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
                        if let url = URL(string: "https://github.com/guyue/MacRightClick") {
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
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        shouldEnableiCloudMenu = SharedStorageManager.shared.getBool(forKey: "shouldEnableiCloudMenu", defaultValue: false)
        checkFullDiskAccess()
    }

    private func checkFullDiskAccess() {
        let path = "/Library/Application Support/com.apple.TCC"
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: path)
            hasFullDiskAccess = true
        } catch {
            hasFullDiskAccess = false
        }
    }
}

struct DiagnosticsSettingsView: View {
    @State private var isExtensionEnabled = false
    @State private var isDebugLoggingEnabled = false

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

                    Button("打开扩展设置") {
                        FIFinderSyncController.showExtensionManagementInterface()
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
    }
}

struct AdvancedSettingsView: View {
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
            Text("选择要显示在 Finder 右键菜单中的常用动作。高风险动作集中在“高级”页管理。")
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
        }
    }
    
    private func saveStateToSharedDefaults(_ enabled: Bool) {
        SharedStorageManager.shared.setBool(enabled, forKey: "enable_action_\(action.actionId)")
        // 发送分布式通知让 FinderSync 插件知道配置已经发生变动，即时刷新菜单内容
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("guyue.RightClickAssistant.configChanged"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
    
    private func loadStateFromSharedDefaults() {
        isEnabled = SharedStorageManager.shared.getBool(
            forKey: "enable_action_\(action.actionId)",
            defaultValue: action.isEnabledByDefault
        )
    }
}

/// 专为规避 Swift 6 协议 existential 动态类型推导编译挂起设计的具体实体结构
struct ActionItem: Identifiable {
    let id: String
    let action: MenuAction
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
                            FIFinderSyncController.showExtensionManagementInterface()
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
                // macOS 13+ 新版“系统设置”引导路径
                VStack(alignment: .leading, spacing: 10) {
                    StepRow(
                        step: 1,
                        iconName: "macwindow.and.cursorarrow",
                        title: "打开扩展管理窗口",
                        desc: "点击上方的「打开扩展设置」按钮，系统将打开扩展管理面板。"
                    )
                    
                    StepRow(
                        step: 2,
                        iconName: "scroll.fill",
                        title: "滚动到底部，点击「访达」右侧的 ⓘ (信息) 按钮",
                        desc: "在弹出的窗口中向下滚动至最底部，找到「访达」一栏，点击最右侧的 ⓘ 信息图标。\n(⚠️ 请务必点击最右侧的 ⓘ 图标，而不是旁边的开关)",
                        isCrucial: true
                    )
                    
                    StepRow(
                        step: 3,
                        iconName: "checkmark.square.fill",
                        title: "勾选「右键助手扩展」并完成",
                        desc: "在弹出的浮层中，勾选「右键助手扩展」，然后点击「完成」。"
                    )
                }
            } else {
                // macOS 12 及以下旧版“系统偏好设置”引导路径
                VStack(alignment: .leading, spacing: 10) {
                    StepRow(
                        step: 1,
                        iconName: "macwindow.and.cursorarrow",
                        title: "打开扩展管理面板",
                        desc: "点击上方的「打开扩展设置」按钮，系统将打开「系统偏好设置 -> 扩展」。"
                    )
                    
                    StepRow(
                        step: 2,
                        iconName: "sidebar.left",
                        title: "点击左侧边栏的「访达」",
                        desc: "在弹出的窗口中，于左侧边栏的各个大分类列表中，点击选择「访达 (Finder)」分类。"
                    )
                    
                    StepRow(
                        step: 3,
                        iconName: "checkmark.square.fill",
                        title: "勾选启用「右键助手扩展」",
                        desc: "在右侧展开的内容列表中，勾选「右键助手扩展」旁边的复选框，使其处于激活状态。"
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
