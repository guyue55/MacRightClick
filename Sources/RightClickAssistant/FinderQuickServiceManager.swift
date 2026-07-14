import AppKit
import CoreServices
import Foundation

/// 把运行时依赖收口为一个解析入口，动态清单和服务授权始终使用同一份当前状态。
enum FinderQuickActionRuntime {
    static func currentItems() -> [FinderServiceActionItem] {
        let storage = SharedStorageManager.shared
        return FinderQuickActionPolicy.resolveDirectItems(
            actions: ActionDispatcher.shared.allActions,
            favoriteActionIDs: storage.favoriteActionIds,
            isEnabled: { storage.isActionEnabled($0) },
            isExternalAppAvailable: { InstalledAppRegistry.shared.isInstalled($0) }
        )
    }
}

/// 维护 ~/Library/Services 中的轻量快捷服务清单。
/// 动作计算在主线程完成，文件 I/O 串行下沉；内容未变化时不会刷新系统服务。
@MainActor
final class FinderQuickServiceManager {
    static let shared = FinderQuickServiceManager()

    private let ioQueue = DispatchQueue(
        label: "guyue.RightClickAssistant.quick-services",
        qos: .utility
    )
    private let store: FinderQuickServiceBundleStore
    private lazy var helperExecutableData: Data? = {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        return try? Data(
            contentsOf: resourceURL.appendingPathComponent(
                FinderQuickServiceProtocol.executableName
            )
        )
    }()
    private var observer: NSObjectProtocol?
    private var pendingRefresh: DispatchWorkItem?

    private init() {
        let libraryDirectory = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        store = FinderQuickServiceBundleStore(
            servicesDirectoryURL: libraryDirectory.appendingPathComponent("Services", isDirectory: true)
        )
    }

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: SystemReloader.configChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleRefresh()
            }
        }
        scheduleRefresh(delay: 0)
    }

    func stop() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
    }

    func scheduleRefresh(delay: TimeInterval = 0.3) {
        pendingRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        pendingRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func refresh() {
        pendingRefresh = nil
        let items = FinderQuickActionRuntime.currentItems()
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0.0"
        do {
            let data = items.isEmpty
                ? nil
                : try FinderQuickServiceManifest.encodedData(items: items, appVersion: version)
            if data != nil, helperExecutableData == nil {
                AppLog.error("Finder 快捷服务 helper 缺失，保留静态动作面板入口", category: .host)
                return
            }
            synchronize(data, executableData: helperExecutableData)
        } catch {
            AppLog.error("生成 Finder 快捷服务失败：\(error.localizedDescription)", category: .host)
        }
    }

    private func synchronize(_ manifestData: Data?, executableData: Data?) {
        let store = self.store
        ioQueue.async {
            do {
                let didChange = try store.synchronize(
                    manifestData: manifestData,
                    executableData: executableData
                )
                if manifestData != nil {
                    let registrationStatus = LSRegisterURL(store.bundleURL as CFURL, true)
                    guard registrationStatus == noErr else {
                        AppLog.error(
                            "注册 Finder 快捷服务失败，状态码：\(registrationStatus)",
                            category: .host
                        )
                        return
                    }
                }
                guard didChange else { return }
                DispatchQueue.main.async {
                    NSUpdateDynamicServices()
                    AppLog.info("Finder 快捷服务已刷新", category: .host)
                }
            } catch {
                AppLog.error("写入 Finder 快捷服务失败：\(error.localizedDescription)", category: .host)
            }
        }
    }
}
