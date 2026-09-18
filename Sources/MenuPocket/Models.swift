import AppKit
import ApplicationServices

enum VisibilityDelta {
    static func changedIDs(previous: [String: Bool], current: [String: Bool]) -> Set<String> {
        Set(current.keys.filter { previous[$0] != current[$0] })
    }
}

enum VisibilityStatus {
    case applying, hidden, visible, failed(String)

    var text: String {
        switch self {
        case .applying: return "正在应用…"
        case .hidden: return "仅在分组中显示"
        case .visible: return "同时显示在菜单栏"
        case .failed(let reason): return "未生效：\(reason)"
        }
    }

    var badgeText: String {
        if case .failed = self { return "未生效 · 点击查看原因" }
        return text
    }
}

struct IconGroup: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var symbol: String
    var hidden = false
}

struct Placement: Codable, Equatable {
    var groupID: String?
    var pinned = false
    var order = 0
    var label: String?
}

struct Layout: Codable, Equatable {
    var version = 1
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

    func keepInMenuBar(_ id: String) -> Bool {
        guard let groupID = placements[id]?.groupID else { return true }
        return !groups.contains { $0.id == groupID } || placements[id]?.pinned == true
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
        let result = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: url))
        guard result.version == 1 else { throw CocoaError(.fileReadUnknown) }
        guard Set(result.groups.map(\.id)).count == result.groups.count else { throw CocoaError(.fileReadCorruptFile) }
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
