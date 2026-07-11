import SwiftUI

enum ActionStatusFilter: String, CaseIterable, Identifiable {
    case all
    case enabled
    case favorites
    case unavailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部状态"
        case .enabled: return "已启用"
        case .favorites: return "已收藏"
        case .unavailable: return "应用未安装"
        }
    }
}

struct ActionsHubView: View {
    @State private var selectedCategory: ActionCategory?
    @State private var statusFilter: ActionStatusFilter = .all
    @State private var query = ""
    @State private var menuLayoutMode: MenuLayoutMode = .flat
    @State private var selectedProfile: ActionProfile = .custom
    @State private var pendingProfile: ActionProfile?
    @State private var refreshID = UUID()

    private var standardActions: [MenuAction] {
        ActionDispatcher.shared.allActions
            .filter { $0.settingsGroup == .standard }
            .sorted {
                if $0.category == $1.category {
                    return $0.localizedTitle.localizedCompare($1.localizedTitle) == .orderedAscending
                }
                return categoryIndex($0.category) < categoryIndex($1.category)
            }
    }

    var body: some View {
        Form {
            Section("配置档案") {
                Picker("动作档案", selection: Binding(
                    get: { selectedProfile },
                    set: requestProfileChange
                )) {
                    Text("精简").tag(ActionProfile.essential)
                    Text("专业").tag(ActionProfile.professional)
                    Text("自定义").tag(ActionProfile.custom)
                }
                .pickerStyle(.segmented)

                Picker("菜单布局", selection: Binding(
                    get: { menuLayoutMode },
                    set: saveMenuLayout
                )) {
                    ForEach(MenuLayoutMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("筛选") {
                Picker("分类", selection: $selectedCategory) {
                    Text("全部").tag(nil as ActionCategory?)
                    ForEach(ActionCategory.allCases) { category in
                        Text(category.localizedName).tag(Optional(category))
                    }
                }
                .pickerStyle(.segmented)

                Picker("状态", selection: $statusFilter) {
                    ForEach(ActionStatusFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }

            if filteredActions.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        Text("没有符合条件的动作")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
            } else {
                ForEach(ActionCategory.allCases) { category in
                    let actions = filteredActions.filter { $0.category == category }
                    if !actions.isEmpty {
                        Section(category.localizedName) {
                            ForEach(actions, id: \.actionId) { action in
                                ActionRowView(action: action) {
                                    selectedProfile = SharedStorageManager.shared.actionProfile
                                    refreshID = UUID()
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .id(refreshID)
        .searchable(text: $query, prompt: "搜索动作名称或 ID")
        .confirmationDialog(
            profileConfirmationTitle,
            isPresented: Binding(
                get: { pendingProfile != nil },
                set: { if !$0 { pendingProfile = nil } }
            )
        ) {
            Button("应用档案") { applyPendingProfile() }
            Button("取消", role: .cancel) { pendingProfile = nil }
        } message: {
            Text("高级动作不会被批量开启；已有高级动作设置保持不变。")
        }
        .onAppear {
            menuLayoutMode = SharedStorageManager.shared.menuLayoutMode
            selectedProfile = SharedStorageManager.shared.actionProfile
        }
    }

    private var filteredActions: [MenuAction] {
        let favoriteIDs = Set(SharedStorageManager.shared.favoriteActionIds)
        return standardActions.filter { action in
            guard selectedCategory == nil || action.category == selectedCategory else { return false }
            guard ActionSearch.matches(
                title: action.localizedTitle,
                actionID: action.actionId,
                query: query
            ) else { return false }

            switch statusFilter {
            case .all:
                return true
            case .enabled:
                return SharedStorageManager.shared.isActionEnabled(action)
            case .favorites:
                return favoriteIDs.contains(action.actionId)
            case .unavailable:
                guard let bundleID = action.associatedBundleIdentifier else { return false }
                return !InstalledAppRegistry.shared.isInstalled(bundleID)
            }
        }
    }

    private var profileConfirmationTitle: String {
        switch pendingProfile {
        case .essential: return "应用精简档案？"
        case .professional: return "应用专业档案？"
        case .custom, .none: return "应用动作档案？"
        }
    }

    private func requestProfileChange(_ profile: ActionProfile) {
        guard profile != .custom else {
            selectedProfile = .custom
            return
        }
        pendingProfile = profile
    }

    private func applyPendingProfile() {
        guard let profile = pendingProfile else { return }
        let actions = DefaultActionRegistry.makeActions()
        guard SharedStorageManager.shared.applyActionProfile(profile, actions: actions) else {
            showConfigurationSaveFailure("动作档案")
            return
        }
        selectedProfile = profile
        pendingProfile = nil
        postConfigChanged()
        refreshID = UUID()
    }

    private func saveMenuLayout(_ mode: MenuLayoutMode) {
        guard SharedStorageManager.shared.setStringArray(
            [mode.rawValue],
            forKey: SharedStorageManager.Keys.menuLayoutMode
        ) else {
            showConfigurationSaveFailure("菜单布局")
            return
        }
        menuLayoutMode = mode
        postConfigChanged()
    }

    private func categoryIndex(_ category: ActionCategory) -> Int {
        ActionCategory.allCases.firstIndex(of: category) ?? 0
    }
}

/// 保留给高级页使用的动作分组。
struct ActionListGroupView: View {
    let title: String
    let iconName: String
    let items: [ActionItem]
    var showsIdentifiers = false
    var footer: String?

    var body: some View {
        GroupBox(label: Label(title, systemImage: iconName)) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    ActionRowView(action: item.action, showsIdentifier: showsIdentifiers)
                    if item.id != items.last?.id {
                        Divider()
                    }
                }
                if let footer {
                    Divider()
                    Text(footer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct ActionRowView: View {
    let action: MenuAction
    var showsIdentifier = false
    var onConfigurationChanged: () -> Void = {}

    @State private var isEnabled = true
    @State private var isFavorite = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.iconName ?? "gearshape")
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(action.localizedTitle)
                    if isApplicationUnavailable {
                        Label("未安装", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if action.isHighRisk {
                        Label("高级", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if showsIdentifier {
                    Text(action.actionId)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let riskDescription = action.riskDescription {
                    Text(riskDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "取消收藏" : "收藏")
            .accessibilityLabel("\(isFavorite ? "取消收藏" : "收藏") \(action.localizedTitle)")

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: saveEnabledState
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel("启用 \(action.localizedTitle)")
        }
        .padding(.vertical, 5)
        .onAppear(perform: loadState)
    }

    private var isApplicationUnavailable: Bool {
        guard let bundleID = action.associatedBundleIdentifier else { return false }
        return !InstalledAppRegistry.shared.isInstalled(bundleID)
    }

    private func loadState() {
        isEnabled = SharedStorageManager.shared.isActionEnabled(action)
        isFavorite = SharedStorageManager.shared.isFavoriteAction(action)
    }

    private func saveEnabledState(_ enabled: Bool) {
        let key = "enable_action_\(action.actionId)"
        guard SharedStorageManager.shared.applyConfigurationChanges(
            booleanValues: [key: enabled],
            stringArrayValues: [
                SharedStorageManager.Keys.actionProfile: [ActionProfile.custom.rawValue]
            ]
        ) else {
            showConfigurationSaveFailure(action.localizedTitle)
            return
        }
        isEnabled = enabled
        postConfigChanged()
        onConfigurationChanged()
    }

    private func toggleFavorite() {
        let newValue = !isFavorite
        guard SharedStorageManager.shared.setAction(action, favorite: newValue) else {
            showConfigurationSaveFailure("\(action.localizedTitle)收藏状态")
            return
        }
        isFavorite = newValue
        postConfigChanged()
        onConfigurationChanged()
    }
}

struct ActionItem: Identifiable {
    let id: String
    let action: MenuAction
}
