import Foundation
import AppKit
import CryptoKit
import CoreImage

/// 实用小工具类型
public enum UtilityType: String, Codable {
    case calculateMD5 = "calculateMD5"
    case calculateSHA256 = "calculateSHA256"
    case toggleHiddenFiles = "toggleHiddenFiles"
    case textToQRCode = "textToQRCode"
    case convertToPNG = "convertToPNG"
    case convertToJPEG = "convertToJPG"
}

public final class UtilityAction: MenuAction {
    public let actionId: String
    public let localizedTitle: String
    public let iconName: String?
    public let category: ActionCategory = .utility
    
    public let utilityType: UtilityType
    
    public init(type: UtilityType) {
        self.utilityType = type
        self.actionId = "org.antigravity.action.utility.\(type.rawValue)"
        
        switch type {
        case .calculateMD5:
            self.localizedTitle = "获取文件 MD5 校验码"
            self.iconName = "number.square"
        case .calculateSHA256:
            self.localizedTitle = "获取文件 SHA256 校验码"
            self.iconName = "number.square.fill"
        case .toggleHiddenFiles:
            self.localizedTitle = "切换显示隐藏文件"
            self.iconName = "eye.slash"
        case .textToQRCode:
            self.localizedTitle = "转换选中文本为二维码"
            self.iconName = "qrcode"
        case .convertToPNG:
            self.localizedTitle = "转换为 PNG 格式"
            self.iconName = "photo"
        case .convertToJPEG:
            self.localizedTitle = "转换为 JPEG 格式"
            self.iconName = "photo.fill"
        }
    }
    
    public func isAvailable(for targetURLs: [URL]) -> Bool {
        switch utilityType {
        case .toggleHiddenFiles:
            return true // 无需选中任何文件也可以切换
        case .calculateMD5, .calculateSHA256:
            // 只有文件（非目录）可以使用哈希校验
            guard let first = targetURLs.first else { return false }
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir) && !isDir.boolValue
        case .textToQRCode:
            // 选中文本转二维码（可以通过剪切板内的内容）
            return true
        case .convertToPNG, .convertToJPEG:
            // 必须选中了图片格式文件
            guard let first = targetURLs.first else { return false }
            let ext = first.pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "webp", "heic", "tiff", "gif", "bmp"].contains(ext)
        }
    }
    
    public func execute(targetURLs: [URL]) -> Bool {
        switch utilityType {
        case .calculateMD5, .calculateSHA256:
            guard let first = targetURLs.first else { return false }
            return calculateHash(for: first)
            
        case .toggleHiddenFiles:
            return toggleHiddenSystemFiles()
            
        case .textToQRCode:
            return generateQRCodeFromClipboard()
            
        case .convertToPNG, .convertToJPEG:
            var success = true
            for url in targetURLs {
                if !convertImageFormat(from: url, toPNG: (utilityType == .convertToPNG)) {
                    success = false
                }
            }
            return success
        }
    }
    
    // MARK: - 1. 哈希计算
    private func calculateHash(for url: URL) -> Bool {
        do {
            let fileData = try Data(contentsOf: url, options: .mappedIfSafe)
            let hashString: String
            
            if utilityType == .calculateMD5 {
                let digest = Insecure.MD5.hash(data: fileData)
                hashString = digest.map { String(format: "%02hhx", $0) }.joined()
            } else {
                let digest = SHA256.hash(data: fileData)
                hashString = digest.map { String(format: "%02hhx", $0) }.joined()
            }
            
            // 写入系统剪切板并弹窗显示
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hashString, forType: .string)
            
            showInfoAlert(title: "哈希计算成功", content: "已将校验码拷贝至剪贴板：\n\n\(hashString)")
            return true
        } catch {
            print("[UtilityAction] 读取文件计算 Hash 失败: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - 2. 显示/隐藏隐藏文件
    private func toggleHiddenSystemFiles() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        
        // 读取当前状态
        let readProcess = Process()
        readProcess.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        readProcess.arguments = ["read", "com.apple.finder", "AppleShowAllFiles"]
        
        let pipe = Pipe()
        readProcess.standardOutput = pipe
        
        do {
            try readProcess.run()
            readProcess.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let currentVal = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "NO"
            
            let toggleVal = (currentVal == "YES" || currentVal == "1" || currentVal == "true") ? "NO" : "YES"
            
            // 写入新状态并重启 Finder
            let writeProcess = Process()
            writeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            writeProcess.arguments = ["write", "com.apple.finder", "AppleShowAllFiles", toggleVal]
            try writeProcess.run()
            writeProcess.waitUntilExit()
            
            let killProcess = Process()
            killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killProcess.arguments = ["Finder"]
            try killProcess.run()
            killProcess.waitUntilExit()
            
            return true
        } catch {
            print("[UtilityAction] 切换显示隐藏文件失败: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - 3. 生成二维码
    private func generateQRCodeFromClipboard() -> Bool {
        let text = NSPasteboard.general.string(forType: .string) ?? "Antigravity 右键助手"
        
        guard let data = text.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return false
        }
        
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel") // 高纠错
        
        guard let ciImage = filter.outputImage else { return false }
        
        // 放大二维码，避免高清晰度下像素模糊
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: transform)
        
        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        
        // 显示生成的二维码
        DispatchQueue.main.async {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 350),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "文本二维码"
            window.center()
            
            let imageView = NSImageView(frame: NSRect(x: 20, y: 50, width: 280, height: 280))
            imageView.image = nsImage
            
            let label = NSTextField(labelWithString: "内容: " + (text.count > 25 ? String(text.prefix(22)) + "..." : text))
            label.frame = NSRect(x: 20, y: 15, width: 280, height: 25)
            label.alignment = .center
            
            let contentView = NSView(frame: window.frame)
            contentView.addSubview(imageView)
            contentView.addSubview(label)
            
            window.contentView = contentView
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
    
    // MARK: - 4. 图片格式转换
    private func convertImageFormat(from url: URL, toPNG: Bool) -> Bool {
        guard let nsImage = NSImage(contentsOf: url) else { return false }
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return false
        }
        
        let destExt = toPNG ? "png" : "jpg"
        let destURL = url.deletingPathExtension().appendingPathExtension(destExt)
        
        // 自动重名处理
        var finalDestURL = destURL
        var counter = 1
        while FileManager.default.fileExists(atPath: finalDestURL.path) {
            finalDestURL = url.deletingPathExtension().deletingLastPathComponent()
                .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(counter)")
                .appendingPathExtension(destExt)
            counter += 1
        }
        
        do {
            let outData: Data?
            if toPNG {
                outData = bitmap.representation(using: .png, properties: [:])
            } else {
                outData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            }
            
            guard let finalData = outData else { return false }
            try finalData.write(to: finalDestURL)
            print("[UtilityAction] 图片转换成功: \(finalDestURL.path)")
            return true
        } catch {
            print("[UtilityAction] 图片转换失败: \(error.localizedDescription)")
            return false
        }
    }
    
    private func showInfoAlert(title: String, content: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = content
            alert.alertStyle = .informational
            alert.addButton(withTitle: "完成")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
 public extension Data {
    struct HexEncodingOptions: OptionSet {
        public let rawValue: Int
        public static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
}
