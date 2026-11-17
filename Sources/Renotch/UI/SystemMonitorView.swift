import SwiftUI

/// Expanded system monitor: three compact metric rows (CPU / memory / battery),
/// each with a thin progress bar. Kept short so it fits the expanded notch height.
struct SystemMonitorView: View {
    @ObservedObject var service: SystemMonitorService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            metricRow(
                title: "CPU",
                icon: "cpu",
                tint: cpuTint,
                value: cpuText,
                progress: service.metrics.cpuUsage
            )

            Divider().overlay(Color.white.opacity(0.06))

            metricRow(
                title: "Memory",
                icon: "memorychip",
                tint: ramTint,
                value: ramText,
                detail: ramDetail,
                progress: service.metrics.memoryPressure
            )

            if service.metrics.hasBattery {
                Divider().overlay(Color.white.opacity(0.06))

                metricRow(
                    title: "Battery",
                    icon: service.metrics.isCharging ? "battery.100percent.bolt" : batteryIcon,
                    tint: batteryTint,
                    value: batteryText,
                    detail: service.metrics.isCharging ? "Charging" : "On battery",
                    progress: service.metrics.batteryLevel
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
    }

    private func metricRow(
        title: String,
        icon: String,
        tint: Color,
        value: String,
        detail: String? = nil,
        progress: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)

                if let detail {
                    Text(detail)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.notchMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.75), tint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * progress))
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private var cpuText: String {
        guard let cpu = service.metrics.cpuUsage else { return "—" }
        return SystemMetricFormatting.percent(cpu)
    }

    private var cpuTint: Color {
        guard let cpu = service.metrics.cpuUsage else { return .notchMuted }
        switch cpu {
        case ..<0.5: return Color.notchAccent
        case ..<0.8: return Color(red: 0.98, green: 0.72, blue: 0.38)
        default: return Color(red: 0.96, green: 0.38, blue: 0.38)
        }
    }

    private var ramText: String {
        guard let pressure = service.metrics.memoryPressure else { return "—" }
        return SystemMetricFormatting.percent(pressure)
    }

    private var ramDetail: String? {
        guard service.metrics.memoryUsed > 0, service.metrics.memoryTotal > 0 else { return nil }
        return "\(SystemMetricFormatting.bytes(service.metrics.memoryUsed)) / \(SystemMetricFormatting.bytes(service.metrics.memoryTotal))"
    }

    private var ramTint: Color {
        guard let pressure = service.metrics.memoryPressure else { return .notchMuted }
        switch pressure {
        case ..<0.6: return Color.notchAccent
        case ..<0.85: return Color(red: 0.98, green: 0.72, blue: 0.38)
        default: return Color(red: 0.96, green: 0.38, blue: 0.38)
        }
    }

    private var batteryText: String {
        guard let level = service.metrics.batteryLevel else { return "—" }
        return SystemMetricFormatting.percent(level)
    }

    private var batteryIcon: String {
        guard let level = service.metrics.batteryLevel else { return "battery.0percent" }
        switch level {
        case ..<0.125: return "battery.0percent"
        case ..<0.375: return "battery.25percent"
        case ..<0.625: return "battery.50percent"
        case ..<0.875: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var batteryTint: Color {
        guard let level = service.metrics.batteryLevel else { return .notchMuted }
        if service.metrics.isCharging { return Color.notchAccent }
        switch level {
        case ..<0.2: return Color(red: 0.96, green: 0.38, blue: 0.38)
        case ..<0.5: return Color(red: 0.98, green: 0.72, blue: 0.38)
        default: return Color.notchAccent
        }
    }
}
