import Foundation
import Darwin

struct Phone: Identifiable, Hashable {
    let id: String
    let name: String
    let model: String
    let version: String
    let connection: String
    let developerMode: String
    let paired: Bool
    var developerModeEnabled: Bool { developerMode == "已开启" }
    // CoreDevice's "disconnected" means discoverable but without an active
    // developer tunnel; devicectl presents it as "available (paired)".
    var available: Bool { ["connected", "available", "disconnected"].contains(connection.lowercased()) }
    var stateLabel: String { available ? "可连接" : (connection == "connecting" ? "正在连接" : "未连接") }
}

struct CommandResult: Sendable {
    let data: Data?
    let output: String
}

enum DeviceService {
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocationConsole", isDirectory: true)

    static func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
    }

    static func developerDirectory(_ path: String) throws -> String {
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        let dir = expanded.hasSuffix(".app") ? expanded + "/Contents/Developer" : expanded
        guard FileManager.default.fileExists(atPath: dir + "/usr/bin/devicectl") else {
            throw ConsoleError("找不到 Xcode 的 devicectl。请在帮助与设置中选择完整的 Xcode.app；命令行工具目录不能替代完整 Xcode。")
        }
        return dir
    }

    static func discoverXcode(preferred: String?) -> String {
        if let preferred, (try? developerDirectory(preferred)) != nil { return preferred }
        let standard = "/Applications/Xcode.app"
        if (try? developerDirectory(standard)) != nil { return standard }
        for parent in [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")] {
            let apps = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
            for app in apps.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where app.pathExtension == "app" && app.lastPathComponent.lowercased().contains("xcode") {
                if (try? developerDirectory(app.path)) != nil { return app.path }
            }
        }
        return preferred ?? standard
    }

    static func appURL(for path: String) -> URL {
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        return expanded.hasSuffix("/Contents/Developer") ? url.deletingLastPathComponent().deletingLastPathComponent() : url
    }

    static func run(_ arguments: [String], xcode: String, timeout: Int = 25) async throws -> CommandResult {
        let directory = try developerDirectory(xcode)
        do {
            return try await ProcessRunner.run(executable: "/usr/bin/xcrun", arguments: ["devicectl"] + arguments,
                                               environment: ["DEVELOPER_DIR": directory], timeout: timeout, deviceJSON: true)
        } catch let failure as ToolFailure {
            throw ConsoleError("Xcode 命令失败（\(failure.status)）。\n\(failure.output.isEmpty ? "请解锁手机、信任 Mac 并开启开发者模式；在环境检查页面查看准备步骤。" : failure.output)")
        } catch is ToolTimeout {
            throw ConsoleError("Xcode 命令超时，设备状态未确认。若刚才在启动模拟，请使用「停止并清除」后在手机上确认。")
        }
    }

    static func phones(from data: Data?) throws -> [Phone] {
        guard let data, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any], let devices = result["devices"] as? [[String: Any]] else {
            throw ConsoleError("Xcode 返回的设备列表格式无法识别，请查看日志。")
        }
        return devices.compactMap { item in
            let properties = item["properties"] as? [String: Any] ?? [:]
            let hardware = properties["hardware"] as? [String: Any] ?? item["hardwareProperties"] as? [String: Any] ?? [:]
            guard hardware["deviceType"] as? String == "iPhone" else { return nil }
            let state = properties["state"] as? [String: Any] ?? [:]
            let software = properties["software"] as? [String: Any] ?? [:]
            let old = item["deviceProperties"] as? [String: Any] ?? [:]
            let connection = properties["connection"] as? [String: Any] ?? item["connectionProperties"] as? [String: Any] ?? [:]
            let version = software["osVersionNumber"] as? [String: Any]
            let identifier = hardware["udid"] as? String ?? item["identifier"] as? String
            guard let identifier else { return nil }
            let mode = state["developerModeStatus"] as? [String: Any]
            let developer = mode?["enabled"] != nil || old["developerModeStatus"] as? String == "enabled"
            return Phone(id: identifier, name: state["name"] as? String ?? old["name"] as? String ?? "iPhone",
                         model: hardware["marketingName"] as? String ?? "iPhone",
                         version: version?["stringValue"] as? String ?? old["osVersionNumber"] as? String ?? "未知",
                         connection: connection["state"] as? String ?? connection["tunnelState"] as? String ?? "unknown",
                         developerMode: developer ? "已开启" : "未开启或未知", paired: connection["pairingState"] as? String == "paired")
        }.sorted { $0.available && !$1.available }
    }
}
