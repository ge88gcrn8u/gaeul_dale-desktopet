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
        let fresh = makePetView()
        cv.addSubview(fresh)
        petView = fresh
    }

    /// Builds a ready-to-add PetView. The fatal-stall hook lets SpriteKit's
    /// renderer be rebuilt from scratch (fresh SKView) when the watchdog finds
    /// a scene rebuild did not recover rendering after display sleep.
    private func makePetView() -> PetView {
        let v = PetView(frame: contentView?.bounds ?? .zero)
        v.autoresizingMask = [.width, .height]
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.clear.cgColor
        v.onFatalStall = { [weak self] in self?.recreatePetView() }
        return v
    }

    /// SpriteKit's Metal drawable pool can die permanently after display sleep
    /// ("no drawables available"); re-presenting scenes on the same SKView
    /// never recovers. Swap in a brand-new PetView so SpriteKit builds a fresh
    /// renderer / CVDisplayLink, then re-attach the reminder callbacks.
    func recreatePetView() {
        petView?.removeFromSuperview()
        petView = nil
        guard let cv = contentView else { return }
        let fresh = makePetView()
        cv.addSubview(fresh)
        petView = fresh
    }
}
