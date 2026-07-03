import Foundation
import IOKit.hid
import QuakeRuntime

public final class QuakeDevice: @unchecked Sendable {
    public typealias EventHandler = (RuntimeEvent) -> Void

    public enum OpenMode: Sendable {
        case shared
        case seizePreferred
        case seizeRequired
    }

    private let managers: [ManagerBinding]
    private let eventHandler: EventHandler
    private let openMode: OpenMode
    public private(set) var diagnostics: [String] = []
    private var controlDevice: IOHIDDevice?
    private var touchDevice: IOHIDDevice?
    private var controlBuffer = [UInt8](repeating: 0, count: 64)
    private var touchBuffer = [UInt8](repeating: 0, count: 64)
    private var keepAliveTimer: Timer?

    public init(openMode: OpenMode = .seizePreferred, eventHandler: @escaping EventHandler) {
        self.eventHandler = eventHandler
        self.openMode = openMode

        let controlManagers = QuakeProtocol.controlSpecs.map { spec in
            var dictionary: [String: Any] = [
                kIOHIDVendorIDKey: spec.vendorID,
                kIOHIDProductIDKey: spec.productID
            ]
            if let usagePage = spec.usagePage {
                dictionary[kIOHIDPrimaryUsagePageKey] = usagePage
            }
            return ManagerBinding(label: "control VID \(hex(spec.vendorID)) PID \(hex(spec.productID)) usagePage \(hex(spec.usagePage ?? 0))", manager: Self.makeManager(matching: dictionary as CFDictionary))
        }
        let touchManagers = QuakeProtocol.touchSpecs.map { spec in
            ManagerBinding(label: "touch VID \(hex(spec.vendorID)) PID \(hex(spec.productID))", manager: Self.makeManager(matching: [
                kIOHIDVendorIDKey: spec.vendorID,
                kIOHIDProductIDKey: spec.productID
            ] as CFDictionary))
        }
        self.managers = controlManagers + touchManagers
    }

    deinit {
        stop()
    }

    public func start(wake: Bool) throws {
        var openFailures: [IOReturn] = []
        diagnostics.removeAll()
        for binding in managers {
            let manager = binding.manager
            let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openResult == kIOReturnSuccess else {
                diagnostics.append("\(binding.label): manager open failed \(openResult)")
                openFailures.append(openResult)
                continue
            }
            guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
                diagnostics.append("\(binding.label): manager opened but returned no devices")
                continue
            }
            diagnostics.append("\(binding.label): manager opened, \(devices.count) device(s)")
            for device in devices {
                bind(device)
            }
        }

        if controlDevice == nil && touchDevice == nil {
            throw openFailures.isEmpty ? QuakeDeviceError.noSupportedDevices : QuakeDeviceError.managerOpenFailures(openFailures)
        }
        if wake {
            activate()
        }
    }

    public func stop() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil

        if let controlDevice {
            IOHIDDeviceUnscheduleFromRunLoop(controlDevice, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(controlDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let touchDevice {
            IOHIDDeviceUnscheduleFromRunLoop(touchDevice, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(touchDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        for binding in managers {
            IOHIDManagerClose(binding.manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    public func activate() {
        [0.0, 0.3, 0.8, 1.5].forEach { delay in
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                _ = self?.sendControlFrame(QuakeProtocol.screenOn)
                _ = self?.setBrightness(255)
            }
        }
        _ = sendControlFrame(QuakeProtocol.screenOn)
        _ = setBrightness(255)
        _ = sendControlFrame(QuakeProtocol.queryFirmware)
        _ = sendControlFrame(QuakeProtocol.queryMic)
        _ = sendControlFrame(QuakeProtocol.queryLuminance)

        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            _ = self?.sendControlFrame(QuakeProtocol.ping)
        }
    }

    @discardableResult
    public func sendControlFrame(_ frame: [UInt8]) -> Bool {
        let report = [UInt8(0x00)] + frame
        return sendControlReport(report)
    }

    @discardableResult
    public func sendControlReport(_ report: [UInt8]) -> Bool {
        sendControlReport(report, type: kIOHIDReportTypeOutput, includeReportIDInPayload: true)
    }

    @discardableResult
    public func sendControlReport(_ report: [UInt8], type: IOHIDReportType, includeReportIDInPayload: Bool) -> Bool {
        guard let controlDevice else { return false }
        let reportID = CFIndex(report.first ?? 0)
        let payload = includeReportIDInPayload ? report : Array(report.dropFirst())
        return payload.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return false
            }
            let result = IOHIDDeviceSetReport(
                controlDevice,
                type,
                reportID,
                baseAddress,
                payload.count
            )
            return result == kIOReturnSuccess
        }
    }

    @discardableResult
    public func setBrightness(_ value: UInt8) -> Bool {
        sendControlFrame(QuakeProtocol.setBrightness(value))
    }

    @discardableResult
    public func setKnobRing(enabled: Bool) -> Bool {
        if !enabled {
            return turnKnobRingOff()
        }
        var ok = sendControlFrame(QuakeProtocol.setKnobLEDPower(enabled))
        ok = sendControlReport(QuakeProtocol.viaSet(field: 0x02, values: [enabled ? 1 : 0])) && ok
        ok = sendControlReport(QuakeProtocol.viaSet(field: 0x01, values: [200])) && ok
        ok = sendControlReport(QuakeProtocol.viaSet(field: 0x03, values: [128])) && ok
        ok = sendControlReport(QuakeProtocol.viaSet(field: 0x04, values: [96, 255])) && ok
        return ok
    }

    @discardableResult
    public func applyKnobRing(_ output: KnobRingResolvedOutput) -> Bool {
        guard output.animation != .off, output.intensity > 0 else {
            return turnKnobRingOff()
        }

        let color = KnobRingHSL(hex: output.color) ?? KnobRingHSL(hue: 96, saturation: 255)
        let brightness = UInt8(max(1, min(255, Int((output.intensity * 255).rounded()))))
        let speed = UInt8(output.animation == .solid ? 0 : 160)
        let effect = output.animation.viaEffectIndex

        var ok = sendControlFrame(QuakeProtocol.setKnobLEDPower(true))
        ok = sendControlReport(QuakeProtocol.viaSet(field: 0x02, values: [effect])) && ok
        ok = sendControlReport(QuakeProtocol.viaSet(field: 0x01, values: [brightness])) && ok
        ok = sendControlReport(QuakeProtocol.viaSet(field: 0x03, values: [speed])) && ok
        ok = sendControlReport(QuakeProtocol.viaSet(field: 0x04, values: [color.hue, color.saturation])) && ok
        return ok
    }

    @discardableResult
    public func turnKnobRingOff() -> Bool {
        var ok = sendControlFrame(QuakeProtocol.setKnobLEDPower(false))
        let variants: [(IOHIDReportType, Bool)] = [
            (kIOHIDReportTypeOutput, true),
            (kIOHIDReportTypeOutput, false),
            (kIOHIDReportTypeFeature, true),
            (kIOHIDReportTypeFeature, false)
        ]
        for (type, includeReportID) in variants {
            ok = sendControlReport(QuakeProtocol.viaSet(field: 0x02, values: [0]), type: type, includeReportIDInPayload: includeReportID) && ok
            ok = sendControlReport(QuakeProtocol.viaSet(field: 0x01, values: [0]), type: type, includeReportIDInPayload: includeReportID) && ok
        }
        return ok
    }

    @discardableResult
    public func applyKnobRingVIA(enabled: Bool, type: IOHIDReportType, includeReportIDInPayload: Bool) -> Bool {
        var ok = sendControlReport(QuakeProtocol.viaSet(field: 0x02, values: [enabled ? 1 : 0]), type: type, includeReportIDInPayload: includeReportIDInPayload)
        if enabled {
            ok = sendControlReport(QuakeProtocol.viaSet(field: 0x01, values: [220]), type: type, includeReportIDInPayload: includeReportIDInPayload) && ok
            ok = sendControlReport(QuakeProtocol.viaSet(field: 0x03, values: [128]), type: type, includeReportIDInPayload: includeReportIDInPayload) && ok
            ok = sendControlReport(QuakeProtocol.viaSet(field: 0x04, values: [96, 255]), type: type, includeReportIDInPayload: includeReportIDInPayload) && ok
        }
        return ok
    }

    private func bind(_ device: IOHIDDevice) {
        let vendorID = intProperty(kIOHIDVendorIDKey, device: device)
        let productID = intProperty(kIOHIDProductIDKey, device: device)
        let usagePage = intProperty(kIOHIDPrimaryUsagePageKey, device: device)

        guard let spec = QuakeProtocol.classify(vendorID: vendorID, productID: productID, usagePage: usagePage) else {
            return
        }

        let openResult = openDevice(device, interface: spec.interface)
        guard openResult == kIOReturnSuccess else {
            diagnostics.append("\(spec.interface.rawValue): device open failed \(openResult)")
            return
        }

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        switch spec.interface {
        case .control:
            controlDevice = device
            eventHandler(RuntimeEvent(source: "dk-quake", event: .connected(interface: QuakeInterface.control.rawValue)))
            IOHIDDeviceRegisterInputReportCallback(
                device,
                &controlBuffer,
                controlBuffer.count,
                controlInputCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )
        case .touch:
            touchDevice = device
            eventHandler(RuntimeEvent(source: "dk-quake", event: .connected(interface: QuakeInterface.touch.rawValue)))
            IOHIDDeviceRegisterInputReportCallback(
                device,
                &touchBuffer,
                touchBuffer.count,
                touchInputCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }

    private func openDevice(_ device: IOHIDDevice, interface: QuakeInterface) -> IOReturn {
        switch openMode {
        case .shared:
            let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            if result == kIOReturnSuccess {
                diagnostics.append("\(interface.rawValue): device opened shared")
            }
            return result
        case .seizePreferred:
            let seized = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            if seized == kIOReturnSuccess {
                diagnostics.append("\(interface.rawValue): device opened seized")
                return seized
            }
            let shared = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            if shared == kIOReturnSuccess {
                diagnostics.append("\(interface.rawValue): device seize failed \(seized); opened shared fallback")
            }
            return shared
        case .seizeRequired:
            let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            if result == kIOReturnSuccess {
                diagnostics.append("\(interface.rawValue): device opened seized")
            }
            return result
        }
    }

    private static func makeManager(matching dictionary: CFDictionary) -> IOHIDManager {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, [dictionary] as CFArray)
        return manager
    }

    fileprivate func handleControl(bytes: [UInt8]) {
        for event in QuakeProtocol.decodeControlReport(bytes) {
            eventHandler(RuntimeEvent(source: "dk-quake", event: event))
        }
    }

    fileprivate func handleTouch(bytes: [UInt8]) {
        for event in QuakeProtocol.decodeTouchReport(bytes) {
            eventHandler(RuntimeEvent(source: "dk-quake", event: event))
        }
    }
}

private struct KnobRingHSL {
    var hue: UInt8
    var saturation: UInt8

    init(hue: UInt8, saturation: UInt8) {
        self.hue = hue
        self.saturation = saturation
    }

    init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        let body = String(hex.dropFirst())
        guard body.count == 6 || body.count == 8, let value = UInt64(body, radix: 16) else { return nil }

        let red: Double
        let green: Double
        let blue: Double
        if body.count == 8 {
            red = Double((value & 0xFF00_0000) >> 24) / 255
            green = Double((value & 0x00FF_0000) >> 16) / 255
            blue = Double((value & 0x0000_FF00) >> 8) / 255
        } else {
            red = Double((value & 0xFF0000) >> 16) / 255
            green = Double((value & 0x00FF00) >> 8) / 255
            blue = Double(value & 0x0000FF) / 255
        }

        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        let saturation = maxValue == 0 ? 0 : delta / maxValue
        let hueDegrees: Double
        if delta == 0 {
            hueDegrees = 0
        } else if maxValue == red {
            hueDegrees = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxValue == green {
            hueDegrees = 60 * (((blue - red) / delta) + 2)
        } else {
            hueDegrees = 60 * (((red - green) / delta) + 4)
        }
        let normalizedHue = hueDegrees < 0 ? hueDegrees + 360 : hueDegrees
        self.hue = UInt8(max(0, min(255, Int((normalizedHue / 360 * 255).rounded()))))
        self.saturation = UInt8(max(0, min(255, Int((saturation * 255).rounded()))))
    }
}

private extension KnobRingAnimation {
    var viaEffectIndex: UInt8 {
        switch self {
        case .solid:
            return 1
        case .pulse:
            return 8
        case .flash:
            return 32
        case .strobe:
            return 30
        case .progress:
            return 2
        case .off:
            return 0
        }
    }
}

private struct ManagerBinding {
    var label: String
    var manager: IOHIDManager
}

private func hex(_ value: Int) -> String {
    String(format: "0x%04X", value)
}

public enum QuakeDeviceError: Error, CustomStringConvertible {
    case openFailed(IOReturn)
    case managerOpenFailures([IOReturn])
    case noSupportedDevices

    public var description: String {
        switch self {
        case .openFailed(let code):
            return "Could not open HID manager: \(code)"
        case .managerOpenFailures(let codes):
            return "Could not open any HID managers: \(codes.map(String.init).joined(separator: ", "))"
        case .noSupportedDevices:
            return "No supported DK-Quake HID interfaces found"
        }
    }
}

private let controlInputCallback: IOHIDReportCallback = { context, _, _, _, _, report, reportLength in
    guard let context else { return }
    let device = Unmanaged<QuakeDevice>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: UnsafePointer(report), count: reportLength))
    device.handleControl(bytes: bytes)
}

private let touchInputCallback: IOHIDReportCallback = { context, _, _, _, _, report, reportLength in
    guard let context else { return }
    let device = Unmanaged<QuakeDevice>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: UnsafePointer(report), count: reportLength))
    device.handleTouch(bytes: bytes)
}
