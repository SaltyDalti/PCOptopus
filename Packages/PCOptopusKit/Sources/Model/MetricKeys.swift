import Foundation

/// Canonical metric keys for v1. Parallel sensor agents must agree on these strings.
public enum MetricKey: String, Codable, Sendable, CaseIterable {
    case cpuUsedFraction = "cpu.usedFraction"
    case cpuPerformanceCores = "cpu.performanceCores"
    case cpuEfficiencyCores = "cpu.efficiencyCores"
    case memoryPressure = "memory.pressure"
    case memoryCompressorBytes = "memory.compressorBytes"
    case memorySwapBytes = "memory.swapBytes"
    case memoryPhysicalBytes = "memory.physicalBytes"
    case storageContainerBytes = "storage.containerBytes"
    case storageAvailableBytes = "storage.availableBytes"
    case storagePurgeableBytes = "storage.purgeableBytes"
    case storageUsedFraction = "storage.usedFraction"
    case energyPowerSource = "energy.powerSource"
    case energyLowPowerMode = "energy.lowPowerMode"
    case energyThermalState = "energy.thermalState"
    case energyACSleepMinutes = "energy.ac.sleepMinutes"
    case energyACDisplaySleepMinutes = "energy.ac.displaySleepMinutes"
    case energyACDiskSleepMinutes = "energy.ac.diskSleepMinutes"
    case energyACPowerNap = "energy.ac.powernap"
    case energyACWomp = "energy.ac.womp"
    case energyBatterySleepMinutes = "energy.battery.sleepMinutes"
    case energyBatteryDisplaySleepMinutes = "energy.battery.displaySleepMinutes"
    case energyAssertionsPreventSleep = "energy.assertions.preventSleep"
    case energyAssertionProcess = "energy.assertions.processName"
    case energyAssertionMinutes = "energy.assertions.heldMinutes"
    case energyClamshell = "energy.clamshell"
    case backgroundUserAgentCount = "background.userAgentCount"
    case backgroundAgentLabels = "background.agentLabels"
    case softwareBrewPrefixes = "software.brewPrefixes"
    case softwareBrewPathArch = "software.brewPathArch"
    case networkBytesPerSecond = "network.bytesPerSecond"
    case machineName = "machine.name"
    case machineModel = "machine.model"
    case machineChip = "machine.chip"
    case machineGPUCores = "machine.gpuCores"
    case machineMemoryBytes = "machine.memoryBytes"
    case machineOSVersion = "machine.osVersion"
    case machineSIP = "machine.sipEnabled"
}

public enum PowerSourceValue: String, Codable, Sendable {
    case ac = "AC"
    case battery = "Battery"
    case ups = "UPS"
    case unknown = "Unknown"
}

public enum MemoryPressureValue: String, Codable, Sendable {
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"
    case unknown = "Unknown"
}

public enum ThermalStateValue: String, Codable, Sendable {
    case nominal = "Nominal"
    case fair = "Fair"
    case serious = "Serious"
    case critical = "Critical"
}
