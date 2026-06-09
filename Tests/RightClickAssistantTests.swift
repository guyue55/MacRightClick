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
    
    /// 2. 测试新建文件在发生重名时的自增重命名逻辑（完美冲突解决）
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
}
