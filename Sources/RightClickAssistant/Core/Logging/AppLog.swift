import Foundation
import os

/// 统一日志 category，按子系统切分。category 名出现在 `log show` 输出里，便于过滤。
public enum AppLogCategory: String {
    case host
    case ext        // 注：避开 Swift 关键字 `extension`
    case storage
    case action
    case ui
}

/// 极薄的 os.Logger 包装，作为整个项目的统一日志入口。
///
/// - Subsystem 固定为 `guyue.RightClickAssistant`
/// - 通过 `log show --predicate 'subsystem == "guyue.RightClickAssistant"'` 可一次性看到所有 category
/// - debug 级在生产环境零开销（os.Logger 默认不持久化 .debug）
/// - 对外仅暴露 info / debug / error 三档，避免调用方滥用 default 等扰乱级别
public enum AppLog {
    public static let subsystem = "guyue.RightClickAssistant"

    private static let registryQueue = DispatchQueue(label: "guyue.AppLog.registry")
    private nonisolated(unsafe) static var loggers: [String: Logger] = [:] 

    /// 取得指定 category 的 Logger 实例。同 category 的多次调用返回同一个 Logger。
    public static func logger(for category: AppLogCategory) -> Logger {
        return registryQueue.sync {
            if let existing = loggers[category.rawValue] {
                return existing
            }
            let l = Logger(subsystem: subsystem, category: category.rawValue)
            loggers[category.rawValue] = l
            return l
        }
    }

    public static func info(_ message: String, category: AppLogCategory = .host) {
        logger(for: category).info("\(message, privacy: .public)")
    }

    public static func debug(_ message: String, category: AppLogCategory = .host) {
        logger(for: category).debug("\(message, privacy: .public)")
    }

    public static func error(_ message: String, category: AppLogCategory = .host) {
        logger(for: category).error("\(message, privacy: .public)")
    }
}
