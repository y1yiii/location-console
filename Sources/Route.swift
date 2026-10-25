import Foundation

struct Point: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    var valid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
    func distance(to other: Point) -> Double {
        let r = Double.pi / 180
        let a = pow(sin((other.latitude - latitude) * r / 2), 2)
            + cos(latitude * r) * cos(other.latitude * r) * pow(sin((other.longitude - longitude) * r / 2), 2)
        return 6_371_008.8 * 2 * asin(sqrt(min(1, max(0, a))))
    }
    func interpolated(to other: Point, fraction: Double) -> Point {
        var delta = other.longitude - longitude
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        let lon = longitude + delta * fraction
        return Point(latitude: latitude + (other.latitude - latitude) * fraction,
                     longitude: lon > 180 ? lon - 360 : (lon < -180 ? lon + 360 : lon))
    }
    var formatted: String { String(format: "%.6f, %.6f", latitude, longitude) }
}

struct ConsoleError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct Route: Codable {
    let name: String
    let points: [Point]
    let cumulative: [Double]
    var distance: Double { cumulative.last ?? 0 }
    var defaultDuration: Double { max(1, (distance / 1000 * 300).rounded()) }
    var defaultDurationText: String { durationInput(defaultDuration) }

    init(url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 20_000_000 else { throw ConsoleError("GPX 文件超过 20 MB，请先简化轨迹。") }
        let data = try Data(contentsOf: url)
        guard !String(decoding: data, as: UTF8.self).uppercased().contains("<!DOCTYPE") else {
            throw ConsoleError("不支持包含 DTD 的 GPX 文件。请从路线编辑器重新导出。")
        }
        let delegate = GPXReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.problem == nil else {
            throw ConsoleError(delegate.problem ?? "无法解析 GPX：\(parser.parserError?.localizedDescription ?? "文件格式错误")")
        }
        let groups = !delegate.tracks.isEmpty ? delegate.tracks : (!delegate.routes.isEmpty ? delegate.routes : [delegate.waypoints])
        let nonempty = groups.filter { !$0.isEmpty }
        guard nonempty.count == 1 else { throw ConsoleError("请选择一条连续轨迹。当前文件包含 \(nonempty.count) 段，需在 GPX 编辑器中先合并或删除多余段。") }
        try self.init(name: url.deletingPathExtension().lastPathComponent, points: nonempty[0])
    }

    init(name: String, points source: [Point]) throws {
        guard source.count <= 200_000 else { throw ConsoleError("坐标点超过 20 万，请先简化轨迹。") }
        guard source.allSatisfy(\.valid) else { throw ConsoleError("路线中有无效或越界的经纬度。") }
        var cleaned: [Point] = []
        for point in source where cleaned.last != point { cleaned.append(point) }
        guard cleaned.count >= 2 else { throw ConsoleError("GPX 至少需要两个不同的坐标点。") }
        var sums = [0.0]
        for i in 1..<cleaned.count { sums.append(sums.last! + cleaned[i - 1].distance(to: cleaned[i])) }
        guard sums.last! > 0.1 else { throw ConsoleError("路线太短，请重新选择 GPX。") }
        self.name = name.isEmpty ? "已保存路线" : name
        points = cleaned
        cumulative = sums
    }

    private enum CodingKeys: String, CodingKey { case name, points }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(name: container.decode(String.self, forKey: .name), points: container.decode([Point].self, forKey: .points))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(points, forKey: .points)
    }

    func point(at fraction: Double) -> Point {
        let target = max(0, min(1, fraction)) * distance
        if target <= 0 { return points[0] }
        if target >= distance { return points.last! }
        var lo = 1, hi = cumulative.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid] < target { lo = mid + 1 } else { hi = mid }
        }
        let segment = cumulative[lo] - cumulative[lo - 1]
        return points[lo - 1].interpolated(to: points[lo], fraction: segment > 0 ? (target - cumulative[lo - 1]) / segment : 0)
    }

    func nativeData(duration: Double) throws -> Data {
        var samples: [Point] = []
        let steps = Int(ceil(duration / 0.5))
        for i in 0...steps { samples.append(point(at: min(Double(i) * 0.5 / duration, 1))) }
        let config = NativeRoute(mode: "interval", interval: 0.5, speed: distance / duration * 1.001, waypoints: samples)
        return try JSONEncoder().encode(config)
    }
}

private struct NativeRoute: Encodable {
    let mode: String
    let interval: Double
    let speed: Double
    let waypoints: [Point]
}

private final class GPXReader: NSObject, XMLParserDelegate {
    var tracks: [[Point]] = []
    var routes: [[Point]] = []
    var waypoints: [Point] = []
    var problem: String?
    var stack: [String] = []
    var count = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        let element = elementName.components(separatedBy: ":").last!.lowercased()
        let parent = stack.last
        stack.append(element)
        if element == "trkseg" { tracks.append([]) }
        if element == "rte" { routes.append([]) }
        guard ["trkpt", "rtept", "wpt"].contains(element) else { return }
        count += 1
        guard count <= 200_000 else { problem = "坐标点超过 20 万，请先简化轨迹。"; parser.abortParsing(); return }
        guard let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init), Point(latitude: lat, longitude: lon).valid else {
            problem = "GPX 中有缺失或越界的经纬度。"; parser.abortParsing(); return
        }
        let point = Point(latitude: lat, longitude: lon)
        if element == "trkpt", parent == "trkseg", !tracks.isEmpty { tracks[tracks.count - 1].append(point) }
        if element == "rtept", parent == "rte", !routes.isEmpty { routes[routes.count - 1].append(point) }
        if element == "wpt", parent == "gpx" { waypoints.append(point) }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }
}

func parseDuration(_ text: String) throws -> Double {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    let seconds: Double
    if parts.count == 1, let number = Double(value) { seconds = number }
    else if parts.count == 2, let minutes = Double(parts[0]), let rest = Double(parts[1]),
            minutes >= 0, minutes.rounded() == minutes, rest >= 0, rest < 60 { seconds = minutes * 60 + rest }
    else { throw ConsoleError("时长请输入 分:秒（例如 11:30），或总秒数（例如 690）。") }
    guard seconds.isFinite, seconds >= 1, seconds <= 86400 else { throw ConsoleError("时长需要在 1 秒至 24 小时之间。") }
    return seconds
}

func clockString(_ seconds: Double) -> String {
    let s = Int(max(0, seconds.isFinite ? seconds : 0))
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) }
    return String(format: "%02d:%02d", s / 60, s % 60)
}

// Input is always minutes:seconds, including durations over an hour. The
// duration field accepts two components, unlike the elapsed-time display.
func durationInput(_ seconds: Double) -> String {
    let seconds = Int(max(0, seconds.isFinite ? seconds.rounded() : 0))
    return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
}

func chinesePace(_ seconds: Double) -> String {
    let total = Int(max(0, seconds.isFinite ? seconds.rounded() : 0))
    return "\(total / 60)分\(String(format: "%02d", total % 60))秒"
}
