@testable import MonitorerCore

func makeReply(_ body: [UInt8]) -> [UInt8] {
    let packet: [UInt8] = [0x6E, 0x80 | UInt8(body.count)] + body
    return packet + [DDC.checksum(0x50, packet)]
}

func vcpReply(code: UInt8, current: UInt16, maximum: UInt16 = 100, result: UInt8 = 0) -> [UInt8] {
    makeReply([
        0x02, result, code, 0x00,
        UInt8(maximum >> 8), UInt8(maximum & 0xFF), UInt8(current >> 8), UInt8(current & 0xFF),
    ])
}

/// Emulates a display answering Get VCP and Set VCP requests.
final class FakeDisplay: I2CTransport {
    var values: [UInt8: UInt16]
    /// Number of upcoming reads that return a null message, as a busy display does.
    var busyReads: Int
    /// Whether the display accepts Set VCP requests without changing anything.
    var ignoresSets: Bool
    private(set) var writes: [[UInt8]] = []
    private var pending: [UInt8] = []

    init(values: [UInt8: UInt16], busyReads: Int = 0, ignoresSets: Bool = false) {
        self.values = values
        self.busyReads = busyReads
        self.ignoresSets = ignoresSets
    }

    var setRequests: [[UInt8]] { writes.filter { $0[1] == 0x03 } }

    func write(chipAddress: UInt32, dataAddress: UInt32, payload: [UInt8]) throws(DDCError) {
        precondition(chipAddress == 0x37 && dataAddress == 0x51)
        writes.append(payload)
        switch payload[1] {
        case 0x01:
            let code = payload[2]
            if let value = values[code] {
                pending = vcpReply(code: code, current: value)
            } else {
                pending = vcpReply(code: code, current: 0, maximum: 0, result: 1)
            }
        case 0x03:
            if !ignoresSets {
                values[payload[2]] = UInt16(payload[3]) << 8 | UInt16(payload[4])
            }
        default:
            break
        }
    }

    func read(chipAddress: UInt32, offset: UInt32, length: Int) throws(DDCError) -> [UInt8] {
        if busyReads > 0 {
            busyReads -= 1
            return makeReply([])
        }
        return Array((pending + [UInt8](repeating: 0, count: length)).prefix(length))
    }
}

func makeClient(_ display: FakeDisplay) -> DDCClient {
    DDCClient(transport: display, sleep: { _ in })
}
