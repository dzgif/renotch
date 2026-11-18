import SwiftUI

/// Compact single-row system monitor: three consistent percentage chips.
/// RAM is shown as memory pressure (percentage) to match CPU and battery width,
/// so the row never overflows the notch regardless of compact width.
struct CompactSystemView: View {
    @ObservedObject var service: SystemMonitorService

    var body: some View {
        HStack(spacing: 6) {
            chip(icon: "cpu", value: cpuText, tint: cpuTint)
            chip(icon: "memorychip", value: ramText, tint: ramTint)
            chip(icon: "internaldrive", value: diskText, tint: diskTint)
            if service.metrics.hasBattery {
                chip(icon: batteryIcon, value: batteryText, tint: batteryTint)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("CPU \(cpuText), memory \(ramText), disk \(diskText)" + (service.metrics.hasBattery ? ", battery \(batteryText)" : ""))
    }

    private func chip(icon: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 0.5))
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

    private var ramTint: Color {
        guard let pressure = service.metrics.memoryPressure else { return .notchMuted }
        switch pressure {
        case ..<0.6: return Color.notchAccent
        case ..<0.85: return Color(red: 0.98, green: 0.72, blue: 0.38)
        default: return Color(red: 0.96, green: 0.38, blue: 0.38)
        }
    }

    private var diskText: String {
        guard let pressure = service.metrics.diskPressure else { return "—" }
        return SystemMetricFormatting.percent(pressure)
    }

    private var diskTint: Color {
        guard let pressure = service.metrics.diskPressure else { return .notchMuted }
        switch pressure {
        case ..<0.8: return Color.notchAccent
        case ..<0.9: return Color(red: 0.98, green: 0.72, blue: 0.38)
        default: return Color(red: 0.96, green: 0.38, blue: 0.38)
        }
    }

    private var batteryText: String {
        guard let level = service.metrics.batteryLevel else { return "—" }
        return SystemMetricFormatting.percent(level)
    }

    private var batteryIcon: String {
        guard let level = service.metrics.batteryLevel else { return "battery.0percent" }
        if service.metrics.isCharging { return "battery.100percent.bolt" }
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
