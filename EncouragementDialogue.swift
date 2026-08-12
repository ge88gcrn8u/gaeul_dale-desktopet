import AppKit
import SpriteKit
import os

/// Fixed encouragement message catalog (Korean preserved exactly as specified,
/// Chinese = matching translation) + a lightweight SpriteKit speech bubble.
///
/// DAL-E stays quiet and calm: event messages are situation-based, while
/// comfort/playful messages are picked randomly (never repeating the previous
/// one) when the user clicks DAL-E or asks for a hug.
final class EncouragementDialogue {

    static let shared = EncouragementDialogue()

    private let log = Logger(subsystem: "com.squirrelpet.dale", category: "Dialogue")

    /// Called whenever a message is spoken, so the chat window can log it too.
    var onMessage: ((Situation) -> Void)?
    /// Called when a warm comfort message is spoken, so the pet can play its
    /// soft "hug" animation.
    var onComfort: (() -> Void)?
    /// Called when a speech bubble starts/stops needing the render loop, so the
    /// animation manager can keep the scene unpaused while it is on screen.
    var onSceneActivity: ((Bool) -> Void)?

    enum Situation {
        // Events
        case appOpen            // 🍂 작은 가을, DAL-E
        case reminderCreated    // 🍁 가을가을한 하루 보내요～
        case reminderCompleted  // 🌰 작은 행복을 하나하나 모아둘게

        // Warm comfort pool
        case comfort            // 🤍 오늘도 포근하게 안아줄게
        case imperfection       // 🌌 비대칭한 선은 Beautiful
        case honesty            // 🌷 내 장점이 뭔지 알아 바로 솔직한 거야
        case slowPace           // 🍂 천천히 가도 괜찮아…
        case smallSteps         // 🌰 작은 걸음도 모이면 멋진 길이 돼
        case goodDay            // ☁️ 오늘 하루도 충분히 잘했어
        case besideYou          // 🐿️ 내가 옆에 있을게…
        case rest               // 🌙 잠깐 쉬어가도 괜찮아

        // Playful pool
        case playful            // 🐿️ 가을가을해~
        case wonder             // 💭 시선 끝은 언제나 Odd
        case joke               // 🫧 두 번 세 번 피곤하게 자꾸 질문하지 마
    }

    private struct Line { let korean: String; let chinese: String }

    private let catalog: [Situation: Line] = [
        .appOpen:           Line(korean: "🍂 작은 가을, DAL-E",                        chinese: "🍂 小小的秋天，DAL-E"),
        .reminderCreated:   Line(korean: "🍁 가을가을한 하루 보내요～",                   chinese: "🍁 度过一个充满秋天气息的一天吧～"),
        .reminderCompleted: Line(korean: "🌰 작은 행복을 하나하나 모아둘게",               chinese: "🌰 把小小的幸福，一颗一颗收藏起来吧"),
        .comfort:           Line(korean: "🤍 오늘도 포근하게 안아줄게",                   chinese: "🤍 今天也会温暖地抱抱你"),
        .playful:           Line(korean: "🐿️ 가을가을해~",                             chinese: "🐿️ 像秋天一样可爱呀～"),
        .wonder:            Line(korean: "💭 시선 끝은 언제나 Odd",                    chinese: "💭 视线的尽头，总是惊奇"),
        .imperfection:      Line(korean: "🌌 비대칭한 선은 Beautiful",                 chinese: "🌌 不对称的线条也很美丽"),
        .joke:              Line(korean: "🫧 두 번 세 번 피곤하게 자꾸 질문하지 마",        chinese: "🫧 别一次又一次地追问\n让人觉得累呀"),
        .honesty:           Line(korean: "🌷 내 장점이 뭔지 알아\n바로 솔직한 거야",        chinese: "🌷 知道我的优点是什么吗\n就是坦率"),
        .slowPace:          Line(korean: "🍂 천천히 가도 괜찮아\n너만의 계절이 있으니까",   chinese: "🍂 慢慢走也没关系\n因为每个人都有属于自己的季节"),
        .smallSteps:        Line(korean: "🌰 작은 걸음도 모이면\n멋진 길이 돼",           chinese: "🌰 小小的脚步积累起来\n也会成为很棒的道路"),
        .goodDay:           Line(korean: "☁️ 오늘 하루도 충분히 잘했어",                 chinese: "☁️ 今天一天，你已经做得很好了"),
        .besideYou:         Line(korean: "🐿️ 내가 옆에 있을게\n너무 서두르지 마",         chinese: "🐿️ 我会陪在你身边\n不要太着急"),
        .rest:              Line(korean: "🌙 잠깐 쉬어가도 괜찮아",                     chinese: "🌙 暂时休息一下也没关系"),
    ]

    /// Warm comforting messages shown on click / hug / long inactivity.
    private let warmPool: [Situation] = [
        .comfort, .imperfection, .honesty,
        .slowPace, .smallSteps, .goodDay, .besideYou, .rest,
    ]

    /// Light playful messages shown after a drag / playful moments.
    private let playfulPool: [Situation] = [.playful, .wonder, .joke]

    private weak var scene: SKScene?
    private weak var squirrel: SquirrelNode?
    private var bubbleNode: SKNode?
    private var lastRandomSituation: Situation?

    func attach(scene: SKScene, squirrel: SquirrelNode) {
        self.scene = scene
        self.squirrel = squirrel
    }

    // MARK: - Triggers

    func say(_ situation: Situation) {
        guard let line = catalog[situation] else { return }
        log.info("💬 say \(String(describing: situation), privacy: .public)")
        onMessage?(situation)
        let style: BubbleStyle = warmPool.contains(situation) ? .comfort : .normal
        showBubble(korean: line.korean, chinese: line.chinese, style: style)
    }

    /// The bilingual text for a situation (used by the chat window).
    func text(for situation: Situation) -> (korean: String, chinese: String)? {
        guard let line = catalog[situation] else { return nil }
        return (line.korean, line.chinese)
    }

    /// A warm random message — different from the previous one each time.
    func sayRandomComfort() {
        var candidates = warmPool.filter { $0 != lastRandomSituation }
        if candidates.isEmpty { candidates = warmPool }
        guard let situation = candidates.randomElement() else { return }
        lastRandomSituation = situation
        onComfort?()
        say(situation)
    }

    /// A playful random message after a drag.
    func sayRandomPlayful() {
        var candidates = playfulPool.filter { $0 != lastRandomSituation }
        if candidates.isEmpty { candidates = playfulPool }
        guard let situation = candidates.randomElement() else { return }
        lastRandomSituation = situation
        say(situation)
    }

    // MARK: - Bubble

    private enum BubbleStyle {
        case normal
        case comfort   // larger, softer, slightly longer
    }

    private struct BubbleMetrics {
        let width: CGFloat
        let height: CGFloat
        let koCenterY: CGFloat
        let zhCenterY: CGFloat
        let tailLength: CGFloat
    }

    private func showBubble(korean: String, chinese: String, style: BubbleStyle) {
        guard let scene = scene, let squirrel = squirrel else { return }
        hideBubble()

        let isComfort = style == .comfort
        let koFont = DalEStyle.roundedFont(size: isComfort ? 15 : 14, weight: .medium)
        let zhFont = DalEStyle.roundedFont(size: isComfort ? 11 : 10.5)
        let padX: CGFloat = isComfort ? 14 : 12
        let padY: CGFloat = isComfort ? 11 : 8
        let gap: CGFloat = 3
        let cornerRadius: CGFloat = isComfort ? 12 : 10
        let lineWidth: CGFloat = 2
        let maxTextWidth = maxBubbleWidth - padX * 2
        let duration: TimeInterval = isComfort ? 6.5 : 4.5

        let koWrapped = wrapped(korean, font: koFont, maxWidth: maxTextWidth)
        let zhWrapped = wrapped(chinese, font: zhFont, maxWidth: maxTextWidth)
        let koSize = measure(koWrapped, font: koFont, maxWidth: maxTextWidth)
        let zhSize = measure(zhWrapped, font: zhFont, maxWidth: maxTextWidth)

        let textWidth = max(koSize.width, zhSize.width, 36)
        let width = min(textWidth + padX * 2, maxBubbleWidth)
        let height = koSize.height + zhSize.height + gap + padY * 2
        let koCenterY = height / 2 - padY - koSize.height / 2
        let zhCenterY = -(height / 2 - padY) + zhSize.height / 2
        let tailLength: CGFloat = isComfort ? 14 : 11

        // Soft warm shadow (slightly larger, offset down).
        let shadow = SKShapeNode(rectOf: CGSize(width: width + 2, height: height + 2),
                                 cornerRadius: cornerRadius + 1)
        shadow.fillColor = DalEStyle.warmShadow
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -3)
        shadow.zPosition = -1

        // Bubble body: soft cream fill + uniform warm-gold outline.
        let bg = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: cornerRadius)
        bg.fillColor = DalEStyle.bubbleBackground
        bg.strokeColor = DalEStyle.warmBorder
        bg.lineWidth = lineWidth

        // Tail pointing down toward DAL-E.
        let tail = makeTail(length: tailLength, width: isComfort ? 20 : 16,
                            fill: DalEStyle.bubbleBackground, stroke: DalEStyle.warmBorder, lineWidth: lineWidth)
        tail.position = CGPoint(x: 0, y: -height / 2 + 1)

        let ko = SKLabelNode(text: koWrapped)
        ko.fontName = koFont.fontName
        ko.fontSize = koFont.pointSize
        ko.fontColor = NSColor(calibratedWhite: 0.2, alpha: 1)
        ko.verticalAlignmentMode = .center
        ko.horizontalAlignmentMode = .center
        ko.numberOfLines = 0
        ko.position = CGPoint(x: 0, y: koCenterY)

        let zh = SKLabelNode(text: zhWrapped)
        zh.fontName = zhFont.fontName
        zh.fontSize = zhFont.pointSize
        zh.fontColor = NSColor(calibratedWhite: 0.4, alpha: 1)
        zh.verticalAlignmentMode = .center
        zh.horizontalAlignmentMode = .center
        zh.numberOfLines = 0
        zh.position = CGPoint(x: 0, y: zhCenterY)

        let bubble = SKNode()
        bubble.zPosition = 500
        bubble.addChild(shadow)
        bubble.addChild(tail)
        bubble.addChild(bg)
        bubble.addChild(ko)
        bubble.addChild(zh)

        // Fit the bubble (with its tail) inside the small scene, scaling it
        // down uniformly if the message is long — never clipped.
        let bubbleBottom = squirrel.position.y + 90
        let maxHeight = max(scene.size.height - bubbleBottom - 4, 40)
        let fitScale = min(1, maxHeight / max(height, 40))

        // Bubble sits close above DAL-E, connected by the tail.
        bubble.position = CGPoint(x: squirrel.position.x,
                                  y: bubbleBottom + height * fitScale / 2)
        bubble.setScale(fitScale * (isComfort ? 0.85 : 0.7))
        bubble.alpha = 0
        scene.addChild(bubble)
        bubbleNode = bubble
        onSceneActivity?(true)

        let rise = SKAction.moveBy(x: 0, y: isComfort ? 4 : 3, duration: 0.35)
        rise.timingMode = .easeOut
        bubble.run(SKAction.sequence([
            SKAction.group([SKAction.fadeIn(withDuration: isComfort ? 0.35 : 0.25),
                            SKAction.scale(to: fitScale, duration: isComfort ? 0.4 : 0.28),
                            rise]),
            SKAction.wait(forDuration: duration),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ])) { [weak self] in
            guard let self else { return }
            if self.bubbleNode === bubble {
                self.bubbleNode = nil
                self.onSceneActivity?(false)
            }
        }
    }

    private var maxBubbleWidth: CGFloat { 172 }

    private func makeTail(length: CGFloat, width: CGFloat, fill: NSColor, stroke: NSColor, lineWidth: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -width / 2, y: 0))
        path.addLine(to: CGPoint(x: width / 2, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -length))
        path.closeSubpath()
        let tail = SKShapeNode(path: path)
        tail.fillColor = fill
        tail.strokeColor = stroke
        tail.lineWidth = lineWidth
        tail.lineJoin = .round
        return tail
    }

    /// Greedy character wrap so long Korean/Chinese lines fit the bubble.
    func wrapped(_ text: String, font: NSFont, maxWidth: CGFloat) -> String {
        var lines: [String] = []
        var current = ""
        for ch in text {
            let candidate = current + String(ch)
            if measure(candidate, font: font, maxWidth: .greatestFiniteMagnitude).width > maxWidth, !current.isEmpty {
                if let space = current.lastIndex(of: " ") {
                    let before = String(current[current.startIndex..<space])
                    let after = String(current[current.index(after: space)...])
                    if !before.isEmpty { lines.append(before) }
                    current = after + String(ch)
                } else {
                    lines.append(current)
                    current = String(ch)
                }
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.joined(separator: "\n")
    }

    func measure(_ text: String, font: NSFont, maxWidth: CGFloat) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    func hideBubble() {
        if bubbleNode != nil {
            bubbleNode?.removeAllActions()
            bubbleNode?.removeFromParent()
            bubbleNode = nil
            onSceneActivity?(false)
        }
    }
}
