import Darwin
import Foundation
import IOKit.ps

/// Polls CPU, memory, and battery metrics for the notch system monitor.
///
/// CPU usage is derived from two consecutive `host_processor_info` samples
/// (delta of user/system/nice over total). Memory comes from `host_statistics64`
/// (active + wired + compressed). Battery comes from IOKit power sources and is
/// nil on Macs without an internal battery.
@MainActor
final class SystemMonitorService: ObservableObject {
    @Published private(set) var metrics: SystemMetrics = .idle

    private var refreshTimer: Timer?
    private var currentInterval: TimeInterval = 5.0

    /// Cumulative CPU tick counts from the previous sample, used to compute a delta.
    private var previousCPUTicks: CPUTicks?

    init() {
        start()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        guard currentInterval != interval else { return }
        currentInterval = interval
        startTimer(interval: interval)
    }

    func pause() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func resume() {
        guard refreshTimer == nil else { return }
        startTimer(interval: currentInterval)
    }

    func refresh() {
        let cpu = sampleCPU()
        let memory = sampleMemory()
        let disk = sampleDisk()
        let battery = sampleBattery()

        metrics = SystemMetrics(
            cpuUsage: cpu ?? metrics.cpuUsage,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            diskUsed: disk.used,
            diskTotal: disk.total,
            batteryLevel: battery.level,
            isCharging: battery.isCharging,
            hasBattery: battery.hasBattery
        )
    }

    private func start() {
        startTimer(interval: currentInterval)
    }

    private func startTimer(interval: TimeInterval) {
        refreshTimer?.invalidate()
        refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.5
        refreshTimer = timer
    }

    // MARK: - CPU

    private struct CPUTicks {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64
    }

    private func sampleCPU() -> Double? {
        var processorCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &infoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0
        for index in 0..<Int(processorCount) {
            let ticks = cpuInfo.advanced(by: index * Int(CPU_STATE_MAX))
            user += UInt64(UInt32(bitPattern: ticks[Int(CPU_STATE_USER)]))
            system += UInt64(UInt32(bitPattern: ticks[Int(CPU_STATE_SYSTEM)]))
            idle += UInt64(UInt32(bitPattern: ticks[Int(CPU_STATE_IDLE)]))
            nice += UInt64(UInt32(bitPattern: ticks[Int(CPU_STATE_NICE)]))
        }

        let current = CPUTicks(user: user, system: system, idle: idle, nice: nice)
        guard let previous = previousCPUTicks else {
            previousCPUTicks = current
            return nil
        }
        previousCPUTicks = current

        let userDelta = current.user &- previous.user
        let systemDelta = current.system &- previous.system
        let idleDelta = current.idle &- previous.idle
        let niceDelta = current.nice &- previous.nice
        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
        guard totalDelta > 0 else { return nil }
        return Double(userDelta + systemDelta + niceDelta) / Double(totalDelta)
    }

    // MARK: - Memory

    private func sampleMemory() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let total = ProcessInfo.processInfo.physicalMemory
        return (used, total)
    }

    // MARK: - Disk

    private func sampleDisk() -> (used: UInt64, total: UInt64) {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return (0, 0)
        }
        let totalInt64 = Int64(total)
        let used = UInt64(max(0, totalInt64 - available))
        return (used, UInt64(totalInt64))
    }

    // MARK: - Battery

    private func sampleBattery() -> (level: Double?, isCharging: Bool, hasBattery: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return (nil, false, false)
        }
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, false, false)
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            let level = (description[kIOPSCurrentCapacityKey] as? Int).map { Double($0) / 100.0 }
            let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            return (level, isCharging, true)
        }

        return (nil, false, false)
    }
}
