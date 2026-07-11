import SwiftUI

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
