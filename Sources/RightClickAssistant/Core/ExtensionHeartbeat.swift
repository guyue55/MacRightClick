import Foundation

public struct ExtensionHeartbeat: Codable, Equatable, Sendable {
    public let timestamp: TimeInterval
    public let processID: Int32
    public let version: String
    public let observedPathCount: Int

    public init(
        timestamp: TimeInterval,
        processID: Int32,
        version: String,
        observedPathCount: Int
    ) {
        self.timestamp = timestamp
        self.processID = processID
        self.version = version
        self.observedPathCount = observedPathCount
    }
}

public enum ExtensionHeartbeatState: Equatable, Sendable {
    case recent(observedPathCount: Int)
    case stale
    case missing
}

/// FinderSync 扩展的最小运行心跳。文件不包含任何用户路径。
public final class ExtensionHeartbeatStore: @unchecked Sendable {
    public let fileURL: URL
    public let minimumWriteInterval: TimeInterval
    public let freshnessInterval: TimeInterval

    private let queue = DispatchQueue(label: "guyue.RightClickAssistant.extension-heartbeat")
    private var lastWriteTimestamp: TimeInterval?

    public init(
        fileURL: URL,
        minimumWriteInterval: TimeInterval = 60,
        freshnessInterval: TimeInterval = 120
    ) {
        self.fileURL = fileURL
        self.minimumWriteInterval = max(0, minimumWriteInterval)
        self.freshnessInterval = max(minimumWriteInterval, freshnessInterval)
    }

    /// 同步写入入口用于测试和显式诊断；Finder 菜单热路径应使用 `record`。
    @discardableResult
    public func write(
        observedPathCount: Int,
        version: String,
        processID: Int32,
        at date: Date = Date(),
        force: Bool = false
    ) -> Bool {
        queue.sync {
            writeUnlocked(
                observedPathCount: observedPathCount,
                version: version,
                processID: processID,
                at: date,
                force: force
            )
        }
    }

    /// 非阻塞记录入口。串行队列内再次检查节流，连续菜单渲染最多每分钟落盘一次。
    public func record(
        observedPathCount: Int,
        version: String,
        processID: Int32,
        at date: Date = Date(),
        force: Bool = false
    ) {
        queue.async { [self] in
            _ = writeUnlocked(
                observedPathCount: observedPathCount,
                version: version,
                processID: processID,
                at: date,
                force: force
            )
        }
    }

    public func state(at date: Date = Date()) -> ExtensionHeartbeatState {
        queue.sync {
            guard let heartbeat = loadUnlocked() else { return .missing }
            let age = date.timeIntervalSince1970 - heartbeat.timestamp
            guard age >= -minimumWriteInterval,
                  age <= freshnessInterval else {
                return .stale
            }
            return .recent(observedPathCount: max(0, heartbeat.observedPathCount))
        }
    }

    private func writeUnlocked(
        observedPathCount: Int,
        version: String,
        processID: Int32,
        at date: Date,
        force: Bool
    ) -> Bool {
        let timestamp = date.timeIntervalSince1970
        let previousTimestamp = lastWriteTimestamp ?? loadUnlocked()?.timestamp
        if !force,
           let previousTimestamp {
            let elapsed = timestamp - previousTimestamp
            if elapsed >= 0 && elapsed < minimumWriteInterval {
                return false
            }
        }

        let heartbeat = ExtensionHeartbeat(
            timestamp: timestamp,
            processID: processID,
            version: version,
            observedPathCount: max(0, observedPathCount)
        )
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(heartbeat)
            try data.write(to: fileURL, options: .atomic)
            lastWriteTimestamp = timestamp
            return true
        } catch {
            AppLog.error("扩展心跳写入失败: \(error.localizedDescription)", category: .storage)
            return false
        }
    }

    private func loadUnlocked() -> ExtensionHeartbeat? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ExtensionHeartbeat.self, from: data)
    }
}
