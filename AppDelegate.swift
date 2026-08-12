import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var petWindow: PetWindow?
    var chatWindow: ChatWindow?
    var gardenWindow: ReminderGardenWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let sf = screen.visibleFrame
        let w: CGFloat = 200, h: CGFloat = 250

        // Restore saved position or default to lower-right
        var x = sf.maxX - w - 80, y = sf.minY + 100
        if let saved = UserDefaults.standard.string(forKey: "PetWindowOrigin") {
            let parts = saved.split(separator: ",")
            if parts.count == 2, let sx = Double(parts[0]), let sy = Double(parts[1]) {
                x = max(sf.minX, min(CGFloat(sx), sf.maxX - w))
                y = max(sf.minY, min(CGFloat(sy), sf.maxY - h))
            }
        }

        petWindow = PetWindow(contentRect: NSRect(x: x, y: y, width: w, height: h))
        petWindow?.makeKeyAndOrderFront(nil)
        petWindow?.orderFrontRegardless()

        // Reminder pipeline: scheduler + native notifications.
        ReminderScheduler.shared.start()
        ReminderNotifications.shared.requestPermissionIfNeeded()
        ReminderNotifications.shared.refreshAll()

        // Route DAL-E's spoken messages into the chat window log.
        EncouragementDialogue.shared.onMessage = { [weak self] situation in
            self?.chatWindow?.post(situation: situation)
        }

    }

    func applicationWillTerminate(_ notification: Notification) {
        if let w = petWindow {
            let o = w.frame.origin
            UserDefaults.standard.set("\(o.x),\(o.y)", forKey: "PetWindowOrigin")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { petWindow?.makeKeyAndOrderFront(nil) }
        return true
    }

    // MARK: - Companion windows

    func openChat() {
        if chatWindow == nil { chatWindow = ChatWindow() }
        chatWindow?.showAndFocus()
    }

    func openGarden() {
        if gardenWindow == nil { gardenWindow = ReminderGardenWindow() }
        gardenWindow?.showAndFocus()
    }
}
