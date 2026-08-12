import Foundation

/// Reminder lifecycle state (persisted).
enum ReminderStatus: String, Codable {
    case scheduled   // waiting for its time
    case due         // time reached, not yet presented
    case active      // DAL-E is currently presenting it
    case completed
}

/// How often a reminder repeats.
enum ReminderFrequency: String, Codable, CaseIterable {
    case once
    case daily
    case weekly
    case monthly

    var label: String {
        switch self {
        case .once:    return "仅一次"
        case .daily:   return "每天"
        case .weekly:  return "每周"
        case .monthly: return "每月"
        }
    }
}

/// User-entered reminder data from the creation/edit form.
struct ReminderDraft {
    var title: String
    var frequency: ReminderFrequency = .once
    var scheduledAt: Date?   // one-time reminders only
    var hour: Int = 0
    var minute: Int = 0
    var weekdays: [Int] = [] // ISO weekday: 1 = Monday … 7 = Sunday
    var dayOfMonth: Int = 1
}

/// A single reminder/task.
///
/// Persisted as JSON in UserDefaults (see ReminderStore). One-time reminders
/// use `scheduledAt` as their absolute time; recurring reminders always store
/// the *next* occurrence in `scheduledAt` plus their repeat rule, so the whole
/// scheduler / notification pipeline treats them exactly like one-time ones.
struct Reminder: Codable, Equatable {
    var id: String
    var title: String
    var scheduledAt: Date
    var status: ReminderStatus
    var frequency: ReminderFrequency
    var weekdays: [Int]
    var dayOfMonth: Int
    var hour: Int
    var minute: Int
    var enabled: Bool

    var isCompleted: Bool { status == .completed }
    var isRecurring: Bool { frequency != .once }

    /// Derived state for display: a scheduled reminder whose time has passed is "due".
    var displayState: ReminderStatus {
        if status == .completed { return .completed }
        if status == .active { return .active }
        return scheduledAt <= Date() ? .due : .scheduled
    }

    /// Human-readable repeat summary: "每天 08:00", "每周 一·三·五 18:30", "每月第 1 日 10:00".
    var scheduleSummary: String {
        switch frequency {
        case .once:
            let f = DateFormatter()
            f.dateFormat = "MM-dd HH:mm"
            return f.string(from: scheduledAt)
        case .daily:
            return String(format: "每天 %02d:%02d", hour, minute)
        case .weekly:
            let names = ["一", "二", "三", "四", "五", "六", "日"]
            let days = weekdays.sorted().map { names[max(0, $0 - 1)] }.joined(separator: "·")
            return String(format: "每周 %@ %02d:%02d", days, hour, minute)
        case .monthly:
            return String(format: "每月第 %d 日 %02d:%02d", dayOfMonth, hour, minute)
        }
    }

    init(id: String = UUID().uuidString, title: String, scheduledAt: Date,
         status: ReminderStatus = .scheduled, frequency: ReminderFrequency = .once,
         weekdays: [Int] = [], dayOfMonth: Int = 1, hour: Int = 0, minute: Int = 0,
         enabled: Bool = true) {
        self.id = id
        self.title = title
        self.scheduledAt = scheduledAt
        self.status = status
        self.frequency = frequency
        self.weekdays = weekdays
        self.dayOfMonth = dayOfMonth
        self.hour = hour
        self.minute = minute
        self.enabled = enabled
    }

    // MARK: - Next occurrence (recurring rules)

    /// The next occurrence strictly after `date`, per the repeat rule.
    func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        switch frequency {
        case .once:
            return nil

        case .daily:
            var comps = calendar.dateComponents([.year, .month, .day], from: date)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            var candidate = calendar.date(from: comps) ?? date
            if candidate <= date {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate

        case .weekly:
            let selected = Set(weekdays)
            for offset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: offset, to: date) ?? date
                let isoWeekday = ((calendar.component(.weekday, from: day) + 5) % 7) + 1
                if selected.contains(isoWeekday) {
                    var comps = calendar.dateComponents([.year, .month, .day], from: day)
                    comps.hour = hour
                    comps.minute = minute
                    comps.second = 0
                    let candidate = calendar.date(from: comps) ?? day
                    if candidate > date { return candidate }
                }
            }
            return nil

        case .monthly:
            let targetDay = min(dayOfMonth, Reminder.daysInMonth(of: date, calendar: calendar))
            var comps = calendar.dateComponents([.year, .month], from: date)
            comps.day = targetDay
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            var candidate = calendar.date(from: comps) ?? date
            if candidate <= date {
                let nextMonth = calendar.date(byAdding: .month, value: 1, to: date) ?? date
                let d = min(dayOfMonth, Reminder.daysInMonth(of: nextMonth, calendar: calendar))
                var c2 = calendar.dateComponents([.year, .month], from: nextMonth)
                c2.day = d
                c2.hour = hour
                c2.minute = minute
                c2.second = 0
                candidate = calendar.date(from: c2) ?? date
            }
            return candidate
        }
    }

    private static func daysInMonth(of date: Date, calendar: Calendar) -> Int {
        guard let range = calendar.range(of: .day, in: .month, for: date) else { return 30 }
        return range.count
    }

    // MARK: - Codable (migrates the older {completed: Bool} format)

    private enum CodingKeys: String, CodingKey {
        case id, title, scheduledAt, status, frequency, weekdays, dayOfMonth, hour, minute, enabled, completed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        scheduledAt = try c.decode(Date.self, forKey: .scheduledAt)
        if let s = try? c.decode(ReminderStatus.self, forKey: .status) {
            status = s
        } else if let completed = try? c.decode(Bool.self, forKey: .completed), completed {
            status = .completed
        } else {
            status = .scheduled
        }
        frequency = (try? c.decode(ReminderFrequency.self, forKey: .frequency)) ?? .once
        weekdays = (try? c.decode([Int].self, forKey: .weekdays)) ?? []
        dayOfMonth = (try? c.decode(Int.self, forKey: .dayOfMonth)) ?? 1
        hour = (try? c.decode(Int.self, forKey: .hour)) ?? 0
        minute = (try? c.decode(Int.self, forKey: .minute)) ?? 0
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(scheduledAt, forKey: .scheduledAt)
        try c.encode(status, forKey: .status)
        try c.encode(frequency, forKey: .frequency)
        try c.encode(weekdays, forKey: .weekdays)
        try c.encode(dayOfMonth, forKey: .dayOfMonth)
        try c.encode(hour, forKey: .hour)
        try c.encode(minute, forKey: .minute)
        try c.encode(enabled, forKey: .enabled)
    }
}
