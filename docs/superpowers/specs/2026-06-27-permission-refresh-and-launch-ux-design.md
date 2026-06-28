# 权限刷新与启动体验设计方案

## 背景

当前已经修复了 FinderSync 作用范围覆盖不足的问题，并在完全磁盘访问权限检测到授权后提示用户重启 Finder。继续检查后，还有两个体验风险需要系统化处理：

1. 完全磁盘访问权限授予后，macOS TCC 不保证把新权限热更新给已运行进程；仅重启 Finder 可能不够，主 App 也可能需要重新启动。
2. App 现在是 `LSUIElement` 菜单栏形态，依赖 `applicationDidFinishLaunching` 时的 active/frontmost 状态判断是否主动打开，存在误判风险。用户从启动台或应用程序打开时，可能看不到设置窗口。

## 业内与平台参考

- Apple Finder Sync 官方模型：扩展通过注册 monitored folders，为对应项目提供 badge、label 和 contextual menu。因此右键菜单显示属于 FinderSync 监听范围问题，不是完全磁盘访问权限本身的问题。参考：https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html
- Apple FinderSync badge API：清空 badge 应使用空字符串，当前剪切角标刷新方向符合该模型。参考：https://developer.apple.com/documentation/findersync/fifindersynccontroller/setbadgeidentifier%28_%3Afor%3A%29
- Apple HIG 菜单栏模型：菜单栏额外项适合在 App 后台运行时提供快速状态与操作入口，但用户主动打开 App 时仍应有明确入口进入主界面。参考：https://developer.apple.com/design/Human-Interface-Guidelines/the-menu-bar
- Microsoft PowerToys 右键扩展经验：图片缩放、批量重命名等右键功能应偏向低阻塞、可配置、可恢复，并在功能异常时提供清晰入口，而不是要求用户理解扩展生命周期。参考：https://learn.microsoft.com/en-us/windows/powertoys/image-resizer 与 https://learn.microsoft.com/en-us/windows/powertoys/powerrename

## 设计目标

1. 用户授权完全磁盘访问后，不需要理解 TCC、FinderSync、主 App、Finder 之间的关系。
2. 对权限变更后的必要重载给出明确操作：重新打开 App + 重启 Finder + 刷新 FinderSync 配置。
3. 用户主动打开 App 时，设置窗口必须稳定出现；FinderSync 后台拉起时必须静默。
4. 所有重载操作都可重复执行、可失败提示，不产生破坏性副作用。

## 非目标

- 不尝试绕过 macOS TCC 权限模型。
- 不做后台轮询权限状态，避免菜单栏 App 常驻时无意义唤醒。
- 不把完全磁盘访问权限和右键菜单显示混为一个状态；两者在 UI 上需要明确区分。

## 方案 A：权限授权后的“一键重载”流程

### 交互

在权限页检测到 `hasFullDiskAccess` 从 `false` 变为 `true` 后弹出对话框：

- 标题：`完全磁盘访问权限已生效`
- 内容：`为确保 Finder 扩展和主程序都使用新权限，建议立即重新打开右键助手并重启 Finder。`
- 按钮：
  - `重新打开并重启 Finder`
  - `仅重启 Finder`
  - `稍后`

### 行为

`重新打开并重启 Finder`：

1. 写入一个短生命周期 relaunch marker，例如 `pending_permission_relaunch = true`。
2. 通过 `open -n /Applications/RightClickAssistant.app --args --rightclickassistant-user-open` 或当前 bundle path 重新打开 App。
3. 当前进程延迟 0.3 秒退出。
4. 新进程启动后：
   - 清理 marker。
   - 发送 `configChanged`。
   - 重启 Finder。
   - 显示设置窗口并定位权限页或显示 HUD。

`仅重启 Finder`：

1. 发送 `configChanged`。
2. 执行 Finder 重启。
3. 2 秒后刷新扩展状态。

`稍后`：

1. 不执行重载。
2. 权限页保留提示条：`权限已授予，建议重启 Finder 或重新打开 App 以完成刷新。`

### 架构

新增 `PermissionRefreshCoordinator`：

- `detectTransition(previous:current:) -> PermissionRefreshEvent?`
- `restartFinder()`
- `relaunchAppAndRestartFinder(bundleURL:)`
- `clearPendingRelaunchMarkerIfNeeded()`

`PermissionsSettingsView` 只负责状态展示和调用 coordinator，不直接散落 `Process` 调用。

### 失败处理

- `open` 失败：HUD 显示无法重新打开 App，保留“仅重启 Finder”按钮。
- `killall Finder` 失败：HUD 显示重启失败，并提示可手动退出 Finder 或重新登录。
- 新进程未启动：旧进程不应立刻退出；先尝试 `open` 成功后再退出。

## 方案 B：启动来源显式化

### 问题

当前策略通过 `NSApp.isActive` 和 frontmost bundle 判断主动打开，但 `LSUIElement` App 在 launch 阶段可能还没成为前台，判断不稳定。

### 方案

引入明确启动参数：

- FinderSync 后台拉起：`--rightclickassistant-background`
- 用户主动打开：默认无参数，但在 `applicationDidFinishLaunching` 后延迟 0.3 秒二次判断。
- Relaunch 权限刷新：`--rightclickassistant-user-open --rightclickassistant-permission-refresh`

### 决策规则

1. 存在 `--rightclickassistant-background`：永远不显示设置窗口。
2. 存在 `--rightclickassistant-user-open`：永远显示设置窗口。
3. `silentLaunchEnabled == false`：显示设置窗口。
4. 无明确参数：
   - 先静默启动。
   - 延迟 0.3 秒后，如果 App 是 active/frontmost 或没有 pending action，显示设置窗口。
   - 如果启动后立即消费了 FinderSync pending action，则保持静默。

### 测试

补充 `LaunchPresentationPolicyTests`：

- background 参数优先级最高。
- user-open 参数强制显示。
- silentLaunch 关闭时显示。
- 无参数且 active/frontmost 时显示。
- 无参数且有 pending Finder action 时静默。

## 方案 C：权限页状态分层

权限页拆成三个独立状态，避免用户误解：

1. `完全磁盘访问权限`
   - 影响文件读写、受保护目录、哈希/复制/移动等操作。
2. `Finder 扩展状态`
   - 影响右键菜单能否出现。
3. `右键菜单作用范围`
   - 影响在哪些路径显示菜单。

每个状态都有单独操作：

- FDA：打开系统设置、重新检测、重新打开并重启 Finder。
- Finder 扩展：一键注册扩展、打开系统扩展设置。
- 作用范围：所有目录 / 自定义目录、刷新 Finder。

## 推荐落地顺序

1. 提取 `FinderReloader` 或 `SystemReloader`，统一所有 Finder 重启逻辑。
2. 实现 `PermissionRefreshCoordinator`，把权限页的重启和 relaunch 逻辑收敛。
3. 扩展 `LaunchPresentationPolicy`，加入 explicit user-open / permission-refresh 参数。
4. 权限页增加提示条和三按钮弹窗。
5. 补单元测试和真机验收脚本。

## 验收清单

- 从系统设置授予完全磁盘访问，切回 App 后出现重载提示。
- 点击“重新打开并重启 Finder”后，App 重新打开，Finder 被重启，权限页显示已授权。
- FinderSync 后台拉起 App 时不弹窗口、不抢焦点。
- 用户从启动台或 `/Applications` 双击打开 App 时设置窗口稳定出现。
- `/Applications`、`~/Documents`、`/Volumes/<disk>`、iCloud/CloudStorage 下右键菜单可见。
- 若 `killall Finder` 失败，有明确 HUD 提示。
