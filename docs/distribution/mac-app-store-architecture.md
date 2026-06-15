# Mac App Store 分发架构前提与迁移清单

当前主分发路线为官网/GitHub Releases 站外分发。切换至 Mac App Store（MAS）需要满足以下硬性要求。

## 1. App Sandbox

macOS 上架 MAS 的应用**必须启用 App Sandbox**。当前主 App 在站外分发路线下未开启沙盒，而 Finder Sync 扩展始终在沙盒内运行。

需要修改：

- 主 App 的 entitlements 文件中启用 `com.apple.security.app-sandbox`。
- 评估所有 `Process` 调用（如 `defaults write`、`killall Finder`）在沙盒内是否可用，必要时迁移到 XPC Service。
- 切换隐藏文件功能在沙盒内无法直接操作系统偏好，需重新设计或移除。

## 2. 正式 App Group

当前站外分发使用 Extension 沙盒目录（`~/Library/Containers/guyue.RightClickAssistant.Extension/Data`）作为共享中介。MAS 下应改用 Apple 正式的 App Group 容器。

需要修改：

- `SharedStorageManager.forceLocalSandboxExchange` 改为 `false`。
- 确认 `group.guyue.RightClickAssistant` 已在 Developer 账号的 App ID 和 Provisioning Profile 中配置。
- 测试 App Group `containerURL(forSecurityApplicationGroupIdentifier:)` 在两端的读写一致性。

## 3. Security-Scoped Access / Bookmarks

沙盒内无法直接访问用户任意目录。若功能需要访问用户选择的文件夹（如"复制/移动到…"的目标目录），必须使用 security-scoped bookmarks。

需要修改：

- "复制到..."、"移动到..." 等需要用户在 `NSOpenPanel` 中选择目录的动作，应将选中的 URL 转为 security-scoped bookmark 持久化。
- 消费 bookmark 时调用 `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`。
- 主 App 的 entitlements 中添加 `com.apple.security.files.user-selected.read-write`（当前已有）。

## 4. 高风险动作审核

MAS 审核对以下动作敏感：

| 动作 | MAS 风险 | 建议 |
|------|---------|------|
| 永久删除 | 无撤销 | 保留确认对话框，提供更详细的警告文案 |
| 切换隐藏文件 | `defaults write` + `killall Finder` 不可用 | 移除或改为用户手动操作的引导说明 |
| 跨目录复制/移动 | 无问题 | 确认 security-scoped bookmark 正常 |

## 5. 隐私说明

MAS 提交需要填写隐私标签（App Privacy）。当前项目不收集数据，应在 App Store Connect 中声明：

- 不收集任何用户数据（Data Not Collected）。
- 若调试日志开启后写入路径信息，需在文档中说明为本地日志且不自动上传。

## 6. build.sh 变更

`Scripts/build.sh` 当前在 `DISTRIBUTION_ROUTE=mac-app-store` 时会直接退出并提示原因。MAS 就绪后：

- 移除退出逻辑。
- 使用 `DEVELOPER_ID_APPLICATION` 替换为 `APPLE_DISTRIBUTION_CERTIFICATE`（如 "Apple Distribution: …" 或 "3rd Party Mac Developer Application: …"）。
- 签名时使用 `--options runtime` 不变，但 provisioning profile 需要切换到 Mac App Store 类型。

## 总结

MAS 路线与站外分发是两种不同的签名、沙盒和分发模式。建议在 `feature/mac-app-store` 分支上独立推进，保持 `main` 分支始终可构建可发布的站外版本。

## 7. Distribution.swift 常量映射

本轮新增 `Sources/RightClickAssistant/Core/Distribution.swift` 把"分发路线"从运行时探测下沉为编译期常量，三条路线的常量映射如下：

| Route             | `-D` 宏          | `usesAppGroup` | `allowsCrossContainerExchange` | 优化级 |
| ----------------- | ----------------- | -------------- | ------------------------------ | ------ |
| `website-dev`     | `WEBSITE_DEV`     | false          | true                           | -Onone |
| `website-release` | `WEBSITE_RELEASE` | false          | true                           | -O     |
| `mac-app-store`   | `MAC_APP_STORE`   | true           | false                          | -O     |

- `usesAppGroup`：仅 MAS 路线开启（数据走 `~/Library/Group Containers/group.…`）。website 路线主 App 是非 sandbox（仅声明 `application-groups` 建立同 AppGroup 信任域），运行时直接走 cross-container 物理路径与扩展互通，未走 Group Containers，避免对 1.0.x 现网用户造成数据迁移。
- `allowsCrossContainerExchange`：仅 MAS 路线为 `false`（沙盒禁止跨 container 直接读）。website 路线主 App 非 sandbox 可直接读 `~/Library/Containers/<extBundle>/Data`，与 1.0.x 行为一致；FinderSync 仍是 sandbox + AppGroup，靠 AppGroup 同源关系接受主 App 的访问。

如未来希望把 website 路线也切到 Group Containers 路径，需要：

1. 把 `usesAppGroup` 在 `website-*` 分支下也返回 `true`
2. 写一次性数据迁移：把旧 `Library/Containers/<extBundle>/Data` 下的 `config.json` / `PendingActions/` / `FailedActions/` 拷到新 Group Container
3. 在两台真机（macOS 13 / 14）上回归 14 步验收清单

`Scripts/build.sh` 通过 `case "$DISTRIBUTION_ROUTE"` 注入对应 `-D` 宏，Swift 端只读编译期常量，不再依赖运行时探测；切换路线只改一个环境变量即可。

entitlements 模板也按路线分叉，三份外置 plist 在 `entitlements/` 目录下：

- `entitlements/website.host.entitlements` → `website-dev` / `website-release`
- `entitlements/mas.host.entitlements`     → `mac-app-store`（占位，本轮 build.sh 仍 exit 2 拦截）
- `entitlements/extension.entitlements`    → 三条路线共用（FinderSync 必须 sandbox + AppGroup）
