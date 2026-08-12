import AppKit

/// The warm, cozy DAL-E chat window.
///
/// DAL-E speaks here in rounded bubbles with an autumn feel; there is no fake
/// AI — the companion posts its fixed encouragement messages and lets the user
/// act (create reminders, open the reminder garden, ask for a hug).
final class ChatWindow: NSWindow {

    private let stack = NSStackView()
    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let dialogue = EncouragementDialogue.shared
    private let maxBubbleWidth: CGFloat = 300

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
                   styleMask: [.titled, .closable, .resizable],
                   backing: .buffered,
                   defer: false)
        title = "🐿️ DAL-E · 秋日小松鼠"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 380, height: 480)
        backgroundColor = DalEStyle.creamBackground
        buildUI()
        postSystem("🍁 欢迎回来～我是 DAL-E，你的秋日小松鼠伙伴。")
    }

    // MARK: - Public API

    func showAndFocus() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func post(situation: EncouragementDialogue.Situation) {
        guard let t = dialogue.text(for: situation) else { return }
        addDaleMessage(korean: t.korean, chinese: t.chinese)
    }

    func postSystem(_ text: String) {
        addSystemNote(text)
    }

    // MARK: - UI

    private func buildUI() {
        guard let cv = contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = DalEStyle.creamBackground.cgColor

        let headerTitle = NSTextField(labelWithString: "🐿️ DAL-E")
        headerTitle.font = DalEStyle.roundedFont(size: 20, weight: .bold)
        headerTitle.textColor = DalEStyle.textColor

        let headerSub = NSTextField(labelWithString: "秋天的小松鼠伙伴 · 安静又温暖")
        headerSub.font = DalEStyle.roundedFont(size: 11)
        headerSub.textColor = DalEStyle.subtextColor

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        documentView.wantsLayer = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        documentView.addSubview(stack)
        scrollView.documentView = documentView

        let createBtn = makeActionButton(title: "⏰ 创建提醒", action: #selector(createReminder))
        let gardenBtn = makeActionButton(title: "🌰 提醒花园", action: #selector(openGarden))
        let comfortBtn = makeActionButton(title: "🤍 抱抱我", action: #selector(comfort))

        let buttonRow = NSStackView(views: [createBtn, gardenBtn, comfortBtn])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .fillEqually

        for v in [headerTitle, headerSub, scrollView, buttonRow] {
            v.translatesAutoresizingMaskIntoConstraints = false
            cv.addSubview(v)
        }

        let clip = scrollView.contentView
        documentView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            headerTitle.topAnchor.constraint(equalTo: cv.topAnchor, constant: 14),
            headerTitle.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            headerSub.topAnchor.constraint(equalTo: headerTitle.bottomAnchor, constant: 2),
            headerSub.leadingAnchor.constraint(equalTo: headerTitle.leadingAnchor),

            scrollView.topAnchor.constraint(equalTo: headerSub.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -10),

            buttonRow.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 14),
            buttonRow.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -14),
            buttonRow.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -14),
            buttonRow.heightAnchor.constraint(equalToConstant: 34),

            documentView.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: clip.topAnchor),
            documentView.widthAnchor.constraint(equalTo: clip.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            documentView.bottomAnchor.constraint(equalTo: stack.bottomAnchor),
        ])
    }

    private func makeActionButton(title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.font = DalEStyle.roundedFont(size: 12, weight: .medium)
        b.contentTintColor = DalEStyle.autumnOrange
        return b
    }

    // MARK: - Messages

    private func addDaleMessage(korean: String, chinese: String?) {
        let row = makeDaleRow(korean: korean, chinese: chinese)
        stack.addArrangedSubview(row)
        scrollToBottom()
    }

    private func addSystemNote(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = DalEStyle.roundedFont(size: 11)
        label.textColor = DalEStyle.subtextColor
        label.translatesAutoresizingMaskIntoConstraints = false
        let maxW = maxBubbleWidth + 40
        let size = measure(text, font: label.font!, maxWidth: maxW)
        label.widthAnchor.constraint(equalToConstant: min(max(size.width, 60), maxW)).isActive = true
        stack.addArrangedSubview(label)
        scrollToBottom()
    }

    private func makeDaleRow(korean: String, chinese: String?) -> NSView {
        let koFont = DalEStyle.roundedFont(size: 15, weight: .medium)
        let zhFont = DalEStyle.roundedFont(size: 11)

        let padX: CGFloat = 11
        let padY: CGFloat = 8
        let maxTextWidth = maxBubbleWidth - padX * 2

        let koSize = measure(korean, font: koFont, maxWidth: maxTextWidth)
        var zhSize = CGSize.zero
        if let chinese, !chinese.isEmpty {
            zhSize = measure(chinese, font: zhFont, maxWidth: maxTextWidth)
        }

        let textWidth = max(koSize.width, zhSize.width, 40)
        let bubbleWidth = min(textWidth + padX * 2, maxBubbleWidth)
        let bubbleHeight = koSize.height + zhSize.height + padY * 2 + (zhSize.height > 0 ? 3 : 0)

        let bubble = DalEStyle.roundedView(cornerRadius: 11, fill: DalEStyle.bubbleBackground, border: DalEStyle.warmBorder, lineWidth: 2)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.widthAnchor.constraint(equalToConstant: bubbleWidth).isActive = true
        bubble.heightAnchor.constraint(equalToConstant: bubbleHeight).isActive = true

        let ko = NSTextField(labelWithString: korean)
        ko.font = koFont
        ko.textColor = DalEStyle.textColor
        ko.frame = NSRect(x: padX, y: bubbleHeight - padY - koSize.height, width: koSize.width, height: koSize.height)
        bubble.addSubview(ko)

        if let chinese, !chinese.isEmpty {
            let zh = NSTextField(labelWithString: chinese)
            zh.font = zhFont
            zh.textColor = DalEStyle.subtextColor
            zh.frame = NSRect(x: padX, y: padY, width: zhSize.width, height: zhSize.height)
            bubble.addSubview(zh)
        }

        let avatar = NSTextField(labelWithString: "🐿️")
        avatar.font = NSFont.systemFont(ofSize: 22)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.widthAnchor.constraint(equalToConstant: 28).isActive = true

        let row = NSStackView(views: [avatar, bubble])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func measure(_ text: String, font: NSFont, maxWidth: CGFloat) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    private func scrollToBottom() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.documentView.layoutSubtreeIfNeeded()
            let bottom = self.documentView.bounds.height
            let visible = self.scrollView.contentView.bounds.height
            self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, bottom - visible)))
        }
    }

    // MARK: - Actions

    @objc private func createReminder() {
        guard let r = ReminderUI.presentCreationForm() else { return }
        ReminderScheduler.shared.remindersChanged()
        dialogue.say(.reminderCreated)
        postSystem("⏰ 已创建提醒：\(r.scheduleSummary) · \(r.title)")
    }

    @objc private func openGarden() {
        (NSApp.delegate as? AppDelegate)?.openGarden()
    }

    @objc private func comfort() {
        dialogue.sayRandomComfort()
    }
}

/// Simple flipped container so messages stack top-down inside the scroll view.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
