import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Page: String, CaseIterable, Identifiable {
    case home = "控制台", setup = "环境检查", coordinate = "固定定位", route = "路线回放", logs = "运行日志", help = "帮助与设置"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .setup: return "checklist"
        case .coordinate: return "mappin.and.ellipse"
        case .route: return "point.topleft.down.to.point.bottomright.curvepath"
        case .logs: return "text.alignleft"
        case .help: return "gearshape"
        }
    }
}

struct Simulation: Codable {
    let deviceID: String
    let deviceName: String
    let kind: String
    let title: String
    let started: Date
    let duration: Double?
    let routePath: String?
}

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var page: Page? = .home
    @Published var phones: [Phone] = []
    @Published var selectedID = ""
    @Published var busy = false
    @Published var isRefreshing = false
    @Published var isCheckingEnvironment = false
    @Published var environmentReport: SetupReport?
    @Published var deviceSnapshotFresh = false
    @Published var refreshCooldown = false
    @Published var operation = ""
    @Published var error: String?
    @Published var notice = "连接 iPhone 后，刷新设备即可开始。"
    @Published var route: Route?
    @Published var savedRoutes: [SavedRoute] = []
    @Published var selectedRouteID: UUID?
    @Published var durationText = ""
    @Published var latitude = ""
    @Published var longitude = ""
    @Published var simulation: Simulation?
    @Published var uncertain = false
    @Published var logs: [String] = []
    @Published var xcodePath: String {
        didSet {
            UserDefaults.standard.set(xcodePath, forKey: "xcodePath")
            if oldValue != xcodePath { environmentReport = nil; deviceSnapshotFresh = false }
        }
    }
    private var keepAwake: Process?
    private var refreshTask: Task<CommandResult, Error>?
    private var environmentTask: Task<SetupReport, Error>?
    private let stateURL = DeviceService.support.appendingPathComponent("session.json")
    private let logURL = DeviceService.support.appendingPathComponent("console.log")
    private let routeStore = RouteLibraryStore()
    private var library = RouteLibraryDocument()
    private var libraryReady = false

    var selectedPhone: Phone? { phones.first { $0.id == selectedID } }
    var phoneReady: Bool { deviceSnapshotFresh && selectedPhone?.available == true && selectedPhone?.paired == true && selectedPhone?.developerModeEnabled == true }
    var canStart: Bool { !busy && simulation == nil && phoneReady && environmentReport?.xcodePath == xcodePath && environmentReport?.supportsCoordinates == true }
    var canStartRoute: Bool { canStart && environmentReport?.supportsRoutes == true }
    var canRefresh: Bool { !busy && !refreshCooldown }
    var duration: Double? { try? parseDuration(durationText) }
    var speed: Double? { guard let route, let duration else { return nil }; return route.distance / duration * 3.6 }
    var paceSecondsPerKM: Double? { guard let route, let duration else { return nil }; return duration / route.distance * 1000 }
    var phoneCheck: SetupCheck {
        guard deviceSnapshotFresh else { return SetupCheck(id: "phone", title: "iPhone 开发准备", status: .pending, detail: "点击「刷新设备」读取当前连接状态。解锁和信任提示需要在手机上确认。") }
        guard let phone = selectedPhone, phone.available else { return SetupCheck(id: "phone", title: "iPhone 开发准备", status: .needsAction, detail: "尚未选中可连接的 iPhone。请用数据线连接、解锁并信任 Mac，然后刷新。") }
        guard phone.paired else { return SetupCheck(id: "phone", title: "iPhone 开发准备", status: .needsAction, detail: "配对尚未确认。请在手机上信任 Mac，并在 Xcode 的设备窗口完成连接准备。") }
        guard phone.developerModeEnabled else { return SetupCheck(id: "phone", title: "iPhone 开发准备", status: .needsAction, detail: "开发者模式未开启或未确认。请在手机「设置 → 隐私与安全性 → 开发者模式」开启，按提示重启确认，再刷新。") }
        return SetupCheck(id: "phone", title: "iPhone 开发准备", status: .passed, detail: "\(phone.model) · iOS \(phone.version)：已配对，开发者模式已开启。请保持解锁和连接；是否接受定位请求仍以实际操作为准。")
    }

    private init() {
        xcodePath = DeviceService.discoverXcode(preferred: UserDefaults.standard.string(forKey: "xcodePath"))
        if !UserDefaults.standard.bool(forKey: "setupPageShown") {
            page = .setup
            UserDefaults.standard.set(true, forKey: "setupPageShown")
        }
        do {
            try DeviceService.prepareDirectory()
            if let data = try? Data(contentsOf: stateURL) {
                simulation = try JSONDecoder().decode(Simulation.self, from: data)
                uncertain = true
                selectedID = simulation?.deviceID ?? ""
                notice = "发现上次未清除的模拟记录。手机状态未确认；请先停止并清除。"
                preventSleep()
            }
            if let text = try? String(contentsOf: logURL, encoding: .utf8) {
                logs = text.components(separatedBy: "\n\n").filter { !$0.isEmpty }.suffix(150).map { $0 }
            }
        } catch { self.error = error.localizedDescription }
        do {
            library = try routeStore.load()
            libraryReady = true
            savedRoutes = library.routes
            if let entry = library.routes.first(where: { $0.id == library.selectedID }) ?? library.routes.first {
                route = try routeStore.read(entry)
                selectedRouteID = entry.id
                durationText = route!.defaultDurationText
                addLog("已恢复路线库（\(savedRoutes.count) 条），当前路线：\(entry.name)。")
            }
        } catch {
            self.error = "无法完整恢复路线库，原有文件已保留。\n\(error.localizedDescription)"
        }
    }

    func addLog(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        logs.append("[\(formatter.string(from: Date()))] \(text)")
        if logs.count > 150 { logs.removeFirst(logs.count - 150) }
        try? logs.joined(separator: "\n\n").write(to: logURL, atomically: true, encoding: .utf8)
    }

    func prepare() async {
        guard !busy else { return }
        await checkEnvironment()
        if environmentReport?.passed("xcode") == true { await refresh() }
    }

    func checkEnvironment() async {
        guard !busy else { return }
        busy = true; isCheckingEnvironment = true; error = nil
        environmentReport = nil
        operation = "正在检查 Xcode 环境，可取消"
        let xcode = xcodePath
        let task = Task { try await SetupEnvironment.inspect(xcode: xcode) }
        environmentTask = task
        defer { busy = false; isCheckingEnvironment = false; operation = ""; environmentTask = nil }
        do {
            let report = try await task.value
            environmentReport = report
            notice = report.supportsRoutes ? "本机定位接口已就绪。连接 iPhone 并刷新设备后可以使用。" : "环境检查有待处理的项目，请打开「环境检查」按提示配置。"
            addLog("环境检查完成：固定定位 \(report.supportsCoordinates ? "可用" : "未就绪")，路线回放 \(report.supportsRoutes ? "可用" : "未就绪")。")
            if !report.supportsRoutes { page = .setup }
        } catch is CancellationError {
            notice = "环境检查已取消，稍后可在「环境检查」重新运行。"
        } catch { fail(error) }
    }

    func cancelRead() {
        if isCheckingEnvironment { environmentTask?.cancel() }
        if isRefreshing { cancelRefresh() }
    }

    func openXcode() { NSWorkspace.shared.open(DeviceService.appURL(for: xcodePath)) }

    func exportEnvironmentReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "定位控制台环境报告.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var text = "定位控制台 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") 环境报告\n"
        if let report = environmentReport {
            text += "检查时间：\(ISO8601DateFormatter().string(from: report.checkedAt))\n"
            for check in report.checks { text += "\n[\(check.status == .passed ? "通过" : "待处理")] \(check.title)\n\(check.detail)\n" }
        } else { text += "本机环境尚未完成检查。\n" }
        text += "\n[设备] \(phoneCheck.detail)\n\n本报告不包含设备标识、设备名称、路线坐标或原始运行日志。\n"
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { fail(error) }
    }

    func refresh() async {
        guard canRefresh else { return }
        busy = true; isRefreshing = true; deviceSnapshotFresh = false; operation = "正在读取设备（最多约 25 秒，可取消）"; error = nil
        addLog("开始读取设备。")
        let xcode = xcodePath
        let task = Task { try await DeviceService.run(["list", "devices"], xcode: xcode, timeout: 15) }
        refreshTask = task
        defer {
            refreshTask = nil; busy = false; isRefreshing = false; operation = ""
            refreshCooldown = true
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.refreshCooldown = false
            }
        }
        do {
            let result = try await task.value
            phones = try DeviceService.phones(from: result.data)
            deviceSnapshotFresh = true
            if simulation == nil, !phones.contains(where: { $0.id == selectedID && $0.available }) {
                selectedID = phones.first(where: \.available)?.id ?? phones.first?.id ?? ""
            }
            let connected = phones.filter(\.available).count
            addLog("刷新设备：\(connected) 台可连接，\(phones.count) 台已知 iPhone。")
            if simulation == nil {
                notice = phoneReady && environmentReport?.supportsRoutes == true ? "环境和设备已就绪。请选择定位方式。" : "请在「环境检查」查看本机环境和手机开发准备。"
            }
        } catch is CancellationError {
            notice = "已取消设备读取。原有设备列表保留，稍后可再次刷新。"
            addLog("已取消设备读取。")
        } catch { fail(error) }
    }

    func cancelRefresh() {
        guard isRefreshing else { return }
        operation = "正在取消设备读取"
        refreshTask?.cancel()
    }

    func importGPX() {
        guard !busy, simulation == nil else { return }
        guard libraryReady else { error = "路线库尚未成功读取，为避免覆盖原有数据，请先处理路线库错误。"; return }
        let panel = NSOpenPanel()
        panel.title = "导入一条连续 GPX 路线"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "gpx") ?? .xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try Route(url: url)
            library = try routeStore.adding(imported, to: library)
            savedRoutes = library.routes
            selectedRouteID = library.selectedID
            route = imported
            durationText = imported.defaultDurationText
            page = .route; error = nil
            addLog("已保存到路线库：\(imported.name)，\(String(format: "%.1f", imported.distance)) 米；默认耗时 \(durationText)。")
        } catch { fail(error) }
    }

    func selectRoute(_ id: UUID) {
        guard !busy, simulation == nil, libraryReady,
              let entry = library.routes.first(where: { $0.id == id }) else { return }
        if selectedRouteID == id && route != nil { return }
        do {
            let loaded = try routeStore.read(entry)
            var updated = library
            updated.selectedID = id
            try routeStore.save(updated)
            library = updated
            selectedRouteID = id
            route = loaded
            durationText = loaded.defaultDurationText
            error = nil
            addLog("已选用保存的路线：\(entry.name)，默认耗时 \(durationText)。")
        } catch { fail(error) }
    }

    func deleteRoute(_ id: UUID) {
        guard !busy, simulation == nil, libraryReady,
              let entry = library.routes.first(where: { $0.id == id }) else { return }
        do {
            var updated = library
            updated.routes.removeAll { $0.id == id }
            let removingSelection = selectedRouteID == id
            if removingSelection || updated.selectedID == id { updated.selectedID = nil }
            // Commit the catalog before removing coordinates. A failed catalog
            // write must not leave a saved entry pointing at a deleted file.
            try routeStore.save(updated)
            library = updated
            savedRoutes = updated.routes
            if removingSelection {
                selectedRouteID = nil
                route = nil
                durationText = ""
            }
            error = nil
            addLog("已从路线库删除：\(entry.name)。")
            do { try routeStore.trashCopy(id) }
            catch { fail(ConsoleError("已从路线库移除，但路线副本未能移到废纸篓：\(error.localizedDescription)")) }
        } catch { fail(error) }
    }

    func resetDuration() {
        guard !busy, simulation == nil, let route else { return }
        durationText = route.defaultDurationText
    }

    func selectXcode() {
        let panel = NSOpenPanel()
        panel.title = "选择 Xcode.app"
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try DeviceService.developerDirectory(url.path)
            xcodePath = url.path; error = nil
            Task { await prepare() }
        }
        catch { fail(error) }
    }

    func startCoordinate() async {
        guard canStart, let phone = selectedPhone else { return }
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let lon = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              Point(latitude: lat, longitude: lon).valid else {
            error = "请输入有效的纬度（-90～90）和经度（-180～180），使用小数点。"; return
        }
        let point = Point(latitude: lat, longitude: lon)
        let session = Simulation(deviceID: phone.id, deviceName: phone.name, kind: "coordinate", title: point.formatted,
                                 started: Date(), duration: nil, routePath: nil)
        await start(session, arguments: ["device", "simulate", "location", "coordinate", "--device", phone.id,
                                        "--latitude", String(lat), "--longitude", String(lon)])
    }

    func startRoute() async {
        guard canStartRoute, let phone = selectedPhone, let route else { return }
        do {
            let duration = try parseDuration(durationText)
            let path = DeviceService.support.appendingPathComponent("route-" + UUID().uuidString + ".json")
            try route.nativeData(duration: duration).write(to: path, options: .atomic)
            let session = Simulation(deviceID: phone.id, deviceName: phone.name, kind: "route", title: route.name,
                                     started: Date(), duration: duration, routePath: path.path)
            await start(session, arguments: ["device", "simulate", "location", "route", "--device", phone.id, "--route-file", path.path])
            if simulation == nil { try? FileManager.default.removeItem(at: path) }
        } catch { fail(error) }
    }

    private func start(_ session: Simulation, arguments: [String]) async {
        busy = true; operation = "正在向 iPhone 发送模拟请求"; error = nil
        defer { busy = false; operation = "" }
        do {
            // Save before dispatch: an interrupted command can still change phone state.
            _ = try DeviceService.developerDirectory(xcodePath)
            try JSONEncoder().encode(session).write(to: stateURL, options: .atomic)
            simulation = session; uncertain = true; preventSleep()
            addLog("发送\(session.kind == "route" ? "路线回放" : "固定定位")请求：\(session.title)，设备 \(session.deviceName)。")
            let result = try await DeviceService.run(arguments, xcode: xcodePath, timeout: 40)
            uncertain = false
            notice = session.kind == "route" ? "回放请求已接受。按计划播放一次，预计到达后保持终点。" : "固定定位请求已接受。请在手机地图确认蓝点位置。"
            addLog("Xcode 已接受请求。\n\(result.output)")
        } catch { fail(error); notice = "启动状态未确认。请停止并清除，再在手机上核对。" }
    }

    @discardableResult func clear() async -> Bool {
        guard !busy else { return false }
        guard let deviceID = simulation?.deviceID ?? selectedPhone?.id else {
            error = "请先连接并选择一台 iPhone。"; return false
        }
        busy = true; operation = "正在清除模拟定位"; error = nil
        defer { busy = false; operation = "" }
        do {
            let result = try await DeviceService.run(["device", "simulate", "location", "clear", "--device", deviceID], xcode: xcodePath, timeout: 25)
            if FileManager.default.fileExists(atPath: stateURL.path) { try FileManager.default.removeItem(at: stateURL) }
            if let path = simulation?.routePath { try? FileManager.default.removeItem(atPath: path) }
            simulation = nil; uncertain = false; allowSleep()
            notice = "清除命令已成功返回。请在手机地图点「当前位置」，确认蓝点恢复；如仍残留，可重启 iPhone。"
            addLog("清除命令成功返回；真实位置恢复情况需在手机确认。\n\(result.output)")
            return true
        } catch { fail(error); return false }
    }

    private func fail(_ error: Error) {
        self.error = error.localizedDescription
        addLog("错误：\(error.localizedDescription)")
    }

    private func preventSleep() {
        guard keepAwake == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-i", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        do { try process.run(); keepAwake = process } catch { addLog("未能阻止 Mac 自动空闲休眠，请保持 Mac 唤醒。") }
    }
    func allowSleep() { keepAwake?.terminate(); keepAwake = nil }

    func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "定位控制台日志.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try logs.joined(separator: "\n\n").write(to: url, atomically: true, encoding: .utf8) }
        catch { fail(error) }
    }

    func openDocumentation() {
        if let url = Bundle.main.url(forResource: "使用说明", withExtension: "md") { NSWorkspace.shared.open(url) }
    }
}
