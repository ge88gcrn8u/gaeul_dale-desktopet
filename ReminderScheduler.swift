import Foundation
import Dispatch
import os

/// Power-efficiency design:
/// - A single one-shot DispatchSourceTimer armed to the *next* future reminder.
/// - No periodic polling. When nothing is pending, the timer is cancelled and
///   the app sleeps (DAL-E stays completely idle).
/// - Whenever reminders change (create / complete / snooze / edit / delete /
///   startup), `remindersChanged()` recalculates: mark newly-due reminders,
///   present the next due one (one at a time — a queue, never multiple
///   windows), then re-arm the one timer.
final class ReminderScheduler {

    static let shared = ReminderScheduler()

    private let log = Logger(subsystem: "com.squirrelpet.dale", category: "ReminderScheduler")
    private let store = ReminderStore.shared
    private var timer: DispatchSourceTimer?
    private(set) var activeReminderID: String?

    /// When the current active reminder was presented (used for auto-expiry).
    private var activeSince: Date?
    private var expiryTimer: DispatchSourceTimer?

    /// How long a reminder may stay "active" (DAL-E jumping, left-click opens
    /// the completion dialog) before it auto-silences back to `.due`. Prevents
    /// the pet from jumping all night and hijacking every left-click.
    private let activeReminderTimeout: TimeInterval = 30 * 60

    /// Reminders that already rang and auto-expired this session. Keyed by
    /// "id|scheduledAt" so the *next* occurrence of a recurring reminder can
    /// ring again; cleared on restart (due reminders re-present per design).
    private var suppressedDueKeys: Set<String> = []

    /// Called when a due reminder should be presented (wake DAL-E + jump).
    var onActivate: ((Reminder) -> Void)?
    /// Called when no reminder is being presented anymore (stop jump).
    var onIdle: (() -> Void)?

    var hasActiveReminder: Bool { activeReminderID != nil }
    var activeReminder: Reminder? {
        guard let id = activeReminderID else { return nil }
        return store.reminder(id: id)
    }

    // MARK: - Lifecycle

    /// Start the scheduler (call once at app launch).
    func start() {
        remindersChanged()
    }

    /// Re-evaluate due reminders and the next timer.
    /// Call after any create / complete / snooze / edit / delete.
    func remindersChanged() {
        let now = Date()

        // 0. Auto-expire a reminder that has been active too long (e.g. it rang
        //    while the user was away): stop the jump, keep it as `.due` so it
        //    stays visible, and don't re-present this same occurrence.
        if let id = activeReminderID, let since = activeSince,
           now.timeIntervalSince(since) > activeReminderTimeout {
            log.info("⏰ Reminder \(id, privacy: .public) active too long — expiring")
            expireActiveReminder(id: id)
        }

        // 1. Drop the active reminder if it no longer exists, is completed,
        //    disabled, or was edited/snoozed into the future.
        if let id = activeReminderID, let r = store.reminder(id: id) {
            let stillActive = !r.isCompleted && r.enabled && r.scheduledAt <= now
            if !stillActive {
                log.info("⏰ Reminder \(id, privacy: .public) no longer active — idle")
                activeReminderID = nil
                activeSince = nil
                cancelExpiryTimer()
                onIdle?()
            }
        } else if activeReminderID != nil {
            activeReminderID = nil
            activeSince = nil
            cancelExpiryTimer()
            onIdle?()
        }

        // 2. Mark newly-due reminders (scheduled → due).
        for r in store.all where !r.isCompleted && r.status == .scheduled && r.scheduledAt <= now {
            store.setStatus(id: r.id, .due)
        }

        // 3. If nothing is active, present the earliest due reminder (queue).
        if activeReminderID == nil, let due = nextDueReminder(at: now) {
            store.setStatus(id: due.id, .active)
            activeReminderID = due.id
            activeSince = now
            log.info("⏰ Reminder \(due.title, privacy: .public) due — activating (jump)")
            onActivate?(due)
        }

        // 4. Arm a single one-shot timer for the next future reminder.
        armNextTimer()
        armExpiryTimer()
    }

    /// Stop presenting the current reminder (call after complete / snooze / edit / delete).
    func stopActive() {
        guard activeReminderID != nil else { return }
        log.info("⏰ Stop presenting active reminder")
        activeReminderID = nil
        activeSince = nil
        cancelExpiryTimer()
        onIdle?()
    }

    // MARK: - Auto-expiry

    private func nextDueReminder(at now: Date) -> Reminder? {
        store.pending
            .filter { $0.scheduledAt <= now && !suppressedDueKeys.contains(suppressionKey(for: $0)) }
            .min { $0.scheduledAt < $1.scheduledAt }
    }

    private func suppressionKey(for r: Reminder) -> String {
        "\(r.id)|\(r.scheduledAt.timeIntervalSince1970)"
    }

    private func expireActiveReminder(id: String) {
        if let r = store.reminder(id: id) {
            store.setStatus(id: id, .due)
            suppressedDueKeys.insert(suppressionKey(for: r))
        }
        activeReminderID = nil
        activeSince = nil
        cancelExpiryTimer()
        onIdle?()
    }

    private func armExpiryTimer() {
        expiryTimer?.cancel()
        expiryTimer = nil
        guard let since = activeSince, activeReminderID != nil else { return }
        let remaining = activeReminderTimeout - Date().timeIntervalSince(since)
        guard remaining > 0.05 else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + remaining, leeway: .seconds(1))
        t.setEventHandler { [weak self] in
            self?.expiryTimerDidFire()
        }
        t.resume()
        expiryTimer = t
    }

    private func cancelExpiryTimer() {
        expiryTimer?.cancel()
        expiryTimer = nil
    }

    private func expiryTimerDidFire() {
        expiryTimer = nil
        guard let id = activeReminderID, let since = activeSince,
              Date().timeIntervalSince(since) > activeReminderTimeout else { return }
        log.info("⏰ Reminder \(id, privacy: .public) timed out")
        expireActiveReminder(id: id)
        remindersChanged()
    }

    // MARK: - Timer

    private func armNextTimer() {
        timer?.cancel()
        timer = nil
        guard let next = store.nextPending(after: Date()) else { return }

        let delay = max(next.scheduledAt.timeIntervalSinceNow, 0.05)
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + delay, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.remindersChanged()
        }
        t.resume()
        timer = t
    }
}
