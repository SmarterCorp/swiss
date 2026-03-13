import Foundation
import IOKit

func runBatteryCommand() {
    let snapshot = IOServiceMatching("AppleSmartBattery")
    let service = IOServiceGetMatchingService(kIOMainPortDefault, snapshot)
    guard service != 0 else {
        print("No battery found (desktop Mac?).")
        return
    }
    defer { IOObjectRelease(service) }

    var propsRef: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let props = propsRef?.takeRetainedValue() as? [String: Any] else {
        print("Failed to read battery properties.")
        return
    }

    let currentCap = props["CurrentCapacity"] as? Int ?? 0
    let maxCap = props["MaxCapacity"] as? Int ?? 1
    let designCap = props["DesignCapacity"] as? Int ?? 1
    let cycleCount = props["CycleCount"] as? Int ?? 0
    let isCharging = props["IsCharging"] as? Bool ?? false
    let externalConnected = props["ExternalConnected"] as? Bool ?? false
    let timeToEmpty = props["AvgTimeToEmpty"] as? Int ?? 0
    let timeToFull = props["AvgTimeToFull"] as? Int ?? 0
    let temperature = props["Temperature"] as? Int ?? 0

    let percent = Int(round(Double(currentCap) / Double(maxCap) * 100))
    let health = Int(round(Double(maxCap) / Double(designCap) * 100))
    let tempC = Double(temperature) / 100.0

    let status: String
    if isCharging {
        status = "Charging"
    } else if externalConnected {
        status = "Connected (not charging)"
    } else {
        status = "On Battery"
    }

    let timeStr: String
    if isCharging && timeToFull > 0 && timeToFull < 65535 {
        timeStr = "\(timeToFull / 60)h \(timeToFull % 60)m to full"
    } else if !isCharging && timeToEmpty > 0 && timeToEmpty < 65535 {
        timeStr = "\(timeToEmpty / 60)h \(timeToEmpty % 60)m remaining"
    } else {
        timeStr = "Calculating..."
    }

    func sq(_ value: Int, good: ClosedRange<Int>, warn: ClosedRange<Int>) -> String {
        if good.contains(value) { return "🟩" }
        if warn.contains(value) { return "🟨" }
        return "🟥"
    }

    func sqTemp(_ t: Double) -> String {
        if t <= 35   { return "🟩" }
        if t <= 40   { return "🟨" }
        return "🟥"
    }

    let w = 13 // label column width
    let pad = "  " // square column placeholder (2 chars to match emoji width)
    print("Battery:")
    print("  \("Charge".padding(toLength: w, withPad: " ", startingAt: 0)) \(sq(percent, good: 60...100, warn: 20...59)) \(percent)%")
    print("  \("Status".padding(toLength: w, withPad: " ", startingAt: 0)) \(pad) \(status)")
    print("  \("Time".padding(toLength: w, withPad: " ", startingAt: 0)) \(pad) \(timeStr)")
    print("  \("Health".padding(toLength: w, withPad: " ", startingAt: 0)) \(sq(health, good: 80...200, warn: 50...79)) \(health)% (\(maxCap)/\(designCap) mAh)")
    print("  \("Cycles".padding(toLength: w, withPad: " ", startingAt: 0)) \(pad) \(cycleCount)")
    print("  \("Temperature".padding(toLength: w, withPad: " ", startingAt: 0)) \(sqTemp(tempC)) \(String(format: "%.1f", tempC))°C")
}
