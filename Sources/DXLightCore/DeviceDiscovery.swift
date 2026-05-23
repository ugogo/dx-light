import Foundation
import IOKit
import IOKit.hid
import IOKit.serial
import IOKit.usb

public enum DeviceDiscovery {
    public static func discoverAll() -> [DiscoveredDevice] {
        hidDevices() + serialDevices()
    }

    public static func discoverPreferred() -> DiscoveredDevice? {
        let devices = discoverAll()
        return devices.first(where: { $0.kind == .hid && $0.productID == RobobloqConstants.lightProductID })
            ?? devices.first(where: { $0.kind == .serial && $0.productID == RobobloqConstants.cdcProductID })
            ?? devices.first
    }

    static func hidDevices() -> [DiscoveredDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: RobobloqConstants.lightVendorID,
            kIOHIDProductIDKey as String: RobobloqConstants.lightProductID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        return deviceSet.compactMap { device in
            let vendorID = Int(IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0)
            let productID = Int(IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0)
            guard vendorID == RobobloqConstants.lightVendorID,
                  productID == RobobloqConstants.lightProductID,
                  isVendorLightInterface(device) else {
                return nil
            }

            let manufacturer = IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
            let path = hidPath(for: device)

            return DiscoveredDevice(
                kind: .hid,
                path: path,
                vendorID: vendorID,
                productID: productID,
                manufacturer: manufacturer,
                product: product
            )
        }
    }

    static func isVendorLightInterface(_ device: IOHIDDevice) -> Bool {
        let usagePage = Int(IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0)
        let maxOutput = Int(IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0)
        return usagePage == 0xFF00 || maxOutput >= 64
    }

    static func serialDevices() -> [DiscoveredDevice] {
        var devices: [DiscoveredDevice] = []
        let matching = IOServiceMatching(kIOSerialBSDServiceValue)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            guard let properties = IORegistryEntryCreateCFProperty(
                service,
                kIOCalloutDeviceKey as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String else {
                continue
            }

            if let usbDevice = usbParent(of: service) {
                let vendorID = registryInt(usbDevice, key: kUSBVendorID)
                let productID = registryInt(usbDevice, key: kUSBProductID)
                if vendorID == RobobloqConstants.lightVendorID,
                   productID == RobobloqConstants.cdcProductID {
                    devices.append(
                        DiscoveredDevice(
                            kind: .serial,
                            path: properties,
                            vendorID: vendorID,
                            productID: productID,
                            manufacturer: registryString(usbDevice, key: "USB Vendor Name"),
                            product: registryString(usbDevice, key: kUSBProductString)
                        )
                    )
                }
            }
        }

        return devices
    }

    public static func makeTransport(for device: DiscoveredDevice) -> any DeviceTransport {
        switch device.kind {
        case .hid:
            return HIDTransport(device: device)
        case .serial:
            return SerialTransport(device: device)
        }
    }

    static func hidPath(for device: IOHIDDevice) -> String {
        if let uniqueID = IOHIDDeviceGetProperty(device, kIOHIDUniqueIDKey as CFString) {
            return "hid-\(uniqueID)"
        }
        if let location = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) {
            return "hid-\(location)"
        }
        if let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String, !serial.isEmpty {
            return "hid-\(serial)"
        }
        return UUID().uuidString
    }

    private static func usbParent(of service: io_object_t) -> io_registry_entry_t? {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(parent) }

        if let usbClass = registryString(parent, key: kIOClassKey), usbClass.contains("USB") {
            return parent
        }

        var usbParent: io_registry_entry_t = 0
        if IORegistryEntryGetParentEntry(parent, kIOServicePlane, &usbParent) == KERN_SUCCESS {
            defer { IOObjectRelease(usbParent) }
            return usbParent
        }
        return parent
    }

    private static func registryInt(_ entry: io_registry_entry_t, key: String) -> Int {
        Int(registryValue(entry, key: key) as? Int ?? 0)
    }

    private static func registryString(_ entry: io_registry_entry_t, key: String) -> String? {
        registryValue(entry, key: key) as? String
    }

    private static func registryValue(_ entry: io_registry_entry_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
