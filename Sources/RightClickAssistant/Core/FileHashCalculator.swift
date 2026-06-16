import Foundation
import CryptoKit

/// 支持的文件哈希算法。
public enum HashAlgorithm: String, Codable {
    case md5
    case sha256
}

/// 流式文件哈希计算器。使用 FileHandle 分块读取，避免将大文件一次性载入内存。
public enum FileHashCalculator {

    /// 默认分块大小：4 MB。
    public nonisolated(unsafe) static var chunkSize: Int = 4 * 1024 * 1024

    /// 对指定文件计算哈希值，返回小写十六进制字符串。
    public static func hashFile(at url: URL, algorithm: HashAlgorithm) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        switch algorithm {
        case .md5:
            var digest = Insecure.MD5()
            while autoreleasepool(invoking: {
                let data = try? handle.read(upToCount: chunkSize)
                guard let chunk = data, !chunk.isEmpty else { return false }
                digest.update(data: chunk)
                return true
            }) { /* continue */ }
            let result = digest.finalize()
            return result.map { String(format: "%02hhx", $0) }.joined()

        case .sha256:
            var digest = SHA256()
            while autoreleasepool(invoking: {
                let data = try? handle.read(upToCount: chunkSize)
                guard let chunk = data, !chunk.isEmpty else { return false }
                digest.update(data: chunk)
                return true
            }) { /* continue */ }
            let result = digest.finalize()
            return result.map { String(format: "%02hhx", $0) }.joined()
        }
    }
}
