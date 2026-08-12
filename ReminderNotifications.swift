import AppKit
import Foundation
import UserNotifications

/// macOS native notification handling for reminders (UNUserNotificationCenter).
///
/// - One notification per reminder, identified by the reminder id (no duplicates).
/// - Notifications are scheduled by the OS (event-driven, zero app timers).
/// - Every schedule call first ensures permission (requests it if needed);
///   if permission is denied, the user is gently told once per launch.
/// - Deleted / completed / disabled reminders have their pending + delivered
///   notifications cancelled/removed, and orphaned notifications are cleaned up.
final class ReminderNotifications {

    static let shared = ReminderNotifications()
    private init() {}

    private lazy var center = UNUserNotificationCenter.current()

    /// Notifications need a proper app bundle (bundle identifier).
    /// When running unbundled (e.g. a raw CLI binary), skip safely.
    private var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    private var didWarnDenied = false

    // MARK: - Permission

    /// Ask the user once for notification permission (idempotent).
    func requestPermissionIfNeeded() {
        guard isAvailable else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Ensure permission is granted; requests it if not yet determined.
    /// Calls `completion(true)` when notifications may be delivered.
    private func ensurePermission(completion: @escaping (Bool) -> Void) {
        guard isAvailable else { completion(false); return }
        center.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                self?.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    completion(granted)
                }
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .denied:
                self?.warnDeniedOnce()
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }

    /// A gentle one-time (per launch) notice when notifications are off.
    private func warnDeniedOnce() {
        guard !didWarnDenied else { return }
        didWarnDenied = true
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "🔔 通知未开启"
            alert.informativeText = "DAL-E 提醒需要 macOS 通知权限。\n请在 系统设置 → 通知 → Dal-E 中开启通知，提醒才会出现在通知中心。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }

    // MARK: - Schedule

    /// Schedule (or update) the notification for a single reminder.
    /// Passed a reminder that is completed/disabled or already in the past,
    /// it just cancels. Permission is ensured before scheduling.
    func schedule(for reminder: Reminder) {
        guard isAvailable else { return }
        ensurePermission { [weak self] granted in
            guard let self, granted else { return }
            self.scheduleNow(reminder)
        }
    }

    private func scheduleNow(_ reminder: Reminder) {
        // Replace any existing notification for this reminder (update, no duplicates).
        center.removePendingNotificationRequests(withIdentifiers: [reminder.id])

        guard !reminder.isCompleted, reminder.enabled, reminder.scheduledAt > Date() else {
            center.removeDeliveredNotifications(withIdentifiers: [reminder.id])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "🐿️ DAL-E Reminder"
        content.body = "Time to \(reminder.title)!"
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminder.scheduledAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                NSLog("DAL-E notification scheduling failed: %@", error.localizedDescription)
            }
        }
    }

    /// Cancel pending + remove delivered notification for one reminder.
    func cancel(id: String) {
        guard isAvailable else { return }
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    // MARK: - Reconcile

    /// Reconcile notifications with the store (called at app launch):
    /// future pending reminders get notifications, everything else is cancelled,
    /// and any orphaned notification (not matching a stored reminder) is removed.
    func refreshAll() {
        let store = ReminderStore.shared
        let now = Date()
        let knownIDs = Set(store.all.map { $0.id })
        for r in store.all {
            if r.isCompleted || !r.enabled || r.scheduledAt <= now {
                cancel(id: r.id)
            } else {
                schedule(for: r)
            }
        }
        // Clean up orphaned notifications (removed reminders, old test data…).
        center.getPendingNotificationRequests { [weak self] requests in
            let orphans = requests.map { $0.identifier }.filter { !knownIDs.contains($0) }
            if !orphans.isEmpty {
                self?.center.removePendingNotificationRequests(withIdentifiers: orphans)
                self?.center.removeDeliveredNotifications(withIdentifiers: orphans)
            }
        }
    }
}
