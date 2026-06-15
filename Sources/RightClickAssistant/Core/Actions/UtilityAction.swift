import Foundation
import AppKit
import CryptoKit
import CoreImage

// MARK: - 二维码面板生命周期持有者
/// 文件作用域强引用：QRCodePanelController 内部的 NSPanel 不会被 UI 框架自动持有，
/// 一旦控制器随 dispatch closure 退栈即析构，面板会瞬间消失。这里用 fileprivate 单
/// 变量持有最近一次打开的控制器，再次生成时旧实例自动被替换并随面板关闭一起释放。
fileprivate var activeQRController: QRCodePanelController?

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
    private let imageConverter: ImageConverterProtocol

    public var isHighRisk: Bool {
        return utilityType == .toggleHiddenFiles
    }

    public var isEnabledByDefault: Bool {
        switch utilityType {
        case .calculateSHA256, .textToQRCode:
            return true
        case .calculateMD5, .toggleHiddenFiles, .convertToPNG, .convertToJPEG:
            return false
        }
    }

    public var riskDescription: String? {
        if utilityType == .toggleHiddenFiles {
            return "会修改 Finder 系统偏好并重启 Finder，可能打断当前 Finder 操作。"
        }
        return nil
    }
    
    public init(type: UtilityType, imageConverter: ImageConverterProtocol = DefaultImageConverter()) {
        self.utilityType = type
        self.imageConverter = imageConverter
        self.actionId = "guyue.action.utility.\(type.rawValue)"
        
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
            self.localizedTitle = "从剪贴板生成二维码"
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
        return isAvailable(for: targetURLs, isContainer: false)
    }
    
    public func isAvailable(for targetURLs: [URL], isContainer: Bool) -> Bool {
        if isContainer {
            // 右键空白背景 (Container) 时：
            switch utilityType {
            case .toggleHiddenFiles, .textToQRCode:
                return true // 切换隐藏文件与二维码无需选中文件也极其有用
            case .calculateMD5, .calculateSHA256, .convertToPNG, .convertToJPEG:
                return false // 哈希校验和图片格式转换在空白背景下毫无意义，直接隐藏
            }
        } else {
            // 正常选中项目 (Items) 时：
            switch utilityType {
            case .toggleHiddenFiles:
                return true // 依然可以切换
            case .calculateMD5, .calculateSHA256:
                // 必须选中且只操作单个文件（非目录）
                guard targetURLs.count == 1, let first = targetURLs.first else { return false }
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir) && !isDir.boolValue
            case .textToQRCode:
                return true // 文本生成二维码依然可用
            case .convertToPNG, .convertToJPEG:
                // 必须选中了至少一个项目，且选中的每一个项目都必须是物理文件（绝非目录）且为受支持的图片格式
                guard !targetURLs.isEmpty else { return false }
                let supportedExts = ["png", "jpg", "jpeg", "webp", "heic", "tiff", "gif", "bmp"]
                for url in targetURLs {
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue else {
                        return false // 如果其中有任何一个是目录，则此格式转换动作不适用
                    }
                    let ext = url.pathExtension.lowercased()
                    guard supportedExts.contains(ext) else {
                        return false // 如果其中有任何一个不是受支持的图片格式，则不适用
                    }
                }
                return true
            }
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
            let isPNG = (utilityType == .convertToPNG)
            let formatStr = isPNG ? "PNG" : "JPEG"
            
            var successCount = 0
            var failureCount = 0
            var lastErrorMsg = "未知错误"
            let totalCount = targetURLs.count
            
            for (index, url) in targetURLs.enumerated() {
                // 批量转换进度反馈：每处理一张图片更新 HUD，避免用户无感知等待
                if totalCount > 1 {
                    SharedHUDManager.show(
                        title: "正在转换图片",
                        content: "进度: \(index + 1) / \(totalCount)",
                        isSuccess: true
                    )
                }
                
                let result = imageConverter.convert(url: url, toFormat: formatStr)
                switch result {
                case .success(let destURL):
                    successCount += 1
                    print("[UtilityAction] 图片转换成功: \(destURL.path)")
                case .failure(let error):
                    failureCount += 1
                    lastErrorMsg = error.localizedDescription
                    print("[UtilityAction] 图片转换失败: \(error.localizedDescription)")
                }
            }
            
            if totalCount > 0 {
                if failureCount == 0 {
                    SharedHUDManager.show(
                        title: "批量转换完成",
                        content: "已成功将 \(successCount) 张图片转换为 \(formatStr) 格式",
                        isSuccess: true
                    )
                } else if successCount == 0 {
                    SharedHUDManager.show(
                        title: "批量转换失败",
                        content: "转换失败。原因：\(lastErrorMsg)",
                        isSuccess: false
                    )
                } else {
                    SharedHUDManager.show(
                        title: "转换部分成功",
                        content: "成功转换 \(successCount) 张，失败 \(failureCount) 张。最近错误：\(lastErrorMsg)",
                        isSuccess: false
                    )
                }
            } else {
                SharedHUDManager.show(
                    title: "转换无效",
                    content: "未选中任何有效的图片文件进行转换",
                    isSuccess: false
                )
            }
            return failureCount == 0
        }
    }

    private func runOnMainThread<T>(_ block: () -> T) -> T {
        if Thread.isMainThread {
            return block()
        }
        return DispatchQueue.main.sync {
            block()
        }
    }

    private func confirmToggleHiddenFiles() -> Bool {
        return runOnMainThread {
            let alert = NSAlert()
            alert.messageText = "确认切换 Finder 隐藏文件显示？"
            alert.informativeText = "此操作会修改 Finder 系统偏好并重启 Finder，当前 Finder 窗口可能短暂关闭或刷新。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确认切换并重启 Finder")
            alert.addButton(withTitle: "取消")
            alert.window.level = .modalPanel
            alert.window.orderFrontRegardless()
            return alert.runModal() == .alertFirstButtonReturn
        }
    }
    
    // MARK: - 1. 流式哈希计算
    private func calculateHash(for url: URL) -> Bool {
        let algorithm: HashAlgorithm = utilityType == .calculateSHA256 ? .sha256 : .md5
        let label = utilityType == .calculateSHA256 ? "SHA256" : "MD5"
        // 大文件哈希可能耗时较长，提前展示"正在计算"让用户感知进度
        SharedHUDManager.show(title: "正在计算 \(label)", content: url.lastPathComponent, isSuccess: true)
        do {
            let hashString = try FileHashCalculator.hashFile(at: url, algorithm: algorithm)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hashString, forType: .string)
            SharedHUDManager.show(title: "\(label) 计算完成", content: "已复制到剪贴板", isSuccess: true)
            return true
        } catch {
            print("[UtilityAction] 流式计算 \(label) 失败: \(error.localizedDescription)")
            SharedHUDManager.show(title: "\(label) 计算失败", content: error.localizedDescription, isSuccess: false)
            return false
        }
    }
    
    // MARK: - 2. 显示/隐藏隐藏文件
    private func toggleHiddenSystemFiles() -> Bool {
        guard confirmToggleHiddenFiles() else {
            return false
        }

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
            
            // 用 AppleScript 让 Finder 优雅退出，比 killall 安全：
            // - 系统会保存 Finder 当前状态（拖拽中、复制进度框、未关窗口），不会粗暴打断
            // - 退出后 launchd 会自动重新拉起 Finder
            // 保险起见，500ms 后再用 `open -a Finder` 显式触发重启，覆盖某些不会自动复活的边角场景。
            let osa = Process()
            osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            osa.arguments = ["-e", "tell application \"Finder\" to quit"]
            try osa.run()
            osa.waitUntilExit()

            Thread.sleep(forTimeInterval: 0.5)

            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            relaunch.arguments = ["-a", "Finder"]
            try? relaunch.run()
            
            let stateStr = toggleVal == "YES" ? "显示" : "隐藏"
            SharedHUDManager.show(
                title: "系统配置更新成功",
                content: "已成功切换系统隐藏文件状态为：【\(stateStr)】",
                isSuccess: true
            )
            return true
        } catch {
            print("[UtilityAction] 切换显示隐藏文件失败: \(error.localizedDescription)")
            SharedHUDManager.show(
                title: "切换状态失败",
                content: "在调用系统指令 defaults 或重启 Finder 时发生错误：\(error.localizedDescription)",
                isSuccess: false
            )
            return false
        }
    }
    
    // MARK: - 3. 生成二维码
    private func generateQRCodeFromClipboard() -> Bool {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SharedHUDManager.show(
                title: "生成二维码失败",
                content: "剪贴板中未检测到有效文本，请先拷贝文本后再试",
                isSuccess: false
            )
            return false
        }
        
        guard let data = text.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            SharedHUDManager.show(
                title: "生成二维码失败",
                content: "系统二维码生成滤镜 CIFilter 初始化失败",
                isSuccess: false
            )
            return false
        }
        
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel") // 高纠错
        
        guard let ciImage = filter.outputImage else {
            SharedHUDManager.show(
                title: "生成二维码失败",
                content: "未能从 CIFilter 生成目标 CIImage",
                isSuccess: false
            )
            return false
        }
        
        // 放大二维码，避免高清晰度下像素模糊
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: transform)
        
        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        
        // 以浮动面板展示二维码，不抢焦点。
        DispatchQueue.main.async {
            // 把 NSPanel 装配 / 保存 PNG / 拷贝图片三件事交给 QRCodePanelController，
            // UtilityAction 这里只负责"剪贴板取文本 → 生成二维码 NSImage → 交给控制器"。
            // controller 必须由文件作用域强引用，否则面板会被立即释放。
            let controller = QRCodePanelController(image: nsImage, text: text)
            activeQRController = controller
            controller.show()

            SharedHUDManager.show(
                title: "二维码已生成",
                content: "剪贴板内容已转为二维码",
                isSuccess: true
            )
        }
        return true
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

// MARK: - 5. 图片格式转换接口与默认实现
/// 图像转换服务协议，方便后续灵活变更转换实现或支持更多格式
public protocol ImageConverterProtocol {
    func convert(url: URL, toFormat format: String) -> Result<URL, Error>
}

/// 默认的图像转换器实现
public final class DefaultImageConverter: ImageConverterProtocol {
    public init() {}
    
    public func convert(url: URL, toFormat format: String) -> Result<URL, Error> {
        let normalizedFormat = format.lowercased()
        guard normalizedFormat == "png" || normalizedFormat == "jpeg" || normalizedFormat == "jpg" else {
            return .failure(NSError(domain: "guyue.ImageConverter", code: 400, userInfo: [NSLocalizedDescriptionKey: "不支持的目标转换格式：\(format)"]))
        }
        
        guard let nsImage = NSImage(contentsOf: url) else {
            return .failure(NSError(domain: "guyue.ImageConverter", code: 404, userInfo: [NSLocalizedDescriptionKey: "无法读取或解析输入图片文件"]))
        }
        
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return .failure(NSError(domain: "guyue.ImageConverter", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法提取图片的 Bitmap 表达"]))
        }
        
        let destExt = normalizedFormat == "png" ? "png" : "jpg"
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
            if normalizedFormat == "png" {
                outData = bitmap.representation(using: .png, properties: [:])
            } else {
                outData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            }
            
            guard let finalData = outData else {
                return .failure(NSError(domain: "guyue.ImageConverter", code: 500, userInfo: [NSLocalizedDescriptionKey: "生成目标图像二进制数据失败"]))
            }
            
            try finalData.write(to: finalDestURL)
            return .success(finalDestURL)
        } catch {
            return .failure(error)
        }
    }
}
