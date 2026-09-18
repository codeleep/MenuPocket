import AppKit
import SwiftUI
import ApplicationServices

@MainActor
final class AppState: ObservableObject {
    @Published var layout: Layout
    @Published var items: [MenuIcon] = []
    @Published var selectedGroup: String? = nil
    @Published var search = ""
    @Published var message = ""
    @Published var error = ""
    @Published var scanning = false
    @Published var working = false
    @Published var trusted = AXIsProcessTrusted()
    @Published var showingPermissions = false
    @Published var editingIcon: MenuIcon?
    @Published var visibility: [String: VisibilityStatus] = [:]
    @Published var thumbnails: [String: NSImage] = [:]
    let repository: LayoutRepository
    let operations = ItemOperator()
    private var scanGeneration = 0
    private var saveEnabled = true
    var layoutChanged: (() -> Void)?
    var visibilityChanged: ((Set<String>) -> Void)?
    var scanCompleted: (() -> Void)?
    var retryVisibility: ((String) -> Void)?
    var activateItem: ((MenuIcon, Bool) async -> Void)?

    init(repository: LayoutRepository = LayoutRepository()) {
        self.repository = repository
        do { layout = try repository.load() }
        catch {
            layout = Layout()
            saveEnabled = false
            self.error = "布局文件无法读取，已保留原文件且暂停写入：\(error.localizedDescription)"
        }
    }

    func refresh() {
        guard !scanning, !working else { return }
        trusted = AXIsProcessTrusted()
        scanning = true
        scanGeneration += 1
        let generation = scanGeneration
        DispatchQueue.global(qos: .userInitiated).async {
            let icons = MenuScanner().scan()
            DispatchQueue.main.async {
                guard generation == self.scanGeneration else { return }
                for icon in icons { self.layout.migrateAliases(icon.legacyIDs, to: icon.id) }
                // Migrate a fallback window identity after accessibility is granted in this session.
                for icon in icons where self.layout.placements[icon.id] == nil {
                    if let old = self.items.first(where: { $0.windowID != nil && $0.windowID == icon.windowID && $0.pid == icon.pid }),
                       let placement = self.layout.placements[old.id] {
                        self.layout.placements[icon.id] = placement
                        self.layout.placements.removeValue(forKey: old.id)
                    }
                }
                let windows = MenuScanner.windows()
                self.items = icons.map { icon in
                    var resolved = icon
                    if icon.windowID == nil,
                       let old = self.items.first(where: { $0.id == icon.id && $0.pid == icon.pid }),
                       let id = old.windowID, let window = windows.first(where: { $0.id == id }) {
                        resolved.windowID = id
                        resolved.frame = window.frame
                    }
                    return resolved
                }
                self.scanning = false
                self.message = self.trusted ? "发现 \(icons.count) 个菜单栏项目 · \(icons.filter(\.isSystem).count) 个来自系统应用" : "等待辅助功能授权；窗口占位不会被当作真实图标展示。"
                self.persist()
                self.scanCompleted?()
            }
        }
    }

    func persist() {
        guard saveEnabled else { return }
        do { try repository.save(layout) }
        catch { self.error = "布局保存失败：\(error.localizedDescription)" }
    }

    private func changed(from previous: Layout? = nil) {
        persist()
        layoutChanged?()
        if let previous {
            let ids = Set(items.map(\.id))
            let before = Dictionary(uniqueKeysWithValues: ids.map { ($0, previous.keepInMenuBar($0)) })
            let after = Dictionary(uniqueKeysWithValues: ids.map { ($0, layout.keepInMenuBar($0)) })
            let changedIDs = VisibilityDelta.changedIDs(previous: before, current: after)
            if !changedIDs.isEmpty { visibilityChanged?(changedIDs) }
        }
    }

    func createGroup(_ raw: String) {
        let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        guard !name.isEmpty else { return }
        guard !layout.groups.contains(where: { $0.name == name }) else { error = "已有同名分组。"; return }
        let group = IconGroup(name: name, symbol: "folder")
        layout.groups.append(group)
        selectedGroup = group.id
        changed()
    }

    func rename(_ group: IconGroup, to raw: String) {
        let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        guard !name.isEmpty, let index = layout.groups.firstIndex(where: { $0.id == group.id }) else { return }
        guard !layout.groups.contains(where: { $0.id != group.id && $0.name == name }) else { error = "已有同名分组。"; return }
        layout.groups[index].name = name
        changed()
    }

    func delete(_ group: IconGroup) {
        let previous = layout
        layout.removeGroup(group.id)
        if selectedGroup == group.id { selectedGroup = nil }
        changed(from: previous)
    }

    func hide(_ group: IconGroup) {
        guard let index = layout.groups.firstIndex(where: { $0.id == group.id }) else { return }
        layout.groups[index].hidden.toggle()
        changed()
    }

    func reorderGroup(_ group: IconGroup, by offset: Int) {
        guard let index = layout.groups.firstIndex(where: { $0.id == group.id }), layout.groups.indices.contains(index + offset) else { return }
        layout.groups.swapAt(index, index + offset)
        changed()
    }

    func move(_ id: String, groupID: String?) {
        guard !working, items.contains(where: { $0.id == id }) else { return }
        let previous = layout
        layout.move(id, into: groupID)
        changed(from: previous)
    }

    func setMenuBarVisible(_ id: String, visible: Bool) {
        guard !working, let groupID = layout.placements[id]?.groupID,
              layout.groups.contains(where: { $0.id == groupID }) else { return }
        guard layout.keepInMenuBar(id) != visible else { return }
        let previous = layout
        layout.placements[id]?.pinned = visible
        changed(from: previous)
    }

    func reorder(_ item: MenuIcon, by offset: Int) {
        let group = layout.placements[item.id]?.groupID
        let ordered = groupItems(group)
        guard let index = ordered.firstIndex(where: { $0.id == item.id }), ordered.indices.contains(index + offset) else { return }
        var ids = ordered.map(\.id)
        ids.swapAt(index, index + offset)
        for (position, id) in ids.enumerated() {
            var placement = layout.placements[id] ?? Placement()
            placement.order = position
            layout.placements[id] = placement
        }
        changed()
    }

    func groupItems(_ groupID: String?) -> [MenuIcon] {
        items.filter { layout.placements[$0.id]?.groupID == groupID }.sorted {
            let a = layout.placements[$0.id]?.order ?? 0
            let b = layout.placements[$1.id]?.order ?? 0
            return a == b ? $0.id < $1.id : a < b
        }
    }

    func displayName(_ item: MenuIcon) -> String { layout.placements[item.id]?.label ?? item.name }

    func filtered(_ groupID: String?) -> [MenuIcon] {
        groupItems(groupID).filter { search.isEmpty || displayName($0).localizedCaseInsensitiveContains(search) || $0.appName.localizedCaseInsensitiveContains(search) }
    }

    func open(_ item: MenuIcon, rightClick: Bool = false) {
        guard !working else { return }
        if !trusted { showingPermissions = true; return }
        Task { await activateItem?(item, rightClick) }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
}
