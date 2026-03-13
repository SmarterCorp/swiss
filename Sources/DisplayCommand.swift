import Foundation
import CoreGraphics

// MARK: - Private API

typealias CGSConfigureDisplayEnabledFunc = @convention(c) (
    CGDisplayConfigRef?, CGDirectDisplayID, Bool
) -> CGError

@_silgen_name("CoreDisplay_DisplayCreateInfoDictionary")
func CoreDisplay_DisplayCreateInfoDictionary(_ displayID: CGDirectDisplayID) -> Unmanaged<CFDictionary>?

// MARK: - Display helpers

private func getExternalDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &displays, &count)
    return displays.filter { CGDisplayIsBuiltin($0) == 0 }
}

private func displayName(for displayID: CGDirectDisplayID) -> String {
    if let info = CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as? [String: Any],
       let names = info["DisplayProductName"] as? [String: String],
       let name = names["en_US"] ?? names.values.first {
        return name
    }
    return "Display(\(displayID))"
}

// MARK: - State file

private let stateFile = NSString("~/.swiss-display-state").expandingTildeInPath

private func saveDisabledDisplays(_ ids: [CGDirectDisplayID]) {
    let data = ids.map { String($0) }.joined(separator: "\n")
    try? data.write(toFile: stateFile, atomically: true, encoding: .utf8)
}

private func loadDisabledDisplays() -> [CGDirectDisplayID] {
    guard let data = try? String(contentsOfFile: stateFile, encoding: .utf8) else { return [] }
    return data.split(separator: "\n").compactMap { UInt32($0) }
}

private func clearState() {
    try? FileManager.default.removeItem(atPath: stateFile)
}

// MARK: - Display toggle

private func setDisplayEnabled(_ displayID: CGDirectDisplayID, enabled: Bool, using fn: CGSConfigureDisplayEnabledFunc) -> Bool {
    var config: CGDisplayConfigRef?
    let beginResult = CGBeginDisplayConfiguration(&config)
    guard beginResult == .success else {
        print("  CGBeginDisplayConfiguration failed: \(beginResult.rawValue)")
        return false
    }

    let configureResult = fn(config, displayID, enabled)
    guard configureResult == .success else {
        print("  CGSConfigureDisplayEnabled failed: \(configureResult.rawValue)")
        CGCancelDisplayConfiguration(config)
        return false
    }

    let completeResult = CGCompleteDisplayConfiguration(config, .permanently)
    guard completeResult == .success else {
        print("  CGCompleteDisplayConfiguration failed: \(completeResult.rawValue)")
        return false
    }

    return true
}

// MARK: - Command entry point

func runDisplayCommand(args: [String]) {
    guard let action = args.first, action == "on" || action == "off" else {
        print("Usage: swiss display <on|off>")
        exit(1)
    }

    guard let handle = dlopen(nil, RTLD_NOW),
          let sym = dlsym(handle, "CGSConfigureDisplayEnabled") else {
        print("Error: CGSConfigureDisplayEnabled not found.")
        exit(1)
    }
    let configureDisplayEnabled = unsafeBitCast(sym, to: CGSConfigureDisplayEnabledFunc.self)

    if action == "off" {
        let externals = getExternalDisplays()
        if externals.isEmpty {
            print("No external monitors found.")
            exit(0)
        }

        var disabled: [CGDirectDisplayID] = []
        for displayID in externals {
            let name = displayName(for: displayID)
            print("Disconnecting \(name) (id: \(displayID))...")

            if setDisplayEnabled(displayID, enabled: false, using: configureDisplayEnabled) {
                print("  Done")
                disabled.append(displayID)
            } else {
                print("  Failed to disconnect")
            }
        }

        if !disabled.isEmpty {
            saveDisabledDisplays(disabled)
            print("\nTo reconnect: swiss display on")
        }

    } else {
        let savedIDs = loadDisabledDisplays()
        if savedIDs.isEmpty {
            print("No saved disconnected monitors.")
            print("Try first: swiss display off")
            exit(1)
        }

        for displayID in savedIDs {
            print("Reconnecting display (id: \(displayID))...")

            if setDisplayEnabled(displayID, enabled: true, using: configureDisplayEnabled) {
                print("  Done")
            } else {
                print("  Failed to reconnect")
            }
        }

        clearState()
        print("\nDone.")
    }
}
