import Foundation
import AppKit

/// 表示右键动作分类
public enum ActionCategory: String, Codable, CaseIterable, Identifiable {
    case newFile = "newFile"          // 新建文件
    case fileManage = "fileManage"    // 文件管理（复制、剪切、彻底删除等）
    case terminal = "terminal"        // 终端与编辑器联动
    case utility = "utility"          // 常用小工具（Hash、二维码、图片转换等）
    
    public var id: String { self.rawValue }
    
    public var localizedName: String {
        switch self {
        case .newFile: return "新建文件"
        case .fileManage: return "文件管理"
        case .terminal: return "终端/编辑器"
        case .utility: return "实用工具"
        }
    }
}

/// 统一的右键动作抽象接口
public protocol MenuAction {
    /// 唯一标识符，用于分发调度
    var actionId: String { get }
    
    /// 显示在右键菜单中的国际化标题
    var localizedTitle: String { get }
    
    /// 图标名称（System Symbol 或本地资源）
    var iconName: String? { get }
    
    /// 动作所属分类
    var category: ActionCategory { get }
    
    /// 判断此动作在当前选中的文件/文件夹下是否可用
    /// - Parameter urls: 用户右键选中的资源列表
    func isAvailable(for targetURLs: [URL]) -> Bool
    
    /// 执行动作
    /// - Parameter targetURLs: 用户右键选中的资源列表
    /// - Returns: 是否执行成功
    func execute(targetURLs: [URL]) -> Bool
}

// 提供默认实现
public extension MenuAction {
    func isAvailable(for targetURLs: [URL]) -> Bool {
        // 默认情况下，只要选中了对象，或者在空白处（此时 urls 为当前路径）就可用
        return true
    }
}
