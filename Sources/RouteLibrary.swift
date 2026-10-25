import Foundation
import CryptoKit

struct SavedRoute: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let distance: Double
    let pointCount: Int
    let importedAt: Date
    let fingerprint: String
    var distanceLabel: String {
        distance >= 1000 ? String(format: "%.2f 公里", distance / 1000) : String(format: "%.0f 米", distance)
    }
}

struct RouteLibraryDocument: Codable {
    var version = 1
    var selectedID: UUID?
    var routes: [SavedRoute] = []
}

struct RouteLibraryStore {
    private let catalog = DeviceService.support.appendingPathComponent("route-library.json")
    private let directory = DeviceService.support.appendingPathComponent("SavedRoutes", isDirectory: true)
    private let legacy = DeviceService.support.appendingPathComponent("last-route.json")

    func load() throws -> RouteLibraryDocument {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: catalog.path) {
            let size = try catalog.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10_000_000 else { throw ConsoleError("路线目录超过大小限制，请保留数据并检查路线库。") }
            let document = try JSONDecoder().decode(RouteLibraryDocument.self, from: Data(contentsOf: catalog))
            guard document.version == 1 else { throw ConsoleError("路线库版本不受支持，请更新软件。") }
            guard Set(document.routes.map(\.id)).count == document.routes.count,
                  document.routes.allSatisfy({ $0.distance.isFinite && $0.distance > 0 && (2...200_000).contains($0.pointCount) }) else {
                throw ConsoleError("路线目录数据无效，原有文件已保留。")
            }
            return document
        }
        var document = RouteLibraryDocument()
        // Migrate the last route saved by 1.1. An empty catalog is also saved,
        // so removing the last entry cannot resurrect the legacy route.
        if FileManager.default.fileExists(atPath: legacy.path) {
            let route = try readRoute(at: legacy)
            document = try adding(route, to: document)
            // The validated coordinates and catalog have both been committed.
            // Retire the obsolete copy through the normal recoverable Trash.
            try? FileManager.default.trashItem(at: legacy, resultingItemURL: nil)
        } else { try save(document) }
        return document
    }

    func save(_ document: RouteLibraryDocument) throws {
        try JSONEncoder().encode(document).write(to: catalog, options: .atomic)
    }

    func read(_ entry: SavedRoute) throws -> Route {
        try readRoute(at: file(for: entry.id))
    }

    func adding(_ route: Route, to original: RouteLibraryDocument) throws -> RouteLibraryDocument {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(route)
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var document = original
        if let existing = document.routes.first(where: { $0.fingerprint == fingerprint }) {
            // Re-import also repairs a missing or damaged coordinate copy.
            try data.write(to: file(for: existing.id), options: .atomic)
            document.selectedID = existing.id
            try save(document)
            return document
        }
        let entry = SavedRoute(id: UUID(), name: route.name, distance: route.distance,
                               pointCount: route.points.count, importedAt: Date(), fingerprint: fingerprint)
        let url = file(for: entry.id)
        try data.write(to: url, options: .atomic)
        document.routes.insert(entry, at: 0)
        document.selectedID = entry.id
        do { try save(document) }
        catch { try? FileManager.default.removeItem(at: url); throw error }
        return document
    }

    func trashCopy(_ id: UUID) throws {
        let url = file(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    private func file(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }

    private func readRoute(at url: URL) throws -> Route {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 25_000_000 else { throw ConsoleError("路线副本超过大小限制，请重新导入 GPX。") }
        return try JSONDecoder().decode(Route.self, from: Data(contentsOf: url))
    }
}
