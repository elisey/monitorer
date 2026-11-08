import Foundation
import IOKit

// Private IOKit functions for I2C access to displays attached to Apple Silicon Macs.
// The same functions are used by m1ddc and MonitorControl.

@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(
    _ allocator: CFAllocator?, _ service: io_service_t
) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOAVServiceCopyEDID")
private func IOAVServiceCopyEDID(
    _ service: CFTypeRef, _ edid: UnsafeMutablePointer<Unmanaged<CFData>?>
) -> IOReturn

@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(
    _ service: CFTypeRef, _ chipAddress: UInt32, _ offset: UInt32,
    _ buffer: UnsafeMutableRawPointer, _ size: UInt32
) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(
    _ service: CFTypeRef, _ chipAddress: UInt32, _ dataAddress: UInt32,
    _ buffer: UnsafeMutableRawPointer, _ size: UInt32
) -> IOReturn

/// I2C transport through the IOAVService of one external display.
public final class IOAVTransport: I2CTransport {
    private let service: CFTypeRef

    init(service: CFTypeRef) {
        self.service = service
    }

    /// The monitor name from the display's EDID, if it can be read.
    public var displayName: String? {
        var edid: Unmanaged<CFData>?
        guard IOAVServiceCopyEDID(service, &edid) == kIOReturnSuccess,
            let data = edid?.takeRetainedValue()
        else { return nil }
        return EDID.displayName(Array(data as Data))
    }

    public func write(chipAddress: UInt32, dataAddress: UInt32, payload: [UInt8]) throws(DDCError) {
        var buffer = payload
        let status = IOAVServiceWriteI2C(
            service, chipAddress, dataAddress, &buffer, UInt32(buffer.count))
        guard status == kIOReturnSuccess else {
            throw .transport(String(format: "IOAVServiceWriteI2C failed with 0x%08X", status))
        }
    }

    public func read(chipAddress: UInt32, offset: UInt32, length: Int) throws(DDCError) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: length)
        let status = IOAVServiceReadI2C(service, chipAddress, offset, &buffer, UInt32(length))
        guard status == kIOReturnSuccess else {
            throw .transport(String(format: "IOAVServiceReadI2C failed with 0x%08X", status))
        }
        return buffer
    }
}

public enum ExternalDisplays {
    /// Returns the transport of the only external display with the given EDID name.
    public static func find(named name: String) throws(DDCError) -> IOAVTransport {
        let displays = all()
        return displays[try indexOfOnlyDisplay(named: name, among: displays.map(\.displayName))]
    }

    /// Picks the single display with the given name; nil names are unreadable EDIDs.
    static func indexOfOnlyDisplay(named name: String, among names: [String?]) throws(DDCError) -> Int {
        let matches = names.indices.filter { names[$0] == name }
        switch matches.count {
        case 1:
            return matches[0]
        case 0:
            let found = names.map { $0 ?? "unknown" }
            let list = found.isEmpty ? "no external displays" : found.joined(separator: ", ")
            throw .display("display \"\(name)\" not found (found: \(list))")
        default:
            throw .display("\(matches.count) displays named \"\(name)\" found; cannot choose one")
        }
    }

    /// Returns one transport per external display port known to the display coprocessor.
    static func all() -> [IOAVTransport] {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator)
                == kIOReturnSuccess
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var transports: [IOAVTransport] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(
                entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard location == "External",
                let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)
            else { continue }
            transports.append(IOAVTransport(service: service.takeRetainedValue()))
        }
        return transports
    }
}
