/// The monitor's active video input, exposed as VCP 0x60 (MCCS Input Select).
///
/// Values follow MCCS 2.2 and were confirmed on a Philips 346B1C by switching the input
/// over DDC and reading it back (see tools/ddc-probe). The monitor only looks at the low
/// byte of a write; on reads it puts an extra vendor-specific value in the high byte
/// (0x3515 for USB-C, 0x2111 for HDMI 1), so only the low byte identifies the input.
public enum InputSource: UInt8, CaseIterable, Sendable {
    case hdmi1 = 0x11
    case usbC = 0x15

    public static let vcpCode: UInt8 = 0x60

    public var displayName: String {
        switch self {
        case .hdmi1: "HDMI"
        case .usbC: "USB-C"
        }
    }

    init?(reading: UInt16) {
        self.init(rawValue: UInt8(reading & 0xFF))
    }
}

public struct InputSourceController {
    private let client: DDCClient

    public init(client: DDCClient) {
        self.client = client
    }

    /// The current input, or nil when the monitor is on an input this tool does not manage.
    public func current() throws(DDCError) -> InputSource? {
        InputSource(reading: try client.getVCP(InputSource.vcpCode).current)
    }

    /// Switches to the input unless the monitor is already on it.
    ///
    /// The monitor keeps answering DDC on the inactive input, so this works both when
    /// switching away from this Mac and when switching back to it.
    public func set(_ input: InputSource) throws(DDCError) {
        guard try current() != input else { return }
        try client.setVCP(InputSource.vcpCode, UInt16(input.rawValue)) {
            InputSource(reading: $0) == input
        }
    }
}
