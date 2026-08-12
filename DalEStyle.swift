import AppKit

/// Shared DAL-E visual language: warm autumn palette + playful rounded font.
enum DalEStyle {

    // Colors
    static let creamBackground = NSColor(calibratedRed: 1.00, green: 0.96, blue: 0.90, alpha: 1)
    static let cardBackground  = NSColor(calibratedRed: 1.00, green: 0.98, blue: 0.94, alpha: 1)
    static let bubbleBackground = NSColor(calibratedRed: 1.00, green: 0.97, blue: 0.92, alpha: 1)
    static let warmBorder      = NSColor(calibratedRed: 0.82, green: 0.58, blue: 0.27, alpha: 1)
    static let warmShadow      = NSColor(calibratedRed: 0.45, green: 0.30, blue: 0.12, alpha: 0.12)
    static let autumnOrange    = NSColor(calibratedRed: 0.85, green: 0.53, blue: 0.22, alpha: 1)
    static let textColor       = NSColor(calibratedRed: 0.25, green: 0.18, blue: 0.10, alpha: 1)
    static let subtextColor    = NSColor(calibratedRed: 0.48, green: 0.38, blue: 0.27, alpha: 1)
    static let softGreen       = NSColor(calibratedRed: 0.42, green: 0.62, blue: 0.40, alpha: 1)

    /// Softer, playful rounded font (falls back gracefully for Korean/Chinese glyphs).
    static func roundedFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: descriptor, size: size) ?? base
        }
        return base
    }

    /// Rounded-corner card / bubble view helper.
    static func roundedView(cornerRadius: CGFloat, fill: NSColor, border: NSColor? = nil, lineWidth: CGFloat = 1) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.backgroundColor = fill.cgColor
        if let border {
            v.layer?.borderColor = border.cgColor
            v.layer?.borderWidth = lineWidth
        }
        return v
    }
}
