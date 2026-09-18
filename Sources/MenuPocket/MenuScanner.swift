import AppKit
import ApplicationServices

enum Accessibility {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func text(_ element: AXUIElement, _ attribute: String) -> String {
        value(element, attribute) as? String ?? ""
    }

    static func children(_ element: AXUIElement, _ attribute: String = kAXChildrenAttribute) -> [AXUIElement] {
        value(element, attribute) as? [AXUIElement] ?? []
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = value(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}

struct StatusWindow {
    var id: CGWindowID
    var pid: pid_t
    var title: String
    var owner: String
    var frame: CGRect
}

final class MenuScanner {
    static func windows() -> [StatusWindow] {
        let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        return rows.compactMap { row in
            guard let level = row[kCGWindowLayer as String] as? Int, level == statusLevel,
                  let raw = row[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: raw as CFDictionary), frame.height > 0, frame.height <= 64,
                  let pid = row[kCGWindowOwnerPID as String] as? Int,
                  let id = row[kCGWindowNumber as String] as? UInt32 else { return nil }
            return StatusWindow(id: id, pid: pid_t(pid), title: row[kCGWindowName as String] as? String ?? "",
                                owner: row[kCGWindowOwnerName as String] as? String ?? "应用", frame: frame)
        }
    }

    func scan() -> [MenuIcon] {
        // Without AX consent, window-server decorations cannot be reliably distinguished
        // from real menu extras (especially ControlCenter glass windows on macOS 26).
        guard AXIsProcessTrusted() else { return [] }
        let windows = Self.windows()
        // On macOS 26 the rendered window can belong to ControlCenter, not the source app.
        // Resolve its accessible owner by hit-testing the real window, instead of guessing by PID.
        let system = AXUIElementCreateSystemWide()
        var hits: [(window: StatusWindow, element: AXUIElement, pid: pid_t, identifier: String)] = []
        for window in windows {
            var hit: AXUIElement?
            if AXUIElementCopyElementAtPosition(system, Float(window.frame.midX), Float(window.frame.midY), &hit) == .success,
               let hit, Accessibility.text(hit, kAXRoleAttribute) == kAXMenuBarItemRole {
                var pid: pid_t = 0
                AXUIElementGetPid(hit, &pid)
                hits.append((window, hit, pid, Accessibility.text(hit, kAXIdentifierAttribute)))
            }
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: [MenuIcon] = []
        var usedWindows = Set<CGWindowID>()
        var ownersWithExtras = Set<pid_t>()
        let trusted = AXIsProcessTrusted()
        var diagnostics: [[String: Any]] = []
        // Prefer a source application's AX representation over its anonymous host proxy.
        let applications = NSWorkspace.shared.runningApplications.sorted {
            let a = $0.bundleIdentifier == "com.apple.controlcenter"
            let b = $1.bundleIdentifier == "com.apple.controlcenter"
            return a == b ? $0.processIdentifier < $1.processIdentifier : !a
        }
        for app in applications where app.processIdentifier != ownPID {
            let pid = app.processIdentifier
            let owned = windows.filter { $0.pid == pid }
            guard trusted else { continue }
            let root = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(root, 0.25)
            var bars: [AXUIElement] = []
            if let extra = Accessibility.value(root, kAXExtrasMenuBarAttribute), CFGetTypeID(extra) == AXUIElementGetTypeID() {
                bars.append(extra as! AXUIElement)
            }
            // ControlCenter/SystemUIServer sometimes expose their extras through AXChildren.
            if bars.isEmpty && (!owned.isEmpty || app.bundleIdentifier == "com.apple.controlcenter" || app.bundleIdentifier == "com.apple.systemuiserver") {
                bars = Accessibility.children(root).filter { Accessibility.text($0, kAXRoleAttribute) == kAXMenuBarRole }
            }
            let bundleID = app.bundleIdentifier ?? app.bundleURL?.path ?? app.localizedName ?? "pid:\(pid)"
            var occurrences: [String: Int] = [:]
            for bar in bars {
                for element in Accessibility.children(bar) {
                    let role = Accessibility.text(element, kAXRoleAttribute)
                    guard role == kAXMenuBarItemRole || role == kAXButtonRole else { continue }
                    guard let frame = Accessibility.frame(element), frame.width > 0, frame.height > 0, frame.height <= 64 else { continue }
                    ownersWithExtras.insert(pid)
                    let identifier = Accessibility.text(element, kAXIdentifierAttribute)
                    let title = Accessibility.text(element, kAXTitleAttribute)
                    let description = Accessibility.text(element, kAXDescriptionAttribute)
                    let help = Accessibility.text(element, kAXHelpAttribute)
                    // Count identities before deduplication so removing a hosted proxy
                    // does not shift the saved identities of the remaining anonymous items.
                    let key = !identifier.isEmpty ? identifier : "item"
                    let ordinal = occurrences[key, default: 0]
                    occurrences[key] = ordinal + 1
                    let identity = "\(bundleID)|\(key)|\(ordinal)"
                    let candidate = owned.min { Self.distance($0.frame, frame) < Self.distance($1.frame, frame) }
                    let ownerHits = hits.filter { $0.pid == pid }
                    let exact = ownerHits.first { CFEqual($0.element, element) || (!identifier.isEmpty && $0.identifier == identifier) }
                    let match = exact?.window ?? candidate.flatMap { Self.distance($0.frame, frame) < 8 ? $0 : nil }
                    if let match, usedWindows.contains(match.id) {
                        if bundleID == "com.apple.controlcenter", identifier.isEmpty,
                           let index = result.firstIndex(where: { $0.windowID == match.id }),
                           result[index].bundleID != bundleID {
                            result[index].legacyIDs.append(identity)
                        }
                        diagnostics.append(["source": bundleID, "window": match.id, "reason": "duplicate window",
                                            "representedBy": result.first(where: { $0.windowID == match.id })?.bundleID ?? "unknown"])
                        continue
                    }
                    if let match { usedWindows.insert(match.id) }
                    let appName = app.localizedName ?? "应用"
                    let candidates = [title, description, help, match?.title ?? ""]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    let anonymousSystemItem = bundleID == "com.apple.controlcenter" && identifier.isEmpty
                    let hostNames = Set([appName, "控制中心", "Control Center", "ControlCenter"])
                    let meaningfulName = candidates.first { !$0.isEmpty && (!anonymousSystemItem || !hostNames.contains($0)) }
                    let unresolved = anonymousSystemItem && meaningfulName == nil
                    let name = meaningfulName ?? (unresolved ? "未识别系统项目 \(ordinal + 1)" : appName)
                    var actions: CFArray?
                    AXUIElementCopyActionNames(element, &actions)
                    result.append(MenuIcon(id: identity, pid: pid, bundleID: bundleID,
                        name: name, appName: appName, windowID: match?.id, frame: match?.frame ?? frame, element: element,
                        actions: actions as? [String] ?? [],
                        image: unresolved ? NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: name)! : Self.icon(for: app, name: name),
                        isSystem: bundleID.hasPrefix("com.apple.")))
                }
            }
        }
        // Keep windows that have no AX representation visible as individually labelled entries.
        // They are never advertised as AX-clickable, and remain subject to geometric verification.
        var ordinals: [String: Int] = [:]
        for window in windows.sorted(by: { $0.id < $1.id }) where window.pid != ownPID && !usedWindows.contains(window.id) && !ownersWithExtras.contains(window.pid) && !window.title.isEmpty && window.frame.width < 600 {
            guard let app = NSRunningApplication(processIdentifier: window.pid), app.bundleIdentifier != "com.apple.WindowManager" else { continue }
            let bundleID = app.bundleIdentifier ?? app.bundleURL?.path ?? window.owner
            let key = "\(bundleID)|window:\(window.title)"
            let ordinal = ordinals[key, default: 0]
            ordinals[key] = ordinal + 1
            let name = window.title.isEmpty ? window.owner : window.title
            result.append(MenuIcon(id: "\(key)|\(ordinal)", pid: window.pid, bundleID: bundleID, name: name,
                appName: app.localizedName ?? window.owner, windowID: window.id, frame: window.frame,
                element: nil, actions: [], image: Self.icon(for: app, name: name), isSystem: bundleID.hasPrefix("com.apple.")))
        }
        if let data = try? JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys]) {
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MenuPocket/scan-diagnostics.json")
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return result.sorted { $0.frame.minX < $1.frame.minX }
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width)
    }

    private static func icon(for app: NSRunningApplication, name: String) -> NSImage {
        let lower = name.lowercased()
        let symbols = [("wi-fi", "wifi"), ("wifi", "wifi"), ("蓝牙", "antenna.radiowaves.left.and.right"),
                       ("bluetooth", "antenna.radiowaves.left.and.right"), ("sound", "speaker.wave.2"),
                       ("音量", "speaker.wave.2"), ("声音", "speaker.wave.2"), ("battery", "battery.100"),
                       ("电池", "battery.100"), ("control center", "switch.2"), ("控制中心", "switch.2")]
        if app.bundleIdentifier?.hasPrefix("com.apple.") == true,
           let symbol = symbols.first(where: { lower.contains($0.0) })?.1,
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: name) { return image }
        return app.icon ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: name)!
    }
}
