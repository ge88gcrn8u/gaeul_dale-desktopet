import AppKit

class PetWindow: NSWindow {

    private var petView: PetView!

    /// Normal level: just above the desktop wallpaper (behind app windows).
    private let normalLevel: NSWindow.Level

    /// Level while a reminder rings: above all normal windows (front of every
    /// app / space) so DAL-E's jump is impossible to miss.
    private let reminderLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)

    init(contentRect: NSRect) {
        normalLevel = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        configure()
        setupView()
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = normalLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = false
        isMovable = false
    }

    // MARK: - Reminder: front of all windows

    /// Bring DAL-E above every window (used when a reminder rings).
    func raiseForReminder() {
        level = reminderLevel
        orderFrontRegardless()
    }

    /// Put DAL-E back behind app windows.
    func restoreLevel() {
        level = normalLevel
    }

    private func setupView() {
        guard let cv = contentView else { return }
        petView = PetView(frame: cv.bounds)
        petView.autoresizingMask = [.width, .height]
        petView.wantsLayer = true
        petView.layer?.backgroundColor = NSColor.clear.cgColor
        cv.addSubview(petView)
    }
}
