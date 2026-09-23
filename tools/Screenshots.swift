import AppKit
import SwiftUI

/// Render real application views with isolated, public fixture data. No AX actions run.
@main
struct ScreenshotExport {
    @MainActor
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .aqua)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/images")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let state = AppState(repository: LayoutRepository(url: sandbox.appendingPathComponent("layout.json")))
        state.trusted = true
        state.layout.groups = [
            IconGroup(id: "work", name: "工作", symbol: "briefcase"),
            IconGroup(id: "tools", name: "工具", symbol: "wrench.and.screwdriver"),
            IconGroup(id: "system", name: "系统", symbol: "slider.horizontal.3")
        ]
        let data = [
            ("terminal", "终端", "terminal", "work"),
            ("notes", "备忘录", "note.text", "work"),
            ("calendar", "日历", "calendar", "work"),
            ("downloads", "下载工具", "arrow.down.circle", "tools"),
            ("clipboard", "剪贴板", "doc.on.clipboard", "tools"),
            ("wifi", "Wi-Fi", "wifi", "system"),
            ("battery", "电池", "battery.100", "system"),
            ("clock", "时钟", "clock", "system")
        ]
        for (id, name, symbol, group) in data {
            let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: name)!
            state.items.append(MenuIcon(id: id, pid: 0, bundleID: "demo.\(id)", name: name, appName: name,
                windowID: nil, frame: .zero, element: nil, actions: [], image: icon, isSystem: group == "system"))
            state.layout.move(id, into: group)
        }
        state.message = "示例数据 · 实际支持情况取决于 macOS 和原应用"
        try render(PocketView(state: state), size: NSSize(width: 1060, height: 750),
                   title: "MenuPocket · 管理与设置", to: output.appendingPathComponent("01-management.png"))
        try render(IconSettingsView(state: state, item: state.items[3]), size: NSSize(width: 480, height: 390),
                   title: "MenuPocket · 图标设置", to: output.appendingPathComponent("02-icon-settings.png"))
        try render(QuickPanel(state: state, groupID: "work", openSettings: {}), size: NSSize(width: 360, height: 295),
                   title: "MenuPocket · 分组面板", to: output.appendingPathComponent("03-quick-panel.png"))
        print("Rendered 3 native UI screenshots with isolated demo data: \(output.path)")
    }

    @MainActor
    static func render<Content: View>(_ content: Content, size: NSSize, title: String, to url: URL) throws {
        let scene = VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("演示数据").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).frame(height: 34)
                .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: scene)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
        window.contentView = nil
    }
}
