import AppKit

/// 标准 .service provider，仅负责把动态条目的动作 ID 转发给 Host 的稳定服务入口。
/// 动作授权、目标校验和真实入队全部由 Host 完成。
final class FinderQuickServiceForwarder: NSObject {
    private static let legacyFilenamesType = NSPasteboard.PasteboardType(
        "NSFilenamesPboardType"
    )
    private static let fileURLType = NSPasteboard.PasteboardType("public.file-url")
    private static let actionType = NSPasteboard.PasteboardType(
        FinderQuickServiceProtocol.forwardedActionPasteboardType
    )

    @objc(performFinderService:userData:error:)
    func performFinderService(
        _ pasteboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.terminate(nil)
            }
        }

        guard !userData.isEmpty else {
            errorPointer.pointee = "快捷动作标识为空" as NSString
            return
        }

        let paths = Self.selectionPaths(from: pasteboard)
        guard !paths.isEmpty else {
            errorPointer.pointee = "请先选择文件或文件夹" as NSString
            return
        }

        let forwardingPasteboard = NSPasteboard(
            name: NSPasteboard.Name("guyue.RightClickAssistant.forward.\(UUID().uuidString)")
        )
        forwardingPasteboard.declareTypes(
            [Self.legacyFilenamesType, Self.actionType],
            owner: nil
        )
        defer { forwardingPasteboard.releaseGlobally() }

        guard forwardingPasteboard.setPropertyList(paths, forType: Self.legacyFilenamesType),
              forwardingPasteboard.setString(userData, forType: Self.actionType),
              NSPerformService(
                FinderQuickServiceProtocol.hostPaletteMenuTitle,
                forwardingPasteboard
              ) else {
            errorPointer.pointee = "无法连接右键助手，请先打开应用后重试" as NSString
            return
        }

        errorPointer.pointee = nil
    }

    private static func selectionPaths(from pasteboard: NSPasteboard) -> [String] {
        let legacyPaths = pasteboard.propertyList(forType: legacyFilenamesType) as? [String] ?? []
        let fileURLPaths = (pasteboard.pasteboardItems ?? []).compactMap { item -> String? in
            guard let value = item.string(forType: fileURLType),
                  let url = URL(string: value),
                  url.isFileURL else {
                return nil
            }
            return url.standardizedFileURL.path
        }
        var seen = Set<String>()
        return (legacyPaths + fileURLPaths).filter { path in
            !path.isEmpty && (path as NSString).isAbsolutePath && seen.insert(path).inserted
        }
    }
}

let application = NSApplication.shared
let provider = FinderQuickServiceForwarder()
application.setActivationPolicy(.prohibited)
application.servicesProvider = provider
application.run()
