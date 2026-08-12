import AppKit
import ServiceManagement

/// Manages macOS Login Item registration using SMAppService (macOS 13+).
class LoginItemManager {

    static let shared = LoginItemManager()

    private init() {}

    /// Whether the app is currently registered as a login item.
    var isLoginItemEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // Fallback: check if our LaunchAgent exists
            return legacyLoginItemEnabled
        }
    }

    /// Toggle login item registration.
    func toggle() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "开机启动设置失败"
                alert.informativeText = "无法修改登录项设置：\(error.localizedDescription)\n\n请尝试将 App 拖入 系统设置 → 通用 → 登录项。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "确定")
                alert.runModal()
            }
        } else {
            toggleLegacyLoginItem()
        }
    }

    // MARK: - Legacy (pre-macOS 13)

    private var legacyLaunchAgentURL: URL {
        let lib = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        return lib.appendingPathComponent("com.squirrelpet.dale.plist")
    }

    private var legacyLoginItemEnabled: Bool {
        return FileManager.default.fileExists(atPath: legacyLaunchAgentURL.path)
    }

    private func toggleLegacyLoginItem() {
        if legacyLoginItemEnabled {
            try? FileManager.default.removeItem(at: legacyLaunchAgentURL)
        } else {
            let plist: [String: Any] = [
                "Label": "com.squirrelpet.dale",
                "ProgramArguments": [Bundle.main.executablePath ?? ""],
                "RunAtLoad": true,
                "KeepAlive": false,
            ]
            try? FileManager.default.createDirectory(
                at: legacyLaunchAgentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            (plist as NSDictionary).write(to: legacyLaunchAgentURL, atomically: true)
        }

        let alert = NSAlert()
        alert.messageText = legacyLoginItemEnabled ? "已移除开机启动" : "已添加开机启动"
        alert.informativeText = "需要重新登录才能生效。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}
