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

func runUSBCommand() {
    var devices = getDevicesFromSystemProfiler()
    if devices.isEmpty {
        devices = getDevicesFromIOKit()
    }

    if devices.isEmpty {
        print("No USB devices found.")
        return
    }

    print("USB Devices (\(devices.count)):")
    print("")

    for (i, device) in devices.enumerated() {
        let isLast = i == devices.count - 1
        printDevice(device, prefix: "", indent: "", isLast: isLast)
    }
}
