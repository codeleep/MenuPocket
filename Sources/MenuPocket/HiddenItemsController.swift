import AppKit
import ApplicationServices

/// The spacer is an implementation detail, never a user-facing menu-bar item.
@MainActor
final class HiddenItemsController {
    private let state: AppState
    private let entrances: () -> [NSStatusItem]
    private var spacer: NSStatusItem?
    private var task: Task<Void, Never>?
    private var observed: [String: Bool] = [:]
    private var pendingIDs = Set<String>()
    private var needsFullApply = false
    private var generation = 0
    private var spacerWindowID: CGWindowID?
    private var spacerInsets = NSEdgeInsetsZero
    private var hiddenIDs = Set<String>()
    private var events: [[String: Any]] = []

    init(state: AppState, entrances: @escaping () -> [NSStatusItem]) {
        self.state = state
        self.entrances = entrances
    }

    static func frame(_ item: NSStatusItem) -> CGRect? {
        // On macOS 26 window.frame can cover the whole menu bar. Use the button's rect.
        guard let button = item.button, let window = button.window else { return nil }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }

    private var desired: [String: Bool] {
        Dictionary(uniqueKeysWithValues: state.items.map { ($0.id, state.layout.keepInMenuBar($0.id)) })
    }

    func schedule(force: Bool = false) {
        let current = desired
        hiddenIDs.formIntersection(current.keys)
        let changed = VisibilityDelta.changedIDs(previous: observed, current: current)
        observed = current
        enqueue(changed, full: force || spacer == nil)
    }

    func schedule(ids: Set<String>) {
        observed = desired
        enqueue(ids, full: spacer == nil)
    }

    private func enqueue(_ ids: Set<String>, full: Bool) {
        pendingIDs.formUnion(ids)
        needsFullApply = needsFullApply || full
        guard needsFullApply || !pendingIDs.isEmpty, task == nil else { return }
        let token = generation
        task = Task {
            defer { if token == generation { task = nil } }
            try? await Task.sleep(for: .milliseconds(400))
            while needsFullApply || !pendingIDs.isEmpty {
                while state.working || state.scanning || NSEvent.pressedMouseButtons != 0 {
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: .milliseconds(150))
                }
                guard !Task.isCancelled else { return }
                let full = needsFullApply
                let ids = pendingIDs
                needsFullApply = false
                pendingIDs.removeAll()
                if full { await apply() }
                else { await applyChanges(ids) }
            }
        }
    }

    private func trackSpacerWindow() {
        guard let spacer, let rect = Self.frame(spacer) else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let candidates = MenuScanner.windows().filter { $0.frame.contains(center) }
        guard candidates.count == 1, let window = candidates.first else { return }
        spacerWindowID = window.id
        spacerInsets = NSEdgeInsets(top: rect.minY - window.frame.minY, left: rect.minX - window.frame.minX,
                                    bottom: window.frame.maxY - rect.maxY, right: window.frame.maxX - rect.maxX)
    }

    private func spacerFrame() -> CGRect? {
        if let id = spacerWindowID, let window = MenuScanner.windows().first(where: { $0.id == id }) {
            return CGRect(x: window.frame.minX + spacerInsets.left, y: window.frame.minY + spacerInsets.top,
                          width: max(0, window.frame.width - spacerInsets.left - spacerInsets.right),
                          height: max(0, window.frame.height - spacerInsets.top - spacerInsets.bottom))
        }
        return spacer.flatMap(Self.frame)
    }

    private func applyChanges(_ ids: Set<String>) async {
        guard state.trusted, let spacer else { return }
        let targets = state.items.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        state.working = true
        events = [["scope": "items", "requestedIDs": targets.map(\.id)]]
        let previousLength = spacer.length
        defer { state.working = false; writeDiagnostics() }
        // Keep the same spacer and all existing item positions. Only the changed items move.
        // A CG window tracks its real location; the app-side proxy may lag after resizing.
        guard let id = spacerWindowID, MenuScanner.windows().contains(where: { $0.id == id }) else {
            for item in targets { state.visibility[item.id] = .failed("无法定位内部占位，未重新应用其他图标；请重新打开应用后重试") }
            return
        }
        for item in targets { state.visibility[item.id] = .applying }
        spacer.length = 12
        try? await Task.sleep(for: .milliseconds(180))
        events.append(["boundary": spacerFrame().map(NSStringFromRect) ?? "missing", "windowID": id])
        for item in targets {
            if Task.isCancelled { spacer.length = previousLength; return }
            let visible = state.layout.keepInMenuBar(item.id)
            do {
                try await state.operations.place(item, leftOf: !visible, boundary: { self.spacerFrame() })
                if visible { hiddenIDs.remove(item.id) }
                else { hiddenIDs.insert(item.id) }
                events.append(["id": item.id, "visible": visible, "result": "placed"])
            } catch {
                state.visibility[item.id] = .failed(error.localizedDescription)
                events.append(["id": item.id, "error": error.localizedDescription])
            }
        }
        spacer.length = hiddenIDs.isEmpty ? 12 : 10_000
        try? await Task.sleep(for: .milliseconds(200))
        for item in targets {
            if case .failed = state.visibility[item.id] { continue }
            guard let frame = state.operations.currentFrame(item) else {
                state.visibility[item.id] = .failed("图标已退出或窗口改变，无法确认显示结果")
                continue
            }
            let visible = state.operations.isVisible(frame)
            let expected = state.layout.keepInMenuBar(item.id)
            state.visibility[item.id] = visible == expected ? (visible ? .visible : .hidden) : .failed("系统未确认本次显示偏好已生效")
            events.append(["id": item.id, "after": NSStringFromRect(frame), "visible": visible])
        }
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        pendingIDs.removeAll()
        needsFullApply = false
        observed.removeAll()
        spacerWindowID = nil
        if let spacer { NSStatusBar.system.removeStatusItem(spacer) }
        spacer = nil
        state.visibility.removeAll()
    }

    private func apply() async {
        guard state.trusted else { return }
        state.working = true
        defer { state.working = false; writeDiagnostics() }
        for item in state.items { state.visibility[item.id] = .applying }
        events = [["scope": "all"]]
        // Recreate after releasing the old allocation. macOS 26 can retain the off-screen
        // button origin when only shrinking a very wide, titleless status item in place.
        if let spacer { NSStatusBar.system.removeStatusItem(spacer) }
        spacer = nil
        spacerWindowID = nil
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        spacer = NSStatusBar.system.statusItem(withLength: 12)
        spacer?.button?.title = ""
        hiddenIDs.removeAll()
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        trackSpacerWindow()
        guard let spacer, let boundary = spacerFrame() else { return }
        events.append(["boundary": NSStringFromRect(boundary), "entrances": entrances().compactMap(Self.frame).map(NSStringFromRect)])
        guard entrances().allSatisfy({ item in
            guard let frame = Self.frame(item) else { return false }
            return frame.minX >= boundary.maxX - 2
        }) else {
            self.spacer?.length = 0
            for item in state.items where !state.layout.keepInMenuBar(item.id) {
                state.visibility[item.id] = .failed("分组入口位置无法安全保护，原图标未隐藏")
            }
            return
        }
        var canHide = true
        // Restore retained icons first, so hiding cannot accidentally cover a visible preference.
        let ordered = state.items.sorted { state.layout.keepInMenuBar($0.id) && !state.layout.keepInMenuBar($1.id) }
        for item in ordered {
            if Task.isCancelled { self.spacer?.length = 0; return }
            let visible = state.layout.keepInMenuBar(item.id)
            state.visibility[item.id] = .applying
            do {
                try await state.operations.place(item, leftOf: !visible, boundary: { self.spacerFrame() })
                let current = state.operations.currentFrame(item)
                events.append(["id": item.id, "visible": visible, "frame": current.map(NSStringFromRect) ?? "missing", "result": "placed"])
                if visible { state.visibility[item.id] = .visible }
                else { hiddenIDs.insert(item.id) }
            } catch {
                let current = state.operations.currentFrame(item)
                events.append(["id": item.id, "visible": visible, "frame": current.map(NSStringFromRect) ?? "missing", "error": error.localizedDescription])
                state.visibility[item.id] = .failed(error.localizedDescription)
                if visible, let current, let edge = spacerFrame(), current.minX < edge.maxX - 2 { canHide = false }
            }
        }
        if canHide && !hiddenIDs.isEmpty {
            spacer.length = 10_000
            try? await Task.sleep(for: .milliseconds(200))
            for item in state.items where hiddenIDs.contains(item.id) {
                let frame = state.operations.currentFrame(item)
                let hidden = frame.map { !state.operations.isVisible($0) } ?? false
                state.visibility[item.id] = hidden ? .hidden : .failed("图标位置已调整，但系统仍显示原图标")
                events.append(["id": item.id, "after": frame.map(NSStringFromRect) ?? "missing", "hidden": hidden])
            }
        } else {
            spacer.length = 0
            for id in hiddenIDs { state.visibility[id] = .failed("部分常驻图标未能恢复，为避免误隐藏已取消此次隐藏") }
            hiddenIDs.removeAll()
        }
    }

    private func writeDiagnostics() {
        let url = state.repository.url.deletingLastPathComponent().appendingPathComponent("visibility-diagnostics.json")
        guard let data = try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
