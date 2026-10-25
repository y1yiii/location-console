import Foundation
import Darwin

struct ToolFailure: LocalizedError {
    let status: Int32
    let output: String
    var errorDescription: String? { "工具退出码 \(status)：\n\(output)" }
}

struct ToolTimeout: LocalizedError {
    var errorDescription: String? { "工具响应超时，请检查 Xcode 是否已完成首次初始化。" }
}

enum ProcessRunner {
    static func run(executable: String, arguments: [String], environment: [String: String] = [:],
                    timeout: Int, deviceJSON: Bool = false) async throws -> CommandResult {
        let command = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try DeviceService.prepareDirectory()
            let job = DeviceService.support.appendingPathComponent("Command-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: job) }
            let output = job.appendingPathComponent("console.txt")
            let json = job.appendingPathComponent("result.json")
            FileManager.default.createFile(atPath: output.path, contents: nil)
            let handle = try FileHandle(forWritingTo: output)
            defer { try? handle.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments + (deviceJSON ? ["--timeout", String(timeout), "--json-output", json.path] : [])
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            process.standardOutput = handle
            process.standardError = handle
            process.standardInput = FileHandle.nullDevice
            try process.run()
            defer {
                if process.isRunning {
                    process.terminate()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
            }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(timeout + 4))
            while process.isRunning && clock.now < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
            try Task.checkCancellation()
            if process.isRunning {
                process.terminate()
                let stopDeadline = clock.now.advanced(by: .seconds(2))
                while process.isRunning && clock.now < stopDeadline { try await Task.sleep(nanoseconds: 100_000_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                throw ToolTimeout()
            }
            // isRunning == false permits reading terminationStatus. Avoid
            // waitUntilExit: it previously blocked on a worker's run loop.
            let text = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
            guard process.terminationStatus == 0 else {
                throw ToolFailure(status: process.terminationStatus, output: String(text.suffix(5000)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return CommandResult(data: deviceJSON ? (try? Data(contentsOf: json)) : nil, output: text)
        }
        return try await withTaskCancellationHandler(operation: { try await command.value }, onCancel: { command.cancel() })
    }
}
