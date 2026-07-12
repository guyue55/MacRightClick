import Foundation
import AppKit

/// 机器端全自动物理仿真验证工具 (ActionVerifier)
/// 检验宿主进程对核心动作的分发、保活与执行成效。
@main
struct ActionVerifier {
    static func main() {
        print("==============================================================================")
        print("🧪 [Verifier] 开始执行 10 项关键链路机器端物理仿真校验...")
        print("==============================================================================")
        
        // 1. 初始化测试专属物理大本营
        let homeDir = NSHomeDirectory()
        let testDirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RightClickAssistantVerifier-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: testDirURL)
        try? FileManager.default.createDirectory(at: testDirURL, withIntermediateDirectories: true)
        
        print("📂 [Verifier] 1. 创建测试物理专属工作区: \(testDirURL.path)")
        
        let sharedRootPath = ProcessInfo.processInfo.environment["RIGHTCLICKASSISTANT_SHARED_ROOT"]
            ?? (homeDir as NSString).appendingPathComponent(
                "Library/Containers/guyue.RightClickAssistant.Extension/Data"
            )
        let sharedRootURL = URL(fileURLWithPath: sharedRootPath, isDirectory: true)
        let pendingActionsDirectoryURL = sharedRootURL.appendingPathComponent("PendingActions")
        try? FileManager.default.createDirectory(at: pendingActionsDirectoryURL, withIntermediateDirectories: true)
        print("📂 [Verifier] 2. 中介动作队列地址: \(pendingActionsDirectoryURL.path)")

        let requiredProfessionalActions = [
            "guyue.action.newfile.docx",
            "guyue.action.newfile.html",
            "guyue.action.utility.calculateMD5",
            "guyue.action.utility.convertToJPG"
        ]
        let configURL = sharedRootURL.appendingPathComponent("config.json")
        let config = (try? Data(contentsOf: configURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let disabledRequiredActions = requiredProfessionalActions.filter {
            config["enable_action_\($0)"] as? Bool != true
        }
        if !disabledRequiredActions.isEmpty {
            print("❌ [Verifier] 运行前请在“动作”页应用“专业”档案，确保关键链路动作已启用。")
            print("❌ [Verifier] 当前未启用: \(disabledRequiredActions.joined(separator: ", "))")
            try? FileManager.default.removeItem(at: testDirURL)
            exit(2)
        }
        
        // 我们选取代表 4 大分类的核心动作集进行严丝合缝的机器物理断言
        var passCount = 0
        var failCount = 0
        var testCount = 0
        
        func runTest(name: String, actionId: String, targets: [URL], assertion: () -> Bool) {
            testCount += 1
            print("\n------------------------------------------------------------------------------")
            print("▶️ [Verifier] 测试项: \(name) [ID: \(actionId)]")
            
            // A. 写入独立 UUID 队列事件，避免连续测试覆盖
            let actionData: [String: Any] = [
                "schemaVersion": 2,
                "id": UUID().uuidString,
                "createdAt": Date().timeIntervalSince1970,
                "actionId": actionId,
                "paths": targets.map { $0.path },
                "invocationKind": "items"
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
                "schemaVersion": 2,
                "id": UUID().uuidString,
                "createdAt": Date().timeIntervalSince1970,
                "actionId": "guyue.action.newfile.md",
                "paths": [testDirURL.path],
                "invocationKind": "items"
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
            let clipStr = NSPasteboard.general.string(forType: .string) ?? ""
            print("ℹ️ [Verifier] 剪贴板 MD5 结果: \(clipStr)")
            return clipStr == "6f6b4a05c9f02fd24430a09bc98e7759"
        }
        
        runTest(name: "物理计算 SHA256 码并写入剪切板", actionId: "guyue.action.utility.calculateSHA256", targets: [hashTestFile]) {
            let clipStr = NSPasteboard.general.string(forType: .string) ?? ""
            print("ℹ️ [Verifier] 剪贴板 SHA256 结果: \(clipStr)")
            return clipStr == "c6af35fd81aaf5c475cbe8dc51795fe0e0ba6eb6304b9234df430aa4c102305e"
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
        print("🟢 通过项: \(passCount) / \(testCount)")
        print("🔴 失败项: \(failCount) / \(testCount)")
        print("==============================================================================")
        
        if failCount > 0 {
            exit(1)
        } else {
            print("✅ [Verifier] 验证通过：多进程动作队列、生命周期与核心 Action 逻辑符合预期。")
            exit(0)
        }
    }
}
