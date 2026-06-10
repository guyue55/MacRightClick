import SwiftUI
import FinderSync


/// 侧边栏导航条目
enum SidebarItem: String, CaseIterable, Identifiable {
    case general = "general"
    case newFile = "newFile"
    case fileManage = "fileManage"
    case terminal = "terminal"
    case utility = "utility"
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .general: return "通用设置"
        case .newFile: return "新建文件管理"
        case .fileManage: return "文件操作管理"
        case .terminal: return "终端与编辑器"
        case .utility: return "实用工具箱"
        }
    }
    
    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .newFile: return "doc.badge.plus"
        case .fileManage: return "scissors"
        case .terminal: return "terminal"
        case .utility: return "wrench.and.screwdriver"
        }
    }
}

public struct ContentView: View {
    @State private var selectedTab: SidebarItem = .general
    
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
                
                // 系统集成状态 Banner
                ExtensionStatusBanner()
                
                // 根据当前选项卡，动态渲染内容
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .general:
                            GeneralSettingsView()
                        case .newFile:
                            ActionsManagerView(category: .newFile)
                        case .fileManage:
                            ActionsManagerView(category: .fileManage)
                        case .terminal:
                            ActionsManagerView(category: .terminal)
                        case .utility:
                            ActionsManagerView(category: .utility)
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

// MARK: - A. 通用设置面板
struct GeneralSettingsView: View {
    @State private var isLaunchEnabled = false
    @State private var shouldEnableiCloudMenu = false
    
    @State private var hasFullDiskAccess = false
    @State private var isPulsing = false
    let fdaTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    
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
                        content: newValue ? "右键助手将在您登录系统时自动为您保驾护航" : "已从系统开机自启项中安全移除",
                        iconName: newValue ? "bolt.fill" : "bolt.slash.fill",
                        isSuccess: true
                    )
                } else {
                    // 物理回滚 UI 状态
                    self.isLaunchEnabled = LaunchServiceManager.shared.isEnabled
                    SharedHUDManager.show(
                        title: "自启设置失败",
                        content: "系统限制或进程授权不足，请前往系统设置重试",
                        isSuccess: false
                    )
                }
            }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label("系统集成", systemImage: "cpu")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("开机时自动启动右键助手", isOn: launchEnabledBinding)
                        .toggleStyle(.checkbox)
                        .font(.body)
                    
                    Text("启用后，右键助手会在登录系统时自动启动并在后台处理右键动作。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    Toggle("启用操作成功悬浮通知", isOn: Binding(
                        get: { SharedStorageManager.shared.getBool(forKey: "enable_success_hud", defaultValue: true) },
                        set: { SharedStorageManager.shared.setBool($0, forKey: "enable_success_hud") }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.body)
                    
                    Text("启用后，成功动作会显示简短悬浮提示。关闭后，成功动作保持静默；失败、权限不足或系统拦截仍会提示。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()
                        .padding(.vertical, 4)

                    Toggle("启用详细调试日志", isOn: Binding(
                        get: { SharedStorageManager.shared.isDebugLoggingEnabled },
                        set: { SharedStorageManager.shared.setBool($0, forKey: SharedStorageManager.Keys.enableDebugLogging) }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.body)

                    Text("默认关闭。开启后会记录菜单渲染、路径监听和动作过滤细节，便于排查 Finder 扩展问题。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GroupBox(label: Label("系统权限与诊断", systemImage: "shield.and.key.badge.shield.exclamationmark")) {
                VStack(alignment: .leading, spacing: 12) {
                    if hasFullDiskAccess {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.green)
                                .frame(width: 28, height: 28)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(6)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text("完全磁盘访问权限 (FDA) 已授予")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                Text("右键助手可以访问更多受保护目录，部分文件操作会更稳定。")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(isPulsing ? 1.3 : 0.8)
                                    .opacity(isPulsing ? 1.0 : 0.4)
                                    .onAppear {
                                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                                            isPulsing = true
                                        }
                                    }
                                Text("已授权")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.orange)
                                    .frame(width: 28, height: 28)
                                    .background(Color.orange.opacity(0.15))
                                    .cornerRadius(6)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("完全磁盘访问权限 (FDA) 尚未授予")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(.primary)
                                    Text("这可能会限制右键助手的部分深度文件和系统级脚本操作。建议前往系统设置中授权。")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            
                            HStack {
                                Spacer()
                                Button(action: {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Text("前往系统设置授予权限")
                                        Image(systemName: "arrow.up.forward.app.fill")
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GroupBox(label: Label("云同步盘特殊兼容", systemImage: "icloud")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("在 iCloud 与 OneDrive 文件夹中强制显示菜单", isOn: Binding(
                        get: { shouldEnableiCloudMenu },
                        set: { newValue in
                            shouldEnableiCloudMenu = newValue
                            SharedStorageManager.shared.setBool(newValue, forKey: "shouldEnableiCloudMenu")
                            DistributedNotificationCenter.default().postNotificationName(
                                Notification.Name("guyue.RightClickAssistant.configChanged"),
                                object: nil,
                                userInfo: nil,
                                deliverImmediately: true
                            )
                        }
                    ))
                        .toggleStyle(.checkbox)
                        .font(.body)
                    
                    Text("某些云同步目录由系统 File Provider 托管，Finder 扩展可能无法稳定出现。开启后会额外监听常见云盘位置。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GroupBox(label: Label("关于项目", systemImage: "info.circle")) {
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
            checkFullDiskAccess()
            isLaunchEnabled = LaunchServiceManager.shared.isEnabled
            shouldEnableiCloudMenu = SharedStorageManager.shared.getBool(forKey: "shouldEnableiCloudMenu", defaultValue: false)
        }
        .onReceive(fdaTimer) { _ in
            checkFullDiskAccess()
            isLaunchEnabled = LaunchServiceManager.shared.isEnabled
            shouldEnableiCloudMenu = SharedStorageManager.shared.getBool(forKey: "shouldEnableiCloudMenu", defaultValue: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            checkFullDiskAccess()
            isLaunchEnabled = LaunchServiceManager.shared.isEnabled
            shouldEnableiCloudMenu = SharedStorageManager.shared.getBool(forKey: "shouldEnableiCloudMenu", defaultValue: false)
        }
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

// MARK: - B. 动作管理统一面板（根据不同分类渲染）
struct ActionsManagerView: View {
    let category: ActionCategory
    
    private var items: [ActionItem] {
        let actions = ActionDispatcher.shared.actions(in: category)
        return actions.map { ActionItem(id: $0.actionId, action: $0) }
    }

    private var standardItems: [ActionItem] {
        items.filter { !$0.action.isHighRisk }
    }

    private var advancedItems: [ActionItem] {
        items.filter { $0.action.isHighRisk }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("您可以在下方自由勾选启用或禁用具体的右键菜单项。禁用的条目将不会出现在您的访达右键中。")
                .font(.body)
                .foregroundColor(.secondary)
            
            ActionListGroupView(
                title: "\(category.localizedName)列表",
                iconName: "list.bullet.indent",
                items: standardItems
            )

            if !advancedItems.isEmpty {
                ActionListGroupView(
                    title: "高级功能（默认关闭）",
                    iconName: "exclamationmark.triangle",
                    items: advancedItems,
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
                        ActionRowView(action: item.action)
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
                Text("唯一标示: \(action.actionId)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
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
