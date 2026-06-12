import Foundation
import AppKit

/// 全局磨砂玻璃 HUD 提示管理器 (SharedHUDManager)
/// 提供带微动画、支持毛玻璃特效的屏幕顶部中央紧凑型通知。
/// 实现了高内聚低耦合、接口隔离与完全双写配置感知（注2、注4）。
public final class SharedHUDManager {
    private static weak var activePanel: NSPanel?
    
    /// 显示一个全局悬浮 HUD 通知
    /// - Parameters:
    ///   - title: 通知主标题
    ///   - content: 详细内容说明
    ///   - iconName: 自定义系统 SFSymbol 图标名称（若为 nil 则根据 isSuccess 自动决定）
    ///   - isSuccess: 是否代表操作成功（用以调整图标颜色与微视觉渲染）
    public static func show(title: String, content: String, iconName: String? = nil, isSuccess: Bool = true) {
        // 1. 成功通知静默过滤。
        // 当用户在设置中关闭了“启用操作成功悬浮通知”后，成功的日常 HUD 提示保持静默；
        // 错误/失败 HUD 仍会显示，便于发现权限或系统拦截问题。
        let isHUDEnabled = SharedStorageManager.shared.getBool(forKey: "enable_success_hud", defaultValue: true)
        if isSuccess && !isHUDEnabled {
            print("[SharedHUD] 成功提示静默过滤拦截: \(title) - \(content)")
            return
        }
        
        DispatchQueue.main.async {
            // 2. 经典防冲突重叠机制：如果已有悬浮窗，立即物理关闭并回收
            if let existing = activePanel {
                existing.close()
                activePanel = nil
            }
            
            let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
            // 3. 胶囊几何尺寸，长内容自适应加宽。
            let baseWidth: CGFloat = 260
            let maxWidth: CGFloat = min(520, screenRect.size.width * 0.66)
            let contentWidth = CGFloat((content as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .regular)
            ]).width)
            let width: CGFloat = max(baseWidth, min(baseWidth + contentWidth * 0.6, maxWidth))
            let height: CGFloat = 48
            let x = screenRect.origin.x + (screenRect.size.width - width) / 2
            let y = screenRect.origin.y + screenRect.size.height - height - 30 // 位于菜单栏下方
            
            let panel = NSPanel(
                contentRect: NSRect(x: x, y: y, width: width, height: height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            activePanel = panel
            
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            
            // 5. 高清磨砂玻璃面板 (Visual Effect View)
            let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            visualEffectView.material = .hudWindow
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.layer?.cornerRadius = 24 // Capsule pill
            visualEffectView.wantsLayer = true
            
            // 6. 新增 1px 自适应微边框，通过半透明描边极大强化深色和浅色模式下的边缘视网膜锐利度
            visualEffectView.layer?.borderWidth = 1.0
            visualEffectView.layer?.borderColor = NSColor.separatorColor.cgColor
            
            // 7. 多态图标微缩型自适应渲染
            let iconImageView = NSImageView(frame: NSRect(x: 16, y: (height - 20) / 2, width: 20, height: 20))
            let defaultIcon = isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            iconImageView.image = NSImage(systemSymbolName: iconName ?? defaultIcon, accessibilityDescription: nil)
            iconImageView.contentTintColor = isSuccess ? .systemGreen : .systemRed
            
            // 8. 紧凑型精细双行文字排版
            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.frame = NSRect(x: 46, y: 24, width: width - 46 - 16, height: 16)
            titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
            titleLabel.textColor = .labelColor
            titleLabel.backgroundColor = .clear
            titleLabel.isBezeled = false
            titleLabel.isEditable = false
            titleLabel.cell?.lineBreakMode = .byTruncatingTail
            
            let contentLabel = NSTextField(labelWithString: content)
            contentLabel.frame = NSRect(x: 46, y: 8, width: width - 46 - 16, height: 14)
            contentLabel.font = .systemFont(ofSize: 10, weight: .regular)
            contentLabel.textColor = .secondaryLabelColor
            contentLabel.backgroundColor = .clear
            contentLabel.isBezeled = false
            contentLabel.isEditable = false
            contentLabel.cell?.lineBreakMode = .byTruncatingTail
            
            visualEffectView.addSubview(iconImageView)
            visualEffectView.addSubview(titleLabel)
            visualEffectView.addSubview(contentLabel)
            
            panel.contentView = visualEffectView
            
            // 9. 模拟物理回弹的阻尼弹簧入场动画 (Damped Spring/Overshoot Physics)
            // 初始状态 y + 15，alpha 0。弹性滑落至最终位置 y 轴，在 0.4s 内完成。
            panel.setFrame(NSRect(x: x, y: y + 15, width: width, height: height), display: true)
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.4
                // 阻尼回弹贝塞尔时间曲线 (Overshoot: controlPoints: 0.15, 0.85, 0.35, 1.1)
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0.85, 0.35, 1.1)
                panel.animator().setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
                panel.animator().alphaValue = 1.0
            }, completionHandler: {
                // 停留 2.0 秒后自动淡出并回收销毁
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.3
                        panel.animator().alphaValue = 0
                    }, completionHandler: {
                        panel.close()
                        if activePanel === panel {
                            activePanel = nil
                        }
                    })
                }
            })
        }
    }
}
