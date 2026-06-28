import Darwin
import Foundation

public struct SystemCommandResult: Equatable {
    public let executablePath: String
    public let arguments: [String]
    public let terminationStatus: Int32?
    public let standardOutput: String
    public let standardError: String
    public let errorDescription: String?

    public var isSuccess: Bool {
        errorDescription == nil && terminationStatus == 0
    }

    public init(
        executablePath: String,
        arguments: [String],
        terminationStatus: Int32?,
        standardOutput: String = "",
        standardError: String = "",
        errorDescription: String? = nil
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.errorDescription = errorDescription
    }
}

public struct FinderExtensionRegistrationOutcome: Equatable {
    public let announceResult: SystemCommandResult?
    public let enableResult: SystemCommandResult?
    public let restartFinderResult: SystemCommandResult?
    public let errorDescription: String?

    public var isSuccess: Bool {
        errorDescription == nil
            && announceResult?.isSuccess == true
            && enableResult?.isSuccess == true
            && restartFinderResult?.isSuccess == true
    }
}

private final class CommandOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    var snapshot: Data {
        lock.lock()
        let current = data
        lock.unlock()
        return current
    }
}

/// Centralizes system-level reload operations used after FinderSync or
/// permission changes. Keeping Process calls here avoids slightly different
/// restart behavior being duplicated across settings, diagnostics and actions.
public enum SystemReloader {
    public static let configChangedNotification = Notification.Name("guyue.RightClickAssistant.configChanged")
    public static let finderExtensionBundleIdentifier = "guyue.RightClickAssistant.Extension"

    public static func postConfigChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            configChangedNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    @discardableResult
    public static func restartFinder() -> SystemCommandResult {
        runCommand(executablePath: "/usr/bin/killall", arguments: ["Finder"])
    }

    @discardableResult
    public static func relaunchApp(bundleURL: URL, arguments: [String]) -> SystemCommandResult {
        runCommand(executablePath: "/usr/bin/open", arguments: ["-n", bundleURL.path, "--args"] + arguments)
    }

    public static func queryFinderExtension(
        bundleIdentifier: String = finderExtensionBundleIdentifier
    ) -> SystemCommandResult {
        runCommand(executablePath: "/usr/bin/pluginkit", arguments: ["-m", "-i", bundleIdentifier])
    }

    @discardableResult
    public static func registerFinderExtension(
        appBundleURL: URL,
        extensionBundleIdentifier: String = finderExtensionBundleIdentifier
    ) -> FinderExtensionRegistrationOutcome {
        let extensionURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("PlugIns", isDirectory: true)
            .appendingPathComponent("RightClickAssistantExtension.appex", isDirectory: true)

        guard FileManager.default.fileExists(atPath: extensionURL.path) else {
            return FinderExtensionRegistrationOutcome(
                announceResult: nil,
                enableResult: nil,
                restartFinderResult: nil,
                errorDescription: "未找到扩展组件"
            )
        }

        let announce = runCommand(executablePath: "/usr/bin/pluginkit", arguments: ["-a", extensionURL.path])
        guard announce.isSuccess else {
            return FinderExtensionRegistrationOutcome(
                announceResult: announce,
                enableResult: nil,
                restartFinderResult: nil,
                errorDescription: announce.errorDescription ?? "pluginkit 注册返回码: \(announce.terminationStatus.map { String($0) } ?? "unknown")"
            )
        }

        let enable = runCommand(
            executablePath: "/usr/bin/pluginkit",
            arguments: ["-e", "use", "-i", extensionBundleIdentifier]
        )
        guard enable.isSuccess else {
            return FinderExtensionRegistrationOutcome(
                announceResult: announce,
                enableResult: enable,
                restartFinderResult: nil,
                errorDescription: enable.errorDescription ?? "pluginkit 启用返回码: \(enable.terminationStatus.map { String($0) } ?? "unknown")"
            )
        }

        postConfigChanged()
        let restart = restartFinder()
        return FinderExtensionRegistrationOutcome(
            announceResult: announce,
            enableResult: enable,
            restartFinderResult: restart,
            errorDescription: restart.isSuccess
                ? nil
                : restart.errorDescription ?? "Finder 重启返回码: \(restart.terminationStatus.map { String($0) } ?? "unknown")"
        )
    }

    public static func runCommand(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval = 10
    ) -> SystemCommandResult {
        let proc = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputBuffer = CommandOutputBuffer()
        let errorBuffer = CommandOutputBuffer()
        let readGroup = DispatchGroup()
        let terminationSemaphore = DispatchSemaphore(value: 0)

        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = arguments
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe
        proc.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        do {
            try proc.run()

            readGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                outputBuffer.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
                readGroup.leave()
            }

            readGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                errorBuffer.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
                readGroup.leave()
            }

            let waitResult = terminationSemaphore.wait(timeout: .now() + timeoutSeconds)
            let timedOut = waitResult == .timedOut
            if timedOut {
                if proc.isRunning {
                    proc.terminate()
                }
                if terminationSemaphore.wait(timeout: .now() + 1) == .timedOut, proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                    _ = terminationSemaphore.wait(timeout: .now() + 1)
                }
            }

            _ = readGroup.wait(timeout: .now() + 1)

            let output = String(data: outputBuffer.snapshot, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorBuffer.snapshot, encoding: .utf8) ?? ""
            let errorDescription = timedOut
                ? "命令超时（\(String(format: "%.1f", timeoutSeconds)) 秒）"
                : nil

            let result = SystemCommandResult(
                executablePath: executablePath,
                arguments: arguments,
                terminationStatus: proc.terminationStatus,
                standardOutput: output,
                standardError: errorOutput,
                errorDescription: errorDescription
            )
            if !result.isSuccess {
                AppLog.error(
                    "系统命令失败: \(executablePath) \(arguments.joined(separator: " ")), status=\(proc.terminationStatus), error=\(errorDescription ?? ""), stderr=\(errorOutput)",
                    category: .ui
                )
            }
            return result
        } catch {
            AppLog.error("无法执行系统命令 \(executablePath): \(error.localizedDescription)", category: .ui)
            return SystemCommandResult(
                executablePath: executablePath,
                arguments: arguments,
                terminationStatus: nil,
                standardOutput: "",
                standardError: "",
                errorDescription: error.localizedDescription
            )
        }
    }
}
