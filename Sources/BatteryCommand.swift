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

    let chargeEmoji: String
    switch percent {
    case 60...100: chargeEmoji = "🟢"
    case 20...59:  chargeEmoji = "🟡"
    default:       chargeEmoji = "🔴"
    }

    let healthEmoji: String
    switch health {
    case 80...200: healthEmoji = "🟢"
    case 50...79:  healthEmoji = "🟡"
    default:       healthEmoji = "🔴"
    }

    let tempEmoji: String
    switch tempC {
    case ...35:    tempEmoji = "🟢"
    case 35.1...40: tempEmoji = "🟡"
    default:       tempEmoji = "🔴"
    }

    print("Battery:")
    print("  Charge:      \(chargeEmoji) \(percent)%")
    print("  Status:      \(status)")
    print("  Time:        \(timeStr)")
    print("  Health:      \(healthEmoji) \(health)% (\(maxCap)/\(designCap) mAh)")
    print("  Cycles:      \(cycleCount)")
    print("  Temperature: \(tempEmoji) \(String(format: "%.1f", tempC))°C")
}
