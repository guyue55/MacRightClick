# Changelog

本项目所有重要的版本变更都会记录在本文件中。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

---

## [v1.0.1] — 2026-06-16

本轮聚焦三个主题：**安全（高风险动作 HIG 化）**、**体验（菜单作用范围、注册启用、HUD 行为）**、**健壮性（跨进程死锁、并发安全、CI 稳定性）**。

### Fixed

- **ext**: 「一键注册扩展」现在自动执行 `pluginkit -a` 注册 + `pluginkit -e use -i guyue.RightClickAssistant.Extension` 启用 + `killall Finder` 重启访达三步，不再仅注册不生效（这是过去用户反复踩到的「等了一会没生效」的根因）。
- **ux**: 「一键注册扩展」按钮颜色统一为橙色，与未激活态 warning 基调一致，消除文本「上方橙色的」与实际颜色不一致的 bug。
- **host**: `processPendingAction` 异步化 + Distribution 路线感知 UserDefaults 路由，斩断启动期 `cfprefsd` 死锁。
- **storage**: PendingAction 改 lease/ack/reclaim 三件套，进程崩溃不丢事件。
- **filemanage**: `paste` 走 `BackgroundActionRunner`，跨盘大文件不再阻塞 folder-monitor 队列；彻底删除走 `DeletionRequestCoordinator`，斩断死锁链。
- **interactive**: `moveTo` / `copyTo` / `toggleHidden` 走 `InteractiveActionRunner`，斩断 P0-1 / P0-2 死锁。
- **host+ext**: statusItem 兜底 + FinderSync 启动时自愈拉起主 App。
- **ci**: `hdiutil create` 加 detach 清理 + 重试，消除 CI DMG 打包 Resource busy 竞态。
- **tests**: 修 `InteractiveActionRunnerTests` + `SharedStorageManagerLeaseTests` 的 Swift 6.1 并发与可选值检查。

### Added

- **ux**: 右键菜单作用范围默认 `.everywhere`，新增 `WatchScope` 开关；概览页单一引导入口；高级页恢复默认拆两档；权限页改事件驱动。
- **hud**: HUD 跟随鼠标所在屏幕，支持点击 / Esc 立即关闭。
- **safety**: 状态栏托盘移除「切换隐藏文件」高风险入口，`killall Finder` 改 AppleScript 优雅退出。
- **filemanage**: 永久删除走 HIG critical 三按钮，新增「移到废纸篓」中间档；跨卷 Copy-Then-Delete 事务化，失败时清理残留。
- **newfile**: Office 三件套（`.docx` / `.xlsx` / `.pptx`）改读 Bundle Templates 最小骨架，可双击直开。
- **qr**: 二维码窗口加保存为 PNG / 拷贝图片按钮，长内容支持滚动文本预览。
- **cache**: 新增 `AppLog` / `Distribution` / `ActionConfigCache` / `InstalledAppRegistry` 四个共享模块，菜单渲染主路径走进程内缓存（首次右键之后命中缓存 < 0.1ms）。
- **stress**: 新增 `run_stress.py` / `run_reclaim_stress.py` 真机压测 harness，压测纳入 CI。
- **logging**: 全局日志切 OSLog（`subsystem == "guyue.RightClickAssistant"`），按 category 区分 `host` / `ext` / `storage` / `action` / `ui`；废弃 `extension.log` 文件追加路径。

### Changed

- **build**: entitlements 外置到 `entitlements/`，按 `DISTRIBUTION_ROUTE` 选模板；`website-release` / MAS 路线启用 `-O`，本地开发路线保留 `-Onone`。
- **core**: 全面适配 Swift 6.1 并发安全检查（`@MainActor` / `nonisolated(unsafe)` / `Sendable` / `@unchecked Sendable`）。
- **ux**: 修复使用体验缺陷——消除右键动作触发时主窗口弹出、Dock 图标闪现和二维码窗口抢焦点。

### Documentation

- 补充 OSLog 诊断指引、Distribution 常量映射表、spec / plan 命名对齐。
- 新增 UX 强化与分发路线收敛设计稿（`docs/superpowers/specs/2026-06-15-ux-hardening-design.md`）与实施计划（`docs/superpowers/plans/2026-06-15-ux-hardening.md`）。
- 归档真机验收报告（`docs/superpowers/acceptance/2026-06-16-realmachine-acceptance.md`）。
- README Q2 指引补充 `pluginkit -e use` 启用步骤；新增「更新日志」章节并指向本文件。

完整提交记录见 [GitHub Releases v1.0.1](https://github.com/guyue55/MacRightClick/releases/tag/v1.0.1)。

---

## [v0.0.2] — 2026-06-10

- 队列可靠性与诊断能力增强；支持访达菜单收藏与自定义监听目录；重构设置页信息架构；第一阶段安全入口与信任文案收敛。

## [v0.0.1] — 2026-06-10

- 首个公开发布版：28 个核心右键动作、Universal 2 双架构、FinderSync + 主 App 双进程穿透分发架构。

---

[v1.0.1]: https://github.com/guyue55/MacRightClick/releases/tag/v1.0.1
[v0.0.2]: https://github.com/guyue55/MacRightClick/releases/tag/v0.0.2
[v0.0.1]: https://github.com/guyue55/MacRightClick/releases/tag/v0.0.1
