import SwiftUI
import CoreLocation
import Combine
import UIKit

@main
struct LocationProbeApp: App {
    var body: some Scene {
        WindowGroup { ProbeView() }
    }
}

struct Sample: Identifiable {
    let id = UUID()
    let receivedAt: Date
    let location: CLLocation
    let callbackGap: Double?
    let derivedSpeed: Double?
    var simulated: String {
        guard let source = location.sourceInformation else { return "未知" }
        return source.isSimulatedBySoftware ? "是" : "否"
    }
    var accessory: String {
        guard let source = location.sourceInformation else { return "未知" }
        return source.isProducedByAccessory ? "是" : "否"
    }
}

@MainActor
final class LocationMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var samples: [Sample] = []
    @Published var count = 0
    @Published var running = false
    @Published var status = "点开始后允许使用定位，并开启精确位置。"
    @Published var precision = "尚未确认"
    @Published var exportURL: URL?
    private let manager = CLLocationManager()
    private var file: FileHandle?
    private var previousLocation: CLLocation?
    private var previousCallbackUptime: TimeInterval?
    private let iso = ISO8601DateFormatter()

    override init() {
        super.init()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        guard !running else { return }
        do {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let name = "location-\(Int(Date().timeIntervalSince1970)).csv"
            let url = folder.appendingPathComponent(name)
            let header = "received_at,location_timestamp,callback_gap_s,location_age_s,latitude,longitude,horizontal_accuracy_m,speed_mps,speed_accuracy_mps,course_deg,course_accuracy_deg,is_simulated_by_software,is_produced_by_accessory,derived_speed_mps,accuracy_authorization\n"
            try Data(header.utf8).write(to: url, options: .atomic)
            file = try FileHandle(forWritingTo: url)
            try file?.seekToEnd()
            exportURL = url
            samples = []
            count = 0
            previousLocation = nil
            previousCallbackUptime = nil
            running = true
            status = "等待位置；请保持此 App 在前台。"
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                updateAuthorization()
            }
        } catch {
            status = "无法创建记录：\(error.localizedDescription)"
            running = false
            try? file?.close()
            file = nil
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        running = false
        do {
            try file?.synchronize()
            try file?.close()
            file = nil
            status = "已停止，共记录 \(count) 个位置。"
        } catch {
            file = nil
            status = "文件保存出现错误：\(error.localizedDescription)"
        }
    }

    private func updateAuthorization() {
        precision = manager.accuracyAuthorization == .fullAccuracy ? "精确位置" : "大致位置"
        guard running else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            status = "记录中；请保持此 App 在前台。"
        case .denied, .restricted:
            stop()
            status = "定位未获授权，请到设置中允许定位。"
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard running else { return }
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        let gap = previousCallbackUptime.map { uptime - $0 }
        previousCallbackUptime = uptime
        for (index, location) in locations.enumerated() {
            var derived: Double?
            if let previous = previousLocation {
                let dt = location.timestamp.timeIntervalSince(previous.timestamp)
                if dt > 0, previous.horizontalAccuracy >= 0, location.horizontalAccuracy >= 0 {
                    derived = location.distance(from: previous) / dt
                }
            }
            let sample = Sample(receivedAt: now, location: location,
                                callbackGap: index == 0 ? gap : nil, derivedSpeed: derived)
            let source = location.sourceInformation
            let fields = [
                iso.string(from: now), iso.string(from: location.timestamp),
                index == 0 ? gap.map { String($0) } ?? "" : "",
                String(now.timeIntervalSince(location.timestamp)),
                String(location.coordinate.latitude), String(location.coordinate.longitude),
                String(location.horizontalAccuracy), String(location.speed),
                String(location.speedAccuracy), String(location.course), String(location.courseAccuracy),
                source.map { $0.isSimulatedBySoftware ? "true" : "false" } ?? "unknown",
                source.map { $0.isProducedByAccessory ? "true" : "false" } ?? "unknown",
                derived.map { String($0) } ?? "",
                manager.accuracyAuthorization == .fullAccuracy ? "full" : "reduced"
            ]
            do {
                try file?.write(contentsOf: Data((fields.joined(separator: ",") + "\n").utf8))
            } catch {
                stop()
                status = "写入失败：\(error.localizedDescription)"
                return
            }
            samples.insert(sample, at: 0)
            if samples.count > 20 { samples.removeLast(samples.count - 20) }
            previousLocation = location
            count += 1
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "定位报告错误：\(error.localizedDescription)"
    }
}

struct ProbeView: View {
    @StateObject private var monitor = LocationMonitor()
    private func number(_ value: Double?, suffix: String = "") -> String {
        guard let value else { return "未知" }
        return String(format: "%.3f", value) + suffix
    }

    var body: some View {
        NavigationStack {
            List {
                Section("记录") {
                    Text(monitor.status)
                    LabeledContent("位置授权", value: monitor.precision)
                    LabeledContent("已记录", value: "\(monitor.count) 个位置")
                    Button(monitor.running ? "停止记录" : "开始新记录") {
                        if monitor.running { monitor.stop() } else { monitor.start() }
                    }
                    if !monitor.running, let url = monitor.exportURL {
                        ShareLink("导出 CSV 记录", item: url)
                    }
                    Button("打开此 App 的设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                if let sample = monitor.samples.first {
                    Section("最近收到的位置") {
                        LabeledContent("系统速度", value: sample.location.speed < 0 ? "无效（\(sample.location.speed)）" : number(sample.location.speed * 3.6, suffix: " km/h"))
                        LabeledContent("坐标推算速度", value: number(sample.derivedSpeed.map { $0 * 3.6 }, suffix: " km/h"))
                        LabeledContent("水平精度", value: sample.location.horizontalAccuracy < 0 ? "无效" : number(sample.location.horizontalAccuracy, suffix: " m"))
                        LabeledContent("软件模拟标记", value: sample.simulated)
                        LabeledContent("外设来源标记", value: sample.accessory)
                        LabeledContent("回调间隔", value: number(sample.callbackGap, suffix: " s"))
                        Text(String(format: "纬度 %.7f， 经度 %.7f", sample.location.coordinate.latitude, sample.location.coordinate.longitude))
                            .font(.footnote).textSelection(.enabled)
                    }
                }
                Section("说明") {
                    Text("保持本页前台。日志保存在手机本地，可停止后手动导出。位置来源缺失时显示未知，不推断为否。")
                    Text("系统速度与根据坐标推算的速度分别记录。坐标漂移也会影响推算结果。负速度或负精度保留在 CSV 中，表示相应值无效。")
                    Text("这里测量的是本诊断 App 收到的数据；其他 App 的授权、采样及处理方式可能不同。")
                }
            }
            .navigationTitle("定位诊断")
        }
    }
}
