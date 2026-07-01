import Foundation
import IOKit.hid
import QuakeRuntime

public final class QuakeDevice: @unchecked Sendable {
    public typealias EventHandler = (RuntimeEvent) -> Void

    private let managers: [ManagerBinding]
    private let eventHandler: EventHandler
    public private(set) var diagnostics: [String] = []
    private var controlDevice: IOHIDDevice?
    private var touchDevice: IOHIDDevice?
    private var controlBuffer = [UInt8](repeating: 0, count: 64)
    private var touchBuffer = [UInt8](repeating: 0, count: 64)
    private var keepAliveTimer: Timer?

    public init(eventHandler: @escaping EventHandler) {
        self.eventHandler = eventHandler

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
            }
        }
        _ = sendControlFrame(QuakeProtocol.screenOn)
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

        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            diagnostics.append("\(spec.interface.rawValue): device open failed \(openResult)")
            return
        }
        diagnostics.append("\(spec.interface.rawValue): device opened")

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
