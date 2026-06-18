import Foundation

/// 完全磁盘访问权限检测器。
///
/// 不把检测押在单个目录上：Safari、Mail、Messages 等目录在不同系统状态下可能不存在、
/// 被迁移或有额外数据保护。只要任一受保护探针可读，就说明当前宿主 App 已获得 FDA。
public enum FullDiskAccessChecker {
    public enum ProbeKind: Equatable {
        case file
        case directory
    }

    public struct Probe: Equatable {
        public let url: URL
        public let kind: ProbeKind

        public init(url: URL, kind: ProbeKind) {
            self.url = url
            self.kind = kind
        }
    }

    public static func defaultProbes(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Probe] {
        [
            Probe(
                url: homeDirectory.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
                kind: .file
            ),
            Probe(
                url: homeDirectory.appendingPathComponent("Library/Mail"),
                kind: .directory
            ),
            Probe(
                url: homeDirectory.appendingPathComponent("Library/Messages"),
                kind: .directory
            ),
            Probe(
                url: homeDirectory.appendingPathComponent("Library/Application Support/AddressBook"),
                kind: .directory
            ),
            Probe(
                url: homeDirectory.appendingPathComponent("Library/Safari"),
                kind: .directory
            )
        ]
    }

    public static func hasFullDiskAccess(
        probes: [Probe] = defaultProbes(),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        canRead: (Probe) -> Bool = Self.canReadProbe
    ) -> Bool {
        for probe in probes where fileExists(probe.url.path) {
            if canRead(probe) {
                return true
            }
        }
        return false
    }

    public static func canReadProbe(_ probe: Probe) -> Bool {
        do {
            switch probe.kind {
            case .file:
                let handle = try FileHandle(forReadingFrom: probe.url)
                try? handle.close()
                return true
            case .directory:
                _ = try FileManager.default.contentsOfDirectory(
                    at: probe.url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                return true
            }
        } catch {
            return false
        }
    }
}
