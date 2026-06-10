import Foundation
import AppKit

/// 文件剪切板单例，用于在进程内存中管理“剪切”状态
public final class FileCutClipboard {
    public static let shared = FileCutClipboard()
    private init() {}
    
    private let queue = DispatchQueue(label: "guyue.cutboard")
    
    private var clipboardURL: URL {
        return SharedStorageManager.shared.sharedContainerURL.appendingPathComponent("clipboard.json")
    }
    
    public var cutURLs: [URL] {
        get {
            queue.sync {
                guard let data = try? Data(contentsOf: clipboardURL),
                      let paths = try? JSONDecoder().decode([String].self, from: data) else {
                    return []
                }
                return paths.map { URL(fileURLWithPath: $0) }
            }
        }
        set {
            queue.sync {
                let paths = newValue.map { $0.path }
                if let data = try? JSONEncoder().encode(paths) {
                    try? data.write(to: clipboardURL, options: .atomic)
                }
            }
        }
    }
    
    public func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: clipboardURL)
        }
    }
}

/// 支持的右键文件管理动作子类型
public enum FileManageType: String, Codable {
    case cut = "cut"                  // 剪切
    case paste = "paste"              // 粘贴（执行移动）
    case permanentDelete = "delete"   // 彻底删除
    case copyPath = "copyPath"        // 拷贝完整路径
    case copyName = "copyName"        // 拷贝文件名
    case moveTo = "moveTo"            // 移动到...
    case copyTo = "copyTo"            // 复制到...
}

public final class FileManageAction: MenuAction {
    public let actionId: String
    public let localizedTitle: String
    public let iconName: String?
    public let category: ActionCategory = .fileManage
    
    public let manageType: FileManageType
    private let customTargetPath: URL? // 针对特定复制到/移动到文件夹的预设路径
    
    public init(type: FileManageType, customTargetPath: URL? = nil, customTitle: String? = nil) {
        self.manageType = type
        self.customTargetPath = customTargetPath
        self.actionId = "guyue.action.filemanage.\(type.rawValue)"
        
        if let title = customTitle {
            self.localizedTitle = title
        } else {
            switch type {
            case .cut: self.localizedTitle = "剪切"
            case .paste: self.localizedTitle = "粘贴"
            case .permanentDelete: self.localizedTitle = "彻底删除"
            case .copyPath: self.localizedTitle = "拷贝完整路径"
            case .copyName: self.localizedTitle = "拷贝文件名"
            case .moveTo: self.localizedTitle = "移动到..."
            case .copyTo: self.localizedTitle = "复制到..."
            }
        }
        
        switch type {
        case .cut: self.iconName = "scissors"
        case .paste: self.iconName = "doc.on.clipboard"
        case .permanentDelete: self.iconName = "trash.slash"
        case .copyPath: self.iconName = "link"
        case .copyName: self.iconName = "pencil.and.outline"
        case .moveTo: self.iconName = "arrow.right.doc.on.clipboard"
        case .copyTo: self.iconName = "doc.on.doc"
        }
    }
    
    public func isAvailable(for targetURLs: [URL]) -> Bool {
        return isAvailable(for: targetURLs, isContainer: false)
    }
    
    public func isAvailable(for targetURLs: [URL], isContainer: Bool) -> Bool {
        if isContainer {
            // 右键空白背景 (Container) 时：只有“粘贴”操作可能可用（前提是剪切板内有被剪切的文件）
            // 此时 cut, permanentDelete, copyPath, copyName, moveTo, copyTo 等针对特定选中项目的动作全部隐藏
            return manageType == .paste && !FileCutClipboard.shared.cutURLs.isEmpty
        } else {
            // 正常选中项目 (Items) 时：
            switch manageType {
            case .paste:
                // 粘贴必须建立在已经剪切了文件，且当前选中了目录（或选中的项目是目录）的前提下
                return !FileCutClipboard.shared.cutURLs.isEmpty && !targetURLs.isEmpty
            case .cut, .permanentDelete, .copyPath, .copyName, .moveTo, .copyTo:
                // 这些操作都需要选中至少一个目标文件或文件夹
                return !targetURLs.isEmpty
            }
        }
    }
    
    public func execute(targetURLs: [URL]) -> Bool {
        guard !targetURLs.isEmpty else { return false }
        
        switch manageType {
        case .cut:
            FileCutClipboard.shared.cutURLs = targetURLs
            print("[FileManage] 剪切了 \(targetURLs.count) 个文件。")
            SharedHUDManager.show(
                title: "剪切成功",
                content: "已将 \(targetURLs.count) 个项目加入剪切板，请在目标文件夹右键粘贴",
                isSuccess: true
            )
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("guyue.RightClickAssistant.configChanged"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return true
            
        case .paste:
            let cutFiles = FileCutClipboard.shared.cutURLs
            guard !cutFiles.isEmpty else { return false }
            
            // 确定粘贴的目的文件夹
            let destinationDir = getDestinationDirectory(from: targetURLs.first!)
            
            var successCount = 0
            for fileURL in cutFiles {
                let destURL = destinationDir.appendingPathComponent(fileURL.lastPathComponent)
                
                // 处理同名重命名或冲突覆盖（这里直接采用重命名策略防止覆盖用户重要数据）
                var finalDestURL = destURL
                var counter = 1
                let nameWithoutExtension = fileURL.deletingPathExtension().lastPathComponent
                let fileExtension = fileURL.pathExtension
                
                while FileManager.default.fileExists(atPath: finalDestURL.path) {
                    let newName = "\(nameWithoutExtension) \(counter).\(fileExtension)"
                    finalDestURL = destinationDir.appendingPathComponent(newName)
                    counter += 1
                }
                
                do {
                    try FileManager.default.moveItem(at: fileURL, to: finalDestURL)
                    successCount += 1
                } catch {
                    print("[FileManage] 移动文件直接失败（可能由于跨磁盘卷），启动商业级 Copy-Then-Delete 安全降级兜底: \(error.localizedDescription)")
                    do {
                        // A. 先安全复制
                        try FileManager.default.copyItem(at: fileURL, to: finalDestURL)
                        // B. 物理校验目的文件确实成功且完整生成
                        if FileManager.default.fileExists(atPath: finalDestURL.path) {
                            // C. 彻底且安全地删除原磁盘上的源文件
                            try FileManager.default.removeItem(at: fileURL)
                            successCount += 1
                            print("[FileManage] 跨卷降级兜底转移成功: \(fileURL.lastPathComponent)")
                        } else {
                            throw NSError(domain: "guyue.FileManage", code: 500, userInfo: [NSLocalizedDescriptionKey: "复制文件后，检验目的文件存在性失败"])
                        }
                    } catch let fallbackError {
                        print("[FileManage] 跨卷降级兜底也宣告失败: \(fileURL.lastPathComponent) -> \(fallbackError.localizedDescription)")
                    }
                }
            }
            
            print("[FileManage] 成功粘贴/移动了 \(successCount) 个文件。")
            FileCutClipboard.shared.clear() // 移动完成，清空剪切板
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("guyue.RightClickAssistant.configChanged"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            if successCount > 0 {
                SharedHUDManager.show(
                    title: "粘贴成功",
                    content: "已成功移动并粘贴了 \(successCount) 个项目",
                    isSuccess: true
                )
            } else {
                SharedHUDManager.show(
                    title: "粘贴失败",
                    content: "请检查该目录是否有可写的系统或安全权限",
                    isSuccess: false
                )
            }
            return successCount > 0
            
        case .permanentDelete:
            // 彻底删除需要二次确认，如果静默删除可以用此接口，但在真实的右键菜单中最好弹出确认框或通过系统静默 rm -rf
            // 这里我们展示核心删除逻辑：
            let alert = NSAlert()
            alert.messageText = "确定要彻底删除选中的项目吗？"
            alert.informativeText = "此操作将绕过废纸篓直接从硬盘删除文件，且无法撤销！"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定彻底删除")
            alert.addButton(withTitle: "取消")
            
            // 让对话框置顶弹出
            NSApp.activate(ignoringOtherApps: true)
            alert.window.level = .modalPanel
            alert.window.orderFrontRegardless()
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                var successCount = 0
                for fileURL in targetURLs {
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                        successCount += 1
                    } catch {
                        print("[FileManage] 彻底删除失败: \(fileURL.path) -> \(error.localizedDescription)")
                    }
                }
                if successCount > 0 {
                    SharedHUDManager.show(
                        title: "删除成功",
                        content: "已彻底从磁盘抹除 \(successCount) 个项目",
                        isSuccess: true
                    )
                } else {
                    SharedHUDManager.show(
                        title: "删除失败",
                        content: "请检查系统权限或文件是否被锁定",
                        isSuccess: false
                    )
                }
                return successCount > 0
            }
            return false
            
        case .copyPath:
            let paths = targetURLs.map { $0.path }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paths, forType: .string)
            print("[FileManage] 已成功拷贝 \(targetURLs.count) 个路径到系统剪贴板。")
            SharedHUDManager.show(
                title: "路径已拷贝",
                content: "已成功将物理路径写入剪切板",
                isSuccess: true
            )
            return true
            
        case .copyName:
            let names = targetURLs.map { $0.lastPathComponent }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(names, forType: .string)
            print("[FileManage] 已成功拷贝 \(targetURLs.count) 个文件名到系统剪贴板。")
            SharedHUDManager.show(
                title: "名称已拷贝",
                content: "已成功将文件名写入剪切板",
                isSuccess: true
            )
            return true
            
        case .moveTo, .copyTo:
            // 如果预设了自定义路径直接操作，否则弹出 NSOpenPanel 让用户自由选择目标文件夹
            let destinationDir: URL
            if let customPath = customTargetPath {
                destinationDir = customPath
            } else {
                let openPanel = NSOpenPanel()
                openPanel.canChooseFiles = false
                openPanel.canChooseDirectories = true
                openPanel.allowsMultipleSelection = false
                openPanel.prompt = "选择目标文件夹"
                
                NSApp.activate(ignoringOtherApps: true)
                openPanel.level = .modalPanel
                openPanel.orderFrontRegardless()
                guard openPanel.runModal() == .OK, let selectedURL = openPanel.url else {
                    return false
                }
                destinationDir = selectedURL
            }
            
            var successCount = 0
            for fileURL in targetURLs {
                let destURL = destinationDir.appendingPathComponent(fileURL.lastPathComponent)
                
                // 冲突命名解决
                var finalDestURL = destURL
                var counter = 1
                let nameWithoutExtension = fileURL.deletingPathExtension().lastPathComponent
                let fileExtension = fileURL.pathExtension
                
                while FileManager.default.fileExists(atPath: finalDestURL.path) {
                    let newName = "\(nameWithoutExtension) \(counter).\(fileExtension)"
                    finalDestURL = destinationDir.appendingPathComponent(newName)
                    counter += 1
                }
                
                do {
                    if manageType == .copyTo {
                        try FileManager.default.copyItem(at: fileURL, to: finalDestURL)
                    } else {
                        // 针对移动 (moveTo) 动作在直接调用 moveItem 出错时启动安全 Copy-Then-Delete 降级兜底
                        do {
                            try FileManager.default.moveItem(at: fileURL, to: finalDestURL)
                        } catch {
                            print("[FileManage] 移动到直接失败（跨盘卷），触发 Copy-Then-Delete 降级防护: \(error.localizedDescription)")
                            try FileManager.default.copyItem(at: fileURL, to: finalDestURL)
                            if FileManager.default.fileExists(atPath: finalDestURL.path) {
                                try FileManager.default.removeItem(at: fileURL)
                                print("[FileManage] 跨磁盘卷 moveTo 降级复制后删除原件成功")
                            } else {
                                throw error
                            }
                        }
                    }
                    successCount += 1
                } catch {
                    print("[FileManage] \(manageType == .copyTo ? "复制" : "移动")操作彻底失败: \(error.localizedDescription)")
                }
            }
            if successCount > 0 {
                SharedHUDManager.show(
                    title: manageType == .copyTo ? "复制成功" : "移动成功",
                    content: "已成功\(manageType == .copyTo ? "复制" : "移动") \(successCount) 个项目到目标目录",
                    isSuccess: true
                )
            } else {
                SharedHUDManager.show(
                    title: manageType == .copyTo ? "复制失败" : "移动失败",
                    content: "项目转移过程中权限不足或被系统拦截",
                    isSuccess: false
                )
            }
            return successCount > 0
        }
    }
    
    private func getDestinationDirectory(from url: URL) -> URL {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }
}
