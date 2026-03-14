import Foundation
import CoreWLAN

private func getLocalIP() -> String {
    var address = "N/A"
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
    defer { freeifaddrs(ifaddr) }

    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let name = String(cString: ptr.pointee.ifa_name)
        let family = ptr.pointee.ifa_addr.pointee.sa_family
        if name == "en0" && family == UInt8(AF_INET) {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)
        }
    }
    return address
}

func runWiFiCommand() {
    guard let iface = CWWiFiClient.shared().interface() else {
        print("No WiFi interface found.")
        return
    }

    let ssid = iface.ssid() ?? "Not connected"
    let bssid = iface.bssid() ?? "N/A"
    let rssi = iface.rssiValue()
    let noise = iface.noiseMeasurement()
    let channel = iface.wlanChannel()
    let txRate = iface.transmitRate()
    let ip = getLocalIP()

    let channelNumber = channel?.channelNumber ?? 0
    let channelBand: String
    if let ch = channel {
        channelBand = ch.channelBand == .band5GHz ? "5 GHz" : ch.channelBand == .band6GHz ? "6 GHz" : "2.4 GHz"
    } else {
        channelBand = "unknown"
    }

    if jsonMode {
        printJSON([
            "ssid": ssid,
            "bssid": bssid,
            "rssi": rssi,
            "noise": noise,
            "channel": channelNumber,
            "channel_band": channelBand,
            "tx_rate": txRate,
            "ip": ip,
        ])
        return
    }

    let signalQuality: String
    switch rssi {
    case -30...0:    signalQuality = "Excellent"
    case -50...(-31): signalQuality = "Good"
    case -60...(-51): signalQuality = "Fair"
    case -70...(-61): signalQuality = "Weak"
    default:         signalQuality = "Poor"
    }

    print("WiFi:")
    print("  Network:    \(ssid)")
    print("  BSSID:      \(bssid)")
    print("  Signal:     \(rssi) dBm (\(signalQuality))")
    print("  Noise:      \(noise) dBm")
    if let ch = channel {
        print("  Channel:    \(ch.channelNumber) (\(ch.channelBand == .band5GHz ? "5 GHz" : ch.channelBand == .band6GHz ? "6 GHz" : "2.4 GHz"))")
    }
    print("  TX Rate:    \(String(format: "%.0f", txRate)) Mbps")
    print("  IP:         \(ip)")
}
