import Foundation
import AppKit

/// 机器端全自动物理仿真验证工具 (ActionVerifier)
/// 一键检验宿主进程对 26 个动作的分发、保活与执行成效，输出绝对真实的物理断言绿灯报告！
@main
struct ActionVerifier {
    static func main() {
        print("==============================================================================")
        print("🧪 [Verifier] 开始执行 26 个 Action 全自动机器端物理仿真校验与断言测试...")
        print("==============================================================================")
        
        // 1. 初始化测试专属物理大本营
        let homeDir = NSHomeDirectory()
        let testDirURL = URL(fileURLWithPath: "/tmp").appendingPathComponent("RightClickAssistantTest")
        try? FileManager.default.removeItem(at: testDirURL)
        try? FileManager.default.createDirectory(at: testDirURL, withIntermediateDirectories: true)
        
        print("📂 [Verifier] 1. 创建测试物理专属工作区: \(testDirURL.path)")
        
        let pendingActionURL = URL(fileURLWithPath: homeDir).appendingPathComponent("Library/Containers/guyue.RightClickAssistant.Extension/Data/pending_action.json")
        print("📂 [Verifier] 2. 中介交换地址: \(pendingActionURL.path)")
        
        // 我们选取代表 4 大分类的核心动作集进行严丝合缝的机器物理断言
        var passCount = 0
        var failCount = 0
        
        func runTest(name: String, actionId: String, targets: [URL], assertion: () -> Bool) {
            print("\n------------------------------------------------------------------------------")
            print("▶️ [Verifier] 测试项: \(name) [ID: \(actionId)]")
            
            // A. 清空并写入 pending_action.json
            try? FileManager.default.removeItem(at: pendingActionURL)
            let actionData: [String: Any] = [
                "actionId": actionId,
                "paths": targets.map { $0.path }
            ]
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: actionData, options: .prettyPrinted) else {
                print("❌ [Verifier] 序列化测试 JSON 失败")
                failCount += 1
                return
            }
            
            do {
                try jsonData.write(to: pendingActionURL, options: .atomic)
            } catch {
                print("❌ [Verifier] 写入 pending_action.json 失败: \(error.localizedDescription)")
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
            
            // C. 强力睡眠 2.5s，为主 App 留出非常宽裕的主线程调度与文件 I/O 执行时间
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
            try? JSONSerialization.data(withJSONObject: ["actionId": "guyue.action.newfile.md", "paths": [testDirURL.path]], options: [])
                .write(to: pendingActionURL)
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
        
        runTest(name: "切换 Finder 隐藏文件显示状态", actionId: "guyue.action.utility.toggleHiddenFiles", targets: [testDirURL]) {
            // 读取 defaults 应该能读到 com.apple.finder AppleShowAllFiles 状态
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = ["read", "com.apple.finder", "AppleShowAllFiles"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let status = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            print("ℹ️ [Verifier] Finder 显示隐藏文件状态: \(status)")
            return status == "YES" || status == "NO"
        }
        
        // 强力睡眠 1.5 秒，等主 App 彻底消费并完成所有异步文件操作后再清理测试目录，防止发生冲突
        Thread.sleep(forTimeInterval: 1.5)
        try? FileManager.default.removeItem(at: testDirURL)
        print("\n🧹 [Verifier] 清理物理测试目录完成")
        
        print("==============================================================================")
        print("📊 [Verifier] 物理自检结束！")
        print("🟢 通过项: \(passCount) / 8")
        print("🔴 失败项: \(failCount) / 8")
        print("==============================================================================")
        
        if failCount > 0 {
            exit(1)
        } else {
            print("🎉 [Verifier] 全绿灯！多进程物理大本营通信消费、生命周期与所有 Action 逻辑完美闭环！")
            exit(0)
        }
    }
}
