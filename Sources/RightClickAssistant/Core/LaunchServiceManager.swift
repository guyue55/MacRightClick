import Foundation
import ServiceManagement

/// 现代 macOS 系统级自启动管理服务 (LaunchServiceManager)
/// 采用 macOS 13.0 (Ventura) 引入的现代 SMAppService API，
/// 使用系统“登录项”能力注册或注销开机自启。
public final class LaunchServiceManager {
    public static let shared = LaunchServiceManager()
    
    private init() {}
    
    /// 获取当前自启动在系统中的真实注册状态
    public var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            return status == .enabled
        }
        return false
    }
    
    /// 注册或注销开机自启动
    /// - Parameter enabled: true 为注册自启，false 为注销自启
    /// - Returns: 操作是否成功
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled {
                    if service.status != .enabled {
                        try service.register()
                        SharedStorageManager.shared.writeLog("[LaunchService] 成功向 macOS 注册 SMAppService 开机自启动")
                    }
                } else {
                    if service.status == .enabled {
                        try service.unregister()
                        SharedStorageManager.shared.writeLog("[LaunchService] 成功向 macOS 注销 SMAppService 开机自启动")
                    }
                }
                return true
            } catch {
                SharedStorageManager.shared.writeLog("[LaunchService] 注册或注销自启动失败: \(error.localizedDescription)")
                return false
            }
        } else {
            SharedStorageManager.shared.writeLog("[LaunchService] 当前 macOS 系统版本低于 13.0，无法使用 SMAppService 自启动注册")
            return false
        }
    }
}
