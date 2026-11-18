import SwiftUI

struct CompactCalendarView: View {
    @ObservedObject var service: AppleCalendarService

    private var nextEvent: CalendarEventItem? {
        service.accessState == .authorized ? service.nextEvent : nil
    }

    var body: some View {
        HStack(spacing: 9) {
            dateTile

            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(subline)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(Color.notchMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 4)

            if let nextEvent {
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(relativeCountdown(to: nextEvent.startDate) ?? nextEvent.shortTime)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(isImminent(nextEvent.startDate) ? Color(red: 0.96, green: 0.38, blue: 0.38) : Color.notchAccent)
                        .lineLimit(1)
                        .fixedSize()
                        .contentTransition(.numericText())
                }
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Relative countdown to the event, or nil when it is a day or more out
    /// (in which case the plain clock time reads better).
    private func relativeCountdown(to date: Date) -> String? {
        let interval = date.timeIntervalSinceNow
        guard interval < 86_400 else { return nil }
        if interval <= 60 { return "now" }
        if interval < 3_600 {
            return "in \(max(1, Int(interval / 60)))m"
        }
        let hours = Int(interval / 3_600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3_600) / 60)
        return minutes == 0 ? "in \(hours)h" : "in \(hours)h \(minutes)m"
    }

    /// True when the event starts within 15 minutes — used for the urgency tint.
    private func isImminent(_ date: Date) -> Bool {
        let interval = date.timeIntervalSinceNow
        return interval > 0 && interval < 15 * 60
    }

    /// Mini calendar tile showing the next event's date (or today when there
    /// is nothing upcoming), replacing the plain calendar glyph. The square
    /// scales down when the compact bar is configured shorter than usual so
    /// it never overflows the container.
    private var dateTile: some View {
        let date = nextEvent?.startDate ?? Date()
        let connected = service.accessState == .authorized
        return VStack(spacing: 0) {
            Text(date.formatted(.dateTime.weekday(.narrow)).uppercased())
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundStyle(connected ? Color.notchAccent : Color.notchMuted)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 24, maxHeight: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.notchAccent.opacity(connected ? 0.14 : 0.07))
        )
        .accessibilityHidden(true)
    }

    private var headline: String {
        switch service.accessState {
        case .authorized:
            return nextEvent?.title ?? "No upcoming events"
        case .notDetermined:
            return "Connect Apple Calendar"
        case .requesting:
            return "Connecting…"
        case .denied, .restricted:
            return "Calendar access is off"
        }
    }

    private var subline: String {
        switch service.accessState {
        case .authorized:
            guard let nextEvent else { return "Nothing in the next 14 days" }
            return "\(nextEvent.dayLabel) · \(nextEvent.calendarTitle)"
        case .notDetermined:
            return "Tap to grant access"
        case .requesting:
            return "Waiting for permission"
        case .denied, .restricted:
            return "Enable access in System Settings"
        }
    }

    private var accessibilityText: String {
        if let nextEvent {
            return "Next event: \(nextEvent.title), \(nextEvent.dayLabel) at \(nextEvent.shortTime)"
        }
        return "Calendar: \(headline), \(subline)"
    }
}
