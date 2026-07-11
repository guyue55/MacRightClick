import XCTest
@testable import RightClickAssistantCore

/// 验证 PendingAction 消费的事务化（P1-2）：
/// 1. 拿到 lease 但没 ack（模拟崩溃）→ 重启后 reclaim 能把孤儿事件搬回 PendingActions；
/// 2. ack 后 InFlight 文件被清理，下一次启动 reclaim 不会复活已完成事件；
/// 3. lease.event 与原始 enqueue 内容一致。
final class SharedStorageManagerLeaseTests: XCTestCase {

    private var manager: SharedStorageManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let storage = try TestStorage.make()
        addTeardownBlock {
            try TestStorage.removeIfPresent(storage.root)
        }
        manager = storage.manager
    }

    func testInjectedStorageNeverUsesProductionContainer() throws {
        let storage = try TestStorage.make()
        addTeardownBlock {
            try TestStorage.removeIfPresent(storage.root)
        }

        XCTAssertEqual(
            storage.manager.sharedContainerURL.standardizedFileURL,
            storage.root.standardizedFileURL
        )
        XCTAssertFalse(storage.manager.sharedContainerURL.path.contains("/Library/Containers/"))
    }

    func testStorageRejectsSymlinkResolvingIntoContainersBeforeCreation() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RightClickAssistantUnsafePathTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let containersRoot = fixtureRoot
            .appendingPathComponent("Library/Containers", isDirectory: true)
        let linkedRoot = fixtureRoot.appendingPathComponent("linked-root", isDirectory: true)

        try FileManager.default.createDirectory(at: containersRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try TestStorage.removeIfPresent(fixtureRoot)
        }
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: containersRoot)

        XCTAssertThrowsError(
            try TestStorage.make(testCaseName: #function, baseDirectory: linkedRoot)
        ) { error in
            guard case TestStorageError.unsafeContainerPath(let resolvedURL) = error else {
                return XCTFail("应抛出 unsafeContainerPath，实际为 \(error)")
            }
            XCTAssertTrue(resolvedURL.path.contains("/Library/Containers/"))
        }
    }

    func testInjectedConfigurationBypassesAppGroupDefaults() throws {
        let storage = try TestStorage.make()
        addTeardownBlock {
            try TestStorage.removeIfPresent(storage.root)
        }

        let suiteName = "guyue.RightClickAssistantTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let boolKey = "isolated_bool"
        let arrayKey = "isolated_array"
        defaults.set(false, forKey: boolKey)
        defaults.set(["app-group"], forKey: arrayKey)

        let manager = SharedStorageManager(
            sharedContainerURLOverride: storage.root,
            usesAppGroup: true,
            sharedDefaults: defaults
        )

        manager.setBool(true, forKey: boolKey)
        manager.setStringArray(["temporary", "temporary"], forKey: arrayKey)
        manager.setActionEnabledStates([
            "test.injected.enabled": true,
            "test.injected.disabled": false
        ])

        XCTAssertTrue(manager.getBool(forKey: boolKey, defaultValue: false))
        XCTAssertEqual(manager.getStringArray(forKey: arrayKey), ["temporary"])
        XCTAssertTrue(manager.getBool(forKey: "enable_action_test.injected.enabled"))
        XCTAssertFalse(manager.getBool(forKey: "enable_action_test.injected.disabled"))
        XCTAssertFalse(defaults.bool(forKey: boolKey))
        XCTAssertEqual(defaults.stringArray(forKey: arrayKey), ["app-group"])
        XCTAssertNil(defaults.object(forKey: "enable_action_test.injected.enabled"))
        XCTAssertNil(defaults.object(forKey: "enable_action_test.injected.disabled"))

        let configData = try Data(contentsOf: manager.configURL)
        let config = try XCTUnwrap(
            JSONSerialization.jsonObject(with: configData) as? [String: Any]
        )
        XCTAssertEqual(config[boolKey] as? Bool, true)
        XCTAssertEqual(config[arrayKey] as? [String], ["temporary"])

        manager.removeValue(forKey: boolKey)
        manager.removeValue(forKey: arrayKey)

        XCTAssertTrue(manager.getBool(forKey: boolKey, defaultValue: true))
        XCTAssertEqual(manager.getStringArray(forKey: arrayKey, defaultValue: ["default"]), ["default"])
        XCTAssertFalse(defaults.bool(forKey: boolKey))
        XCTAssertEqual(defaults.stringArray(forKey: arrayKey), ["app-group"])
    }

    func testMASConfigurationMirrorsCanonicalConfigToInjectedDefaults() throws {
        let storage = try TestStorage.make()
        addTeardownBlock {
            try TestStorage.removeIfPresent(storage.root)
        }

        let suiteName = "guyue.RightClickAssistantTests.mas.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let manager = SharedStorageManager(
            sharedContainerURLOverride: storage.root,
            usesAppGroup: true,
            sharedDefaults: defaults,
            allowAppGroupDefaultsWithContainerOverride: true
        )

        XCTAssertTrue(manager.setBool(true, forKey: "mas_bool"))
        XCTAssertTrue(manager.setStringArray(["one", "two"], forKey: "mas_array"))
        XCTAssertTrue(manager.setActionEnabledStates(["mas.action": false]))

        XCTAssertTrue(defaults.bool(forKey: "mas_bool"))
        XCTAssertEqual(defaults.stringArray(forKey: "mas_array"), ["one", "two"])
        XCTAssertFalse(defaults.bool(forKey: "enable_action_mas.action"))

        // config.json 是权威值；即使旧偏好残留冲突值，读取也不能回退到旧状态。
        defaults.set(false, forKey: "mas_bool")
        XCTAssertTrue(manager.getBool(forKey: "mas_bool", defaultValue: false))
    }

    func testConfigurationWriteFailureIsReportedBeforeDefaultsAreMirrored() throws {
        let storage = try TestStorage.make()
        addTeardownBlock {
            try TestStorage.removeIfPresent(storage.root)
        }

        let suiteName = "guyue.RightClickAssistantTests.write-failure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(false, forKey: "write_failure")
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let manager = SharedStorageManager(
            sharedContainerURLOverride: storage.root,
            usesAppGroup: true,
            sharedDefaults: defaults,
            allowAppGroupDefaultsWithContainerOverride: true
        )
        try FileManager.default.createDirectory(at: manager.configURL, withIntermediateDirectories: true)

        XCTAssertFalse(manager.setBool(true, forKey: "write_failure"))
        XCTAssertFalse(defaults.bool(forKey: "write_failure"))
    }

    func testSetActionEnabledStatesWritesAllStatesInOneConfigurationMutation() throws {
        manager.setStringArray(["keep"], forKey: "unrelated")

        manager.setActionEnabledStates([
            "test.batch.enabled": true,
            "test.batch.disabled": false
        ])

        XCTAssertTrue(manager.getBool(forKey: "enable_action_test.batch.enabled"))
        XCTAssertFalse(manager.getBool(forKey: "enable_action_test.batch.disabled"))
        XCTAssertEqual(manager.getStringArray(forKey: "unrelated"), ["keep"])
    }

    func testApplyConfigurationChangesIsAtomicAndNewValuesWinOverRemoval() {
        manager.setBool(false, forKey: "replace_bool")
        manager.setStringArray(["old"], forKey: "replace_array")

        XCTAssertTrue(manager.applyConfigurationChanges(
            booleanValues: ["replace_bool": true],
            stringArrayValues: ["replace_array": ["new", "new"]],
            removingKeys: ["replace_bool", "replace_array", "removed_only"]
        ))

        XCTAssertTrue(manager.getBool(forKey: "replace_bool", defaultValue: false))
        XCTAssertEqual(manager.getStringArray(forKey: "replace_array"), ["new"])
        XCTAssertEqual(manager.getStringArray(forKey: "removed_only"), [])
    }

    func testConcurrentConfigurationMutationsPreserveIndependentKeys() throws {
        let storage = try TestStorage.make()
        addTeardownBlock {
            try TestStorage.removeIfPresent(storage.root)
        }

        let managerBox = TestSendableBox(storage.manager)
        let group = DispatchGroup()
        for index in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                managerBox.value.setBool(true, forKey: "parallel_\(index)")
                group.leave()
            }
        }
        group.wait()

        for index in 0..<100 {
            XCTAssertTrue(
                storage.manager.getBool(forKey: "parallel_\(index)", defaultValue: false)
            )
        }
    }

    func testLeaseRoundTripAndAckRemovesInFlight() throws {
        let url = try manager.enqueueAction(actionId: "test.lease.simple", paths: ["/tmp/a"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let leases = manager.consumePendingActionLeases()
        XCTAssertEqual(leases.count, 1)
        let lease = leases[0]
        XCTAssertEqual(lease.event.actionId, "test.lease.simple")
        XCTAssertEqual(lease.event.paths, ["/tmp/a"])

        // 拿到 lease 时：原 PendingActions 文件已搬到 InFlight。
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNotNil(lease.inFlightURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lease.inFlightURL!.path))

        manager.acknowledge(lease)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lease.inFlightURL!.path))
    }

    func testReclaimAbandonedInFlightRestoresOrphans() throws {
        // 模拟「上一次进程崩在 dispatcher 中」：往别的进程实例 owner 写孤儿文件。
        let bogusPID = 99999
        let bogusDir = manager.inFlightActionsDirectoryURL
            .appendingPathComponent("\(bogusPID)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: bogusDir, withIntermediateDirectories: true)

        let event = SharedActionEvent(
            id: UUID().uuidString,
            createdAt: Date().timeIntervalSince1970,
            actionId: "test.lease.crash",
            paths: ["/tmp/b"]
        )
        let data = try JSONEncoder().encode(event)
        let orphanURL = bogusDir.appendingPathComponent("\(Int64(event.createdAt*1000))-\(event.id).json")
        try data.write(to: orphanURL)

        // reclaim 应当把已确认死亡 owner 的孤儿搬回 PendingActions。
        manager.reclaimAbandonedInFlightActions(processIsAlive: { _ in false })

        let recovered = manager.consumePendingActionLeases()
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].event.actionId, "test.lease.crash")
        manager.acknowledge(recovered[0])

        // bogus PID 子目录被清理。
        XCTAssertFalse(FileManager.default.fileExists(atPath: bogusDir.path))
    }

    func testReclaimSkipsInFlightDirectoryOwnedByLiveProcess() throws {
        let livePID: Int32 = 4242
        let liveDirectory = manager.inFlightActionsDirectoryURL
            .appendingPathComponent("\(livePID)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: liveDirectory, withIntermediateDirectories: true)
        let event = SharedActionEvent(
            id: UUID().uuidString,
            createdAt: Date().timeIntervalSince1970,
            actionId: "test.live-owner",
            paths: ["/tmp/live-owner"]
        )
        let eventURL = liveDirectory.appendingPathComponent("live.json")
        try JSONEncoder().encode(event).write(to: eventURL)

        manager.reclaimAbandonedInFlightActions(processIsAlive: { $0 == livePID })

        XCTAssertTrue(FileManager.default.fileExists(atPath: eventURL.path))
    }

    func testReclaimSkipsCurrentProcessEvenWhenLivenessCheckReturnsFalse() throws {
        _ = try manager.enqueueAction(actionId: "test.current-owner", paths: ["/tmp/current"])
        let lease = try XCTUnwrap(manager.consumePendingActionLeases().first)
        let eventURL = try XCTUnwrap(lease.inFlightURL)

        manager.reclaimAbandonedInFlightActions(processIsAlive: { _ in false })

        XCTAssertTrue(FileManager.default.fileExists(atPath: eventURL.path))
        manager.acknowledge(lease)
    }

    func testReclaimRestoresStaleDirectoryAfterPIDReuse() throws {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let staleDirectory = manager.inFlightActionsDirectoryURL
            .appendingPathComponent("\(currentPID)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staleDirectory, withIntermediateDirectories: true)

        let event = SharedActionEvent(
            id: UUID().uuidString,
            createdAt: Date().timeIntervalSince1970,
            actionId: "test.reused-pid",
            paths: ["/tmp/reused-pid"]
        )
        let eventURL = staleDirectory.appendingPathComponent("stale.json")
        try JSONEncoder().encode(event).write(to: eventURL)

        manager.reclaimAbandonedInFlightActions(processIsAlive: { _ in true })

        XCTAssertFalse(FileManager.default.fileExists(atPath: eventURL.path))
        let recovered = manager.consumePendingActionLeases()
        XCTAssertEqual(recovered.map(\.event.actionId), ["test.reused-pid"])
        recovered.forEach { manager.acknowledge($0) }
    }

    func testReclaimIgnoresNonNumericAndInvalidPIDDirectories() throws {
        let ownerNames = [
            "not-a-pid",
            "+1",
            "0",
            "-1",
            "999999999999999999999",
            "4242-garbage",
            "4242-"
        ]
        let eventURLs = try ownerNames.map { ownerName in
            let directory = manager.inFlightActionsDirectoryURL
                .appendingPathComponent(ownerName, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let eventURL = directory.appendingPathComponent("ignored.json")
            try Data("ignored".utf8).write(to: eventURL)
            return eventURL
        }

        manager.reclaimAbandonedInFlightActions(processIsAlive: { _ in false })

        for eventURL in eventURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: eventURL.path))
        }
    }

    func testReclaimPreservesLegacyPIDOwnerForManualRecovery() throws {
        let legacyDirectory = manager.inFlightActionsDirectoryURL
            .appendingPathComponent("54321", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let eventURL = legacyDirectory.appendingPathComponent("legacy.json")
        try Data("legacy".utf8).write(to: eventURL)

        manager.reclaimAbandonedInFlightActions(processIsAlive: { _ in false })

        XCTAssertTrue(FileManager.default.fileExists(atPath: eventURL.path))
    }

    func testClearFailedActionsRemovesContentsButPreservesDirectory() throws {
        let failedDirectory = manager.failedActionsDirectoryURL
        try Data("failed".utf8).write(to: failedDirectory.appendingPathComponent("failed.json"))
        let nestedDirectory = failedDirectory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try Data("details".utf8).write(to: nestedDirectory.appendingPathComponent("details.txt"))

        try manager.clearFailedActions()

        XCTAssertTrue(FileManager.default.fileExists(atPath: failedDirectory.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: failedDirectory.path), [])
    }

    func testClearFailedActionsPropagatesRemovalErrors() throws {
        let failedDirectory = manager.failedActionsDirectoryURL
        try Data("failed".utf8).write(to: failedDirectory.appendingPathComponent("failed.json"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: failedDirectory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: failedDirectory.path
            )
        }

        XCTAssertThrowsError(try manager.clearFailedActions())
    }

    func testAckPreventsReclaim() throws {
        // 正常 ack 后，reclaim 不应复活已确认的事件。
        let url = try manager.enqueueAction(actionId: "test.lease.normal", paths: ["/tmp/c"])
        let leases = manager.consumePendingActionLeases()
        XCTAssertEqual(leases.count, 1)
        XCTAssertNotNil(leases[0].inFlightURL)
        manager.acknowledge(leases[0])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: leases[0].inFlightURL!.path))

        manager.reclaimAbandonedInFlightActions()
        let again = manager.consumePendingActionLeases()
        XCTAssertEqual(again.count, 0, "已 ack 的事件不应被 reclaim 复活")
    }
}
