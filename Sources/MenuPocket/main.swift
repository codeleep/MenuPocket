import AppKit
import SwiftUI
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var control: NSStatusItem!
    private var groups: [String: NSStatusItem] = [:]
    private var displayedGroups: [IconGroup] = []
    private var window: NSWindow!
    private let quickPopover = NSPopover()
    private var quickGroupID: String?
    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let matches = NSRunningApplication.runningApplications(withBundleIdentifier: "local.codeleep.MenuPocket")
        if matches.count > 1 {
            matches.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?.activate(options: [])
            NSApp.terminate(nil)
            return
        }
        control = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        control.autosaveName = "MenuPocket.All"
        control.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "全部图标")
        control.button?.toolTip = "MenuPocket · 全部图标（⌃⌥⌘B）"
        control.button?.target = self
        control.button?.action = #selector(allClicked)
        control.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        rebuildGroups()
        makeWindow()
        quickPopover.behavior = .transient
        quickPopover.animates = false
        state.layoutChanged = { [weak self] in
            self?.rebuildGroups()
        }
        state.activateItem = { [weak self] item, right in await self?.activate(item, right: right) }
        registerShortcuts()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appsChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appsChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.window.isVisible || self.quickPopover.isShown else { return }
                self.state.refresh()
            }
        }
        state.refresh()
        // Startup/reopen is an explicit management entry; status-item clicks use only the popover.
        showSettings(group: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(group: nil)
        return true
    }

    private func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 950, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MenuPocket · 管理与设置"
        window.contentView = NSHostingView(rootView: PocketView(state: state))
        window.minSize = NSSize(width: 840, height: 560)
        window.isReleasedWhenClosed = false
        window.center()
    }

    private func rebuildGroups() {
        let visible = state.layout.groups.filter { !$0.hidden }
        let displayed = visible
        guard displayed != displayedGroups else { return }
        if displayed.map(\.id) == displayedGroups.map(\.id) {
            displayedGroups = displayed
            for group in displayed {
                groups[group.id]?.button?.title = String(group.name.prefix(6))
                groups[group.id]?.button?.toolTip = "\(group.name) · 点击查看组内图标"
            }
            return
        }
        quickPopover.close()
        displayedGroups = displayed
        // Recreate in the requested order. Restoring per-item system autosave positions
        // would silently override the user's newly chosen group order.
        for item in groups.values { NSStatusBar.system.removeStatusItem(item) }
        groups.removeAll()
        for group in displayed.reversed() {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            groups[group.id] = item
            item.button?.title = String(group.name.prefix(6))
            item.button?.identifier = NSUserInterfaceItemIdentifier(group.id)
            item.button?.toolTip = "\(group.name) · 点击查看组内图标"
            item.button?.target = self
            item.button?.action = #selector(groupClicked(_:))
        }
        control?.button?.toolTip = "MenuPocket · 全部图标（⌃⌥⌘B）"
    }

    @objc private func groupClicked(_ button: NSStatusBarButton) {
        showQuickPanel(group: button.identifier?.rawValue, anchor: button)
    }

    @objc private func allClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            quickPopover.close()
            let menu = NSMenu()
            let all = menu.addItem(withTitle: "管理与设置…", action: #selector(openSettings), keyEquivalent: "")
            all.target = self
            menu.addItem(.separator())
            let quit = menu.addItem(withTitle: "退出 MenuPocket", action: #selector(self.quit), keyEquivalent: "")
            quit.target = self
            control.menu = menu
            control.button?.performClick(nil)
            control.menu = nil
        } else { showAll() }
    }

    @objc func showAll() {
        guard let button = control.button else { return }
        showQuickPanel(group: nil, anchor: button)
    }

    @objc private func openSettings() { showSettings(group: nil) }

    private func showQuickPanel(group: String?, anchor: NSStatusBarButton, toggle: Bool = true) {
        if toggle && quickPopover.isShown && quickGroupID == group {
            quickPopover.performClose(nil)
            return
        }
        quickPopover.close()
        quickGroupID = group
        let view = QuickPanel(state: state, groupID: group) { [weak self] in
            guard let self else { return }
            self.showSettings(group: group)
            if !self.state.trusted { self.state.showingPermissions = true }
        }
        let host = NSHostingController(rootView: view)
        quickPopover.contentViewController = host
        quickPopover.contentSize = host.view.fittingSize
        quickPopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        quickPopover.contentViewController?.view.window?.makeKey()
        state.refresh()
    }

    private func showSettings(group: String?) {
        quickPopover.close()
        state.selectedGroup = group
        state.search = ""
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        state.refresh()
    }

    private func activate(_ item: MenuIcon, right: Bool) async {
        guard !state.working else { return }
        state.error = ""
        state.working = true
        defer { state.working = false }
        let fromQuickPanel = quickPopover.isShown
        let sourceGroup = quickGroupID
        quickPopover.close()
        if !fromQuickPanel { window.orderOut(nil) }
        do {
            // First use the owning app's accessibility action, which also works for some off-screen items.
            if item.element != nil && item.actions.contains(right ? kAXShowMenuAction : kAXPressAction) {
                let acknowledged = try await state.operations.activate(item, rightClick: right)
                state.message = acknowledged ? "原应用已接受操作请求。" : "已向原图标发送操作；应用未确认完成，请检查原菜单。"
                return
            }
            let acknowledged = try await state.operations.activate(item, rightClick: right)
            state.message = acknowledged ? "原应用已接受操作请求。" : "已向原图标发送操作；应用未确认完成，请检查原菜单。"
        } catch {
            state.error = "\(item.name)：\(error.localizedDescription)"
            if fromQuickPanel, let anchor = (sourceGroup.flatMap { groups[$0]?.button } ?? control.button) {
                showQuickPanel(group: sourceGroup, anchor: anchor, toggle: false)
            } else { showSettings(group: state.selectedGroup) }
        }
    }

    @objc private func appsChanged() { state.refresh() }

    @objc private func screensChanged() {
        quickPopover.close()
        rebuildGroups()
        state.refresh()
        state.message = "显示器布局已变化，已刷新分组入口。"
    }

    private func registerShortcuts() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(pointer).takeUnretainedValue()
            MainActor.assumeIsolated {
                if id.id == 1 { delegate.showAll() }
            }
            return noErr
        }, 1, &spec, context, &eventHandler)
        guard result == noErr else { state.error = "全局快捷键监听注册失败。"; return }
        for (key, id) in [(kVK_ANSI_B, UInt32(1))] {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey | cmdKey),
                                            EventHotKeyID(signature: 0x4D504B54, id: id), GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference { hotKeys.append(reference) }
            else { state.error = "快捷键 ⌃⌥⌘B 被占用；仍可通过菜单栏或重新打开应用访问。" }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        for key in hotKeys { UnregisterEventHotKey(key) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        for item in groups.values { NSStatusBar.system.removeStatusItem(item) }
        if let control { NSStatusBar.system.removeStatusItem(control) }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
