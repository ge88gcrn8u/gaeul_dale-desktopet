import AppKit

class PetWindow: NSWindow {

    private var petView: PetView!

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        configure()
        setupView()
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = false
        isMovable = false
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
