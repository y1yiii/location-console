import Foundation

enum SetupStatus: String, Sendable {
    case passed, needsAction, pending
    var icon: String {
        switch self {
        case .passed: return "checkmark.circle.fill"
        case .needsAction: return "exclamationmark.circle.fill"
        case .pending: return "circle.dotted"
        }
    }
}

struct SetupCheck: Identifiable, Sendable {
    let id: String
    let title: String
    let status: SetupStatus
    let detail: String
}

struct SetupReport: Sendable {
    let xcodePath: String
    let xcodeVersion: String
    let checkedAt: Date
    let checks: [SetupCheck]
    func passed(_ id: String) -> Bool { checks.first { $0.id == id }?.status == .passed }
    var supportsCoordinates: Bool { ["host", "xcode", "firstLaunch", "coordinate", "clear"].allSatisfy(passed) }
    var supportsRoutes: Bool { supportsCoordinates && passed("route") }
}

enum SetupEnvironment {
    static func inspect(xcode: String) async throws -> SetupReport {
        var checks: [SetupCheck] = []
        #if arch(arm64)
        let silicon = true
        let architectureLabel = "Apple Silicon"
        #else
        let silicon = false
        let architectureLabel = "非 Apple Silicon"
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let hostReady = silicon && os.majorVersion >= 14
        checks.append(SetupCheck(id: "host", title: "Mac 与系统", status: hostReady ? .passed : .needsAction,
                                 detail: "\(architectureLabel) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)\(hostReady ? "。Xcode 仍需支持此系统。" : "。当前发布包面向 Apple Silicon，应用最低加载版本为 macOS 14。")"))
        let directory: String
        do { directory = try DeviceService.developerDirectory(xcode) }
        catch {
            checks.append(SetupCheck(id: "xcode", title: "完整 Xcode", status: .needsAction,
                                     detail: "未找到完整 Xcode。请先安装并打开 Xcode，或点击「选择 Xcode」指定已安装的位置。"))
            for (id, title) in [("firstLaunch", "Xcode 首次初始化"), ("coordinate", "固定定位接口"), ("route", "路线回放接口"), ("clear", "清除模拟接口")] {
                checks.append(SetupCheck(id: id, title: title, status: .pending, detail: "找到 Xcode 后才能检查。"))
            }
            return SetupReport(xcodePath: xcode, xcodeVersion: "未找到", checkedAt: Date(), checks: checks)
        }
        let environment = ["DEVELOPER_DIR": directory]
        var version = "版本未确认"
        do {
            let result = try await ProcessRunner.run(executable: "/usr/bin/xcodebuild", arguments: ["-version"], environment: environment, timeout: 8)
            version = String(result.output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            checks.append(SetupCheck(id: "xcode", title: "完整 Xcode", status: .passed, detail: version.replacingOccurrences(of: "\n", with: " · ")))
        } catch is CancellationError { throw CancellationError() }
        catch {
            checks.append(SetupCheck(id: "xcode", title: "完整 Xcode", status: .needsAction,
                                     detail: "已找到 Xcode，但无法读取版本。请先打开 Xcode 完成初始化，再重新检查。"))
        }
        do {
            _ = try await ProcessRunner.run(executable: "/usr/bin/xcodebuild", arguments: ["-checkFirstLaunchStatus"], environment: environment, timeout: 12)
            checks.append(SetupCheck(id: "firstLaunch", title: "Xcode 首次初始化", status: .passed, detail: "Xcode 报告首次初始化已完成。此检查不会接受许可或安装组件。"))
        } catch is CancellationError { throw CancellationError() }
        catch {
            checks.append(SetupCheck(id: "firstLaunch", title: "Xcode 首次初始化", status: .needsAction,
                                     detail: "Xcode 尚未准备好或状态无法读取。点击「打开 Xcode」，按其提示完成许可及组件安装，再检查。"))
        }
        for (kind, title, tokens) in [
            ("coordinate", "固定定位接口", ["--latitude", "--longitude"]),
            ("route", "路线回放接口", ["--route-file", "--speed"]),
            ("clear", "清除模拟接口", ["simulate location clear"])
        ] {
            try Task.checkCancellation()
            do {
                let result = try await ProcessRunner.run(executable: "/usr/bin/xcrun", arguments: ["devicectl", "device", "simulate", "location", kind, "--help"], environment: environment, timeout: 8)
                let supported = tokens.allSatisfy { result.output.contains($0) }
                checks.append(SetupCheck(id: kind, title: title, status: supported ? .passed : .needsAction,
                                         detail: supported ? "当前 Xcode 提供此接口。这里只读取帮助信息，不改变手机位置。" : "当前 Xcode 的接口格式不符合本软件要求。请换用支持此功能的 Xcode，再重新检查。"))
            } catch is CancellationError { throw CancellationError() }
            catch {
                checks.append(SetupCheck(id: kind, title: title, status: .needsAction,
                                         detail: "当前 Xcode 未能提供此接口。请完成 Xcode 初始化，或换用支持此功能的版本。"))
            }
        }
        return SetupReport(xcodePath: xcode, xcodeVersion: version, checkedAt: Date(), checks: checks)
    }
}
