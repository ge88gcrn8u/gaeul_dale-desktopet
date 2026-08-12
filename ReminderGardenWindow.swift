import AppKit

/// "DAL-E Reminder Garden" — a cozy card-style reminder manager.
/// View / edit / enable / disable / delete reminders, styled as autumn cards
/// (no tables, no corporate dashboards).
final class ReminderGardenWindow: NSWindow {

    private let stack = NSStackView()
    private let scrollView = NSScrollView()
    private let documentView = GardenFlippedView()
    private let store = ReminderStore.shared
    private let scheduler = ReminderScheduler.shared

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 470, height: 620),
                   styleMask: [.titled, .closable, .resizable],
                   backing: .buffered,
                   defer: false)
        title = "🌰 DAL-E 提醒花园"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 420, height: 440)
        backgroundColor = DalEStyle.creamBackground
        buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(remindersChanged),
                                               name: .remindersDidChange, object: nil)
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    func showAndFocus() {
        refresh()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        let all = store.all.sorted { $0.scheduledAt < $1.scheduledAt }
        if all.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: "🍂 提醒花园还是空的～\n右键 DAL-E → ⏰ 提醒 → 创建提醒，种下第一颗小种子吧。")
            empty.font = DalEStyle.roundedFont(size: 13)
            empty.textColor = DalEStyle.subtextColor
            empty.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(empty)
        } else {
            for r in all {
                stack.addArrangedSubview(makeCard(for: r))
            }
        }
        scrollToTop()
    }

    // MARK: - UI

    private func buildUI() {
        guard let cv = contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = DalEStyle.creamBackground.cgColor

        let headerTitle = NSTextField(labelWithString: "🐿️ DAL-E 提醒花园")
        headerTitle.font = DalEStyle.roundedFont(size: 20, weight: .bold)
        headerTitle.textColor = DalEStyle.textColor

        let headerSub = NSTextField(labelWithString: "每一颗小提醒，都在这里安静长大")
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
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        documentView.addSubview(stack)
        scrollView.documentView = documentView

        for v in [headerTitle, headerSub, scrollView] {
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
            scrollView.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -12),

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

    private func makeCard(for reminder: Reminder) -> NSView {
        let cardWidth: CGFloat = 400
        let cardHeight: CGFloat = 124

        let card = DalEStyle.roundedView(cornerRadius: 16, fill: DalEStyle.cardBackground, border: DalEStyle.warmBorder, lineWidth: 1)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
        card.heightAnchor.constraint(equalToConstant: cardHeight).isActive = true

        let state = reminder.enabled ? reminder.displayState : nil
        let stateLabel = state.map { ReminderUI.statusText($0) } ?? "Disabled"
        let stateColor = state.map { ReminderUI.statusColor($0) } ?? .systemGray

        // Emoji + title
        let emoji = NSTextField(labelWithString: ReminderUI.statusEmoji(reminder.displayState))
        emoji.font = NSFont.systemFont(ofSize: 22)
        emoji.frame = NSRect(x: 14, y: cardHeight - 42, width: 30, height: 28)

        let title = NSTextField(labelWithString: reminder.title)
        title.font = DalEStyle.roundedFont(size: 15, weight: .bold)
        title.textColor = DalEStyle.textColor
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 50, y: cardHeight - 38, width: cardWidth - 64, height: 22)

        // Repeat / schedule summary
        let summary = NSTextField(labelWithString: (reminder.isRecurring ? "🔁 " : "📅 ") + reminder.scheduleSummary)
        summary.font = DalEStyle.roundedFont(size: 12)
        summary.textColor = DalEStyle.subtextColor
        summary.frame = NSRect(x: 50, y: cardHeight - 62, width: cardWidth - 64, height: 18)

        // Status badge
        let badge = DalEStyle.roundedView(cornerRadius: 9,
                                          fill: stateColor.withAlphaComponent(0.18),
                                          border: stateColor.withAlphaComponent(0.5))
        badge.frame = NSRect(x: 14, y: 14, width: 96, height: 22)
        let badgeLabel = NSTextField(labelWithString: stateLabel)
        badgeLabel.font = DalEStyle.roundedFont(size: 11, weight: .medium)
        badgeLabel.textColor = stateColor
        badgeLabel.alignment = .center
        badgeLabel.frame = badge.bounds.insetBy(dx: 4, dy: 2)
        badge.addSubview(badgeLabel)

        // Actions: Edit / Enable-Disable / Delete
        let editBtn = NSButton(title: "✏️ 编辑", target: self, action: #selector(editReminder(_:)))
        editBtn.bezelStyle = .rounded
        editBtn.font = DalEStyle.roundedFont(size: 11, weight: .medium)
        editBtn.contentTintColor = DalEStyle.autumnOrange
        editBtn.identifier = NSUserInterfaceItemIdentifier(reminder.id)
        editBtn.frame = NSRect(x: cardWidth - 194, y: 12, width: 56, height: 26)

        let toggleBtn = NSButton(title: reminder.enabled ? "⏸ 禁用" : "▶️ 启用",
                                 target: self, action: #selector(toggleReminder(_:)))
        toggleBtn.bezelStyle = .rounded
        toggleBtn.font = DalEStyle.roundedFont(size: 11, weight: .medium)
        toggleBtn.contentTintColor = reminder.enabled ? .systemOrange : DalEStyle.softGreen
        toggleBtn.identifier = NSUserInterfaceItemIdentifier(reminder.id)
        toggleBtn.frame = NSRect(x: cardWidth - 130, y: 12, width: 56, height: 26)

        let deleteBtn = NSButton(title: "🗑 删除", target: self, action: #selector(deleteReminder(_:)))
        deleteBtn.bezelStyle = .rounded
        deleteBtn.font = DalEStyle.roundedFont(size: 11, weight: .medium)
        deleteBtn.contentTintColor = .systemRed
        deleteBtn.identifier = NSUserInterfaceItemIdentifier(reminder.id)
        deleteBtn.frame = NSRect(x: cardWidth - 66, y: 12, width: 58, height: 26)

        for v in [emoji, title, summary, badge, editBtn, toggleBtn, deleteBtn] { card.addSubview(v) }
        return card
    }

    private func scrollToTop() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.documentView.layoutSubtreeIfNeeded()
            self.scrollView.contentView.scroll(to: .zero)
        }
    }

    // MARK: - Actions

    @objc private func editReminder(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let r = store.reminder(id: id) else { return }
        if let draft = ReminderUI.presentEditForm(for: r) {
            store.update(id: id, draft: draft)
            scheduler.remindersChanged()
        }
    }

    @objc private func toggleReminder(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let r = store.reminder(id: id) else { return }
        store.setEnabled(id: id, !r.enabled)
        scheduler.remindersChanged()
    }

    @objc private func deleteReminder(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let r = store.reminder(id: id) else { return }
        let confirm = NSAlert()
        confirm.messageText = "🗑 删除提醒"
        confirm.informativeText = "确定删除「\(r.title)」吗？"
        confirm.addButton(withTitle: "删除")
        confirm.addButton(withTitle: "取消")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        store.delete(id: id)
        scheduler.remindersChanged()
    }

    @objc private func remindersChanged() {
        refresh()
    }
}

private final class GardenFlippedView: NSView {
    override var isFlipped: Bool { true }
}
