import Foundation
import IOKit.hid

public struct HIDDeviceInfo: Equatable, Sendable {
    public var interface: QuakeInterface
    public var vendorID: Int
    public var productID: Int
    public var usagePage: Int?
    public var usage: Int?
    public var product: String?
    public var manufacturer: String?
    public var transport: String?
    public var isSupported: Bool

    public init(
        interface: QuakeInterface,
        vendorID: Int,
        productID: Int,
        usagePage: Int?,
        usage: Int?,
        product: String?,
        manufacturer: String?,
        transport: String?,
        isSupported: Bool
    ) {
        self.interface = interface
        self.vendorID = vendorID
        self.productID = productID
        self.usagePage = usagePage
        self.usage = usage
        self.product = product
        self.manufacturer = manufacturer
        self.transport = transport
        self.isSupported = isSupported
    }
}

public final class HIDManager {
    public init() {}

    public func enumerateSupportedDevices() -> [HIDDeviceInfo] {
        enumerateDevices(includeRelated: false)
    }

    public func enumerateRelatedDevices() -> [HIDDeviceInfo] {
        enumerateDevices(includeRelated: true)
    }

    private func enumerateDevices(includeRelated: Bool) -> [HIDDeviceInfo] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let specs = includeRelated ? QuakeProtocol.relatedSpecs : QuakeProtocol.supportedSpecs
        let matches = specs.map { spec in
            var dictionary: [String: Any] = [
                kIOHIDVendorIDKey: spec.vendorID,
                kIOHIDProductIDKey: spec.productID
            ]
            if !includeRelated, let usagePage = spec.usagePage {
                dictionary[kIOHIDPrimaryUsagePageKey] = usagePage
            }
            return dictionary as CFDictionary
        } as CFArray

        IOHIDManagerSetDeviceMatchingMultiple(manager, matches)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        return devices.compactMap { device in
            let vendorID = intProperty(kIOHIDVendorIDKey, device: device)
            let productID = intProperty(kIOHIDProductIDKey, device: device)
            let usagePage = intProperty(kIOHIDPrimaryUsagePageKey, device: device)
            let usage = intProperty(kIOHIDPrimaryUsageKey, device: device)
            guard let spec = QuakeProtocol.classify(vendorID: vendorID, productID: productID, usagePage: usagePage) else {
                if includeRelated, QuakeProtocol.relatedSpecs.contains(where: { $0.vendorID == vendorID && $0.productID == productID }) {
                    return HIDDeviceInfo(
                        interface: .control,
                        vendorID: vendorID,
                        productID: productID,
                        usagePage: usagePage == 0 ? nil : usagePage,
                        usage: usage == 0 ? nil : usage,
                        product: stringProperty(kIOHIDProductKey, device: device),
                        manufacturer: stringProperty(kIOHIDManufacturerKey, device: device),
                        transport: stringProperty(kIOHIDTransportKey, device: device),
                        isSupported: false
                    )
                }
                return nil
            }
            return HIDDeviceInfo(
                interface: spec.interface,
                vendorID: vendorID,
                productID: productID,
                usagePage: usagePage == 0 ? nil : usagePage,
                usage: usage == 0 ? nil : usage,
                product: stringProperty(kIOHIDProductKey, device: device),
                manufacturer: stringProperty(kIOHIDManufacturerKey, device: device),
                transport: stringProperty(kIOHIDTransportKey, device: device),
                isSupported: true
            )
        }.sorted { lhs, rhs in
            if lhs.interface.rawValue != rhs.interface.rawValue {
                return lhs.interface.rawValue < rhs.interface.rawValue
            }
            return lhs.vendorID < rhs.vendorID
        }
    }
}

func intProperty(_ key: String, device: IOHIDDevice) -> Int {
    let value = IOHIDDeviceGetProperty(device, key as CFString)
    if let number = value as? NSNumber {
        return number.intValue
    }
    return 0
}

func stringProperty(_ key: String, device: IOHIDDevice) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString) as? String
}
