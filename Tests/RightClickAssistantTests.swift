import XCTest
import AppKit
@testable import RightClickAssistantCore

final class RightClickAssistantTests: XCTestCase {
    
    var tempDirectory: URL!
    var storage: SharedStorageManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        // 创建一个独立的临时目录作为测试运行沙盒，避免对用户磁盘产生脏数据
        let uniqueName = UUID().uuidString
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueName)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        addTeardownBlock {
            try TestStorage.removeIfPresent(temporaryDirectory)
        }
        tempDirectory = temporaryDirectory

        let testStorage = try TestStorage.make()
        addTeardownBlock {
            try TestStorage.removeIfPresent(testStorage.root)
        }
        storage = testStorage.manager
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

    func testDefaultRegistryHasUniqueThirtyActionIDs() {
        let actions = DefaultActionRegistry.makeActions()

        XCTAssertEqual(actions.count, 30)
        XCTAssertEqual(Set(actions.map(\.actionId)).count, actions.count)
    }

    func testMenuActionExistentialUsesConcreteAssociatedBundleIdentifier() {
        let action: MenuAction = TerminalOpenAction(type: .vscode)

        XCTAssertEqual(action.associatedBundleIdentifier, "com.microsoft.VSCode")
    }

    func testEssentialProfileNeverChangesHighRiskActions() {
        let actions = DefaultActionRegistry.makeActions()
        let states = ActionProfile.essential.states(for: actions)

        XCTAssertFalse(states.keys.contains("guyue.action.filemanage.delete"))
        XCTAssertFalse(states.keys.contains("guyue.action.filemanage.moveTo"))
        XCTAssertFalse(states.keys.contains("guyue.action.utility.toggleHiddenFiles"))
    }

    func testProfessionalProfileEnablesProfessionalButNotAdvancedActions() {
        let actions = DefaultActionRegistry.makeActions()
        let states = ActionProfile.professional.states(for: actions)

        XCTAssertEqual(states["guyue.action.newfile.json"], true)
        XCTAssertEqual(states["guyue.action.terminal.vscode"], true)
        XCTAssertNil(states["guyue.action.filemanage.delete"])
    }

    func testActionSearchMatchesTitleAndIdentifier() {
        XCTAssertTrue(ActionSearch.matches(
            title: "新建文本文件",
            actionID: "guyue.action.newfile.txt",
            query: "文本"
        ))
        XCTAssertTrue(ActionSearch.matches(
            title: "新建文本文件",
            actionID: "guyue.action.newfile.txt",
            query: "newfile.txt"
        ))
        XCTAssertFalse(ActionSearch.matches(
            title: "新建文本文件",
            actionID: "guyue.action.newfile.txt",
            query: "二维码"
        ))
    }

    func testProfessionalProfileNeverEnablesAdvancedTier() {
        let actions = DefaultActionRegistry.makeActions()
        let states = ActionProfile.professional.states(for: actions)
        let advancedIDs = Set(actions.filter { $0.tier == .advanced }.map(\.actionId))

        XCTAssertTrue(advancedIDs.isDisjoint(with: states.keys))
    }

    func testFreshSettingsMigrationAppliesEssentialProfile() {
        let actions = DefaultActionRegistry.makeActions()

        storage.migrateSettingsIfNeeded(actions: actions)

        XCTAssertEqual(storage.actionProfile, .essential)
        XCTAssertTrue(storage.getBool(
            forKey: "enable_action_guyue.action.newfile.txt",
            defaultValue: false
        ))
        XCTAssertFalse(storage.getBool(
            forKey: "enable_action_guyue.action.newfile.json",
            defaultValue: true
        ))
        XCTAssertFalse(storage.getBool(
            forKey: "enable_action_guyue.action.filemanage.delete",
            defaultValue: false
        ))
        XCTAssertTrue(storage.getBool(
            forKey: SharedStorageManager.Keys.actionProfileMigrationV1,
            defaultValue: false
        ))
    }

    func testLegacySettingsMigrationPreservesEffectiveStatesAndHighRiskChoice() {
        let actions = DefaultActionRegistry.makeActions()
        XCTAssertTrue(storage.setBool(false, forKey: "enable_action_guyue.action.newfile.txt"))
        XCTAssertTrue(storage.setBool(true, forKey: "enable_action_guyue.action.newfile.json"))
        XCTAssertTrue(storage.setBool(true, forKey: "enable_action_guyue.action.filemanage.delete"))

        storage.migrateSettingsIfNeeded(actions: actions)

        XCTAssertEqual(storage.actionProfile, .custom)
        XCTAssertFalse(storage.getBool(
            forKey: "enable_action_guyue.action.newfile.txt",
            defaultValue: true
        ))
        XCTAssertTrue(storage.getBool(
            forKey: "enable_action_guyue.action.newfile.json",
            defaultValue: false
        ))
        XCTAssertTrue(storage.getBool(
            forKey: "enable_action_guyue.action.filemanage.delete",
            defaultValue: false
        ))
    }

    func testApplyingProfileLeavesAdvancedActionChoiceUntouched() {
        let actions = DefaultActionRegistry.makeActions()
        let deleteKey = "enable_action_guyue.action.filemanage.delete"
        XCTAssertTrue(storage.setBool(true, forKey: deleteKey))

        XCTAssertTrue(storage.applyActionProfile(.essential, actions: actions))

        XCTAssertEqual(storage.actionProfile, .essential)
        XCTAssertTrue(storage.getBool(forKey: deleteKey, defaultValue: false))
    }

    func testLegacyEventDefaultsToItemsInvocation() throws {
        let data = #"{"id":"1","createdAt":1,"actionId":"test","paths":["/tmp/a"]}"#
            .data(using: .utf8)!

        let event = try JSONDecoder().decode(SharedActionEvent.self, from: data)

        XCTAssertEqual(event.schemaVersion, 1)
        XCTAssertEqual(event.invocationKind, .items)
    }

    func testV2EventRoundTripPreservesContainerInvocation() throws {
        let eventURL = try storage.enqueueAction(
            actionId: "test.container",
            paths: [tempDirectory.path],
            invocationKind: .container
        )
        let data = try Data(contentsOf: eventURL)

        let event = try JSONDecoder().decode(SharedActionEvent.self, from: data)

        XCTAssertEqual(event.schemaVersion, 2)
        XCTAssertEqual(event.invocationKind, .container)
    }

    func testDispatcherRejectsDisabledActionEvenWhenEventWasQueued() throws {
        let target = tempDirectory.appendingPathComponent("enabled-check.txt")
        try Data().write(to: target)
        let action = DispatchProbeAction()
        let dispatcher = ActionDispatcher(isActionEnabled: { _ in false })
        dispatcher.register(action: action)

        XCTAssertFalse(dispatcher.dispatch(
            actionId: action.actionId,
            targetURLs: [target],
            invocationKind: .items
        ))
        XCTAssertFalse(action.didExecute)
    }

    func testDispatcherRevalidatesInvocationContext() throws {
        let target = tempDirectory.appendingPathComponent("context-check.txt")
        try Data().write(to: target)
        let action = DispatchProbeAction(availableInContainer: true)
        let dispatcher = ActionDispatcher(isActionEnabled: { _ in true })
        dispatcher.register(action: action)

        XCTAssertFalse(dispatcher.dispatch(
            actionId: action.actionId,
            targetURLs: [target],
            invocationKind: .items
        ))
        XCTAssertTrue(dispatcher.dispatch(
            actionId: action.actionId,
            targetURLs: [target],
            invocationKind: .container
        ))
    }

    func testDispatcherAllowsPathIndependentActionWithMissingTarget() {
        let action = DispatchProbeAction(requiresExistingTargets: false)
        let dispatcher = ActionDispatcher(isActionEnabled: { _ in true })
        dispatcher.register(action: action)
        let missing = tempDirectory.appendingPathComponent("missing")

        XCTAssertTrue(dispatcher.dispatch(
            actionId: action.actionId,
            targetURLs: [missing],
            invocationKind: .items
        ))
        XCTAssertTrue(action.didExecute)
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
        try TestStorage.removeIfPresent(storage.pendingActionsDirectoryURL)
        try TestStorage.removeIfPresent(storage.pendingActionURL)
        try TestStorage.removeIfPresent(storage.inFlightActionsDirectoryURL)

        _ = try storage.enqueueAction(actionId: "guyue.action.newfile.txt", paths: [tempDirectory.path])
        _ = try storage.enqueueAction(actionId: "guyue.action.newfile.md", paths: [tempDirectory.path])

        let leases = storage.consumePendingActionLeases()
        let events = leases.map { $0.event }
        leases.forEach { storage.acknowledge($0) }

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

    /// 11. 默认菜单保持精简，低频动作由用户按需开启
    func testDefaultMenuKeepsLowFrequencyActionsDisabled() {
        XCTAssertTrue(NewFileAction(fileType: .txt).isEnabledByDefault)
        XCTAssertTrue(FileManageAction(type: .copyPath).isEnabledByDefault)
        XCTAssertTrue(TerminalOpenAction(type: .terminal).isEnabledByDefault)

        XCTAssertFalse(NewFileAction(fileType: .xlsx).isEnabledByDefault)
        XCTAssertFalse(TerminalOpenAction(type: .warp).isEnabledByDefault)
        XCTAssertFalse(UtilityAction(type: .convertToJPEG).isEnabledByDefault)
    }

    /// 12. 收藏动作通过共享配置持久化，供 Finder 菜单生成常用区
    func testFavoriteActionIdsRoundTrip() {
        let action = NewFileAction(fileType: .txt)

        storage.setAction(action, favorite: false)
        XCTAssertFalse(storage.isFavoriteAction(action))

        storage.setAction(action, favorite: true)
        XCTAssertTrue(storage.isFavoriteAction(action))

        storage.setAction(action, favorite: false)
    }

    func testConcurrentFavoriteMutationsPreserveEveryAction() {
        storage.removeValue(forKey: SharedStorageManager.Keys.favoriteActionIds)
        let storageBox = TestSendableBox(storage!)
        let actionIDs = (0..<64).map { "test.favorite.concurrent.\($0)" }
        let group = DispatchGroup()

        for actionID in actionIDs {
            group.enter()
            DispatchQueue.global().async {
                let action = TestMenuAction(
                    id: actionID,
                    title: actionID,
                    category: .utility
                )
                storageBox.value.setAction(action, favorite: true)
                group.leave()
            }
        }
        group.wait()

        XCTAssertEqual(Set(storage.favoriteActionIds), Set(actionIDs))
    }

    /// 13. 默认监听目录不应包含或创建用户项目目录
    func testDefaultWatchedDirectoriesDoNotIncludeGitProject() {
        let paths = SharedStorageManager.defaultWatchedDirectoryPaths(
            homePath: "/Users/example",
            fileExists: { path in
                ["/Users/example/Desktop", "/Users/example/Downloads", "/Users/example/Documents", "/Users/example/GitProject"].contains(path)
            }
        )

        XCTAssertEqual(paths, [
            "/Users/example/Desktop",
            "/Users/example/Downloads",
            "/Users/example/Documents"
        ])
        XCTAssertFalse(paths.contains("/Users/example/GitProject"))
    }

    /// 14. 哈希计算应支持流式读取并给出稳定结果
    func testFileHashCalculatorProducesExpectedHashes() throws {
        let fileURL = tempDirectory.appendingPathComponent("hash.txt")
        try Data("abc".utf8).write(to: fileURL)

        XCTAssertEqual(try FileHashCalculator.hashFile(at: fileURL, algorithm: .md5), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(try FileHashCalculator.hashFile(at: fileURL, algorithm: .sha256), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testHashReadFailureIsNotConvertedIntoPrefixDigest() throws {
        let fileURL = tempDirectory.appendingPathComponent("hash-read-error.txt")
        try Data("abcdef".utf8).write(to: fileURL)
        var reads = 0

        XCTAssertThrowsError(try FileHashCalculator.hashFile(
            at: fileURL,
            algorithm: .sha256,
            readChunk: { handle, count in
                reads += 1
                if reads > 1 {
                    throw CocoaError(.fileReadUnknown)
                }
                return try handle.read(upToCount: min(count, 3))
            }
        ))
    }

    /// 15. 无法解析的队列事件应隔离到 FailedActions，便于诊断而不是静默丢弃
    func testMalformedQueueEventsAreQuarantined() throws {
        try TestStorage.removeIfPresent(storage.pendingActionsDirectoryURL)
        try TestStorage.removeIfPresent(storage.failedActionsDirectoryURL)
        try TestStorage.removeIfPresent(storage.inFlightActionsDirectoryURL)

        let malformedURL = storage.pendingActionsDirectoryURL.appendingPathComponent("malformed.json")
        try Data("{ invalid json".utf8).write(to: malformedURL)

        let leases = storage.consumePendingActionLeases()

        XCTAssertTrue(leases.isEmpty)
        XCTAssertEqual(storage.pendingActionCount, 0)
        XCTAssertEqual(storage.failedActionCount, 1)
    }

    /// 16. ActionConfigCache 命中后不应再穿透到 SharedStorageManager.getBool
    /// 这是 menu(for:) 主热路径的性能与同步 IO 抑制保障。
    func testFinderSyncUsesCacheNoSyncIO() {
        let cache = ActionConfigCache(storage: storage)
        let actionId = "guyue.action.test.cache.no_sync_io"
        let key = "enable_action_\(actionId)"

        // 准备：清掉残留状态，让 cache 从空开始。
        storage.setBool(true, forKey: key)
        cache.invalidate()

        // 装上观察钩子统计 getBool 命中次数。
        var ioHits = 0
        storage.observeGetBoolForTesting = { observedKey in
            if observedKey == key { ioHits += 1 }
        }
        defer { storage.observeGetBoolForTesting = nil }

        _ = cache.isEnabled(actionId, default: false) // miss → 回源一次
        _ = cache.isEnabled(actionId, default: false) // 命中
        _ = cache.isEnabled(actionId, default: false) // 命中

        XCTAssertEqual(ioHits, 1, "首次 miss 后必须命中缓存，避免菜单渲染主路径反复同步读 UserDefaults/config.json")
    }

    // MARK: - QR 二维码面板「保存为 PNG / 拷贝图片」纯逻辑

    /// 17. QRCodeImageRenderer 应能把任意 NSImage 编码为 PNG Data 并以 89 50 4E 47 起头
    /// 这是「保存为 PNG」按钮成功落盘的前置纯逻辑，独立于 NSPanel 单测。
    func testQRCodeImageRendererProducesPNG() {
        // 用一张 1x1 红色 NSImage 作为最小可重现样本。
        let size = NSSize(width: 1, height: 1)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()

        guard let data = QRCodeImageRenderer.encodePNG(from: image) else {
            XCTFail("QRCodeImageRenderer.encodePNG 必须能把 NSImage 转成 PNG Data，避免「保存为 PNG」按钮静默失败")
            return
        }

        XCTAssertGreaterThan(data.count, 0)
        // PNG 文件签名前 4 字节固定为 89 50 4E 47
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    /// 18. QRCodePasteboardWriter 必须把 NSImage 真正写入指定 NSPasteboard
    /// 这是「拷贝图片」按钮的核心承诺，注入测试用 NSPasteboard 隔离剪贴板副作用。
    func testQRCodePasteboardWriterPlacesImage() {
        let size = NSSize(width: 2, height: 2)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.green.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()

        // 使用 withUniqueName 拿到一个独立 pasteboard，避免污染系统 .general 板。
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("guyue.RightClickAssistant.test.qr"))
        pasteboard.clearContents()

        QRCodePasteboardWriter.copy(image: image, to: pasteboard)

        let readBack = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]
        XCTAssertEqual(readBack?.count, 1, "拷贝图片后，pasteboard 应能 readObjects 出 1 张 NSImage")
        XCTAssertEqual(readBack?.first?.size, size, "回读图像的尺寸需与写入图像一致")
    }

    /// 19. 菜单布局模式默认应为直接显示，贴近 Windows 风格一级右键体验
    func testMenuLayoutModeDefaultsToFlat() {
        storage.removeValue(forKey: SharedStorageManager.Keys.menuLayoutMode)

        XCTAssertEqual(storage.menuLayoutMode, .flat)
    }

    /// 20. Flat 模式下收藏动作置顶且连续排列，收藏不应在普通区重复出现
    func testFlatMenuLayoutPlacesFavoritesFirstWithoutDuplicates() {
        let favorite = TestMenuAction(id: "favorite", title: "A Favorite", category: .utility)
        let regularNewFile = TestMenuAction(id: "regular.new", title: "B New", category: .newFile)
        let regularUtility = TestMenuAction(id: "regular.utility", title: "C Utility", category: .utility)

        let sections = FinderMenuLayoutBuilder.build(
            actions: [regularUtility, favorite, regularNewFile],
            mode: .flat,
            isEnabled: { _ in true },
            isFavorite: { $0.actionId == favorite.actionId },
            isAvailable: { _ in true }
        )

        XCTAssertEqual(sections, [
            .directItems(actionIds: [favorite.actionId, regularNewFile.actionId, regularUtility.actionId])
        ])
    }

    /// 21. Grouped 模式保留当前四分类子菜单结构，作为旧体验兼容开关
    func testGroupedMenuLayoutKeepsCategorySubmenus() {
        let newFile = TestMenuAction(id: "new", title: "New", category: .newFile)
        let utility = TestMenuAction(id: "utility", title: "Utility", category: .utility)

        let sections = FinderMenuLayoutBuilder.build(
            actions: [utility, newFile],
            mode: .grouped,
            isEnabled: { _ in true },
            isFavorite: { _ in false },
            isAvailable: { _ in true }
        )

        XCTAssertEqual(sections, [
            .submenu(title: ActionCategory.newFile.localizedName, actionIds: [newFile.actionId]),
            .submenu(title: ActionCategory.utility.localizedName, actionIds: [utility.actionId])
        ])
    }

    /// 22. 菜单布局 builder 必须继续尊重启用状态与可用性过滤
    func testMenuLayoutFiltersDisabledAndUnavailableActions() {
        let visible = TestMenuAction(id: "visible", title: "Visible", category: .newFile)
        let disabled = TestMenuAction(id: "disabled", title: "Disabled", category: .newFile)
        let unavailable = TestMenuAction(id: "unavailable", title: "Unavailable", category: .newFile)

        let sections = FinderMenuLayoutBuilder.build(
            actions: [visible, disabled, unavailable],
            mode: .flat,
            isEnabled: { $0.actionId != disabled.actionId },
            isFavorite: { _ in false },
            isAvailable: { $0.actionId != unavailable.actionId }
        )

        XCTAssertEqual(sections, [
            .directItems(actionIds: [visible.actionId])
        ])
    }

    /// 23. FDA 检测不应只依赖 Safari 目录；用户级 TCC.db 可读时应判定已授权
    func testFullDiskAccessCheckerGrantsWhenTCCDatabaseIsReadable() {
        let home = URL(fileURLWithPath: "/Users/example")
        let probes = FullDiskAccessChecker.defaultProbes(homeDirectory: home)
        let tccPath = "/Users/example/Library/Application Support/com.apple.TCC/TCC.db"

        XCTAssertTrue(probes.contains { $0.url.path == tccPath })

        let granted = FullDiskAccessChecker.hasFullDiskAccess(
            probes: probes,
            fileExists: { $0 == tccPath || $0 == "/Users/example/Library/Safari" },
            canRead: { $0.url.path == tccPath }
        )

        XCTAssertTrue(granted)
    }

    /// 24. 某些机器没有 Safari 数据或 Safari 目录不可读时，其他受保护目录可读也应判定已授权
    func testFullDiskAccessCheckerGrantsWhenAnyProtectedProbeIsReadable() {
        let home = URL(fileURLWithPath: "/Users/example")
        let messagesPath = "/Users/example/Library/Messages"

        let granted = FullDiskAccessChecker.hasFullDiskAccess(
            probes: FullDiskAccessChecker.defaultProbes(homeDirectory: home),
            fileExists: { $0 == messagesPath },
            canRead: { $0.url.path == messagesPath }
        )

        XCTAssertTrue(granted)
    }

    /// 25. 受保护探针存在但均不可读时，应判定尚未授予完全磁盘访问
    func testFullDiskAccessCheckerDeniesWhenExistingProtectedProbesAreUnreadable() {
        let home = URL(fileURLWithPath: "/Users/example")

        let granted = FullDiskAccessChecker.hasFullDiskAccess(
            probes: FullDiskAccessChecker.defaultProbes(homeDirectory: home),
            fileExists: { path in
                path == "/Users/example/Library/Safari"
                    || path == "/Users/example/Library/Messages"
            },
            canRead: { _ in false }
        )

        XCTAssertFalse(granted)
    }

    func testLaunchPresentationPolicyHidesWindowForBackgroundLaunchWhenSilentLaunchIsEnabled() {
        let context = LaunchPresentationPolicy.Context(
            isBackgroundRequest: true,
            appIsActive: false,
            appIsFrontmost: false
        )

        XCTAssertFalse(LaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
            silentLaunchEnabled: true,
            context: context
        ))
    }

    func testLaunchPresentationPolicyShowsWindowForExplicitForegroundLaunchByDefault() {
        let context = LaunchPresentationPolicy.Context(
            isBackgroundRequest: false,
            appIsActive: true,
            appIsFrontmost: true
        )

        XCTAssertTrue(LaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
            silentLaunchEnabled: true,
            context: context
        ))
    }

    func testLaunchPresentationPolicyShowsWindowWhenSilentLaunchIsDisabled() {
        let context = LaunchPresentationPolicy.Context(
            isBackgroundRequest: false,
            appIsActive: false,
            appIsFrontmost: false
        )

        XCTAssertTrue(LaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
            silentLaunchEnabled: false,
            context: context
        ))
    }

    func testLaunchPresentationPolicyShowsWindowForExplicitUserOpen() {
        let context = LaunchPresentationPolicy.Context(
            isBackgroundRequest: false,
            isUserOpenRequest: true,
            appIsActive: false,
            appIsFrontmost: false
        )

        XCTAssertTrue(LaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
            silentLaunchEnabled: true,
            context: context
        ))
    }

    func testLaunchPresentationPolicyShowsWindowForPermissionRefreshRelaunch() {
        let context = LaunchPresentationPolicy.Context(
            isBackgroundRequest: false,
            isPermissionRefreshRequest: true,
            appIsActive: false,
            appIsFrontmost: false
        )

        XCTAssertTrue(LaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
            silentLaunchEnabled: true,
            context: context
        ))
    }

    func testPermissionRefreshRelaunchUsesRefreshAndForegroundArguments() {
        XCTAssertEqual(
            PermissionRefreshCoordinator.permissionRefreshRelaunchArguments,
            [LaunchPresentationPolicy.permissionRefreshArgument,
             LaunchPresentationPolicy.userOpenArgument]
        )
    }

    func testPermissionRefreshRelaunchDefersFinderRestartToNewProcess() {
        let relaunch = SystemCommandResult(
            executablePath: "/usr/bin/open",
            arguments: [],
            terminationStatus: 0
        )
        let outcome = PermissionRefreshCoordinator.ReloadOutcome(
            choice: .relaunchAppAndRestartFinder,
            relaunchResult: relaunch,
            restartFinderResult: nil
        )

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertNil(outcome.restartFinderResult)
    }

    func testPermissionRefreshCoordinatorPromptsOnlyOnFreshGrantTransition() {
        XCTAssertTrue(PermissionRefreshCoordinator.shouldPromptAfterGrant(
            previous: false,
            current: true,
            hasLoadedInitialState: true,
            didPrompt: false
        ))

        XCTAssertFalse(PermissionRefreshCoordinator.shouldPromptAfterGrant(
            previous: true,
            current: true,
            hasLoadedInitialState: true,
            didPrompt: false
        ))

        XCTAssertFalse(PermissionRefreshCoordinator.shouldPromptAfterGrant(
            previous: false,
            current: true,
            hasLoadedInitialState: false,
            didPrompt: false
        ))

        XCTAssertFalse(PermissionRefreshCoordinator.shouldPromptAfterGrant(
            previous: false,
            current: true,
            hasLoadedInitialState: true,
            didPrompt: true
        ))
    }

    func testPermissionRefreshCoordinatorOffersManualRelaunchFallbackWhenPermissionStillLooksDenied() {
        XCTAssertTrue(PermissionRefreshCoordinator.shouldOfferManualRelaunchFallback(currentFullDiskAccess: false))
        XCTAssertFalse(PermissionRefreshCoordinator.shouldOfferManualRelaunchFallback(currentFullDiskAccess: true))
    }

    func testSystemCommandResultUsesTerminationStatusForSuccess() {
        let success = SystemCommandResult(
            executablePath: "/usr/bin/true",
            arguments: [],
            terminationStatus: 0,
            standardOutput: "",
            standardError: "",
            errorDescription: nil
        )
        let failedExit = SystemCommandResult(
            executablePath: "/usr/bin/false",
            arguments: [],
            terminationStatus: 1,
            standardOutput: "",
            standardError: "",
            errorDescription: nil
        )
        let launchFailure = SystemCommandResult(
            executablePath: "/missing",
            arguments: [],
            terminationStatus: nil,
            standardOutput: "",
            standardError: "",
            errorDescription: "No such file"
        )

        XCTAssertTrue(success.isSuccess)
        XCTAssertFalse(failedExit.isSuccess)
        XCTAssertFalse(launchFailure.isSuccess)
    }

    func testSystemReloaderCapturesLargeCommandOutputWithoutBlocking() {
        let result = SystemReloader.runCommand(
            executablePath: "/bin/sh",
            arguments: ["-c", "/usr/bin/yes x | /usr/bin/head -c 200000"]
        )

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.standardOutput.count, 200_000)
    }

    func testSystemReloaderTimesOutLongRunningCommand() {
        let startedAt = Date()
        let result = SystemReloader.runCommand(
            executablePath: "/bin/sleep",
            arguments: ["2"],
            timeoutSeconds: 0.1
        )

        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errorDescription?.contains("超时") == true)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1.5)
    }

    func testPluginkitParserDetectsExtensionRegistrationStates() {
        let bundleId = "guyue.RightClickAssistant.Extension"

        XCTAssertEqual(
            FinderExtensionDiagnostics.registrationState(
                pluginKitOutput: "",
                commandSucceeded: true,
                bundleIdentifier: bundleId
            ),
            .notRegistered
        )
        XCTAssertEqual(
            FinderExtensionDiagnostics.registrationState(
                pluginKitOutput: "+    guyue.RightClickAssistant.Extension(1.1.1)",
                commandSucceeded: true,
                bundleIdentifier: bundleId
            ),
            .enabled
        )
        XCTAssertEqual(
            FinderExtensionDiagnostics.registrationState(
                pluginKitOutput: "     guyue.RightClickAssistant.Extension(1.1.1)",
                commandSucceeded: true,
                bundleIdentifier: bundleId
            ),
            .registeredButNotEnabled
        )
        XCTAssertEqual(
            FinderExtensionDiagnostics.registrationState(
                pluginKitOutput: "",
                commandSucceeded: false,
                bundleIdentifier: bundleId
            ),
            .unknown
        )
    }

    func testHealthSnapshotRecommendsRepairActionsByPriority() {
        let denied = FinderExtensionDiagnostics.makeSnapshot(
            fullDiskAccessGranted: false,
            finderSyncControllerEnabled: true,
            pluginKitState: .enabled,
            watchScope: .everywhere,
            observedPathCount: 4,
            pendingActionCount: 0,
            failedActionCount: 0
        )
        let unregistered = FinderExtensionDiagnostics.makeSnapshot(
            fullDiskAccessGranted: true,
            finderSyncControllerEnabled: false,
            pluginKitState: .notRegistered,
            watchScope: .everywhere,
            observedPathCount: 4,
            pendingActionCount: 0,
            failedActionCount: 0
        )
        let needsFinderRestart = FinderExtensionDiagnostics.makeSnapshot(
            fullDiskAccessGranted: true,
            finderSyncControllerEnabled: false,
            pluginKitState: .enabled,
            watchScope: .everywhere,
            observedPathCount: 4,
            pendingActionCount: 0,
            failedActionCount: 0
        )
        let healthy = FinderExtensionDiagnostics.makeSnapshot(
            fullDiskAccessGranted: true,
            finderSyncControllerEnabled: true,
            pluginKitState: .enabled,
            watchScope: .everywhere,
            observedPathCount: 4,
            pendingActionCount: 0,
            failedActionCount: 0
        )

        XCTAssertEqual(denied.recommendedRepairAction, .openFullDiskAccessSettings)
        XCTAssertEqual(unregistered.recommendedRepairAction, .registerExtension)
        XCTAssertEqual(needsFinderRestart.recommendedRepairAction, .restartFinder)
        XCTAssertEqual(healthy.recommendedRepairAction, .none)
    }

    func testHealthSnapshotPrioritizesMenuExtensionRepairBeforeFullDiskAccess() {
        let unregisteredAndDenied = FinderExtensionDiagnostics.makeSnapshot(
            fullDiskAccessGranted: false,
            finderSyncControllerEnabled: false,
            pluginKitState: .notRegistered,
            watchScope: .everywhere,
            observedPathCount: 4,
            pendingActionCount: 0,
            failedActionCount: 0
        )
        let enabledButNeedsFinderRestartAndDenied = FinderExtensionDiagnostics.makeSnapshot(
            fullDiskAccessGranted: false,
            finderSyncControllerEnabled: false,
            pluginKitState: .enabled,
            watchScope: .everywhere,
            observedPathCount: 4,
            pendingActionCount: 0,
            failedActionCount: 0
        )

        XCTAssertEqual(unregisteredAndDenied.recommendedRepairAction, .registerExtension)
        XCTAssertEqual(enabledButNeedsFinderRestartAndDenied.recommendedRepairAction, .restartFinder)
    }

    func testFDAIsWarningWhenFinderMenuIsHealthy() {
        let snapshot = FinderExtensionDiagnostics.makeSnapshot(
            fullDiskAccessGranted: false,
            finderSyncControllerEnabled: true,
            pluginKitState: .enabled,
            heartbeatState: .recent(observedPathCount: 7),
            watchScope: .everywhere,
            pendingActionCount: 0,
            oldestPendingAge: nil,
            failedActionCount: 0
        )

        XCTAssertEqual(snapshot.healthLevel, .warning)
        XCTAssertEqual(snapshot.menuServiceLevel, .healthy)
        XCTAssertEqual(snapshot.recommendedRepairAction, .openFullDiskAccessSettings)
    }

    func testMissingHeartbeatMakesMenuUnverified() {
        let snapshot = FinderExtensionDiagnostics.makeSnapshot(
            fullDiskAccessGranted: true,
            finderSyncControllerEnabled: true,
            pluginKitState: .enabled,
            heartbeatState: .missing,
            watchScope: .everywhere,
            pendingActionCount: 0,
            oldestPendingAge: nil,
            failedActionCount: 0
        )

        XCTAssertEqual(snapshot.menuServiceLevel, .unverified)
        XCTAssertEqual(snapshot.healthLevel, .warning)
        XCTAssertEqual(snapshot.recommendedRepairAction, .restartFinder)
    }

    func testDiagnosticSummaryContainsNoUserPaths() {
        let snapshot = FinderExtensionDiagnostics.makeSnapshot(
            fullDiskAccessGranted: true,
            finderSyncControllerEnabled: true,
            pluginKitState: .enabled,
            heartbeatState: .recent(observedPathCount: 7),
            watchScope: .custom,
            pendingActionCount: 2,
            oldestPendingAge: 12,
            failedActionCount: 1
        )

        let summary = snapshot.diagnosticSummary(appVersion: "1.2.0")

        XCTAssertFalse(summary.contains("/Users/"))
        XCTAssertTrue(summary.contains("Pending: 2"))
        XCTAssertTrue(summary.contains("App Version: 1.2.0"))
    }

    func testExtensionHeartbeatStoreThrottlesWritesAndDetectsStaleState() throws {
        let heartbeatURL = tempDirectory.appendingPathComponent("heartbeat.json")
        let store = ExtensionHeartbeatStore(
            fileURL: heartbeatURL,
            minimumWriteInterval: 60,
            freshnessInterval: 120
        )
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(store.write(
            observedPathCount: 7,
            version: "1.2.0",
            processID: 42,
            at: start
        ))
        XCTAssertFalse(store.write(
            observedPathCount: 9,
            version: "1.2.0",
            processID: 42,
            at: start.addingTimeInterval(30)
        ))
        XCTAssertEqual(
            store.state(at: start.addingTimeInterval(90)),
            .recent(observedPathCount: 7)
        )
        XCTAssertEqual(store.state(at: start.addingTimeInterval(121)), .stale)
    }

    func testOldestPendingActionAgeUsesEventCreationTime() throws {
        let oldEvent = SharedActionEvent(
            id: "old",
            createdAt: 900,
            actionId: "test.old",
            paths: ["/tmp/old"]
        )
        let newEvent = SharedActionEvent(
            id: "new",
            createdAt: 980,
            actionId: "test.new",
            paths: ["/tmp/new"]
        )
        try JSONEncoder().encode(oldEvent).write(
            to: storage.pendingActionsDirectoryURL.appendingPathComponent("old.json")
        )
        try JSONEncoder().encode(newEvent).write(
            to: storage.pendingActionsDirectoryURL.appendingPathComponent("new.json")
        )

        let age = try XCTUnwrap(
            storage.oldestPendingActionAge(at: Date(timeIntervalSince1970: 1_000))
        )
        XCTAssertEqual(age, 100, accuracy: 0.001)
    }

    func testExternalToolManagerFindsHomebrewPathInPriorityOrder() {
        let path = ExternalToolManager.homebrewExecutablePath { candidate in
            candidate == "/usr/local/bin/brew"
        }

        XCTAssertEqual(path, "/usr/local/bin/brew")
    }

    func testExternalToolManagerBuildsHomebrewCaskCommands() {
        let install = ExternalToolManager.command(
            for: .install,
            tool: .visualStudioCode,
            brewExecutablePath: "/opt/homebrew/bin/brew"
        )
        let update = ExternalToolManager.command(
            for: .update,
            tool: .iterm2,
            brewExecutablePath: "/opt/homebrew/bin/brew"
        )

        XCTAssertEqual(install.executablePath, "/opt/homebrew/bin/brew")
        XCTAssertEqual(install.arguments, ["install", "--cask", "visual-studio-code"])
        XCTAssertEqual(update.arguments, ["upgrade", "--cask", "iterm2"])
    }

    func testManagedExternalToolsMapToTerminalEditorApps() {
        XCTAssertEqual(ManagedExternalTool.iterm2.bundleIdentifier, TerminalEditorType.iterm2.bundleIdentifier)
        XCTAssertEqual(ManagedExternalTool.warp.bundleIdentifier, TerminalEditorType.warp.bundleIdentifier)
        XCTAssertEqual(ManagedExternalTool.visualStudioCode.bundleIdentifier, TerminalEditorType.vscode.bundleIdentifier)
        XCTAssertEqual(ManagedExternalTool.sublimeText.bundleIdentifier, TerminalEditorType.sublime.bundleIdentifier)
        XCTAssertEqual(ManagedExternalTool.cursor.bundleIdentifier, TerminalEditorType.cursor.bundleIdentifier)
    }

    func testExternalToolOperationOutcomeReflectsCommandStatus() {
        let success = ExternalToolOperationOutcome(
            operation: .install,
            tool: .iterm2,
            commandResult: SystemCommandResult(
                executablePath: "/opt/homebrew/bin/brew",
                arguments: ["install", "--cask", "iterm2"],
                terminationStatus: 0
            )
        )
        let failure = ExternalToolOperationOutcome(
            operation: .update,
            tool: .warp,
            commandResult: SystemCommandResult(
                executablePath: "/opt/homebrew/bin/brew",
                arguments: ["upgrade", "--cask", "warp"],
                terminationStatus: 1,
                standardError: "Error"
            )
        )

        XCTAssertTrue(success.isSuccess)
        XCTAssertFalse(failure.isSuccess)
    }
}

private final class TestMenuAction: MenuAction {
    let actionId: String
    let localizedTitle: String
    let iconName: String? = nil
    let category: ActionCategory

    init(id: String, title: String, category: ActionCategory) {
        self.actionId = id
        self.localizedTitle = title
        self.category = category
    }

    func execute(targetURLs: [URL]) -> Bool {
        true
    }
}

private final class DispatchProbeAction: MenuAction {
    let actionId = "test.dispatch-probe.\(UUID().uuidString)"
    let localizedTitle = "Dispatch Probe"
    let iconName: String? = nil
    let category: ActionCategory = .utility
    let requiresExistingTargets: Bool
    private let availableInContainer: Bool?
    private(set) var didExecute = false

    init(
        availableInContainer: Bool? = nil,
        requiresExistingTargets: Bool = true
    ) {
        self.availableInContainer = availableInContainer
        self.requiresExistingTargets = requiresExistingTargets
    }

    func isAvailable(for targetURLs: [URL], isContainer: Bool) -> Bool {
        availableInContainer.map { $0 == isContainer } ?? true
    }

    func execute(targetURLs: [URL]) -> Bool {
        didExecute = true
        return true
    }
}
