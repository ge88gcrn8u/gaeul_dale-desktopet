import AppKit

/// AppKit UI for reminders, built with the same native components the project
/// already uses (NSAlert, NSPopUpButton, NSTextField). No new UI framework.
enum ReminderUI {

    // MARK: - Creation form

    /// Presents the create-reminder form (one-time / daily / weekly / monthly).
    /// Returns the new (already persisted) reminder, or nil if cancelled/invalid.
    @discardableResult
    static func presentCreationForm() -> Reminder? {
        let form = ReminderForm(defaultDate: Date().addingTimeInterval(3600))
        guard let draft = presentForm(form, message: "⏰ 创建提醒", confirm: "创建提醒") else { return nil }
        return ReminderStore.shared.add(draft: draft)
    }

    /// Presents a prefilled edit form. Returns the edited draft, or nil.
    static func presentEditForm(for reminder: Reminder) -> ReminderDraft? {
        let form = ReminderForm(defaultDate: reminder.scheduledAt, initial: reminder)
        return presentForm(form, message: "✏️ 编辑提醒", confirm: "保存")
    }

    private static func presentForm(_ form: ReminderForm, message: String, confirm: String) -> ReminderDraft? {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "输入任务内容，选择重复频率与时间（24 小时制）"
        alert.accessoryView = form.view
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = form.taskField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard let draft = form.makeDraft() else {
            showWarning("无法保存提醒", "请填写任务内容，并选择有效的日期与时间。")
            return nil
        }
        if draft.frequency == .once, let date = draft.scheduledAt, date <= Date() {
            showWarning("时间已过去", "请选择一个未来的时间。")
            return nil
        }
        return draft
    }

    // MARK: - Interaction (click DAL-E while a reminder is active)

    enum InteractionChoice {
        case complete
        case snooze
        case edit
        case delete
    }

    /// The reminder card shown when the user clicks jumping DAL-E.
    static func presentInteraction(for reminder: Reminder) -> InteractionChoice {
        let alert = NSAlert()
        alert.messageText = "🐿️ DAL-E"
        alert.informativeText = "⏰ \(reminder.scheduleSummary)\n\n到了该做「\(reminder.title)」的时间啦！"
        alert.addButton(withTitle: "✅ 完成")
        alert.addButton(withTitle: "💤 稍后")
        alert.addButton(withTitle: "✏️ 编辑")
        alert.addButton(withTitle: "🗑 删除")
        switch alert.runModal().rawValue {
        case NSApplication.ModalResponse.alertFirstButtonReturn.rawValue: return .complete
        case NSApplication.ModalResponse.alertSecondButtonReturn.rawValue: return .snooze
        case NSApplication.ModalResponse.alertThirdButtonReturn.rawValue: return .edit
        default: return .delete
        }
    }

    // MARK: - Snooze options

    /// Snooze choices: 10 minutes / 1 hour / tomorrow / custom.
    /// Returns the new scheduled time, or nil if cancelled.
    static func presentSnoozeOptions(for reminder: Reminder) -> Date? {
        let alert = NSAlert()
        alert.messageText = "🌰 稍后提醒"
        alert.informativeText = "「\(reminder.title)」想什么时候再提醒你？"
        alert.addButton(withTitle: "10 分钟后")
        alert.addButton(withTitle: "1 小时后")
        alert.addButton(withTitle: "明天")
        alert.addButton(withTitle: "自定义…")
        alert.addButton(withTitle: "取消")

        let now = Date()
        let choice = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        var candidate: Date?
        switch choice {
        case 0: candidate = now.addingTimeInterval(10 * 60)
        case 1: candidate = now.addingTimeInterval(60 * 60)
        case 2: candidate = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0), matchingPolicy: .nextTime)
        case 3: candidate = presentCustomSnooze()
        default: return nil
        }
        guard let date = candidate, date > Date() else {
            showWarning("无法稍后提醒", "请选择一个未来的时间。")
            return nil
        }
        return date
    }

    private static func presentCustomSnooze() -> Date? {
        let form = ReminderForm(defaultDate: Date().addingTimeInterval(10 * 60), showTask: false)
        let alert = NSAlert()
        alert.messageText = "自定义稍后时间"
        alert.informativeText = "选择新的提醒时间（24 小时制）"
        alert.accessoryView = form.view
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return form.makeDate()
    }

    // MARK: - Status labels

    static func statusText(_ status: ReminderStatus) -> String {
        switch status {
        case .scheduled: return "Scheduled"
        case .due:       return "Due"
        case .active:    return "Active"
        case .completed: return "Completed"
        }
    }

    static func statusEmoji(_ status: ReminderStatus) -> String {
        switch status {
        case .scheduled: return "🍂"
        case .due:       return "⏰"
        case .active:    return "🐿️"
        case .completed: return "🌰"
        }
    }

    static func statusColor(_ status: ReminderStatus) -> NSColor {
        switch status {
        case .scheduled: return .systemGray
        case .due:       return .systemOrange
        case .active:    return .systemOrange
        case .completed: return DalEStyle.softGreen
        }
    }

    // MARK: - Helpers

    static func showWarning(_ title: String, _ text: String) {
        let warn = NSAlert()
        warn.messageText = title
        warn.informativeText = text
        warn.alertStyle = .warning
        warn.addButton(withTitle: "确定")
        warn.runModal()
    }
}

// MARK: - Accessory form view: Task · Repeat · (Date/Days/Day-of-month) · Time

/// Small accessory-view form supporting one-time / daily / weekly / monthly.
private final class ReminderForm: NSObject {

    let view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 210))

    let taskField = NSTextField(frame: NSRect(x: 96, y: 172, width: 264, height: 26))
    let repeatPopup = NSPopUpButton(frame: NSRect(x: 96, y: 132, width: 130, height: 26), pullsDown: false)

    // One-time: date row
    let yearPopup  = NSPopUpButton(frame: .zero, pullsDown: false)
    let monthPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let dayPopup   = NSPopUpButton(frame: .zero, pullsDown: false)
    private let dateSlash1 = NSTextField(labelWithString: "/")
    private let dateSlash2 = NSTextField(labelWithString: "/")

    // Weekly: quick presets + individual weekday checkboxes
    private let presetButtons: [NSButton] = ["工作日", "周末", "每天"].map { NSButton(title: $0, target: nil, action: nil) }
    private let dayChecks: [NSButton] = (0..<7).map { NSButton(checkboxWithTitle: ["一","二","三","四","五","六","日"][$0], target: nil, action: nil) }

    // Monthly: day of month
    let domPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let domUnitLabel = NSTextField(labelWithString: "日")

    // Time row
    let hourPopup   = NSPopUpButton(frame: NSRect(x: 96, y: 52, width: 76, height: 26), pullsDown: false)
    let minutePopup = NSPopUpButton(frame: NSRect(x: 192, y: 52, width: 76, height: 26), pullsDown: false)
    private let colon = NSTextField(labelWithString: ":")

    private let taskLabel = NSTextField(labelWithString: "任务")
    private let repeatLabel = NSTextField(labelWithString: "重复")
    private let contextualLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "时间")

    private let calendar = Calendar.current
    private let defaultDate: Date

    init(defaultDate: Date, initial: Reminder? = nil, showTask: Bool = true) {
        self.defaultDate = defaultDate
        super.init()
        build(initial: initial, showTask: showTask)
    }

    // MARK: - Build

    private func build(initial: Reminder?, showTask: Bool) {
        for v in [taskLabel, repeatLabel, contextualLabel, timeLabel,
                  dateSlash1, dateSlash2, domUnitLabel, colon] {
            v.font = NSFont.systemFont(ofSize: 13)
        }

        // Populate repeat options
        for f in [ReminderFrequency.once, .daily, .weekly, .monthly] {
            repeatPopup.addItem(withTitle: f.label)
        }

        // Date popups
        let nowYear = calendar.component(.year, from: defaultDate)
        for y in nowYear...(nowYear + 3) { yearPopup.addItem(withTitle: "\(y)") }
        for m in 1...12 { monthPopup.addItem(withTitle: "\(m)") }
        rebuildDays()

        // Day-of-month popup
        for d in 1...31 { domPopup.addItem(withTitle: "\(d)") }

        // Time popups (24h)
        for h in 0...23 { hourPopup.addItem(withTitle: String(format: "%02d", h)) }
        for m in 0...59 { minutePopup.addItem(withTitle: String(format: "%02d", m)) }

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: defaultDate)
        yearPopup.selectItem(withTitle: "\(comps.year ?? nowYear)")
        monthPopup.selectItem(withTitle: "\(comps.month ?? 1)")
        rebuildDays(selectDay: comps.day ?? 1)
        hourPopup.selectItem(withTitle: String(format: "%02d", comps.hour ?? 0))
        minutePopup.selectItem(withTitle: String(format: "%02d", comps.minute ?? 0))

        // Prefill from an existing reminder (edit)
        if let initial {
            taskField.stringValue = initial.title
            repeatPopup.selectItem(at: ReminderFrequency.allCases.firstIndex(of: initial.frequency) ?? 0)
            hourPopup.selectItem(withTitle: String(format: "%02d", initial.hour))
            minutePopup.selectItem(withTitle: String(format: "%02d", initial.minute))
            if initial.frequency == .weekly {
                for d in initial.weekdays where d >= 1 && d <= 7 {
                    dayChecks[d - 1].state = .on
                }
            } else if initial.frequency == .monthly {
                domPopup.selectItem(withTitle: "\(min(max(initial.dayOfMonth, 1), 31))")
            } else if initial.frequency == .once {
                let c = calendar.dateComponents([.year, .month, .day], from: initial.scheduledAt)
                yearPopup.selectItem(withTitle: "\(c.year ?? nowYear)")
                monthPopup.selectItem(withTitle: "\(c.month ?? 1)")
                rebuildDays(selectDay: c.day ?? 1)
            }
        }

        yearPopup.target = self;  yearPopup.action = #selector(popupChanged)
        monthPopup.target = self; monthPopup.action = #selector(popupChanged)
        repeatPopup.target = self; repeatPopup.action = #selector(frequencyChanged)

        taskField.placeholderString = "例如：Drink water"
        if !showTask {
            taskField.isHidden = true
            taskLabel.isHidden = true
        }

        for v in [taskLabel, taskField, repeatLabel, repeatPopup, contextualLabel,
                  yearPopup, monthPopup, dayPopup, dateSlash1, dateSlash2,
                  domPopup, domUnitLabel, hourPopup, minutePopup, colon, timeLabel] {
            view.addSubview(v)
        }
        for b in dayChecks {
            b.setButtonType(.switch)
            b.font = NSFont.systemFont(ofSize: 12)
            view.addSubview(b)
        }
        for (i, b) in presetButtons.enumerated() {
            b.bezelStyle = .rounded
            b.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            b.tag = i
            b.target = self
            b.action = #selector(presetSelected(_:))
            view.addSubview(b)
        }

        updateLayout()
    }

    // MARK: - Layout

    private var selectedFrequency: ReminderFrequency {
        let idx = max(0, repeatPopup.indexOfSelectedItem)
        return ReminderFrequency.allCases[min(idx, ReminderFrequency.allCases.count - 1)]
    }

    @objc private func frequencyChanged() { updateLayout() }
    @objc private func popupChanged() { rebuildDays() }

    /// Quick weekday presets: 工作日(一~五) / 周末(六~日) / 每天(一~日).
    /// Individual checkboxes remain for fully custom selection.
    @objc private func presetSelected(_ sender: NSButton) {
        let onDays: [Int]
        switch sender.tag {
        case 0: onDays = [1, 2, 3, 4, 5]
        case 1: onDays = [6, 7]
        default: onDays = [1, 2, 3, 4, 5, 6, 7]
        }
        for i in 0..<7 {
            dayChecks[i].state = onDays.contains(i + 1) ? .on : .off
        }
    }

    private func updateLayout() {
        let freq = selectedFrequency
        let showDate = freq == .once
        let showDays = freq == .weekly
        let showDOM = freq == .monthly

        // Contextual row controls
        let ctxY: CGFloat = 92
        dateSlash1.isHidden = !showDate
        dateSlash2.isHidden = !showDate
        for b in dayChecks { b.isHidden = !showDays }
        for b in presetButtons { b.isHidden = !showDays }
        domPopup.isHidden = !showDOM
        domUnitLabel.isHidden = !showDOM

        if showDate {
            contextualLabel.stringValue = "日期"
            yearPopup.isHidden = false
            monthPopup.isHidden = false
            dayPopup.isHidden = false
            yearPopup.frame = NSRect(x: 96, y: ctxY, width: 86, height: 26)
            dateSlash1.frame = NSRect(x: 186, y: ctxY + 4, width: 12, height: 18)
            monthPopup.frame = NSRect(x: 198, y: ctxY, width: 60, height: 26)
            dateSlash2.frame = NSRect(x: 262, y: ctxY + 4, width: 12, height: 18)
            dayPopup.frame = NSRect(x: 274, y: ctxY, width: 60, height: 26)
        } else if showDays {
            contextualLabel.stringValue = "星期"
            yearPopup.isHidden = true
            monthPopup.isHidden = true
            dayPopup.isHidden = true
            for (i, b) in presetButtons.enumerated() {
                b.frame = NSRect(x: 96 + CGFloat(i) * 60, y: ctxY, width: 56, height: 22)
            }
            for (i, b) in dayChecks.enumerated() {
                b.frame = NSRect(x: 96 + CGFloat(i) * 38, y: ctxY - 36, width: 36, height: 18)
            }
        } else if showDOM {
            contextualLabel.stringValue = "每月"
            yearPopup.isHidden = true
            monthPopup.isHidden = true
            dayPopup.isHidden = true
            domPopup.frame = NSRect(x: 96, y: ctxY, width: 70, height: 26)
            domUnitLabel.frame = NSRect(x: 170, y: ctxY + 4, width: 30, height: 18)
        } else {
            contextualLabel.stringValue = ""
            yearPopup.isHidden = true
            monthPopup.isHidden = true
            dayPopup.isHidden = true
        }

        // Time row moves up when the contextual row is hidden (daily mode);
        // weekly mode needs two rows (presets + checkboxes) so it sits lower.
        let timeY: CGFloat = showDays ? 20 : ((showDate || showDOM) ? 52 : 92)
        hourPopup.frame.origin.y = timeY
        minutePopup.frame.origin.y = timeY
        colon.frame = NSRect(x: 176, y: timeY + 4, width: 10, height: 18)
        timeLabel.frame = NSRect(x: 16, y: timeY + 4, width: 60, height: 18)

        taskLabel.frame = NSRect(x: 16, y: 176, width: 60, height: 18)
        repeatLabel.frame = NSRect(x: 16, y: 136, width: 60, height: 18)
        contextualLabel.frame = NSRect(x: 16, y: ctxY + 4, width: 60, height: 18)
    }

    private func rebuildDays(selectDay: Int? = nil) {
        let year = Int(yearPopup.titleOfSelectedItem ?? "") ?? calendar.component(.year, from: Date())
        let month = Int(monthPopup.titleOfSelectedItem ?? "") ?? 1
        let days = daysInMonth(year: year, month: month)
        let previous = dayPopup.titleOfSelectedItem.flatMap(Int.init)
        dayPopup.removeAllItems()
        for d in 1...days { dayPopup.addItem(withTitle: "\(d)") }
        let wanted = selectDay ?? min(previous ?? 1, days)
        if wanted >= 1 && wanted <= days {
            dayPopup.selectItem(withTitle: "\(wanted)")
        } else {
            dayPopup.selectItem(at: 0)
        }
    }

    private func daysInMonth(year: Int, month: Int) -> Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let date = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: date) else { return 31 }
        return range.count
    }

    // MARK: - Result

    func makeDraft() -> ReminderDraft? {
        let title = taskField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        guard let hour = Int(hourPopup.titleOfSelectedItem ?? ""),
              let minute = Int(minutePopup.titleOfSelectedItem ?? "") else { return nil }

        let freq = selectedFrequency
        var draft = ReminderDraft(title: title, frequency: freq, hour: hour, minute: minute)

        switch freq {
        case .once:
            guard let date = makeDate() else { return nil }
            draft.scheduledAt = date
        case .weekly:
            let days = (0..<7).filter { dayChecks[$0].state == .on }.map { $0 + 1 }
            guard !days.isEmpty else { return nil }
            draft.weekdays = days
        case .monthly:
            draft.dayOfMonth = Int(domPopup.titleOfSelectedItem ?? "") ?? 1
        case .daily:
            break
        }
        return draft
    }

    func makeDate() -> Date? {
        guard let year = Int(yearPopup.titleOfSelectedItem ?? ""),
              let month = Int(monthPopup.titleOfSelectedItem ?? ""),
              let day = Int(dayPopup.titleOfSelectedItem ?? ""),
              let hour = Int(hourPopup.titleOfSelectedItem ?? ""),
              let minute = Int(minutePopup.titleOfSelectedItem ?? "") else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)
    }
}
