import Foundation
import IOKit

// MARK: - USB Speed mapping

private func speedDescription(_ speed: String) -> String {
    switch speed.lowercased() {
    case "low_speed", "1.5 mb/s":
        return "USB 1.1 Low Speed (1.5 Mbps)"
    case "full_speed", "12 mb/s":
        return "USB 1.1 Full Speed (12 Mbps)"
    case "high_speed", "480 mb/s":
        return "USB 2.0 High Speed (480 Mbps)"
    case "super_speed", "5 gb/s":
        return "USB 3.0 SuperSpeed (5 Gbps)"
    case "super_speed_plus", "10 gb/s":
        return "USB 3.1 SuperSpeed+ (10 Gbps)"
    case "super_speed_plus_by2", "20 gb/s":
        return "USB 3.2 (20 Gbps)"
    default:
        if speed.isEmpty { return "Unknown" }
        return speed
    }
}

private func speedFromNumeric(_ speed: Int) -> String {
    switch speed {
    case 0:  return "USB 1.1 Low Speed (1.5 Mbps)"
    case 1:  return "USB 1.1 Full Speed (12 Mbps)"
    case 2:  return "USB 2.0 High Speed (480 Mbps)"
    case 3:  return "USB 3.0 SuperSpeed (5 Gbps)"
    case 4:  return "USB 3.1 SuperSpeed+ (10 Gbps)"
    case 5:  return "USB 3.2 (20 Gbps)"
    default: return "Unknown (\(speed))"
    }
}

// MARK: - USB Device info

private struct USBDevice {
    let name: String
    let vendorName: String
    let vendorID: String
    let productID: String
    let serialNumber: String
    let speed: String
    let locationID: String
    let maxPower: String
    let children: [USBDevice]
}

// MARK: - Method 1: Parse system_profiler SPUSBHostDataType (macOS 26+)

private func getDevicesFromSystemProfiler() -> [USBDevice] {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    process.arguments = ["SPUSBHostDataType", "-json"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return []
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return []
    }

    let busArray = json["SPUSBHostDataType"] as? [[String: Any]]
        ?? json["SPUSBDataType"] as? [[String: Any]]
        ?? []

    var devices: [USBDevice] = []
    for bus in busArray {
        if let items = bus["_items"] as? [[String: Any]] {
            for item in items {
                devices.append(contentsOf: parseProfilerDevice(item))
            }
        }
    }
    return devices
}

private func parseProfilerDevice(_ item: [String: Any]) -> [USBDevice] {
    let name = item["_name"] as? String ?? "Unknown Device"
    let vendorID = item["vendor_id"] as? String ?? ""
    let productID = item["product_id"] as? String ?? ""
    let serialNumber = item["serial_num"] as? String ?? ""
    let speed = item["USBKeySpeed"] as? String ?? ""
    let locationID = item["USBKeyLocationID"] as? String
        ?? item["location_id"] as? String ?? ""
    let maxPower = item["USBKeyMaxPower"] as? String
        ?? item["bus_power"] as? String ?? ""
    let manufacturer = item["manufacturer"] as? String ?? ""

    var children: [USBDevice] = []
    if let items = item["_items"] as? [[String: Any]] {
        for child in items {
            children.append(contentsOf: parseProfilerDevice(child))
        }
    }

    let device = USBDevice(
        name: name,
        vendorName: manufacturer,
        vendorID: vendorID,
        productID: productID,
        serialNumber: serialNumber,
        speed: speedDescription(speed),
        locationID: locationID,
        maxPower: maxPower.isEmpty ? "0 mA" : maxPower,
        children: children
    )

    return [device]
}

// MARK: - Method 2: IOKit direct (fallback)

private func getDevicesFromIOKit() -> [USBDevice] {
    var devices: [USBDevice] = []
    let classNames = ["IOUSBHostDevice", "IOUSBDevice", "AppleUSBDevice"]

    for className in classNames {
        var iter = io_iterator_t()
        let matching = IOServiceMatching(className)
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            continue
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iter)
            }

            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            let name = props["USB Product Name"] as? String
                ?? props["kUSBProductString"] as? String
                ?? props["Product Name"] as? String
                ?? "Unknown Device"

            let vendorName = props["USB Vendor Name"] as? String
                ?? props["kUSBVendorString"] as? String
                ?? ""

            let vendorID = (props["idVendor"] as? Int).map { String(format: "0x%04x", $0) } ?? ""
            let productID = (props["idProduct"] as? Int).map { String(format: "0x%04x", $0) } ?? ""
            let serialNumber = props["USB Serial Number"] as? String
                ?? props["kUSBSerialNumberString"] as? String
                ?? ""
            let speed = props["UsbDeviceSpeed"] as? Int ?? props["Device Speed"] as? Int ?? -1
            let locationID = (props["locationID"] as? Int).map { String(format: "0x%08x", $0) } ?? ""
            let maxPowerRaw = props["bMaxPower"] as? Int ?? 0
            let maxPowerMA = speed >= 3 ? maxPowerRaw * 8 : maxPowerRaw * 2

            let device = USBDevice(
                name: name,
                vendorName: vendorName,
                vendorID: vendorID,
                productID: productID,
                serialNumber: serialNumber,
                speed: speedFromNumeric(speed),
                locationID: locationID,
                maxPower: "\(maxPowerMA) mA",
                children: []
            )
            devices.append(device)
        }

        if !devices.isEmpty { break }
    }

    return devices.sorted { $0.locationID < $1.locationID }
}

// MARK: - Power Adapter info from IOKit

private struct PowerAdapter {
    let name: String
    let watts: Int
    let vendor: String
    let productID: String
    let serialNumber: String
    let adapterVoltage: Int      // mV
    let maxCurrent: Int          // mA
    let liveWatts: Double
    let liveVoltage: Double      // V
    let liveCurrent: Double      // A
    let pdVersion: String
    let pdProfiles: [(voltage: Int, current: Int)] // mV, mA
}

private func getPowerAdapter() -> PowerAdapter? {
    var iter = io_iterator_t()
    let matching = IOServiceMatching("AppleSmartBattery")
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
        return nil
    }
    defer { IOObjectRelease(iter) }

    let service = IOIteratorNext(iter)
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }

    var propsRef: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let props = propsRef?.takeRetainedValue() as? [String: Any] else {
        return nil
    }

    guard let adapterDict = props["AdapterDetails"] as? [String: Any],
          let adapterName = adapterDict["Name"] as? String else {
        return nil
    }

    return parseAdapterDetails(adapterDict, name: adapterName, props: props)
}

private func parseAdapterDetails(_ adapter: [String: Any], name: String,
                                 props: [String: Any]) -> PowerAdapter {
    let watts = adapter["Watts"] as? Int ?? 0
    let vendor = adapter["Manufacturer"] as? String ?? ""
    let productID = adapter["Model"] as? String ?? ""
    let serial = adapter["SerialString"] as? String ?? ""
    let adapterVoltage = adapter["AdapterVoltage"] as? Int ?? 0
    let maxCurrent = adapter["Current"] as? Int ?? 0

    // Live power from PowerTelemetryData
    let telemetry = props["PowerTelemetryData"] as? [String: Any]
    let liveVoltageRaw = telemetry?["SystemVoltageIn"] as? Int ?? 0
    let liveCurrentRaw = telemetry?["SystemCurrentIn"] as? Int ?? 0
    let liveVoltage = Double(liveVoltageRaw) / 1000.0
    let liveCurrent = Double(liveCurrentRaw) / 1000.0
    let liveWatts = liveVoltage * liveCurrent

    // USB PD version from FedDetails
    let pdVersion = parsePdVersion(props)

    // PD voltage profiles from UsbHvcMenu
    var profiles: [(voltage: Int, current: Int)] = []
    if let menu = adapter["UsbHvcMenu"] as? [[String: Any]] {
        for entry in menu {
            let v = entry["MaxVoltage"] as? Int ?? 0
            let c = entry["MaxCurrent"] as? Int ?? 0
            if v > 0 { profiles.append((voltage: v, current: c)) }
        }
    }

    return PowerAdapter(
        name: name, watts: watts, vendor: vendor, productID: productID,
        serialNumber: serial, adapterVoltage: adapterVoltage, maxCurrent: maxCurrent,
        liveWatts: liveWatts, liveVoltage: liveVoltage, liveCurrent: liveCurrent,
        pdVersion: pdVersion, pdProfiles: profiles
    )
}

private func parsePdVersion(_ props: [String: Any]) -> String {
    guard let fedDetails = props["FedDetails"] as? [[String: Any]] else { return "" }
    for fed in fedDetails {
        if let rev = fed["FedPdSpecRevision"] as? Int, rev > 0 {
            return "USB PD \(rev + 1).0"
        }
    }
    return ""
}

private func printPowerAdapter(_ adapter: PowerAdapter) {
    print("Power Adapter:")
    print("")
    print("  \(adapter.name)")
    let maxV = Double(adapter.adapterVoltage) / 1000.0
    let maxA = Double(adapter.maxCurrent) / 1000.0
    print("  Power: \(adapter.watts) W (\(Int(maxV)) V up to \(Int(maxA)) A)")

    let liveStr = String(format: "%.1f W (%.1f V at %.2f A)",
                         adapter.liveWatts, adapter.liveVoltage, adapter.liveCurrent)
    print("  Live Power: \(liveStr)")

    if !adapter.pdVersion.isEmpty {
        print("  Version: \(adapter.pdVersion)")
    }
    if !adapter.vendor.isEmpty { print("  Vendor: \(adapter.vendor)") }
    if !adapter.productID.isEmpty { print("  Product: \(adapter.productID)") }
    if !adapter.serialNumber.isEmpty { print("  Serial: \(adapter.serialNumber)") }

    if !adapter.pdProfiles.isEmpty {
        let profileStrs = adapter.pdProfiles.map { p in
            "\(p.voltage / 1000)V/\(p.current / 1000)A"
        }
        print("  PD Profiles: \(profileStrs.joined(separator: ", "))")
    }
    print("")
}

private func adapterToJSON(_ adapter: PowerAdapter) -> [String: Any] {
    var dict: [String: Any] = [
        "name": adapter.name,
        "watts": adapter.watts,
        "vendor": adapter.vendor,
        "product_id": adapter.productID,
        "serial_number": adapter.serialNumber,
        "adapter_voltage_mv": adapter.adapterVoltage,
        "max_current_ma": adapter.maxCurrent,
        "live_watts": adapter.liveWatts,
        "live_voltage_v": adapter.liveVoltage,
        "live_current_a": adapter.liveCurrent,
    ]
    if !adapter.pdVersion.isEmpty { dict["pd_version"] = adapter.pdVersion }
    if !adapter.pdProfiles.isEmpty {
        dict["pd_profiles"] = adapter.pdProfiles.map { ["voltage_mv": $0.voltage, "current_ma": $0.current] }
    }
    return dict
}

// MARK: - Formatting

private func printDevice(_ device: USBDevice, prefix: String, indent: String, isLast: Bool) {
    let connector = isLast ? "└── " : "├── "
    let childIndent = isLast ? "    " : "│   "

    print("\(prefix)\(connector)\(device.name)")

    let info = prefix + childIndent
    if !device.vendorID.isEmpty {
        let vendor = device.vendorName.isEmpty
            ? "Vendor: \(device.vendorID)"
            : "Vendor: \(device.vendorName) (\(device.vendorID))"
        print("\(info)\(vendor)  Product: \(device.productID)")
    }

    if !device.speed.contains("Unknown") {
        print("\(info)Speed: \(device.speed)")
    }

    if !device.serialNumber.isEmpty {
        print("\(info)Serial: \(device.serialNumber)")
    }

    if device.maxPower != "0 mA" {
        print("\(info)Power: \(device.maxPower)")
    }

    if !device.locationID.isEmpty {
        print("\(info)Location: \(device.locationID)")
    }

    for (i, child) in device.children.enumerated() {
        let childIsLast = i == device.children.count - 1
        printDevice(child, prefix: info, indent: childIndent, isLast: childIsLast)
    }

    if !isLast {
        print("\(prefix)│")
    }
}

// MARK: - Command entry point

private func flattenDevices(_ devices: [USBDevice]) -> [[String: Any]] {
    var result: [[String: Any]] = []
    for device in devices {
        var dict: [String: Any] = [
            "name": device.name,
            "vendor_name": device.vendorName,
            "vendor_id": device.vendorID,
            "product_id": device.productID,
            "serial_number": device.serialNumber,
            "speed": device.speed,
            "location_id": device.locationID,
            "max_power": device.maxPower,
        ]
        if !device.children.isEmpty {
            dict["children"] = flattenDevices(device.children)
        }
        result.append(dict)
    }
    return result
}

func runUSBCommand() {
    var devices = getDevicesFromSystemProfiler()
    if devices.isEmpty {
        devices = getDevicesFromIOKit()
    }
    let adapter = getPowerAdapter()

    if jsonMode {
        var result: [String: Any] = ["devices": flattenDevices(devices)]
        if let adapter = adapter { result["power_adapter"] = adapterToJSON(adapter) }
        printJSON(result)
        return
    }

    if let adapter = adapter {
        printPowerAdapter(adapter)
    }

    if devices.isEmpty {
        if adapter == nil { print("No USB devices found.") }
        return
    }

    print("USB Devices (\(devices.count)):")
    print("")

    for (i, device) in devices.enumerated() {
        let isLast = i == devices.count - 1
        printDevice(device, prefix: "", indent: "", isLast: isLast)
    }
}
