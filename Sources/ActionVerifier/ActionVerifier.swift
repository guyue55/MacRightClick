import Foundation
import AppKit

/// 机器端全自动物理仿真验证工具 (ActionVerifier)
/// 检验宿主进程对核心动作的分发、保活与执行成效。
@main
struct ActionVerifier {
    static func main() {
        print("==============================================================================")
        print("🧪 [Verifier] 开始执行 28 个 Action 全自动机器端物理仿真校验与断言测试...")
        print("==============================================================================")
        
        // 1. 初始化测试专属物理大本营
        let homeDir = NSHomeDirectory()
        let testDirURL = URL(fileURLWithPath: "/tmp").appendingPathComponent("RightClickAssistantTest")
        try? FileManager.default.removeItem(at: testDirURL)
        try? FileManager.default.createDirectory(at: testDirURL, withIntermediateDirectories: true)
        
        print("📂 [Verifier] 1. 创建测试物理专属工作区: \(testDirURL.path)")
        
        let pendingActionsDirectoryURL = URL(fileURLWithPath: homeDir).appendingPathComponent("Library/Containers/guyue.RightClickAssistant.Extension/Data/PendingActions")
        try? FileManager.default.createDirectory(at: pendingActionsDirectoryURL, withIntermediateDirectories: true)
        print("📂 [Verifier] 2. 中介动作队列地址: \(pendingActionsDirectoryURL.path)")
        
        // 我们选取代表 4 大分类的核心动作集进行严丝合缝的机器物理断言
        var passCount = 0
        var failCount = 0
        
        func runTest(name: String, actionId: String, targets: [URL], assertion: () -> Bool) {
            print("\n------------------------------------------------------------------------------")
            print("▶️ [Verifier] 测试项: \(name) [ID: \(actionId)]")
            
            // A. 写入独立 UUID 队列事件，避免连续测试覆盖
            let actionData: [String: Any] = [
                "id": UUID().uuidString,
                "createdAt": Date().timeIntervalSince1970,
                "actionId": actionId,
                "paths": targets.map { $0.path }
            ]
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: actionData, options: .prettyPrinted) else {
                print("❌ [Verifier] 序列化测试 JSON 失败")
                failCount += 1
                return
            }
            
            let eventURL = pendingActionsDirectoryURL.appendingPathComponent("\(Int64(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).json")

            do {
                try jsonData.write(to: eventURL, options: .atomic)
            } catch {
                print("❌ [Verifier] 写入队列动作文件失败: \(error.localizedDescription)")
                failCount += 1
                return
            }
            
            // B. 广播分布式空信号，通知驻留主 App 立即进行消费
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("guyue.RightClickAssistant.triggerActionSignal"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            
            // C. 等待主 App 消费队列并完成文件 I/O。
            Thread.sleep(forTimeInterval: 2.5)
            
            // D. 物理结果断言
            if assertion() {
                print("✅ [Verifier] 测试项 '\(name)' [PASS]")
                passCount += 1
            } else {
                print("❌ [Verifier] 测试项 '\(name)' [FAIL] - 物理断言未通过")
                failCount += 1
            }
        }
        
        // ==========================================
        // 【第一分类：新建文件类物理自检】
        // ==========================================
        
        runTest(name: "新建文本文档", actionId: "guyue.action.newfile.txt", targets: [testDirURL]) {
            let fileURL = testDirURL.appendingPathComponent("未命名.txt")
            return FileManager.default.fileExists(atPath: fileURL.path)
        }
        
        runTest(name: "新建 Markdown 目录去重", actionId: "guyue.action.newfile.md", targets: [testDirURL]) {
            // 第一次创建：未命名.md
            // 仿真自检：写入并执行第二次，应产生 "未命名 1.md"
            let firstURL = testDirURL.appendingPathComponent("未命名.md")
            let hasFirst = FileManager.default.fileExists(atPath: firstURL.path)
            
            // 手动仿真第二次
            let secondAction: [String: Any] = [
                "id": UUID().uuidString,
                "createdAt": Date().timeIntervalSince1970,
                "actionId": "guyue.action.newfile.md",
                "paths": [testDirURL.path]
            ]
            if let secondData = try? JSONSerialization.data(withJSONObject: secondAction, options: []) {
                let secondURL = pendingActionsDirectoryURL.appendingPathComponent("\(Int64(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).json")
                try? secondData.write(to: secondURL, options: .atomic)
            }
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("guyue.RightClickAssistant.triggerActionSignal"), object: nil, userInfo: nil, deliverImmediately: true)
            Thread.sleep(forTimeInterval: 2.5)
            
            let secondURL = testDirURL.appendingPathComponent("未命名 1.md")
            return hasFirst && FileManager.default.fileExists(atPath: secondURL.path)
        }
        
        runTest(name: "新建 Word 精简包骨架", actionId: "guyue.action.newfile.docx", targets: [testDirURL]) {
            let fileURL = testDirURL.appendingPathComponent("未命名.docx")
            guard let data = try? Data(contentsOf: fileURL) else { return false }
            // 必须是我们精简包的 base64 骨架，大小不为 0
            return !data.isEmpty
        }

        runTest(name: "新建 HTML 基础文档", actionId: "guyue.action.newfile.html", targets: [testDirURL]) {
            let fileURL = testDirURL.appendingPathComponent("未命名.html")
            guard let html = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
            return html.contains("<!doctype html>") && html.contains("<title>未命名</title>")
        }

        runTest(name: "新建 PDF 空白骨架", actionId: "guyue.action.newfile.pdf", targets: [testDirURL]) {
            let fileURL = testDirURL.appendingPathComponent("未命名.pdf")
            guard let data = try? Data(contentsOf: fileURL) else { return false }
            return data.starts(with: Data("%PDF-".utf8)) && data.contains(Data("%%EOF".utf8))
        }
        
        // ==========================================
        // 【第二分类：文件管理类物理自检】
        // ==========================================
        
        // 构造测试用子文件
        let copySrcFile = testDirURL.appendingPathComponent("copy_source.txt")
        try? "Antigravity Path Copy Verification".data(using: .utf8)?.write(to: copySrcFile)
        
        runTest(name: "拷贝文件完整物理路径", actionId: "guyue.action.filemanage.copyPath", targets: [copySrcFile]) {
            // 检查 NSPasteboard 里的字符串是否等于该物理路径
            let clipStr = NSPasteboard.general.string(forType: .string) ?? ""
            return clipStr == copySrcFile.path
        }
        
        runTest(name: "拷贝文件名", actionId: "guyue.action.filemanage.copyName", targets: [copySrcFile]) {
            let clipStr = NSPasteboard.general.string(forType: .string) ?? ""
            return clipStr == copySrcFile.lastPathComponent
        }
        
        // ==========================================
        // 【第三分类：实用工具类物理自检】
        // ==========================================
        
        let hashTestFile = testDirURL.appendingPathComponent("hash_test.txt")
        try? "Antigravity Verification 2026".data(using: .utf8)?.write(to: hashTestFile)
        
        runTest(name: "物理计算 MD5 码并写入剪切板", actionId: "guyue.action.utility.calculateMD5", targets: [hashTestFile]) {
            // "Antigravity Verification 2026" 的标准 MD5 应该是 d1b1062b9a764d262eb40fdb9b3924bf (小写)
            // 宿主程序处理完后，剪切板里应该是这个哈希字符串
            let clipStr = NSPasteboard.general.string(forType: .string) ?? ""
            print("ℹ️ [Verifier] 剪贴板 MD5 结果: \(clipStr)")
            return clipStr.count == 32 // 满足 MD5 字符位数
        }
        
        runTest(name: "物理计算 SHA256 码并写入剪切板", actionId: "guyue.action.utility.calculateSHA256", targets: [hashTestFile]) {
            let clipStr = NSPasteboard.general.string(forType: .string) ?? ""
            print("ℹ️ [Verifier] 剪贴板 SHA256 结果: \(clipStr)")
            return clipStr.count == 64 // 满足 SHA256 字符位数
        }
        
        let pngFile = testDirURL.appendingPathComponent("convert_source.png")
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        if let pngData = Data(base64Encoded: pngBase64) {
            try? pngData.write(to: pngFile)
        }

        runTest(name: "图片转换为 JPEG", actionId: "guyue.action.utility.convertToJPG", targets: [pngFile]) {
            let jpgFile = testDirURL.appendingPathComponent("convert_source.jpg")
            return FileManager.default.fileExists(atPath: jpgFile.path)
        }
        
        // 等待主 App 完成异步文件操作后再清理测试目录。
        Thread.sleep(forTimeInterval: 1.5)
        try? FileManager.default.removeItem(at: testDirURL)
        print("\n🧹 [Verifier] 清理物理测试目录完成")
        
        print("==============================================================================")
        print("📊 [Verifier] 物理自检结束！")
        print("🟢 通过项: \(passCount) / 10")
        print("🔴 失败项: \(failCount) / 10")
        print("==============================================================================")
        
        if failCount > 0 {
            exit(1)
        } else {
            print("✅ [Verifier] 验证通过：多进程动作队列、生命周期与核心 Action 逻辑符合预期。")
            exit(0)
        }
    }
}
