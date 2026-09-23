import AppKit
import ApplicationServices

enum OperationFailure: LocalizedError {
    case permission, disappeared, busy, notVisible, unsupported, actionFailed(Int32)
    var errorDescription: String? {
        switch self {
        case .permission: return "需要辅助功能权限才能操作原图标。请在权限页开启后重试。"
        case .disappeared: return "该图标已退出或改变，请刷新列表后重试。"
        case .busy: return "请松开鼠标和修饰键后重试。"
        case .notVisible: return "原图标位于屏幕外或刘海下，且没有可用的辅助功能动作。请按住 ⌘ 将原图标移到可见位置后重试。"
        case .unsupported: return "该图标未提供所需操作，无法保证与原图标行为一致。"
        case .actionFailed(let code): return "原应用没有确认操作（辅助功能错误 \(code)）。请检查是否已打开菜单，勿连续重复点击。"
        }
    }
}

@MainActor
final class ItemOperator {
    private(set) var busy = false

    func currentFrame(_ item: MenuIcon) -> CGRect? {
        if let id = item.windowID, let frame = MenuScanner.windows().first(where: { $0.id == id })?.frame { return frame }
        if let element = item.element { return Accessibility.frame(element) }
        return nil
    }

    func isVisible(_ frame: CGRect) -> Bool {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.contains { screen in
            let rect = NSRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            guard screen.frame.contains(center) else { return false }
            if screen.safeAreaInsets.top > 0,
               let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                return left.contains(center) || right.contains(center)
            }
            return true
        }
    }

    /// False means delivery was attempted but the application did not acknowledge completion.
    /// An AX timeout can occur while a native menu is tracking; never immediately steal its focus.
    func activate(_ item: MenuIcon, rightClick: Bool) async throws -> Bool {
        guard AXIsProcessTrusted() else { throw OperationFailure.permission }
        guard !busy else { throw OperationFailure.busy }
        guard NSRunningApplication(processIdentifier: item.pid)?.isTerminated == false else { throw OperationFailure.disappeared }
        busy = true
        defer { busy = false }
        let action = rightClick ? kAXShowMenuAction : kAXPressAction
        if let element = item.element, item.actions.contains(action) {
            // AX actions target the element itself and do not rely on its on-screen location.
            AXUIElementSetMessagingTimeout(element, 1)
            let status = AXUIElementPerformAction(element, action as CFString)
            if status == .cannotComplete { return false }
            guard status == .success else { throw OperationFailure.actionFailed(status.rawValue) }
            return true
        }
        guard let frame = currentFrame(item), let id = item.windowID else { throw OperationFailure.disappeared }
        guard isVisible(frame) else { throw OperationFailure.notVisible }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let source = CGEventSource(stateID: .privateState)
        let downType: CGEventType = rightClick ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = rightClick ? .rightMouseUp : .leftMouseUp
        guard let down = event(downType, point: point, item: item, windowID: id, source: source),
              let up = event(upType, point: point, item: item, windowID: id, source: source) else { throw OperationFailure.unsupported }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.postToPid(item.pid)
        try? await Task.sleep(for: .milliseconds(60))
        up.postToPid(item.pid)
        return false
    }

    private func event(_ type: CGEventType, point: CGPoint, item: MenuIcon, windowID: CGWindowID, source: CGEventSource?) -> CGEvent? {
        let button: CGMouseButton = (type == .rightMouseDown || type == .rightMouseUp) ? .right : .left
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { return nil }
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(item.pid))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        if let field = CGEventField(rawValue: 0x33) { event.setIntegerValueField(field, value: Int64(windowID)) }
        return event
    }
}
