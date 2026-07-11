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
        case .permissions: return "Finder"
        case .diagnostics: return "诊断"
        case .advanced: return "高级"
        }
    }

    var iconName: String {
        switch self {
        case .overview: return "gearshape"
        case .actions: return "list.bullet.rectangle"
        case .permissions: return "folder"
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
            List(SidebarItem.allCases, selection: $selectedTab) { item in
                NavigationLink(value: item) {
                    Label(item.title, systemImage: item.iconName)
                        .font(.body)
                        .padding(.vertical, 2)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("右键助手")
            .frame(minWidth: 180, idealWidth: 190, maxWidth: 220)

        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(selectedTab.title)
                        .font(.system(size: 20, weight: .semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()

                detailContent
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 850, minHeight: 600)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .overview:
            OverviewSettingsView()
        case .actions:
            ActionsHubView()
        case .permissions:
            PermissionsSettingsView()
        case .diagnostics:
            ScrollView {
                DiagnosticsSettingsView()
                    .padding(20)
            }
        case .advanced:
            ScrollView {
                AdvancedSettingsView()
                    .padding(20)
            }
        }
    }
}
