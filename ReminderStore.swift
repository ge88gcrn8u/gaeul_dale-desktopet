import Foundation

extension Notification.Name {
    /// Posted after any reminder mutation (create / edit / complete / snooze /
    /// enable / disable / delete) so open UI (e.g. the Reminder Garden) can
    /// refresh itself.
    static let remindersDidChange = Notification.Name("DalERemindersDidChange")
}

/// Persistent storage for reminders.
/// Uses the project's existing storage mechanism (UserDefaults),
/// encoding reminders as ISO8601 JSON so they survive app restarts.
///
/// Every user-facing mutation keeps macOS notifications in sync
/// (schedule for future reminders, cancel for completed/disabled/deleted ones).
final class ReminderStore {

    static let shared = ReminderStore()

    private let storageKey = "DalEReminders.v1"
    private var reminders: [Reminder] = []

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() { load() }

    // MARK: - Access

    var all: [Reminder] { reminders }

    /// Pending = not completed AND enabled. Disabled reminders are kept but
    /// never scheduled / triggered.
    var pending: [Reminder] { reminders.filter { !$0.isCompleted && $0.enabled } }

    func reminder(id: String) -> Reminder? {
        reminders.first { $0.id == id }
    }

    /// Earliest pending reminder scheduled strictly in the future.
    func nextPending(after date: Date = Date()) -> Reminder? {
        pending
            .filter { $0.scheduledAt > date }
            .min { $0.scheduledAt < $1.scheduledAt }
    }

    // MARK: - Mutations

    /// Create a reminder from a form draft (one-time or recurring).
    @discardableResult
    func add(draft: ReminderDraft) -> Reminder? {
        let reminder: Reminder
        if draft.frequency == .once {
            guard let date = draft.scheduledAt else { return nil }
            reminder = Reminder(title: draft.title, scheduledAt: date, hour: draft.hour, minute: draft.minute)
        } else {
            var r = Reminder(title: draft.title, scheduledAt: Date(),
                             frequency: draft.frequency, weekdays: draft.weekdays,
                             dayOfMonth: draft.dayOfMonth, hour: draft.hour, minute: draft.minute)
            guard let next = r.nextOccurrence(after: Date()) else { return nil }
            r.scheduledAt = next
            reminder = r
        }
        reminders.append(reminder)
        save()
        ReminderNotifications.shared.schedule(for: reminder)
        notifyChanged()
        return reminder
    }

    /// Full edit from a form draft. Resets to `.scheduled`; the scheduler
    /// re-derives due/active. Notification is re-scheduled (no duplicates).
    func update(id: String, draft: ReminderDraft) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[i].title = draft.title
        reminders[i].frequency = draft.frequency
        reminders[i].weekdays = draft.weekdays
        reminders[i].dayOfMonth = draft.dayOfMonth
        reminders[i].hour = draft.hour
        reminders[i].minute = draft.minute

        if draft.frequency == .once, let date = draft.scheduledAt {
            reminders[i].scheduledAt = date
        } else if draft.frequency != .once, let next = reminders[i].nextOccurrence(after: Date()) {
            reminders[i].scheduledAt = next
        }
        reminders[i].status = .scheduled
        save()
        ReminderNotifications.shared.schedule(for: reminders[i])
        notifyChanged()
    }

    /// Postpone an unfinished reminder (e.g. snooze) to a new time.
    /// For recurring reminders the repeat rule is left untouched.
    func reschedule(id: String, to date: Date) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[i].scheduledAt = date
        reminders[i].status = .scheduled
        save()
        ReminderNotifications.shared.schedule(for: reminders[i])
        notifyChanged()
    }

    /// Complete the current cycle.
    /// - One-time reminders become `.completed` (terminal).
    /// - Recurring reminders advance to their next occurrence and stay alive.
    func completeCycle(id: String) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        if reminders[i].frequency == .once {
            reminders[i].status = .completed
            save()
            ReminderNotifications.shared.cancel(id: id)
        } else {
            guard let next = reminders[i].nextOccurrence(after: Date()) else { return }
            reminders[i].scheduledAt = next
            reminders[i].status = .scheduled
            save()
            ReminderNotifications.shared.schedule(for: reminders[i])
        }
        notifyChanged()
    }

    func setStatus(id: String, _ status: ReminderStatus) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[i].status = status
        save()
        notifyChanged()
    }

    /// Enable / disable a reminder.
    /// Disabled reminders keep their data but stop firing; enabling recomputes
    /// the next occurrence (if it drifted into the past) and re-schedules.
    func setEnabled(id: String, _ enabled: Bool) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[i].enabled = enabled
        reminders[i].status = .scheduled
        if enabled {
            if reminders[i].frequency != .once, reminders[i].scheduledAt <= Date(),
               let next = reminders[i].nextOccurrence(after: Date()) {
                reminders[i].scheduledAt = next
            }
            save()
            ReminderNotifications.shared.schedule(for: reminders[i])
        } else {
            save()
            ReminderNotifications.shared.cancel(id: id)
        }
        notifyChanged()
    }

    func delete(id: String) {
        ReminderNotifications.shared.cancel(id: id)
        reminders.removeAll { $0.id == id }
        save()
        notifyChanged()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? decoder.decode([Reminder].self, from: data) else {
            return
        }
        reminders = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(reminders) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .remindersDidChange, object: nil)
    }
}
