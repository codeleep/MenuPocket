import AppKit
import ScreenCaptureKit

@MainActor
enum ThumbnailService {
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
        if !CGPreflightScreenCaptureAccess(), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    static func refresh(state: AppState) async {
        guard CGPreflightScreenCaptureAccess() else { state.error = "图标图片预览需要屏幕录制权限；不授权仍可使用应用图标。"; return }
        guard #available(macOS 14.0, *) else { state.error = "原图标图片预览需要 macOS 14 或更新版本。"; return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            var updated: [String: NSImage] = [:]
            for item in state.items {
                guard let id = item.windowID, let window = content.windows.first(where: { $0.windowID == id }),
                      window.frame.width > 0, window.frame.width < 600, window.frame.height <= 64 else { continue }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.width = max(1, Int(window.frame.width * 2))
                config.height = max(1, Int(window.frame.height * 2))
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true
                // Capture only the identified status-item window; no desktop or app-window fallback.
                if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                    updated[item.id] = NSImage(cgImage: image, size: window.frame.size)
                }
            }
            state.thumbnails = updated
            state.message = "已获取 \(updated.count) 个原图标预览；其他项目使用应用图标或系统符号。"
        } catch { state.error = "图标预览读取失败：\(error.localizedDescription)" }
    }
}
