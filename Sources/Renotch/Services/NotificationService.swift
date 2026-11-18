import AppKit
import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    private override init() {
        super.init()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // Deliver banners and sound even when app is frontmost or accessory
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    func playTimerSound() {
        if let sound = NSSound(named: "Glass") ?? NSSound(named: "Ping") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    /// Schedule an OS-level notification so it fires even if the app quits or
    /// the Mac sleeps. Returns the request identifier (needed to cancel).
    @discardableResult
    func scheduleTimerFinished(
        after interval: TimeInterval,
        mode: PomodoroMode = .focus,
        breakMinutes: Int = 5,
        autoAdvance: Bool = true
    ) -> String {
        let id = "virtual-notch-timer-\(UUID().uuidString)"
        guard let center else { return id }

        let content = UNMutableNotificationContent()
        switch mode {
        case .focus:
            content.title = "Focus Session Finished"
            content.body = autoAdvance
                ? "Great work! Starting \(breakMinutes)-minute break now."
                : "Great work! Time to take a break."
        case .breakTime:
            content.title = "Break Finished"
            content.body = "Ready to start your next focus session?"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(0.5, interval), repeats: false)
        )
        center.add(request)
        return id
    }

    func cancelScheduled(_ id: String) {
        guard !id.isEmpty else { return }
        center?.removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Schedule a calendar-based reminder for a to-do. The `date` is the
    /// absolute fire time (already offset from the due date); it survives an
    /// app quit and uses the same identifier the caller passes in for cancels.
    func scheduleTodoReminder(title: String, at date: Date, identifier: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "To-Do Reminder"
        content.body = title
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    func timerFinished(mode: PomodoroMode = .focus, breakMinutes: Int = 5, autoAdvance: Bool = true) {
        playTimerSound()

        guard let center else { return }
        let content = UNMutableNotificationContent()
        switch mode {
        case .focus:
            content.title = "Focus Session Finished"
            content.body = autoAdvance
                ? "Great work! Starting \(breakMinutes)-minute break now."
                : "Great work! Time to take a break."
        case .breakTime:
            content.title = "Break Finished"
            content.body = "Ready to start your next focus session?"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "virtual-notch-timer-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}

