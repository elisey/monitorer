/// DDC/CI packets and reply parsing.
///
/// Packet layout follows VESA DDC/CI. The display listens on I2C address 0x37; the host
/// sends with source address 0x51 and the display replies with source address 0x6E.
/// Request checksums cover the destination address (0x6E) and the source byte (0x51);
/// reply checksums cover the virtual host address (0x50).
public enum DDC {
    public static let chipAddress: UInt32 = 0x37
    public static let dataAddress: UInt32 = 0x51
    static let displayAddress: UInt8 = 0x6E
    static let hostAddress: UInt8 = 0x50

    static let getVCPOpcode: UInt8 = 0x01
    static let getVCPReplyOpcode: UInt8 = 0x02
    static let setVCPOpcode: UInt8 = 0x03

    static let getVCPReplyLength = 11

    static func checksum(_ initial: UInt8, _ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(initial, ^)
    }

    /// Wraps a command body into a host-to-display packet (without the 0x51 source byte).
    static func request(_ body: [UInt8]) -> [UInt8] {
        let packet = [0x80 | UInt8(body.count)] + body
        return packet + [checksum(displayAddress ^ UInt8(dataAddress), packet)]
    }

    static func getVCPRequest(code: UInt8) -> [UInt8] {
        request([getVCPOpcode, code])
    }

    static func setVCPRequest(code: UInt8, value: UInt16) -> [UInt8] {
        request([setVCPOpcode, code, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// Validates a display-to-host reply and returns its body (opcode and payload).
    static func replyBody(_ reply: [UInt8]) throws(DDCError) -> [UInt8] {
        guard reply.count >= 3 else { throw .badReply("reply too short: \(hex(reply))") }
        guard reply[0] == displayAddress else {
            throw .badReply("unexpected source address: \(hex(reply))")
        }
        guard reply[1] & 0x80 != 0 else {
            throw .badReply("length byte has no 0x80 flag: \(hex(reply))")
        }
        let length = Int(reply[1] & 0x7F)
        guard reply.count >= 2 + length + 1 else {
            throw .badReply("reply shorter than declared length \(length): \(hex(reply))")
        }
        guard checksum(hostAddress, Array(reply[..<(2 + length)])) == reply[2 + length] else {
            throw .badReply("checksum mismatch: \(hex(reply))")
        }
        return Array(reply[2..<(2 + length)])
    }

    static func parseGetVCPReply(code: UInt8, reply: [UInt8]) throws(DDCError) -> VCPValue {
        let body = try replyBody(reply)
        guard !body.isEmpty else {
            throw .badReply("display replied with a null message (not ready)")
        }
        guard body.count == 8, body[0] == getVCPReplyOpcode else {
            throw .badReply("unexpected Get VCP reply body: \(hex(body))")
        }
        guard body[2] == code else {
            throw .badReply(String(format: "reply is for VCP 0x%02X, expected 0x%02X", body[2], code))
        }
        guard body[1] == 0 else { throw .unsupported(code: code) }
        return VCPValue(
            code: code,
            maximum: UInt16(body[4]) << 8 | UInt16(body[5]),
            current: UInt16(body[6]) << 8 | UInt16(body[7])
        )
    }
}

public struct VCPValue: Equatable, Sendable {
    public let code: UInt8
    public let maximum: UInt16
    public let current: UInt16
}

public enum DDCError: Error, Equatable, CustomStringConvertible {
    /// A corrupted, unexpected or "not ready" reply; worth retrying.
    case badReply(String)
    /// The I2C call itself failed; worth retrying.
    case transport(String)
    /// The display reports that it does not support the VCP code.
    case unsupported(code: UInt8)
    /// The display never returned a valid reply or never reported the written value.
    case timeout(String)
    /// The display could not be found or identified.
    case display(String)

    public var description: String {
        switch self {
        case .badReply(let message), .transport(let message), .timeout(let message),
            .display(let message):
            message
        case .unsupported(let code):
            String(format: "VCP 0x%02X is not supported by the display", code)
        }
    }

    var isRetryable: Bool {
        switch self {
        case .badReply, .transport: true
        case .unsupported, .timeout, .display: false
        }
    }
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}
