import Foundation

/// 动作面向用户的能力层级。高级层包含破坏性或会改变系统状态的动作。
public enum ActionTier: String, Codable, CaseIterable, Sendable {
    case essential
    case professional
    case advanced
}

/// 设置页可一键应用的动作档案。自定义档案不批量修改任何动作。
public enum ActionProfile: String, Codable, CaseIterable, Sendable {
    case essential
    case professional
    case custom

    /// 返回要批量写入的动作状态。高级动作始终排除，必须由用户逐项开启。
    public func states(for actions: [MenuAction]) -> [String: Bool] {
        guard self != .custom else { return [:] }

        return actions.reduce(into: [String: Bool]()) { states, action in
            guard action.tier != .advanced else { return }
            switch self {
            case .essential:
                states[action.actionId] = action.tier == .essential
            case .professional:
                states[action.actionId] = true
            case .custom:
                break
            }
        }
    }
}

public enum ActionSearch {
    public static func matches(title: String, actionID: String, query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(normalizedQuery)
            || actionID.localizedCaseInsensitiveContains(normalizedQuery)
    }
}
