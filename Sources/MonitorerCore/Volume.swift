/// The monitor's speaker volume, exposed as VCP 0x62 (MCCS Audio Speaker Volume).
///
/// The Philips 346B1C reports a range of 0...100 and echoes written values back exactly.
public struct Volume: Equatable, Sendable {
    public let level: Int
    public let maximum: Int

    public init(level: Int, maximum: Int) {
        self.level = level
        self.maximum = maximum
    }
}

public struct VolumeController {
    public static let vcpCode: UInt8 = 0x62

    private let client: DDCClient

    public init(client: DDCClient) {
        self.client = client
    }

    public func current() throws(DDCError) -> Volume {
        let value = try client.getVCP(Self.vcpCode)
        return Volume(level: Int(value.current), maximum: Int(value.maximum))
    }

    /// Sets the level, clamped to what the monitor reports as its range.
    @discardableResult
    public func set(_ level: Int) throws(DDCError) -> Volume {
        let maximum = Int(try client.getVCP(Self.vcpCode).maximum)
        let clamped = min(max(level, 0), maximum)
        try client.setVCP(Self.vcpCode, UInt16(clamped))
        return Volume(level: clamped, maximum: maximum)
    }
}
