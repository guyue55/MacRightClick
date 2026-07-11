import SwiftUI

// MARK: - A. 新信息架构页面
struct OverviewSettingsView: View {
    @State private var isLaunchEnabled = false
    @State private var isSilentLaunchEnabled = true

    private var launchEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.isLaunchEnabled },
            set: { newValue in
                self.isLaunchEnabled = newValue
                let success = LaunchServiceManager.shared.setEnabled(newValue)
                if success {
                    guard SharedStorageManager.shared.setBool(
                        newValue,
                        forKey: "shouldStartOnLaunch"
                    ) else {
                        _ = LaunchServiceManager.shared.setEnabled(!newValue)
                        self.isLaunchEnabled = LaunchServiceManager.shared.isEnabled
                        showConfigurationSaveFailure("登录时启动")
                        return
                    }
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

            // 注：扩展未启用时，引导入口由 ExtensionStatusBanner 内部的「一键注册扩展」承担；
            // 已启用后，下方的 ExtensionRegistrationBox 才作为「修复入口」出现，避免双入口造成 UX 噪声。
            ExtensionRegistrationBox()

            GroupBox(label: Label("常用", systemImage: "slider.horizontal.3")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("登录时启动右键助手", isOn: launchEnabledBinding)
                        .toggleStyle(.checkbox)

                    Text("保持后台服务可用，Finder 右键动作可以随时由宿主 App 处理。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("静默启动", isOn: Binding(
                        get: { isSilentLaunchEnabled },
                        set: { newValue in
                            guard SharedStorageManager.shared.setBool(
                                newValue,
                                forKey: LaunchPresentationPolicy.silentLaunchKey
                            ) else {
                                showConfigurationSaveFailure("静默启动")
                                return
                            }
                            isSilentLaunchEnabled = newValue
                            SharedHUDManager.show(
                                title: newValue ? "静默启动已启用" : "静默启动已关闭",
                                content: newValue ? "登录和后台拉起时仅保留菜单栏图标" : "下次启动会直接显示设置窗口",
                                iconName: newValue ? "moon.fill" : "macwindow",
                                isSuccess: true
                            )
                        }
                    ))
                    .toggleStyle(.checkbox)

                    Text("用户从启动台或应用程序主动打开时，仍会显示设置窗口。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    Toggle("显示成功提示", isOn: Binding(
                        get: { SharedStorageManager.shared.getBool(forKey: "enable_success_hud", defaultValue: true) },
                        set: { newValue in
                            if !SharedStorageManager.shared.setBool(newValue, forKey: "enable_success_hud") {
                                showConfigurationSaveFailure("成功提示")
                            }
                        }
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
            isSilentLaunchEnabled = SharedStorageManager.shared.getBool(
                forKey: LaunchPresentationPolicy.silentLaunchKey,
                defaultValue: true
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            isLaunchEnabled = LaunchServiceManager.shared.isEnabled
            isSilentLaunchEnabled = SharedStorageManager.shared.getBool(
                forKey: LaunchPresentationPolicy.silentLaunchKey,
                defaultValue: true
            )
        }
    }
}
