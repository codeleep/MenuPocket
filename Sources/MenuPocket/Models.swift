import AppKit
import ApplicationServices

struct IconGroup: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var symbol: String
    var hidden = false
}

struct Placement: Codable, Equatable {
    var groupID: String?
    var order = 0
    var label: String?
}

struct Layout: Codable, Equatable {
    var version = 2
    var groups = [
        IconGroup(name: "开发", symbol: "hammer"),
        IconGroup(name: "网络", symbol: "network"),
        IconGroup(name: "系统", symbol: "slider.horizontal.3")
    ]
    var placements: [String: Placement] = [:]

    mutating func migrateAliases(_ aliases: [String], to id: String) {
        let aliases = aliases.filter { $0 != id }
        if placements[id] == nil, let old = aliases.compactMap({ placements[$0] }).first {
            placements[id] = old
        }
        for alias in aliases { placements.removeValue(forKey: alias) }
    }

    mutating func removeGroup(_ id: String) {
        groups.removeAll { $0.id == id }
        for key in Array(placements.keys) where placements[key]?.groupID == id {
            placements[key]?.groupID = nil
        }
    }

    mutating func move(_ id: String, into groupID: String?) {
        guard groupID == nil || groups.contains(where: { $0.id == groupID }) else { return }
        var placement = placements[id] ?? Placement()
        placement.groupID = groupID
        placement.order = (placements.values.filter { $0.groupID == groupID }.map(\.order).max() ?? -1) + 1
        placements[id] = placement
    }
}

final class LayoutRepository {
    let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MenuPocket/layout.json")
    }

    func load() throws -> Layout {
        guard FileManager.default.fileExists(atPath: url.path) else { return Layout() }
        var result = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: url))
        guard result.version == 1 || result.version == 2 else { throw CocoaError(.fileReadUnknown) }
        guard Set(result.groups.map(\.id)).count == result.groups.count else { throw CocoaError(.fileReadCorruptFile) }
        if result.version == 1 {
            // Keep the original hide/pin preferences available for rollback to older builds.
            var backup = url.appendingPathExtension("v1-backup")
            if FileManager.default.fileExists(atPath: backup.path) {
                backup = backup.appendingPathExtension(UUID().uuidString)
            }
            try FileManager.default.copyItem(at: url, to: backup)
            result.version = 2
        }
        return result
    }

    func save(_ layout: Layout) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(layout).write(to: url, options: .atomic)
    }
}

struct MenuIcon: Identifiable {
    let id: String
    let pid: pid_t
    let bundleID: String
    let name: String
    let appName: String
    var windowID: CGWindowID?
    var frame: CGRect
    let element: AXUIElement?
    let actions: [String]
    let image: NSImage
    let isSystem: Bool
    var legacyIDs: [String] = []
}
