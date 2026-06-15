# 真机验收报告 — UX Hardening

- 日期：2026-06-16
- 分支：`codex/ux-hardening`（PR #1，Draft）
- 验收对象：commit `acb7916` 之后的 `/Applications/RightClickAssistant.app`
- 主机环境：仅 CommandLineTools，无 Xcode.app；XCTest 与 PDFKit `swift test` 因 SwiftBridging 重定义不可跑，验证以 `Scripts/build.sh` 产物 + 系统工具（`codesign`/`mdls`/`qlmanage`/`/usr/bin/log`）+ 静态 grep 为准。

## 0. 本轮最有价值的产物

真机验收过程中发现并修复了一条历史 codesign Bug：

- 现象：主 App 的 `codesign` 调用未带 `--entitlements`，导致打出来的 App 一直处于 adhoc 无 entitlements 的状态，App Group 行为靠运行时偶然容错。
- 修复：commit `acb7916 fix(build): 主 App codesign 必须传 --entitlements，且 website 路线主 App 是非 sandbox`。
- 同步纠正：之前误将 `c4a37e3` 描述为「主 App sandbox」，真相是仅 Extension 沙盒，主 App 一直是非 sandbox；`entitlements/website.host.entitlements` 现在仅含 `application-groups`，无 sandbox key；entitlements 注释里的 `<extBundle>` token 触发 codesign 内嵌 plist 解析报错，已改为纯文字。

## 1. 自动验收 Gate（已通过，证据见命令输出）

| Gate | 来源 | 命令 | 关键证据 |
| --- | --- | --- | --- |
| G1 安装到 /Applications | plan G2 | `codesign --verify --deep --strict --verbose=2 /Applications/RightClickAssistant.app` | `valid on disk` + `satisfies its Designated Requirement` |
| G1' Entitlements 已嵌入 | acb7916 验证 | `codesign -d --entitlements :- /Applications/RightClickAssistant.app` | 含 `com.apple.security.application-groups = group.guyue.RightClickAssistant` |
| 步骤 2 启动 + 进程存活 | spec §5.2 | `pgrep -fl RightClickAssistant` | 主 App + Extension 两 PID 同时存活（验收后已 `pkill -9` 收尾） |
| 步骤 6 Office 模板可解析 | spec §5.2 | `mdls -name kMDItemContentType` 模板 | docx → `org.openxmlformats.wordprocessingml.document`，xlsx → `…spreadsheetml.sheet`，pptx → `…presentationml.presentation` |
| 步骤 7 PDF 模板可解析 | spec §5.2 | python 复刻 `NewFileAction` 字节流 → `mdls` + `qlmanage -t` | 上一轮已通过；本轮二次确认 PDF 走运行时生成（`blank.pdf` 不入 Bundle 是设计选择） |
| 步骤 12 状态栏移除高风险入口 | spec §5.2 | `grep -n NSMenuItem` `Sources/RightClickAssistant/AppDelegate.swift` | 状态栏菜单仅 `显示右键助手设置` / `关于` / `退出`；`toggleHiddenFiles` 仅作为可勾选的右键 Action 注册到 dispatcher（行 147），未暴露在托盘 |
| 步骤 14 OSLog 分层 + 不写 extension.log | spec §5.2 / plan G5 | `/usr/bin/log show --predicate 'subsystem == "guyue.RightClickAssistant"' --last 30m` | 同时看到 `:ext` 与 `:storage` 两个 category；`~/Library/Containers/guyue.RightClickAssistantExtension/Data/Library/Logs/extension.log` 不存在 |

OSLog 实测样本：

```text
02:20:22.129 PID 71591 RightClickAssistantExtension: [guyue.RightClickAssistant:ext]     [FinderSync] 插件初始化启动...
02:20:22.174 PID 71590 RightClickAssistant:          [guyue.RightClickAssistant:storage] [SharedFolderMonitor] 内核级物理文件夹监控服务成功启动 ...
02:21:05.041 PID 71591 RightClickAssistantExtension: [guyue.RightClickAssistant:ext]     [FinderSync] 监控目录注册成功，当前激活数量: 5
```

## 2. 非阻塞观察（不在本轮 commit 修）

- AppDelegate 通过 `SharedStorageManager.writeLog` 写日志，命中的全部是 `:storage` category。原因是 `writeLog` 内部统一走 `AppLog.info(.., category: .storage)`，主 App 自身的生命周期/状态变更也被归入 storage。期望表现是这类事件归到 `:host`。已记录待跟进，不阻断本轮收尾。
- `Templates/blank.pdf` 不存在于 Bundle 是设计选择：`NewFileAction` 用纯字符串拼接 `%PDF-1.4` 字节流在运行时生成（见 [`NewFileAction.swift`](/Users/guyue/GitProject/mac右键/Sources/RightClickAssistant/Core/Actions/NewFileAction.swift:64)），不需要外置模板。建议下一轮把这点写进 spec §5.2 的备注里，避免再被当成缺失。

## 3. 残留 Gate（需要人手 5 分钟点完）

本机环境无法自动覆盖以下 9 项，请按 §4 清单逐条勾选，结果回填到本文件「执行结果」段落。

- spec §5.2 第 3、4、5、8、9、10、11、13 步
- spec §5.3 性能基线：menu(for:) < 30ms 中位数（与第 13 步合并验证）
- plan G6：macOS 13 Ventura / macOS 14 Sonoma 至少一台真机各跑一次

`swift test` 因 CommandLineTools 环境的 SwiftBridging 重定义在本机不可执行，G1（单测）需要在有 Xcode 的环境/CI 上补跑，本轮暂挂。

## 4. 人手点 9 项 Checklist

| # | 来源 | 操作 | 期望现象 | 失败时怎么截图 |
| --- | --- | --- | --- | --- |
| 1 | spec §5.2 step 3 | 菜单栏小图标 → 显示右键助手设置 → 概览页 | 已启用扩展时看到「重新注册扩展」入口；未启用时只看到 banner 内一组按钮 | 截屏整个概览页 |
| 2 | step 4 | 点击「一键注册扩展」 | HUD 显示注册成功，重启 Finder 后右键看得到自定义菜单 | HUD 截屏 + Finder 右键截屏 |
| 3 | step 5 | 在「设置→动作」启用「彻底删除」，回 Desktop 选一个临时文件右键执行 | alert 是 critical 样式（红色感叹号），默认按钮是「取消」，按 Return 不会删除 | alert 弹窗截屏 |
| 4 | step 8 | 副屏右键空白处触发任意 Action | HUD 出现在副屏顶部而不是主屏 | 双屏截屏（cmd+shift+3 全屏） |
| 5 | step 9 | HUD 出现时单击 HUD / 按 Esc | 立即淡出，不等自动消失 | 录屏 5 秒 |
| 6 | step 10 | 高级页 →「恢复全部默认」 | 监听目录、收藏、提示开关全被清空 | 操作前后高级页对比截屏 |
| 7 | step 11 | 高级页 →「仅恢复动作启用状态」 | 收藏目录保留，仅动作开关回到默认 | 操作前后对比截屏 |
| 8 | step 13 + §5.3 | 在 Finder 里连续右键 5 次（不同目录） | 菜单弹出无明显延迟，主观 < 200ms；如开了 signpost，中位数应 < 30ms | 录屏 |
| 9 | plan G6 | 在 macOS 13 / 14 真机各跑一遍前 8 项 | 行为一致 | 写明系统版本 |

## 5. 执行结果（人手验收后回填）

- [ ] 1 概览页单一引导
- [ ] 2 一键注册扩展
- [ ] 3 永久删除 critical alert
- [ ] 4 HUD 跟随副屏
- [ ] 5 HUD 单击 / Esc 立即淡出
- [ ] 6 恢复全部默认
- [ ] 7 仅恢复动作启用状态
- [ ] 8 menu(for:) 主观无延迟
- [ ] 9 macOS 13 / 14 各一次

## 6. 收尾命令记录

```bash
pkill -9 -f RightClickAssistantExtension
pkill -9 -f RightClickAssistant
pgrep -fl RightClickAssistant   # 期望空输出
```

## 7. 链路一览

- spec：[`docs/superpowers/specs/2026-06-15-ux-hardening-design.md`](/Users/guyue/GitProject/mac右键/docs/superpowers/specs/2026-06-15-ux-hardening-design.md)
- plan：[`docs/superpowers/plans/2026-06-15-ux-hardening.md`](/Users/guyue/GitProject/mac右键/docs/superpowers/plans/2026-06-15-ux-hardening.md)
- 关键修复 commit：`acb7916`
- PR：https://github.com/guyue55/MacRightClick/pull/1
