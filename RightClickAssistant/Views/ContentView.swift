import SwiftUI

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
    
    // 我们使用标准的 App Group UserDefaults 保存开关状态，以便让 Extension 跨进程实时读取
    @AppStorage("shouldStartOnLaunch", store: UserDefaults(suiteName: "group.org.antigravity.RightClickAssistant"))
    private var shouldStartOnLaunch = true
    
    @AppStorage("shouldEnableiCloudMenu", store: UserDefaults(suiteName: "group.org.antigravity.RightClickAssistant"))
    private var shouldEnableiCloudMenu = false
    
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
                
                // 根据当前选项卡，动态渲染内容
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .general:
                            generalSettingsView
                        case .newFile:
                            actionsManagerView(category: .newFile)
                        case .fileManage:
                            actionsManagerView(category: .fileManage)
                        case .terminal:
                            actionsManagerView(category: .terminal)
                        case .utility:
                            actionsManagerView(category: .utility)
                        }
                    }
                    .padding()
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 850, minHeight: 600)
    }
    
    // MARK: - A. 通用设置面板
    private var generalSettingsView: some View {
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
                    Text("开源右键助手 (RightClickAssistant) v1.0.0")
                        .font(.headline)
                    Text("完全免费，采用 GPL-3.0 协议开源。致力于打造 macOS 最轻量、最强大的纯净生产力入口，100% 杜绝收费、广告与隐私收集。")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Button("访问 GitHub 源码仓库") {
                        if let url = URL(string: "https://github.com/guyue/mac-right-click-assistant") {
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
    
    // MARK: - B. 动作管理统一面板（根据不同分类渲染）
    private func actionsManagerView(category: ActionCategory) -> some View {
        let actions = ActionDispatcher.shared.actions(in: category)
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("您可以在下方自由勾选启用或禁用具体的右键菜单项。禁用的条目将不会出现在您的访达右键中。")
                .font(.body)
                .foregroundColor(.secondary)
            
            GroupBox(label: Label("\(category.localizedName)列表", systemImage: "list.bullet.indent")) {
                VStack(alignment: .leading, spacing: 4) {
                    if actions.isEmpty {
                        Text("暂无可用动作")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(actions, id: \.actionId) { action in
                            ActionRowView(action: action)
                            if action.actionId != actions.last?.actionId {
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
                Text(action.localizedTitle)
                    .font(.body)
                    .fontWeight(.medium)
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
        if let defaults = UserDefaults(suiteName: "group.org.antigravity.RightClickAssistant") {
            defaults.set(enabled, forKey: "enable_action_\(action.actionId)")
            // 发送分布式通知让 FinderSync 插件知道配置已经发生变动，即时刷新菜单内容
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("org.antigravity.RightClickAssistant.configChanged"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
    }
    
    private func loadStateFromSharedDefaults() {
        if let defaults = UserDefaults(suiteName: "group.org.antigravity.RightClickAssistant") {
            // 默认情况下，全部右键功能都是开启的
            if defaults.object(forKey: "enable_action_\(action.actionId)") == nil {
                isEnabled = true
            } else {
                isEnabled = defaults.bool(forKey: "enable_action_\(action.actionId)")
            }
        }
    }
}
