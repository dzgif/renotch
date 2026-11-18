import Foundation

/// Snapshot of live system metrics for the notch system monitor.
struct SystemMetrics: Equatable, Sendable {
    /// CPU usage as a fraction 0...1. Nil until the first two samples are taken.
    let cpuUsage: Double?
    /// Used physical memory in bytes.
    let memoryUsed: UInt64
    /// Total physical memory in bytes.
    let memoryTotal: UInt64
    /// Used disk space on the root volume in bytes.
    let diskUsed: UInt64
    /// Total disk capacity of the root volume in bytes.
    let diskTotal: UInt64
    /// Battery level as a fraction 0...1. Nil when no battery (desktop) or unknown.
    let batteryLevel: Double?
    /// True when plugged in and charging.
    let isCharging: Bool
    /// True when the Mac has an internal battery (i.e. a laptop).
    let hasBattery: Bool

    static let idle = SystemMetrics(
        cpuUsage: nil,
        memoryUsed: 0,
        memoryTotal: 0,
        diskUsed: 0,
        diskTotal: 0,
        batteryLevel: nil,
        isCharging: false,
        hasBattery: false
    )

    /// Memory pressure as a fraction 0...1.
    var memoryPressure: Double? {
        guard memoryTotal > 0 else { return nil }
        return Double(memoryUsed) / Double(memoryTotal)
    }

    /// Disk usage as a fraction 0...1 of the root volume.
    var diskPressure: Double? {
        guard diskTotal > 0 else { return nil }
        return Double(diskUsed) / Double(diskTotal)
    }
}

enum SystemMetricFormatting {
    /// Formats bytes as a compact human-readable string (e.g. "12.4 GB").
    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.includesUnit = true
        formatter.isAdaptive = false
        return formatter.string(fromByteCount: Int64(value))
    }

    /// Formats a 0...1 fraction as a percentage with no decimals.
    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
