# 设计：MacRightClick UX 强化与分发路线收敛

- 创建日期：2026-06-15
- 状态：草案，待评审
- 作者：Codex
- 范围：单实现周期内可完成；上承 `2026-06-10-macrightclick-phased-roadmap.md`，下启同日期 plan

## 1. 背景

项目当前主分发路线为「website-dev」（Ad-hoc 签名），主 App + FinderSync Extension + 共享存储/通道三件套。上一轮交接已经落地 17 项 UX 修复（见 baseline commit）。本轮针对在那之后的二次审查发现的 14 项缺陷做系统性收敛，覆盖安全、正确性、性能、一致性、健壮性五个维度。

完整缺陷清单与代码定位见同日期会话中的 14 项审查结论；本 spec 聚焦设计选择与边界。

## 2. 目标与非目标

目标（按优先级）：

- A. 安全与正确性
  - A1. 永久删除流程符合 macOS HIG：`.critical` 样式、默认按钮取消、列出文件名摘要、提供「移到废纸篓」中间档
  - A2. Office .docx/.xlsx/.pptx 模板可被 Word/Excel/PowerPoint/Pages 双击直接打开
  - A3. 状态栏托盘移除「切换 Finder 隐藏文件」高风险快捷入口；`killall Finder` 改为 AppleScript 优雅退出
  - A4. Entitlements 与运行时常量按 `DISTRIBUTION_ROUTE` 真正分叉，去掉硬编码 `forceLocalSandboxExchange`
- B. 体验与一致性
  - B1. 概览页扩展未启用时单一引导入口，去除 banner 与 ExtensionRegistrationBox 的视觉重复
  - B2. SharedHUD 跟随鼠标所在屏幕，支持点击/Esc 立即关闭
  - B3. Finder 右键菜单弹出主路径走进程内缓存，目标 < 30ms（30 个 action）
  - B4. Release 构建启用 `-O` 优化
  - B5.「恢复默认」拆「仅动作」与「全部默认」
  - B6. 跨卷 Copy-Then-Delete 事务化（失败 cleanup 残留）
- C. 健壮性与收尾
  - C1. 日志切换到 `os.Logger`（OSLog），停止追加自管 `extension.log`
  - C2. 二维码窗口加「保存为 PNG / 拷贝图片」与长文本滚动预览
  - C3. `OnboardingStepsView` 删除 macOS < 13 死分支
  - C4. `PermissionsSettingsView` 2s 轮询改为事件驱动

非目标：

- Mac App Store 路线本轮仅在代码层让路（条件编译 + 文档），不构建 MAS 产物
- 国际化、菜单二级深度调整、整体视觉重构均不做
- 现有功能矩阵不增不减

## 3. 架构与模块边界

整体仍是「主 App / FinderSync Extension / 共享层」三件套。本轮**不引入新进程或新通信链路**，仅在共享层抽出三个新组件，把横切关注点从视图层和动作层归位。

### 3.1 新增模块（共享层）

| 模块 | 路径 | 职责 | 解决 |
| --- | --- | --- | --- |
| AppLog | `Sources/RightClickAssistant/Core/Logging/AppLog.swift` | 极薄 `os.Logger` 包装，按 `subsystem = guyue.RightClickAssistant` 切 category（`host` / `ext` / `storage` / `action` / `ui`，`ext` 避开 Swift 关键字 `extension`），对外只暴露 `info / debug / error` | C1 |
| Distribution | `Sources/RightClickAssistant/Core/Distribution.swift` | 唯一来源的分发路线常量，`route / usesAppGroup / allowsCrossContainerExchange`，由 build.sh 注入 `-D WEBSITE_DEV / WEBSITE_RELEASE / MAC_APP_STORE` | A4 |
| InstalledAppRegistry | `Sources/RightClickAssistant/Core/InstalledAppRegistry.swift` | 进程内缓存「bundleId → URL?」，TTL 30s + `NSWorkspace.didLaunchApplication / didTerminateApplication` 失效 | B3 |
| ActionConfigCache | `Sources/RightClickAssistant/Core/ActionConfigCache.swift` | 进程内缓存 `enable_action_*` 与 `favoriteActionIds`，配合 `configChanged` 失效 | B3 |

### 3.2 改造模块

| 模块 | 主要改造 | 解决 |
| --- | --- | --- |
| FileManageAction | 抽出 `DestructiveActionConfirmer`（fileprivate），`.critical` + 文件名摘要 + 三按钮（取消/移到废纸篓/永久删除）；跨卷 move 事务化 | A1 / B6 |
| UtilityAction | `killall Finder` 改 osascript quit + 必要时 `open -a Finder`；二维码面板抽出为 fileprivate `QRCodePanelController`（与 UtilityAction 同文件，隔离生命周期与按钮回调），加保存/拷贝/滚动文本 | A3 / C2 |
| NewFileAction | `defaultEmptyBytes` 的 docx/xlsx/pptx 改读 `Bundle.main` 下 `Templates/blank.docx|.xlsx|.pptx`；Resources 仓库直存最小可打开骨架 | A2 |
| AppDelegate | 状态栏托盘去掉「切换 Finder 隐藏文件」菜单项 | A3 |
| SharedHUDManager | `screenFrame(screens:mouseLocation:fallback:)` + 点击手势 + Esc 监听淡出 | B2 |
| FinderSync | `menu(for:)` 主路径走 `ActionConfigCache + InstalledAppRegistry`，所有 `logToSharedContainer(.debug)` 改 `AppLog.debug` | B3 / C1 |
| ContentView | OverviewSettingsView 去重；AdvancedSettingsView 恢复默认拆两按钮；OnboardingStepsView 删 else；PermissionsSettingsView 移除 2s timer | B1 / B5 / C3 / C4 |
| SharedStorageManager | 删 `forceLocalSandboxExchange = true`，改读 `Distribution.allowsCrossContainerExchange`；保留旧 `extension.log` 路径只读供导出 | A4 / C1 |
| build.sh | 按 `DISTRIBUTION_ROUTE` 写不同 entitlements 模板；`website-release` / `mac-app-store` 启用 `-O`；新增 office 模板拷贝步骤 | A4 / B4 / A2 |

### 3.3 模块依赖（自下而上）

```
os.Logger → AppLog
SharedStorageManager ──┬→ Distribution（编译期常量）
                       └→ AppLog
ActionConfigCache  → SharedStorageManager + AppLog
InstalledAppRegistry → AppLog

ActionDispatcher (Host) ──→ Actions（NewFile / FileManage / Terminal / Util）
FinderSync (Extension)  ──┬→ ActionDispatcher
                          ├→ ActionConfigCache
                          └→ InstalledAppRegistry

Actions ──┬→ DestructiveActionConfirmer (内部)
          └→ QRCodePanelController       (内部)

ContentView (Views) ──┬→ SharedStorageManager
                      ├→ ActionDispatcher
                      └→ AppLog
```

模块边界原则：

- 视图层（ContentView 系列）只读写 `SharedStorageManager` 与 `ActionDispatcher`，不直接调系统 API
- Actions 层不直接读写 UserDefaults / config.json，只通过 `SharedStorageManager` 与 cache 层
- Cache 层是 Single Source of Truth in-process，写动作必经过 `SharedStorageManager`，cache 失效靠 `configChanged` 通知
- 跨进程通信通道（`PendingActions/` 队列 + `DistributedNotificationCenter`）零改动

## 4. 数据流与流程

### 4.1 共享存储路径选择

Distribution.swift 编译期常量：

- 当 MAC_APP_STORE：usesAppGroup = true、allowsCrossContainerExchange = false
- 当 WEBSITE_DEV / WEBSITE_RELEASE：usesAppGroup = false、allowsCrossContainerExchange = true

SharedStorageManager.sharedContainerURL 的选择逻辑：

- usesAppGroup 为 true → 用 containerURL(forSecurityApplicationGroupIdentifier:)
- 否则若 allowsCrossContainerExchange 为 true → 用 ~/Library/Containers/<extBundle>/Data
- 都不满足 → fail-fast 写入 AppLog.error 并阻断写入（兜底防止静默错路）

主 App entitlements（website 路线）相应去掉 app-sandbox 与 files.downloads.read-write，仅 release 保留 hardened runtime。Extension entitlements 维持 sandbox=true。

### 4.2 Finder 右键菜单渲染（B3 主热路径）

旧路径每个 action 双读 UserDefaults+config.json，且 TerminalOpenAction.isAvailable 内同步调 NSWorkspace.urlForApplication，30 个 action 累积明显延迟。

新路径：

- 进程启动一次：ActionConfigCache.preheat()、InstalledAppRegistry.preheat([已知 bundleId])
- 每次 menu(for:)：cache.isFavorite(actionId)、cache.isEnabled(actionId, default:)、registry.isInstalled(bundleId)，全部 O(1) 内存
- 收到 configChanged → cache.invalidate()
- 收到 NSWorkspace.didLaunchApplication / didTerminateApplication → registry.invalidate(bundleId)
- 所有 menu 主路径的 logToSharedContainer(.debug) 改 AppLog.debug，OSLog 在生产 0 开销

### 4.3 永久删除流程（A1）

DestructiveActionConfirmer.confirm 输入：

- style：.critical
- title：「确认永久删除？」
- summary：列出最多 5 个文件名 + " 等共 N 项"
- buttons：取消（默认）/ 移到废纸篓 / 永久删除

输出 → 三选一：

- cancel：直接 return false
- recoverable：FileManager.trashItem(at:resultingItemURL:) 逐个，HUD「已移到废纸篓 N 项」
- destructive：FileManager.removeItem 逐个，HUD「已彻底删除 N 项」

按 Return 命中默认按钮（取消），符合 macOS HIG「破坏性默认应被防御」。

### 4.4 跨卷 moveTo / 跨目录粘贴事务化（B6）

伪代码：

- do { copyItem(src, dest); sanityCheck(dest); removeItem(src); }
- catch { try? removeItem(dest); 计入失败计数 }

sanityCheck：dest 为文件时 size > 0；为目录时非空（与 src 一致性可选）。

### 4.5 HUD 多屏与可关闭（B2）

- 屏幕选择：NSScreen.screens.first 中 frame 包含 NSEvent.mouseLocation 的那个，否则 NSScreen.main
- panel.contentView 加 NSClickGestureRecognizer 触发淡出
- 通过 NSEvent.addLocalMonitorForEvents(matching: .keyDown) 监听 keyCode == 53（Esc），命中即淡出
- panel 关闭时移除 monitor，避免泄漏

### 4.6 概览页结构（B1）

- ExtensionStatusBanner.isEnabled == true：绿色 banner + ExtensionRegistrationBox（仅此场景显示，文案改为「重新注册扩展（修复入口）」）
- ExtensionStatusBanner.isEnabled == false：橙色 banner，banner 内含「打开扩展设置」「一键注册扩展」+ OnboardingStepsView，不再叠加 ExtensionRegistrationBox

### 4.7 恢复默认拆分（B5）

- 仅恢复动作启用状态：清 enable_action_*
- 恢复全部默认设置：清 enable_action_* + favoriteActionIds + watchedDirectoryPaths + shouldEnableiCloudMenu + enable_success_hud + enable_debug_logging
- 两项均触发 refreshID + configChanged

## 5. 测试与回归边界

### 5.1 单元测试（XCTest）

- testOfficeTemplatesAreOpenable：Process 调 unzip -l 校验 docx/xlsx/pptx 模板含 [Content_Types].xml 与对应主体 part（如 word/document.xml）；旧 testOfficeFileTemplateBytes 删除
- testPDFTemplateIsParseable：PDFDocument(url:) 能成功打开且 pageCount == 1
- testDestructiveDeleteAlertConfiguration：DestructiveActionConfirmer.makeAlert(...) 配置：alertStyle == .critical、第一个按钮 == "取消"、按 Return 返回 .cancel
- testTrashFallback：mock 出 trash 路径，断言 trashItem 被调用且 src 不再存在
- testCrossVolumeMoveCleanupOnFailure：注入 copy 成功/sanityCheck 抛错的桩，断言 dest 残留被 cleanup
- testActionConfigCacheInvalidation：写 enable_action_X=false → cache.isEnabled(X) == false；写 true 再 invalidate 后 == true
- testInstalledAppRegistryTTL：桩化 NSWorkspace 查询计数，30s 内多次调用只查一次
- testSharedHUDPicksMouseScreen：注入 mouseLocation 在 screen B 的桩，断言 panel.frame 在 screen B
- testResetActionsOnly_PreservesFavorites：设置 favorite + enable，调「仅动作」，favorite 保留 enable 清掉
- testResetAll_ClearsEverything：同上但调「全部默认」，全部清空
- testDistributionRouteConstantsAreConsistent：编译期判断；MAC_APP_STORE 时 usesAppGroup == true 且 allowsCrossContainerExchange == false

### 5.2 手工验收清单

- 1. cp -R build/RightClickAssistant.app /Applications/，pkill 旧进程
- 2. 第一次启动 → 菜单栏小图标出现，无 Dock 图标，无窗口闪现
- 3. 菜单栏 → 显示设置 → 概览页能看到「重新注册扩展」入口（已启用时）；扩展未启用时只看到 banner 内一组按钮
- 4. 「一键注册扩展」按钮 → HUD 显示注册成功，重启 Finder 后右键有菜单
- 5. 启用「彻底删除」→ 在 Desktop 右键 → alert 是 critical 样式（红色感叹号）、默认按钮「取消」（按 Return 不会删）
- 6. Desktop 右键空白 → 新建 Word/Excel/PPT → 双击 → 不报损坏，能打开空白文档
- 7. 新建 PDF → 双击 → Preview 打开空白 1 页
- 8. 双屏：副屏右键 → HUD 出现在副屏顶部
- 9. HUD 出现时单击 / 按 Esc → 立即淡出
- 10. 高级页「恢复全部默认」→ 监听目录、收藏、提示开关都被清空
- 11. 高级页「仅恢复动作启用状态」→ 收藏保留
- 12. 状态栏托盘点开 → 不再有「切换 Finder 隐藏文件」项
- 13. Finder 里连续右键 5 次（不同目录）→ 菜单弹出无明显延迟（< 200ms）
- 14. log show --predicate 'subsystem == "guyue.RightClickAssistant"' --last 1m → 能看到分层 category 输出；本次会话不再追加 extension.log

### 5.3 性能基线

- menu(for:) 在 30 个注册 action 下，第 2 次及之后渲染主路径耗时目标 < 30ms（用 signpost 包一层，跑 5 次取中位数）
- InstalledAppRegistry 命中缓存的查询 < 0.1ms
- 主 App 启动后 30 秒内不应出现 extension.log 文件追加（实测 stat 文件 mtime）
- 二维码窗口从触发到渲染 < 150ms（剪贴板纯文本场景）

### 5.4 失败回滚策略

- Office 模板与 NewFileAction 改动单 commit，回滚靠 git revert
- Cache 模块以 #if DISABLE_PROCESS_CACHE 切回旧路径，作为线上发现死锁/失效问题的逃生口（默认关闭，编译期开关）
- Distribution 切换路线只影响 entitlements 与编译期常量，build.sh 不通过则没有产物

### 5.5 兼容与降级

- 旧版用户从 1.0.1 升级：config.json schema 不变，enable_action_* 键继续兼容；新增 cache 与 Distribution 模块都是进程内行为，不污染配置
- 旧 extension.log 文件保留只读，「诊断」页加一个「导出旧日志」按钮，导出后 7 天内不再追加

## 6. 已确认的开放选项

- 状态栏托盘「切换 Finder 隐藏文件」入口处理：选 A，直接移除（最干净）
- Office 模板生成方式：选 A，仓库直接 commit Resources/Templates/blank.docx|.xlsx|.pptx 二进制（最稳，30~50KB 体积可忽略）

## 7. 风险与未知

- Risk-1：Office 三件套开 .docx/.xlsx/.pptx 的最小骨架在不同版本 Office、Pages、WPS 下表现可能不一致，需要本机交叉验证至少两个：Microsoft Word、Pages
- Risk-2：MAS 路线 Distribution 常量虽已分叉，但首次构建会暴露多个目前依赖「主 App 非 sandbox」的逻辑（如读 ~/Library/Safari 检测 FDA），列入下一周期
- Risk-3：OSLog 切换后旧诊断脚本（README Q&A 里教用户 cat extension.log）需同步更新，避免文档断裂
