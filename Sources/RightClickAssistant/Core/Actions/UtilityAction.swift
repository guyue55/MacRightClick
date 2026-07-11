import Foundation
import AppKit
import CryptoKit
import CoreImage

// MARK: - 二维码面板生命周期持有者
/// 文件作用域强引用：QRCodePanelController 内部的 NSPanel 不会被 UI 框架自动持有，
/// 一旦控制器随 dispatch closure 退栈即析构，面板会瞬间消失。这里用 fileprivate 单
/// 变量持有最近一次打开的控制器，再次生成时旧实例自动被替换并随面板关闭一起释放。
nonisolated(unsafe) fileprivate var activeQRController: QRCodePanelController?

/// 实用小工具类型
public enum UtilityType: String, Codable, Sendable {
    case calculateMD5 = "calculateMD5"
    case calculateSHA256 = "calculateSHA256"
    case toggleHiddenFiles = "toggleHiddenFiles"
    case textToQRCode = "textToQRCode"
    case convertToPNG = "convertToPNG"
    case convertToJPEG = "convertToJPG"
}

public final class UtilityAction: MenuAction, Sendable {
    public let actionId: String
    public let localizedTitle: String
    public let iconName: String?
    public let category: ActionCategory = .utility
    
    public let utilityType: UtilityType
    private let imageConverter: any ImageConverterProtocol

    private static let hashRunner = BackgroundActionRunner(
        actionLabel: "utility.hash",
        ioQueueLabel: "guyue.RightClickAssistant.utility-hash-io"
    )
    private static let imageConversionRunner = BackgroundActionRunner(
        actionLabel: "utility.image-conversion",
        ioQueueLabel: "guyue.RightClickAssistant.utility-image-conversion-io"
    )

    public var tier: ActionTier {
        switch utilityType {
        case .calculateSHA256, .textToQRCode:
            return .essential
        case .calculateMD5, .convertToPNG, .convertToJPEG:
            return .professional
        case .toggleHiddenFiles:
            return .advanced
        }
    }

    public var isHighRisk: Bool {
        return tier == .advanced
    }

    public var requiresExistingTargets: Bool {
        switch utilityType {
        case .toggleHiddenFiles, .textToQRCode:
            return false
        case .calculateMD5, .calculateSHA256, .convertToPNG, .convertToJPEG:
            return true
        }
    }

    public var isEnabledByDefault: Bool {
        return tier == .essential
    }

    public var riskDescription: String? {
        if utilityType == .toggleHiddenFiles {
            return "会修改 Finder 系统偏好并重启 Finder，可能打断当前 Finder 操作。"
        }
        return nil
    }
    
    public init(type: UtilityType, imageConverter: any ImageConverterProtocol = DefaultImageConverter()) {
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
        submit(targetURLs: targetURLs, completion: { _ in }) == .accepted
    }

    public func submit(
        targetURLs: [URL],
        completion: @escaping @Sendable (ActionCompletionStatus) -> Void
    ) -> ActionSubmission {
        switch utilityType {
        case .calculateMD5, .calculateSHA256:
            guard let first = targetURLs.first else {
                completion(.failed)
                return .rejected
            }
            submitHash(for: first, completion: completion)
            return .accepted

        case .toggleHiddenFiles:
            return submitToggleHiddenFiles(completion: completion)

        case .textToQRCode:
            DispatchQueue.main.async { [self] in
                completion(generateQRCodeFromClipboard() ? .succeeded : .failed)
            }
            return .accepted

        case .convertToPNG, .convertToJPEG:
            guard !targetURLs.isEmpty else {
                SharedHUDManager.show(
                    title: "转换无效",
                    content: "未选中任何有效的图片文件进行转换",
                    isSuccess: false
                )
                completion(.failed)
                return .rejected
            }

            let isPNG = (utilityType == .convertToPNG)
            let formatStr = isPNG ? "PNG" : "JPEG"
            let urls = targetURLs
            let converter = imageConverter
            Self.imageConversionRunner.submit({
                Self.convertImages(urls, toFormat: formatStr, using: converter)
            }, completion: completion)
            return .accepted
        }
    }

    // runOnMainThread/confirmToggleHiddenFiles 已退役：
    // 全部走 InteractiveActionRunner（toggleHiddenRunner），
    // 主线程负责 prompt，后台负责 perform。
    
    // MARK: - 1. 流式哈希计算
    private func submitHash(
        for url: URL,
        completion: @escaping @Sendable (ActionCompletionStatus) -> Void
    ) {
        let algorithm: HashAlgorithm = utilityType == .calculateSHA256 ? .sha256 : .md5
        let label = utilityType == .calculateSHA256 ? "SHA256" : "MD5"
        // 大文件哈希可能耗时较长，提前展示"正在计算"让用户感知进度。
        SharedHUDManager.show(title: "正在计算 \(label)", content: url.lastPathComponent, isSuccess: true)
        Self.hashRunner.submit {
            do {
                let hashString = try FileHashCalculator.hashFile(at: url, algorithm: algorithm)
                Task { @MainActor in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hashString, forType: .string)
                    SharedHUDManager.show(
                        title: "\(label) 计算完成",
                        content: "已复制到剪贴板",
                        isSuccess: true
                    )
                    completion(.succeeded)
                }
            } catch {
                let description = error.localizedDescription
                AppLog.error("流式计算 \(label) 失败: \(description)", category: .action)
                Task { @MainActor in
                    SharedHUDManager.show(
                        title: "\(label) 计算失败",
                        content: description,
                        isSuccess: false
                    )
                    completion(.failed)
                }
            }
        }
    }

    private static func convertImages(
        _ urls: [URL],
        toFormat format: String,
        using converter: any ImageConverterProtocol
    ) -> ActionCompletionStatus {
        var successCount = 0
        var failureCount = 0
        var lastErrorMessage = "未知错误"
        let totalCount = urls.count

        for (index, url) in urls.enumerated() {
            if totalCount > 1 {
                SharedHUDManager.show(
                    title: "正在转换图片",
                    content: "进度: \(index + 1) / \(totalCount)",
                    isSuccess: true
                )
            }

            switch converter.convert(url: url, toFormat: format) {
            case .success(let destinationURL):
                successCount += 1
                AppLog.info("图片转换成功: \(destinationURL.path)", category: .action)
            case .failure(let error):
                failureCount += 1
                lastErrorMessage = error.localizedDescription
                AppLog.error("图片转换失败: \(lastErrorMessage)", category: .action)
            }
        }

        let title: String
        let content: String
        let isSuccess: Bool
        if failureCount == 0 {
            title = "批量转换完成"
            content = "已成功将 \(successCount) 张图片转换为 \(format) 格式"
            isSuccess = true
        } else if successCount == 0 {
            title = "批量转换失败"
            content = "转换失败。原因：\(lastErrorMessage)"
            isSuccess = false
        } else {
            title = "转换部分成功"
            content = "成功转换 \(successCount) 张，失败 \(failureCount) 张。最近错误：\(lastErrorMessage)"
            isSuccess = false
        }

        Task { @MainActor in
            SharedHUDManager.show(title: title, content: content, isSuccess: isSuccess)
        }
        return failureCount == 0 ? .succeeded : .failed
    }
    
    // MARK: - 2. 显示/隐藏隐藏文件
    /// 进通用 InteractiveActionRunner：
    /// - prompt 主线程弹 critical 确认；
    /// - perform 后台跑 defaults + osascript + sleep + open -a Finder。
    /// folder-monitor 串行队列不再被 Process.waitUntilExit / Thread.sleep 阻塞。
    private func submitToggleHiddenFiles(
        completion: @escaping @Sendable (ActionCompletionStatus) -> Void
    ) -> ActionSubmission {
        let outcome = UtilityAction.toggleHiddenRunner.run(
            prompt: { () -> Bool? in
                UtilityAction.confirmToggleHiddenAlert() ? true : nil
            },
            perform: { _ in
                UtilityAction.performToggleHiddenFiles()
            },
            completion: completion
        )
        return outcome == .accepted ? .accepted : .rejected
    }

    // MARK: - 3. 生成二维码
    @MainActor
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
        
        // 把 NSPanel 装配 / 保存 PNG / 拷贝图片三件事交给 QRCodePanelController。
        let controller = QRCodePanelController(image: nsImage, text: text)
        activeQRController = controller
        controller.show()
        SharedHUDManager.show(
            title: "二维码已生成",
            content: "剪贴板内容已转为二维码",
            isSuccess: true
        )
        return true
    }
    

}
public extension Data {
    struct HexEncodingOptions: OptionSet, Sendable {
        public let rawValue: Int
        public static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
}

// MARK: - 5. 图片格式转换接口与默认实现
/// 图像转换服务协议，方便后续灵活变更转换实现或支持更多格式
public protocol ImageConverterProtocol: Sendable {
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

// MARK: - toggleHiddenFiles 公共支持（InteractiveActionRunner 拆出的纯函数）
extension UtilityAction {

    /// 与 transferRunner 通过 InteractiveActionGate 共享 modal 互斥。
    /// toggleHiddenRunner 自带串行 IO 队列：多次切换不会并发抢 Finder。
    static let toggleHiddenRunner = InteractiveActionRunner(
        actionLabel: "utility.toggleHidden",
        ioQueueLabel: "guyue.RightClickAssistant.utility-toggle-hidden-io"
    )

    /// 主线程：弹 critical 确认。`true` 表示用户同意，`false` 取消。
    @MainActor
    static func confirmToggleHiddenAlert() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
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

    /// 后台串行队列：执行 defaults + osascript + sleep + open -a Finder。
    /// 任何 Process.waitUntilExit / Thread.sleep 都不再阻塞 folder-monitor 队列。
    static func performToggleHiddenFiles() -> ActionCompletionStatus {
        do {
            // 1. 读取当前值（默认 NO）。
            let read = Process()
            read.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            read.arguments = ["read", "com.apple.finder", "AppleShowAllFiles"]
            let pipe = Pipe()
            read.standardOutput = pipe
            try read.run()
            read.waitUntilExit()
            let raw = pipe.fileHandleForReading.readDataToEndOfFile()
            let current = String(data: raw, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "NO"
            let next = (current == "YES" || current == "1" || current == "true") ? "NO" : "YES"

            // 2. 写入翻转值。
            let write = Process()
            write.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            write.arguments = ["write", "com.apple.finder", "AppleShowAllFiles", next]
            try write.run()
            write.waitUntilExit()
            try requireSuccessfulExit(write, label: "写入 Finder 偏好")

            // 3. 优雅退出 Finder（osascript），launchd 会自动拉回。
            //    保险起见再 500ms 后显式 `open -a Finder`，覆盖某些不会自动复活的边角场景。
            let osa = Process()
            osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            osa.arguments = ["-e", "tell application \"Finder\" to quit"]
            try osa.run()
            osa.waitUntilExit()
            try requireSuccessfulExit(osa, label: "退出 Finder")

            Thread.sleep(forTimeInterval: 0.5)

            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            relaunch.arguments = ["-a", "Finder"]
            try relaunch.run()
            relaunch.waitUntilExit()
            try requireSuccessfulExit(relaunch, label: "重新打开 Finder")

            let stateText = next == "YES" ? "显示" : "隐藏"
            SharedHUDManager.show(
                title: "系统配置更新成功",
                content: "已成功切换系统隐藏文件状态为：【\(stateText)】",
                isSuccess: true
            )
            return .succeeded
        } catch {
            AppLog.error("切换显示隐藏文件失败: \(error.localizedDescription)", category: .action)
            SharedHUDManager.show(
                title: "切换状态失败",
                content: "在调用系统指令 defaults 或重启 Finder 时发生错误：\(error.localizedDescription)",
                isSuccess: false
            )
            return .failed
        }
    }

    private static func requireSuccessfulExit(_ process: Process, label: String) throws {
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "guyue.UtilityAction",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: "\(label)失败，退出码 \(process.terminationStatus)"
                ]
            )
        }
    }
}
