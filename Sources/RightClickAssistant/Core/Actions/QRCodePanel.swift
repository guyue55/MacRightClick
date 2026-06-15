import AppKit

// MARK: - 纯逻辑（可单测）

/// 把 `NSImage` 编码成 PNG `Data`。
///
/// 抽成独立模块的理由：
/// - 「保存为 PNG」按钮的成功率取决于 NSImage → bitmap → PNG 的链路是否完整
/// - NSPanel 装配代码不可单测；但 PNG 编码这一步是纯函数，独立出来后 XCTest 可在
///   非 GUI 上下文里直接断言文件签名
/// - 后续若要换更稳的编码路径（比如 ImageIO CGImageDestination），只需改这里一处
public enum QRCodeImageRenderer {
    public static func encodePNG(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

/// 把 `NSImage` 写入指定 `NSPasteboard`。
///
/// 抽出 pasteboard 形参的理由：
/// - 单测里可以传 `NSPasteboard(name:)` 创建的独立板，避免污染用户的系统剪贴板
/// - 生产代码用 `.general`，行为完全一致
public enum QRCodePasteboardWriter {
    public static func copy(image: NSImage, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}

// MARK: - UI 装配（不可单测，靠 build + 手动验证）

/// 二维码浮动面板控制器。
///
/// 设计要点：
/// - 用 `NSPanel` + `.nonactivatingPanel`，不会抢主窗口焦点，符合工具型悬浮窗语义
/// - 长文本走 `NSScrollView + NSTextView` 滚动预览，短文本同样使用滚动容器（统一布局，
///   不需要按文本长度切换样式）
/// - 「保存为 PNG」/「拷贝图片」两个按钮分别复用 QRCodeImageRenderer 与
///   QRCodePasteboardWriter，UI 这层不再持有编码 / 剪贴板逻辑
/// - panel 必须由调用者强引用（见 UtilityAction.activeQRController），否则
///   控制器会随 stack 退出而析构，panel 立刻消失
final class QRCodePanelController: NSObject {
    private let panel: NSPanel
    private let image: NSImage
    private let text: String

    init(image: NSImage, text: String) {
        self.image = image
        self.text = text
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.title = "文本二维码"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.center()

        let imageView = NSImageView(frame: NSRect(x: 20, y: 100, width: 280, height: 280))
        imageView.image = image
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.white.cgColor
        imageView.layer?.cornerRadius = 6

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 50, width: 280, height: 40))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = NSTextView(frame: scrollView.bounds)
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 11)
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView

        let saveBtn = NSButton(title: "保存为 PNG", target: self, action: #selector(savePNG))
        saveBtn.frame = NSRect(x: 20, y: 12, width: 130, height: 28)
        saveBtn.bezelStyle = .rounded

        let copyBtn = NSButton(title: "拷贝图片", target: self, action: #selector(copyImage))
        copyBtn.frame = NSRect(x: 170, y: 12, width: 130, height: 28)
        copyBtn.bezelStyle = .rounded

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 420))
        content.addSubview(imageView)
        content.addSubview(scrollView)
        content.addSubview(saveBtn)
        content.addSubview(copyBtn)
        panel.contentView = content
    }

    func show() { panel.orderFront(nil) }

    @objc private func savePNG() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "qrcode.png"
        savePanel.level = .modalPanel
        savePanel.orderFrontRegardless()
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        guard let data = QRCodeImageRenderer.encodePNG(from: image) else {
            SharedHUDManager.show(title: "保存失败", content: "PNG 编码失败", isSuccess: false)
            return
        }
        do {
            try data.write(to: url)
            SharedHUDManager.show(title: "已保存", content: url.lastPathComponent, isSuccess: true)
        } catch {
            SharedHUDManager.show(title: "保存失败", content: error.localizedDescription, isSuccess: false)
        }
    }

    @objc private func copyImage() {
        QRCodePasteboardWriter.copy(image: image)
        SharedHUDManager.show(title: "已拷贝图片", content: "可粘贴到聊天或文档", isSuccess: true)
    }
}
