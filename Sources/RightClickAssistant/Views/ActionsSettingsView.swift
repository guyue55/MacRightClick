import SwiftUI

// MARK: - B. 动作管理统一面板（根据不同分类渲染）
struct ActionsHubView: View {
    @State private var selectedCategory: ActionCategory = .newFile
    @State private var menuLayoutMode: MenuLayoutMode = .flat

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择要显示在 Finder 右键菜单中的动作。星标动作会出现在右键菜单的“常用”分组中。")
                .font(.body)
                .foregroundColor(.secondary)

            GroupBox(label: Label("右键菜单展示", systemImage: "menucard")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("右键菜单展示", selection: Binding(
                        get: { menuLayoutMode },
                        set: { newValue in
                            guard SharedStorageManager.shared.setStringArray(
                                [newValue.rawValue],
                                forKey: SharedStorageManager.Keys.menuLayoutMode
                            ) else {
                                showConfigurationSaveFailure("右键菜单展示")
                                return
                            }
                            menuLayoutMode = newValue
                            postConfigChanged()
                            SharedHUDManager.show(
                                title: "菜单展示已更新",
                                content: newValue == .flat ? "已启用一级菜单直接显示" : "已切回分类子菜单显示",
                                isSuccess: true
                            )
                        }
                    )) {
                        ForEach(MenuLayoutMode.allCases) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(menuLayoutMode == .flat
                         ? "已启用的可用动作会直接出现在 Finder 右键一级菜单中，收藏动作置顶。"
                         : "已启用的可用动作会按新建文件、文件管理、终端/编辑器、实用工具分类显示。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Picker("动作分类", selection: $selectedCategory) {
                ForEach(ActionCategory.allCases) { category in
                    Text(category.localizedName).tag(category)
                }
            }
            .pickerStyle(.segmented)

            ActionsManagerView(category: selectedCategory, includeAdvanced: false)
        }
        .onAppear {
            menuLayoutMode = SharedStorageManager.shared.menuLayoutMode
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
                        if !InstalledAppRegistry.shared.isInstalled(bundleId) {
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

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { saveStateToSharedDefaults($0) }
            ))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 6)
        .onAppear {
            loadStateFromSharedDefaults()
            loadFavoriteState()
        }
    }

    private func saveStateToSharedDefaults(_ enabled: Bool) {
        let key = "enable_action_\(action.actionId)"
        let previousValue = SharedStorageManager.shared.getBool(
            forKey: key,
            defaultValue: action.isEnabledByDefault
        )
        guard SharedStorageManager.shared.setBool(enabled, forKey: key) else {
            showConfigurationSaveFailure(action.localizedTitle)
            isEnabled = previousValue
            return
        }
        isEnabled = enabled
        // 发送分布式通知让 FinderSync 插件知道配置已经发生变动，即时刷新菜单内容
        postConfigChanged()
    }

    private func loadStateFromSharedDefaults() {
        let storedValue = SharedStorageManager.shared.getBool(
            forKey: "enable_action_\(action.actionId)",
            defaultValue: action.isEnabledByDefault
        )
        isEnabled = storedValue
    }

    private func loadFavoriteState() {
        isFavorite = SharedStorageManager.shared.isFavoriteAction(action)
    }

    private func toggleFavorite() {
        let newValue = !isFavorite
        guard SharedStorageManager.shared.setAction(action, favorite: newValue) else {
            showConfigurationSaveFailure("\(action.localizedTitle)收藏状态")
            return
        }
        isFavorite = newValue
        postConfigChanged()
    }
}

/// 专为规避 Swift 6 协议 existential 动态类型推导编译挂起设计的具体实体结构
struct ActionItem: Identifiable {
    let id: String
    let action: MenuAction
}
