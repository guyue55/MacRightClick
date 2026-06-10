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
                    Text("完全免费且开源")
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
    // 我们使用标准的 App Group UserDefaults 保存开关状态，以便让 Extension 跨进程实时读取
    @AppStorage("shouldStartOnLaunch", store: UserDefaults(suiteName: "group.guyue.RightClickAssistant"))
    private var shouldStartOnLaunch = true
    
    @AppStorage("shouldEnableiCloudMenu", store: UserDefaults(suiteName: "group.guyue.RightClickAssistant"))
    private var shouldEnableiCloudMenu = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label("系统集成", systemImage: "cpu")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("开机时自动启动右键助手", isOn: $shouldStartOnLaunch)
                        .toggleStyle(.checkbox)
                        .font(.body)
                    
                    Text("启用此项可在开机后，后台静默为您维护右键加速器，完全无感、超低消耗。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GroupBox(label: Label("云同步盘特殊兼容", systemImage: "icloud")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("在 iCloud 与 OneDrive 文件夹中强制显示菜单", isOn: $shouldEnableiCloudMenu)
                        .toggleStyle(.checkbox)
                        .font(.body)
                    
                    Text("因为 macOS 的访达限制，在被其他同步客户端托管的目录中，普通右键扩展可能失效。开启此项后，您可以通过修饰键(如 Option) + 右键或三指轻拍，在云盘目录下完美唤出右键菜单。")
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
                    Text("完全免费，采用 GPL-3.0 协议开源。致力于打造 macOS 最轻量、最强大的纯净生产力入口，100% 杜绝收费、广告与隐私收集。")
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
    }
}

// MARK: - B. 动作管理统一面板（根据不同分类渲染）
struct ActionsManagerView: View {
    let category: ActionCategory
    
    private var items: [ActionItem] {
        let actions = ActionDispatcher.shared.actions(in: category)
        return actions.map { ActionItem(id: $0.actionId, action: $0) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("您可以在下方自由勾选启用或禁用具体的右键菜单项。禁用的条目将不会出现在您的访达右键中。")
                .font(.body)
                .foregroundColor(.secondary)
            
            GroupBox(label: Label("\(category.localizedName)列表", systemImage: "list.bullet.indent")) {
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
                }
                .padding(.vertical, 6)
            }
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
                }
                Text("唯一标示: \(action.actionId)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
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
        if let defaults = UserDefaults(suiteName: "group.guyue.RightClickAssistant") {
            defaults.set(enabled, forKey: "enable_action_\(action.actionId)")
            // 发送分布式通知让 FinderSync 插件知道配置已经发生变动，即时刷新菜单内容
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("guyue.RightClickAssistant.configChanged"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
    }
    
    private func loadStateFromSharedDefaults() {
        if let defaults = UserDefaults(suiteName: "group.guyue.RightClickAssistant") {
            // 默认情况下，全部右键功能都是开启的
            if defaults.object(forKey: "enable_action_\(action.actionId)") == nil {
                isEnabled = true
            } else {
                isEnabled = defaults.bool(forKey: "enable_action_\(action.actionId)")
            }
        }
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
                // 🟢 翡翠绿高阶已激活 Banner
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
                        Text("系统右键引擎安全运行中。您可以在下方自由管理各项右键动作。")
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
                // 🟠 HSL 优雅橘黄未激活 Banner
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
                        Text("右键助手需要系统扩展授权。请一键打开系统设置，并勾选启用 [右键助手扩展]。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        FIFinderSyncController.showExtensionManagementInterface()
                    }) {
                        HStack(spacing: 5) {
                            Text("一键启用扩展")
                            Image(systemName: "arrow.up.forward.app.fill")
                        }
                        .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [Color.orange.opacity(0.08), Color.red.opacity(0.03)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
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
        // 监听系统 willBecomeActive 通知：用户在设置勾选后，切回 App 时瞬间秒刷新，无感切换！
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            checkStatus()
        }
    }
    
    private func checkStatus() {
        isEnabled = FIFinderSyncController.isExtensionEnabled
    }
}

