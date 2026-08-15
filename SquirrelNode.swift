import SpriteKit

/// Loads the real squirrel image from bundle Resources.
class SquirrelNode: SKNode {

    let wholeNode = SKNode()

    /// Eyelid overlay used for the left-eye blink (hidden by default).
    private(set) var eyelidLeft: SKSpriteNode?

    override init() {
        super.init()
        setupSprite()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupSprite() {
        let image = loadImage()
        let texture = SKTexture(image: image)
        let sprite = SKSpriteNode(texture: texture)
        let targetHeight: CGFloat = 150
        sprite.setScale(targetHeight / image.size.height)
        wholeNode.addChild(sprite)
        addChild(wholeNode)
        attachLeftEyelid(to: sprite, imageSize: image.size)
    }

    // MARK: - Left-eye blink (eyelid overlay)

    /// Positions the fur-coloured eyelid over the squirrel's left eye and wires
    /// it up. All coordinates are in squirrel.png pixels (1386×1389) and are
    /// converted to sprite-local points (sprite centre = 0,0, y up).
    private func attachLeftEyelid(to sprite: SKSpriteNode, imageSize: NSSize) {
        guard let lidImage = loadEyelidImage() else { return }
        let lid = SKSpriteNode(texture: SKTexture(image: lidImage))
        lid.size = CGSize(width: lidImage.size.width, height: lidImage.size.height)

        // Anchor at top-centre so `scaleY` closes the eye downward from the top.
        lid.anchorPoint = CGPoint(x: 0.5, y: 1.0)

        // The eyelid asset covers image pixels x 207–586, y 689–927.
        let topLeftX: CGFloat = 207
        let topY: CGFloat = 689
        let centreX = topLeftX + lidImage.size.width / 2
        lid.position = CGPoint(x: centreX - imageSize.width / 2,
                               y: imageSize.height / 2 - topY)

        lid.zPosition = 10
        lid.yScale = 0.01      // collapsed to a sliver at the eye's top…
        lid.alpha = 0          // …and fully invisible until a blink plays
        sprite.addChild(lid)
        eyelidLeft = lid
    }

    /// Plays a real left-eye blink: the eyelid slides down over the eye, holds
    /// briefly, then slides back up. `completion` fires once the lid is open again.
    func blinkLeftEye(completion: (() -> Void)? = nil) {
        guard let lid = eyelidLeft else {
            completion?()
            return
        }
        lid.removeAllActions()

        // Lazy, gentle blink: the eyelid slowly eases down, rests for a while,
        // then slowly eases back up (~1 second total).
        let closeScale = SKAction.scaleY(to: 1.0, duration: 0.28)
        closeScale.timingMode = .easeInEaseOut
        let openScale = SKAction.scaleY(to: 0.01, duration: 0.32)
        openScale.timingMode = .easeInEaseOut
        let close = SKAction.group([
            closeScale,
            SKAction.fadeAlpha(to: 1.0, duration: 0.18),
        ])
        let open = SKAction.group([
            openScale,
            SKAction.fadeAlpha(to: 0.0, duration: 0.20),
        ])
        lid.run(SKAction.sequence([
            close,
            SKAction.wait(forDuration: 0.45),
            open,
            SKAction.run { completion?() },
        ]))
    }

    /// Instantly hides the eyelid and cancels any in-flight blink. Called when a
    /// bigger animation (reminder jump / hug / pause) starts so the blink never
    /// overlaps or leaves a half-closed eyelid behind.
    func resetLeftEyelid() {
        guard let lid = eyelidLeft else { return }
        lid.removeAllActions()
        lid.yScale = 0.01
        lid.alpha = 0
    }

    // MARK: - Assets

    private func loadImage() -> NSImage {
        // Try bundle resources first
        if let img = NSImage(named: "squirrel") { return img }
        for ext in ["png", "PNG", "jpg", "jpeg"] {
            if let path = Bundle.main.path(forResource: "squirrel", ofType: ext),
               let img = NSImage(contentsOfFile: path) { return img }
        }
        // Try adjacent to executable
        let dir = (Bundle.main.executablePath as NSString?)?.deletingLastPathComponent ?? "."
        for name in ["squirrel.png", "squirrel.PNG", "squirrel.jpg"] {
            if let img = NSImage(contentsOfFile: dir + "/" + name) { return img }
        }
        return SquirrelNode.placeholder()
    }

    private func loadEyelidImage() -> NSImage? {
        // Try bundle resources first
        if let img = NSImage(named: "eyelid") { return img }
        for ext in ["png", "PNG"] {
            if let path = Bundle.main.path(forResource: "eyelid", ofType: ext),
               let img = NSImage(contentsOfFile: path) { return img }
        }
        // Try adjacent to executable
        let dir = (Bundle.main.executablePath as NSString?)?.deletingLastPathComponent ?? "."
        for name in ["eyelid.png", "eyelid.PNG"] {
            if let img = NSImage(contentsOfFile: dir + "/" + name) { return img }
        }
        return nil
    }

    private static func placeholder() -> NSImage {
        let s = NSSize(width: 150, height: 150)
        let img = NSImage(size: s)
        img.lockFocus()
        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: NSRect(x: 20, y: 20, width: 110, height: 110)).fill()
        ("🐿️" as NSString).draw(at: NSPoint(x: 35, y: 55), withAttributes: [.font: NSFont.systemFont(ofSize: 48)])
        img.unlockFocus()
        return img
    }
}
