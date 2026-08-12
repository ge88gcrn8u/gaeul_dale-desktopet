import SpriteKit

/// Loads the real squirrel image from bundle Resources.
class SquirrelNode: SKNode {

    let wholeNode = SKNode()

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
    }

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
