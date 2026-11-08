/// The monitor's OSD Picture Format setting, exposed as VCP 0x86 (MCCS Display Scaling).
///
/// Values were observed on a Philips 346B1C by switching the OSD setting by hand and
/// comparing full VCP snapshots (see tools/ddc-probe).
public enum PictureFormat: UInt16, CaseIterable, Sendable {
    case wideScreen = 0x08
    case sixteenByNine = 0x04

    public static let vcpCode: UInt8 = 0x86

    public var displayName: String {
        switch self {
        case .wideScreen: "Wide screen"
        case .sixteenByNine: "16:9"
        }
    }
}

public struct PictureFormatController {
    private let client: DDCClient

    public init(client: DDCClient) {
        self.client = client
    }

    /// The current format, or nil when the monitor is in a format this tool does not manage.
    public func current() throws(DDCError) -> PictureFormat? {
        PictureFormat(rawValue: try client.getVCP(PictureFormat.vcpCode).current)
    }

    /// Switches to the format unless the monitor is already in it.
    public func set(_ format: PictureFormat) throws(DDCError) {
        guard try current() != format else { return }
        try client.setVCP(PictureFormat.vcpCode, format.rawValue)
    }

    /// Switches Wide screen to 16:9 and any other format to Wide screen.
    @discardableResult
    public func toggle() throws(DDCError) -> PictureFormat {
        let target: PictureFormat = try current() == .wideScreen ? .sixteenByNine : .wideScreen
        try client.setVCP(PictureFormat.vcpCode, target.rawValue)
        return target
    }
}
