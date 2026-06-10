import XCTest
@testable import RightClickAssistantCore

final class RightClickAssistantTests: XCTestCase {
    
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        // 创建一个独立的临时目录作为测试运行沙盒，避免对用户磁盘产生脏数据
        let uniqueName = UUID().uuidString
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueName)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    override func tearDown() {
        // 清理测试临时目录下的所有测试生成物
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    /// 1. 测试动作派发器能否正常注册和检索动作
    func testActionDispatcherRegistration() {
        let dispatcher = ActionDispatcher.shared
        let txtAction = NewFileAction(fileType: .txt)
        
        dispatcher.register(action: txtAction)
        
        let retrieved = dispatcher.action(forId: txtAction.actionId)
        XCTAssertNotNil(retrieved, "应该能从派发器中检索出已注册的动作")
        XCTAssertEqual(retrieved?.actionId, txtAction.actionId)
        XCTAssertEqual(retrieved?.category, .newFile)
    }
    
    /// 2. 测试新建文件在发生重名时的自增重命名逻辑
    func testNewFileNameCollisionResolution() {
        let action = NewFileAction(fileType: .txt)
        
        // 第一次创建：应该生成 文件夹/未命名.txt
        let success1 = action.execute(targetURLs: [tempDirectory])
        XCTAssertTrue(success1, "第一次创建文件应该成功")
        
        let expectedURL1 = tempDirectory.appendingPathComponent("未命名.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL1.path), "未命名.txt 文件应当存在")
        
        // 第二次创建：由于“未命名.txt”已存在，应该自动重命名为 文件夹/未命名 1.txt
        let success2 = action.execute(targetURLs: [tempDirectory])
        XCTAssertTrue(success2, "第二次创建文件（重名冲突下）应该成功")
        
        let expectedURL2 = tempDirectory.appendingPathComponent("未命名 1.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL2.path), "冲突下，未命名 1.txt 文件应当存在")
        
        // 第三次创建：应该自动重命名为 文件夹/未命名 2.txt
        let success3 = action.execute(targetURLs: [tempDirectory])
        XCTAssertTrue(success3)
        
        let expectedURL3 = tempDirectory.appendingPathComponent("未命名 2.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL3.path))
    }
    
    /// 3. 测试新建高级文档（如 Office 三件套）时的数据流完整性
    func testOfficeFileTemplateBytes() {
        let action = NewFileAction(fileType: .docx)
        
        let success = action.execute(targetURLs: [tempDirectory])
        XCTAssertTrue(success)
        
        let expectedURL = tempDirectory.appendingPathComponent("未命名.docx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))
        
        // 校验文件内容是否包含标准 Office ZIP 压缩包的魔数（50 4B 03 04 -> PK）
        if let fileData = try? Data(contentsOf: expectedURL) {
            XCTAssertGreaterThan(fileData.count, 0, "Office 默认模板文件不应为 0 字节损坏文件")
            XCTAssertEqual(fileData.prefix(2), Data([0x50, 0x4B]), "Office 容器文件应该以 ZIP 魔数 'PK' 开始")
        } else {
            XCTFail("无法读取生成的文件内容")
        }
    }

    /// 4. 测试新建 PDF 时写入最小合法 PDF 骨架，避免生成 0 字节损坏文件
    func testPDFFileTemplateBytes() {
        let action = NewFileAction(fileType: .pdf)

        let success = action.execute(targetURLs: [tempDirectory])
        XCTAssertTrue(success)

        let expectedURL = tempDirectory.appendingPathComponent("未命名.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))

        guard let fileData = try? Data(contentsOf: expectedURL) else {
            XCTFail("无法读取生成的 PDF 文件内容")
            return
        }

        XCTAssertTrue(fileData.starts(with: Data("%PDF-".utf8)), "PDF 文件应该以标准 PDF 魔数开头")
        XCTAssertTrue(fileData.contains(Data("%%EOF".utf8)), "PDF 文件应该包含 EOF 结束标记")
    }

    /// 5. 测试新建 HTML 时写入基础文档骨架，便于双击后直接编辑和预览
    func testHTMLFileTemplateBytes() {
        let action = NewFileAction(fileType: .html)

        let success = action.execute(targetURLs: [tempDirectory])
        XCTAssertTrue(success)

        let expectedURL = tempDirectory.appendingPathComponent("未命名.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))

        let html = (try? String(contentsOf: expectedURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(html.contains("<!doctype html>"), "HTML 文件应该包含基础 doctype")
        XCTAssertTrue(html.contains("<title>未命名</title>"), "HTML 文件应该包含默认标题")
    }

    /// 6. 测试共享动作通道使用 UUID 队列，连续写入不会互相覆盖
    func testSharedActionQueuePreservesMultipleEvents() throws {
        let storage = SharedStorageManager.shared
        try? FileManager.default.removeItem(at: storage.pendingActionsDirectoryURL)
        try? FileManager.default.removeItem(at: storage.pendingActionURL)

        _ = try storage.enqueueAction(actionId: "guyue.action.newfile.txt", paths: [tempDirectory.path])
        _ = try storage.enqueueAction(actionId: "guyue.action.newfile.md", paths: [tempDirectory.path])

        let events = storage.consumePendingActionEvents()

        XCTAssertEqual(Set(events.map(\.actionId)), Set([
            "guyue.action.newfile.txt",
            "guyue.action.newfile.md"
        ]))
        let remainingFiles = (try? FileManager.default.contentsOfDirectory(atPath: storage.pendingActionsDirectoryURL.path)) ?? []
        XCTAssertTrue(remainingFiles.isEmpty)
    }

    /// 7. 高风险动作默认关闭，避免首次安装即暴露破坏性菜单项
    func testHighRiskActionsAreDisabledByDefault() {
        let permanentDelete = FileManageAction(type: .permanentDelete)
        let moveTo = FileManageAction(type: .moveTo)
        let copyTo = FileManageAction(type: .copyTo)
        let toggleHiddenFiles = UtilityAction(type: .toggleHiddenFiles)
        let newTextFile = NewFileAction(fileType: .txt)

        XCTAssertFalse(permanentDelete.isEnabledByDefault)
        XCTAssertFalse(moveTo.isEnabledByDefault)
        XCTAssertFalse(copyTo.isEnabledByDefault)
        XCTAssertFalse(toggleHiddenFiles.isEnabledByDefault)
        XCTAssertTrue(newTextFile.isEnabledByDefault)
    }

    /// 8. 托盘中的高风险动作必须复用共享启用策略，默认不暴露给用户
    func testHighRiskStatusMenuActionRequiresExplicitEnablement() {
        let storage = SharedStorageManager.shared
        let toggleHiddenFiles = UtilityAction(type: .toggleHiddenFiles)
        let key = "enable_action_\(toggleHiddenFiles.actionId)"

        storage.removeValue(forKey: key)
        XCTAssertFalse(storage.isActionEnabled(toggleHiddenFiles))

        storage.setBool(true, forKey: key)
        XCTAssertTrue(storage.isActionEnabled(toggleHiddenFiles))

        storage.removeValue(forKey: key)
    }

    /// 9. 生产日志默认关闭详细调试，避免右键渲染时持续写入用户路径
    func testDebugLoggingDefaultsToDisabled() {
        let storage = SharedStorageManager.shared

        storage.removeValue(forKey: SharedStorageManager.Keys.enableDebugLogging)
        XCTAssertFalse(storage.isDebugLoggingEnabled)

        storage.setBool(true, forKey: SharedStorageManager.Keys.enableDebugLogging)
        XCTAssertTrue(storage.isDebugLoggingEnabled)

        storage.removeValue(forKey: SharedStorageManager.Keys.enableDebugLogging)
    }

    /// 10. 设置页动作分组应能区分常规动作与高级动作
    func testActionSettingsGroupSeparatesStandardAndAdvancedActions() {
        let newTextFile = NewFileAction(fileType: .txt)
        let permanentDelete = FileManageAction(type: .permanentDelete)
        let toggleHiddenFiles = UtilityAction(type: .toggleHiddenFiles)

        XCTAssertEqual(newTextFile.settingsGroup, .standard)
        XCTAssertEqual(permanentDelete.settingsGroup, .advanced)
        XCTAssertEqual(toggleHiddenFiles.settingsGroup, .advanced)
    }
}
