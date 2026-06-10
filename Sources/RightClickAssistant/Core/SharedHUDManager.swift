import Foundation
import AppKit

/// 全局高保真磨砂玻璃 HUD 提示管理器 (SharedHUDManager)
/// 专为 macOS 商业级桌面体验设计，提供带微动画、支持毛玻璃特效的右上角轻量通知。
public final class SharedHUDManager {
    
    /// 显示一个全局悬浮 HUD 通知
    /// - Parameters:
    ///   - title: 通知主标题
    ///   - content: 详细内容说明
    ///   - iconName: 自定义系统 SFSymbol 图标名称（若为 nil 则根据 isSuccess 自动决定）
    ///   - isSuccess: 是否代表操作成功（用以调整图标颜色与微视觉渲染）
    public static func show(title: String, content: String, iconName: String? = nil, isSuccess: Bool = true) {
        DispatchQueue.main.async {
            let width: CGFloat = 360
            let height: CGFloat = 85
            
            // 1. 定位右上角物理安全显示区域
            let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
            let x = screenRect.origin.x + screenRect.size.width - width - 20
            let y = screenRect.origin.y + screenRect.size.height - height - 20
            
            let panel = NSPanel(
                contentRect: NSRect(x: x, y: y, width: width, height: height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            
            // 2. 核心毛玻璃特效面板 (Visual Effect View)
            let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            visualEffectView.material = .hudWindow
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.layer?.cornerRadius = 12
            visualEffectView.wantsLayer = true
            
            // 3. 多态图标自适应渲染
            let iconImageView = NSImageView(frame: NSRect(x: 16, y: 20, width: 44, height: 44))
            let defaultIcon = isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            iconImageView.image = NSImage(systemSymbolName: iconName ?? defaultIcon, accessibilityDescription: nil)
            iconImageView.contentTintColor = isSuccess ? .systemGreen : .systemRed
            
            // 4. 文字细节布局
            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.frame = NSRect(x: 72, y: 44, width: 270, height: 20)
            titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
            titleLabel.textColor = .labelColor
            
            let contentLabel = NSTextField(labelWithString: content)
            contentLabel.frame = NSRect(x: 72, y: 12, width: 270, height: 30)
            contentLabel.font = .systemFont(ofSize: 11, weight: .regular)
            contentLabel.textColor = .secondaryLabelColor
            contentLabel.cell?.lineBreakMode = .byTruncatingTail
            
            visualEffectView.addSubview(iconImageView)
            visualEffectView.addSubview(titleLabel)
            visualEffectView.addSubview(contentLabel)
            
            panel.contentView = visualEffectView
            
            // 5. 优雅动画过渡效果
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 1.0
            }, completionHandler: {
                // 停留 2.5 秒后自动淡出销毁
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.35
                        panel.animator().alphaValue = 0
                    }, completionHandler: {
                        panel.close()
                    })
                }
            })
        }
    }
}
