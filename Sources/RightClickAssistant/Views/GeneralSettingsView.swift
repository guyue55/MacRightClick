import SwiftUI

struct OverviewSettingsView: View {
    @State private var isLaunchEnabled = false
    @State private var isSilentLaunchEnabled = true
    @State private var showsSuccessHUD = true

    private var launchEnabledBinding: Binding<Bool> {
        Binding(
            get: { isLaunchEnabled },
            set: { newValue in
                let previousValue = isLaunchEnabled
                guard LaunchServiceManager.shared.setEnabled(newValue) else {
                    isLaunchEnabled = LaunchServiceManager.shared.isEnabled
                    SharedHUDManager.show(
                        title: "自启设置失败",
                        content: "请前往系统设置检查登录项权限",
                        isSuccess: false
                    )
                    return
                }
                guard SharedStorageManager.shared.setBool(
                    newValue,
                    forKey: "shouldStartOnLaunch"
                ) else {
                    _ = LaunchServiceManager.shared.setEnabled(previousValue)
                    isLaunchEnabled = LaunchServiceManager.shared.isEnabled
                    showConfigurationSaveFailure("登录时启动")
                    return
                }
                isLaunchEnabled = newValue
            }
        )
    }

    var body: some View {
        Form {
            Section("服务状态") {
                ExtensionStatusBanner()
            }

            Section("启动") {
                Toggle("登录时启动右键助手", isOn: launchEnabledBinding)

                Toggle("后台启动时保持静默", isOn: Binding(
                    get: { isSilentLaunchEnabled },
                    set: saveSilentLaunch
                ))
            }

            Section("反馈") {
                Toggle("显示成功提示", isOn: Binding(
                    get: { showsSuccessHUD },
                    set: saveSuccessHUD
                ))
            }

            Section("关于") {
                LabeledContent("版本") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("许可") {
                    Text("MIT")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("隐私") {
                    Text("无广告 · 无遥测")
                        .foregroundStyle(.secondary)
                }
                Button {
                    if let url = URL(string: "https://github.com/guyue55/MacRightClick") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("查看 GitHub 源码", systemImage: "arrow.up.right.square")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        isLaunchEnabled = LaunchServiceManager.shared.isEnabled
        isSilentLaunchEnabled = SharedStorageManager.shared.getBool(
            forKey: LaunchPresentationPolicy.silentLaunchKey,
            defaultValue: true
        )
        showsSuccessHUD = SharedStorageManager.shared.getBool(
            forKey: "enable_success_hud",
            defaultValue: true
        )
    }

    private func saveSilentLaunch(_ enabled: Bool) {
        guard SharedStorageManager.shared.setBool(
            enabled,
            forKey: LaunchPresentationPolicy.silentLaunchKey
        ) else {
            showConfigurationSaveFailure("静默启动")
            return
        }
        isSilentLaunchEnabled = enabled
    }

    private func saveSuccessHUD(_ enabled: Bool) {
        guard SharedStorageManager.shared.setBool(enabled, forKey: "enable_success_hud") else {
            showConfigurationSaveFailure("成功提示")
            return
        }
        showsSuccessHUD = enabled
    }
}
