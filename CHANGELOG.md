# Changelog

本项目所有重要的版本变更都会记录在本文件中。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

---

## Unreleased

## v1.2.1 — 2026-07-15

### Added

- **finder**: 为 iCloud Drive、文稿和其他 File Provider 保护目录补充系统服务直达动作；收藏优先、常用动作补齐，最多展示 8 项，并保留“右键助手…”完整分类面板。

### Packaging

- **homebrew**: Cask 更新到 v1.2.0 不可变 DMG 及远程制品的真实 SHA-256。
- **homebrew**: 修正 macOS 依赖的弃用语法，并补充 Homebrew 6 第三方 tap 的单 Cask 最小信任安装与故障恢复流程。
- **homebrew**: 安装后提示与中英文文档补充新机器 Gatekeeper 放行步骤、精确的单 App quarantine 移除命令，并修正 Homebrew 6 的 Cask audit 调用。
- **ci**: GitHub Actions 升级并锁定到原生 Node 24 的 `checkout v6.0.2` 与 `upload-artifact v7.0.1`，移除 Node 20 兼容开关。

### Fixed

- **finder**: 云盘兼容改为默认开启，并显式注册 iCloud Drive 的 File Provider 真实根路径。稳定根与桌面/下载/文稿不再用扩展的文件读权限过滤，避免普通受保护目录被错误排除。
- **finder**: 针对 macOS 在 File Provider 域中抑制第三方 FinderSync 动作的情况，新增 5 个低风险系统服务入口，复用原有动作队列、开关与终态确认。
- **finder**: 动态服务 helper 丢失或执行权限异常时自动撤下失效项或修复权限；外部应用可用状态变化会刷新直达项，服务标题用序号稳定展示顺序。
- **concurrency**: 修复外部应用缓存失效通知与界面同步读取可能形成的死锁。
- **tools**: 外部工具区分独立安装、Homebrew 管理、未安装与安装记录损坏四种状态；命令执行前重新校验，避免对手动安装的 iTerm2 误用 `brew upgrade`。
- **tools**: Homebrew 管理的外部工具更新使用 `--greedy`，避免 `auto_updates` Cask 被跳过；Homebrew 库存检测移出主线程并防止过期刷新覆盖新状态。
- **diagnostics**: 诊断页与隐私安全报告显示云盘兼容状态，便于定位 File Provider 目录缺少菜单的问题。

## v1.2.0 — 2026-07-12

### Added

- **actions**: 新增「复制 Shell 安全路径」与「复制 Git 相对路径」，注册动作总数由 28 增至 30。
- **profiles**: 新增精简、专业、自定义三档动作配置，并支持按标题、动作 ID、分类与状态筛选。
- **diagnostics**: 新增扩展心跳、监听入口、队列积压、失败动作与隐私安全诊断报告；诊断页只突出一个优先修复动作。
- **update**: 新增用户主动触发的 GitHub Release 更新检查；不在启动、页面出现或后台自动请求网络。
- **tools**: 新增「高级 -> 外部工具」管理入口，检测 Homebrew 后可通过 Homebrew Cask 安装或更新 iTerm2、Warp、Visual Studio Code、Sublime Text、Cursor。
- **homebrew**: 新增固定版本、真实 SHA-256 与 `livecheck` 的 Homebrew Cask，并提供结构和远程制品校验脚本。

### Changed

- **ui**: 设置窗口重构为通用、动作、Finder、诊断、高级五个原生分组页面，减少嵌套卡片和无效说明。
- **menu**: 默认保持一级平铺，收藏与普通动作连续排列；仍可切换分类子菜单。
- **registry**: Host、FinderSync、设置页与测试统一使用 `DefaultActionRegistry`，消除重复动作清单。
- **events**: 动作事件升级为 schema v2，记录选中项/空白区域调用语义，并在 Host 执行前重新校验目标与可用性。
- **release**: CI 分离只读分支构建与标签发布；当前标签会生成明确标记的 Ad-hoc 社区制品、版本化与 Latest 资产、SHA-256 清单，并禁止覆盖已发布版本。

### Fixed

- **storage**: 测试存储完全隔离到临时目录；配置批量修改原子化，并避免回收仍由活动进程持有的动作租约。
- **queue**: 异步动作只在成功、失败或取消终态后确认租约，宿主退出时不会提前丢弃进行中的事件。
- **actions**: 剪切板快照加入版本号；跨卷移动、哈希、图片转换与高风险交互使用明确的后台/主线程边界；图片转码改用 ImageIO，修复灰度 Alpha PNG 无法转为 JPEG。
- **permissions**: 完全磁盘访问、Finder 扩展注册、Finder 会话与监听范围分层呈现；授权后提供重新打开与刷新 Finder 的闭环。
- **concurrency**: 收紧 Swift 6 `Sendable` / `MainActor` 边界，修复 HUD 生命周期、后台 runner 和系统命令完成回调问题。
- **system-command**: 系统命令执行器在进程退出后完整等待 stdout/stderr 管道读完，避免 `pluginkit` / `brew` 等命令结果被截断。
- **permissions**: 收紧权限刷新协调器的公开 API，避免“重新打开 App”步骤被误用为完整的“重新打开并重启 Finder”流程。

### Documentation

- **readme**: 全文校对中英文 README，更新为 30 个动作、当前下载/Cask 行为、权限边界、显式更新隐私与 v1.2 原生界面截图。
- **distribution**: 明确 GitHub Release 与 Homebrew Cask 为 Ad-hoc、未经 Apple 公证的社区构建，补充 Gatekeeper 放行、SHA-256 校验、Latest 约定、Homebrew 更新与完全卸载注意事项。

## v1.1.1 — 2026-06-18

### Fixed

- **permissions**: 重构并完善完全磁盘访问权限检测逻辑，降低已授权后仍被误判为未授权的概率。
- **menu**: 优化扁平化右键菜单中收藏动作与普通动作之间的间隔，减少一级菜单视觉割裂。

### Documentation

- **readme**: 新增真实软件截图，覆盖 Finder 一级右键菜单、动作配置、权限与诊断页面。
- **readme-en**: 同步英文 README 的截图和功能说明。

## v1.1.0 — 2026-06-18

### Added

- **menu**: 新增扁平化一级右键菜单模式，并设为默认；已启用且当前可用的动作会直接显示在 Finder 右键一级菜单中，收藏动作置顶。
- **menu**: 保留按分类显示的二级菜单模式，用户可在「动作」页切换。
- **core**: 新增 renderer-neutral 的 `MenuLayout` 菜单布局引擎，降低 FinderSync 渲染层与动作编排逻辑的耦合。
- **tests**: 增加菜单布局相关单元测试，覆盖扁平化、分类显示、收藏置顶、禁用与不可用动作过滤。

## v1.0.2 — 2026-06-18

### Changed

- **icon**: 更新应用图标资源与发布制品版本。

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
