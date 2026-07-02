import Foundation
import IOKit.hid
import QuakeHID
import QuakePluginAPI
import QuakeRuntime

let rawArguments = Array(CommandLine.arguments.dropFirst())
let arguments = Set(rawArguments)
let listen = arguments.contains("--listen")
let wake = arguments.contains("--wake")
let selfTest = arguments.contains("--self-test")
let allHID = arguments.contains("--all-hid")
let ledOn = arguments.contains("--led-on")
let ledOff = arguments.contains("--led-off")
let ledTest = arguments.contains("--led-test")
let brightnessValue = parseBrightness(from: rawArguments)

if selfTest {
    runSelfTest()
    exit(0)
}

if let validateIndex = rawArguments.firstIndex(of: "--validate-plugin") {
    guard rawArguments.indices.contains(validateIndex + 1) else {
        fputs("--validate-plugin requires a manifest path\n", stderr)
        exit(64)
    }
    validatePluginManifest(at: rawArguments[validateIndex + 1])
    exit(0)
}

if let validateIndex = rawArguments.firstIndex(of: "--validate-theme") {
    guard rawArguments.indices.contains(validateIndex + 1) else {
        fputs("--validate-theme requires a theme manifest path\n", stderr)
        exit(64)
    }
    validateThemeManifest(at: rawArguments[validateIndex + 1])
    exit(0)
}

if ledOn || ledOff || ledTest || brightnessValue != nil {
    let quake = QuakeDevice { event in
        print(format(event))
    }
    do {
        try quake.start(wake: false)
        for diagnostic in quake.diagnostics {
            print("diag \(diagnostic)")
        }
        if let brightnessValue {
            let ok = quake.setBrightness(brightnessValue)
            print("brightness \(brightnessValue): \(ok)")
            _ = quake.sendControlFrame(QuakeProtocol.queryLuminance)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            quake.stop()
            exit(ok ? 0 : 2)
        }
        if ledTest {
            runLEDTransportTest(quake)
            quake.stop()
            exit(0)
        }
        let ok = quake.setKnobRing(enabled: ledOn)
        print(ledOn ? "knob LED on: \(ok)" : "knob LED off: \(ok)")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        quake.stop()
        exit(ok ? 0 : 2)
    } catch {
        fputs("LED command failed: \(error)\n", stderr)
        exit(2)
    }
}

let manager = HIDManager()
let devices = allHID ? manager.enumerateRelatedDevices() : manager.enumerateSupportedDevices()

print("DK-Quake HID probe")
print("==================")

if devices.isEmpty {
    print("No supported DK-Quake HID interfaces found.")
} else {
    for device in devices {
        let usagePage = device.usagePage.map { String(format: "0x%04X", $0) } ?? "-"
        let usage = device.usage.map { String(format: "0x%04X", $0) } ?? "-"
        let vendor = String(format: "0x%04X", device.vendorID)
        let product = String(format: "0x%04X", device.productID)
        let support = device.isSupported ? "supported" : "related"
        print("- \(device.interface.rawValue): VID \(vendor), PID \(product), usagePage \(usagePage), usage \(usage), \(support), product \(device.product ?? "-"), manufacturer \(device.manufacturer ?? "-"), transport \(device.transport ?? "-")")
    }
}

guard listen else {
    print("")
    print("Run with --self-test to verify protocol encoding/decoding without hardware.")
    print("Run with --validate-plugin <path> to decode and validate a plugin manifest.")
    print("Run with --validate-theme <path> to decode and validate a theme manifest.")
    print("Run with --all-hid to dump every related HID collection without usage-page filtering.")
    print("Run with --led-on, --led-off, or --led-test to test knob ring output reports.")
    print("Run with --brightness <0-255> to set and query screen luminance.")
    print("Run with --listen to open the device and print decoded events.")
    print("Add --wake to send safe screen wake, keep-alive, and state query commands.")
    exit(devices.isEmpty ? 1 : 0)
}

let quake = QuakeDevice { event in
    print(format(event))
}

do {
    try quake.start(wake: wake)
    for diagnostic in quake.diagnostics {
        print("diag \(diagnostic)")
    }
    print("")
    print("Listening. Press Ctrl-C to stop.")
    RunLoop.current.run()
} catch {
    fputs("Probe failed: \(error)\n", stderr)
    exit(2)
}

func format(_ event: RuntimeEvent) -> String {
    switch event.event {
    case .connected(let interface):
        return "connect \(interface)"
    case .disconnected(let interface):
        return "disconnect \(interface)"
    case .touch(let points):
        let body = points.map { "\($0.phase.rawValue)(x:\($0.x),y:\($0.y))" }.joined(separator: " ")
        return "touch \(body)"
    case .knob(let knob):
        switch knob {
        case .rotate(let direction):
            return "knob rotate \(direction)"
        case .press(let index):
            return "knob press index=\(index)"
        case .holdStart:
            return "knob hold start"
        case .holdEnd:
            return "knob hold end"
        }
    case .key(let row, let column, let isDown):
        return isDown ? "key down row=\(row) column=\(column)" : "key up"
    case .state(let state):
        switch state {
        case .firmware(let name, let version):
            return "state firmware name=\(name) version=\(version)"
        case .mic(let enabled):
            return "state mic \(enabled ? "on" : "off")"
        case .luminance(let value):
            return "state luminance \(value)"
        case .pong:
            return "state pong"
        case .stateSync(let busy):
            return "state sync busy=\(busy)"
        case .raw(let command, let payload):
            return "state raw command=\(command) payload=\(payload.map { String(format: "%02X", $0) }.joined(separator: " "))"
        }
    }
}

func runSelfTest() {
    precondition(QuakeProtocol.screenOn == [0xA3, 0x03, 0x01, 0x04, 0x01, 0x06])
    precondition(QuakeProtocol.setBrightness(255) == [0xA3, 0x03, 0x01, 0x05, 0xFF, 0x06])
    precondition(QuakeProtocol.ping == [0xA3, 0x02, 0x02, 0xEF, 0xF1])
    precondition(QuakeProtocol.decodeControlReport([0xA3, 0x03, 0x03, 0x01, 0x01]) == [.knob(.rotate(direction: 1))])
    precondition(QuakeProtocol.decodeControlReport([0xA3, 0x03, 0x03, 0x01, 0x02]) == [.knob(.rotate(direction: -1))])
    precondition(QuakeProtocol.decodeControlReport([0xA3, 0x03, 0x03, 0x02, 0x02]) == [.knob(.press(index: 2))])
    precondition(QuakeProtocol.decodeControlReport([0xA3, 0x03, 0x03, 0x02, 0x05]) == [.knob(.holdStart)])
    precondition(QuakeProtocol.decodeControlReport([0xA3, 0x03, 0x03, 0x02, 0xFF]) == [.knob(.holdEnd)])
    let touch = QuakeProtocol.decodeTouchReport([0xA3, 0x1C, 0x03, 0x1A, 0x01, 0x01, 0xE0, 0x01, 0x80, 0x07])
    precondition(touch == [.touch([TouchPoint(phase: .down, x: 1920, y: 480)])])
    print("Protocol self-test passed.")
}

func parseBrightness(from arguments: [String]) -> UInt8? {
    guard let index = arguments.firstIndex(of: "--brightness") else {
        return nil
    }
    guard arguments.indices.contains(index + 1), let value = Int(arguments[index + 1]), (0...255).contains(value) else {
        fputs("--brightness requires a value from 0 to 255\n", stderr)
        exit(64)
    }
    return UInt8(value)
}

func validatePluginManifest(at path: String) {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        let result = PluginManifestValidator.validate(manifest)
        if result.isValid {
            print("Plugin manifest valid: \(manifest.id) (\(manifest.name))")
        } else {
            print("Plugin manifest invalid: \(manifest.id)")
            for error in result.errors {
                print("error: \(error)")
            }
        }
        for warning in result.warnings {
            print("warning: \(warning)")
        }
        if !result.isValid {
            exit(65)
        }
    } catch {
        fputs("Could not validate plugin manifest: \(error)\n", stderr)
        exit(65)
    }
}

func validateThemeManifest(at path: String) {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let manifest = try JSONDecoder().decode(ThemeManifest.self, from: data)
        let result = ThemeManifestValidator.validate(manifest)
        if result.isValid {
            print("Theme manifest valid: \(manifest.id) (\(manifest.name))")
        } else {
            print("Theme manifest invalid: \(manifest.id)")
            for error in result.errors {
                print("error: \(error)")
            }
        }
        for warning in result.warnings {
            print("warning: \(warning)")
        }
        if !result.isValid {
            exit(65)
        }
    } catch {
        fputs("Could not validate theme manifest: \(error)\n", stderr)
        exit(65)
    }
}

func runLEDTransportTest(_ quake: QuakeDevice) {
    let steps: [(String, () -> Bool)] = [
        ("short-cmd led power on", { quake.sendControlFrame(QuakeProtocol.setKnobLEDPower(true)) }),
        ("via output, report-id included", { quake.applyKnobRingVIA(enabled: true, type: kIOHIDReportTypeOutput, includeReportIDInPayload: true) }),
        ("via output, report-id separate", { quake.applyKnobRingVIA(enabled: true, type: kIOHIDReportTypeOutput, includeReportIDInPayload: false) }),
        ("via feature, report-id included", { quake.applyKnobRingVIA(enabled: true, type: kIOHIDReportTypeFeature, includeReportIDInPayload: true) }),
        ("via feature, report-id separate", { quake.applyKnobRingVIA(enabled: true, type: kIOHIDReportTypeFeature, includeReportIDInPayload: false) })
    ]

    print("Watch the knob ring. Each step pauses for 1.5s.")
    for (name, action) in steps {
        print("LED test step: \(name)")
        let ok = action()
        print("result: \(ok)")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    }
}
