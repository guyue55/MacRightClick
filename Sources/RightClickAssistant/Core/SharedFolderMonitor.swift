import Foundation

/// 共享文件夹监控器，采用 BSD 内核的 kqueue (DispatchSourceFileSystemObject) 机制，
/// 监听共享动作队列目录，用于跨进程异步文件消费与调度触发。
/// 彻底解决 macOS 新版本对分布式通知 (DistributedNotificationCenter) 的后台挂起和安全黑盒拦截问题。
public final class SharedFolderMonitor {
    private let folderURL: URL
    private var monitorSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "guyue.RightClickAssistant.folder-monitor", qos: .userInteractive)
    
    public var onFolderChanged: (() -> Void)?
    
    public init(folderURL: URL) {
        self.folderURL = folderURL
    }
    
    /// 开启物理文件夹监听
    public func start() {
        guard monitorSource == nil else { return }
        
        let path = folderURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            SharedStorageManager.shared.writeLog("[SharedFolderMonitor] 错误: 无法打开文件夹描述符: \(path), errno: \(errno)")
            return
        }
        
        self.fileDescriptor = fd
        
        // 创建 DispatchSource 监听文件夹下的物理写入/删除/重命名等 write 事件
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: queue
        )
        
        source.setEventHandler { [weak self] in
            // 当内核回调事件发生时，异步分发
            self?.onFolderChanged?()
        }
        
        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        
        self.monitorSource = source
        source.resume()
        
        SharedStorageManager.shared.writeLog("[SharedFolderMonitor] 内核级物理文件夹监控服务成功启动，目标: \(path)")
    }
    
    /// 停止监听
    public func stop() {
        monitorSource?.cancel()
        monitorSource = nil
        SharedStorageManager.shared.writeLog("[SharedFolderMonitor] 物理文件夹监控服务已停止")
    }
    
    deinit {
        stop()
    }
}
