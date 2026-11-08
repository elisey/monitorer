import Foundation

public protocol I2CTransport {
    func write(chipAddress: UInt32, dataAddress: UInt32, payload: [UInt8]) throws(DDCError)
    func read(chipAddress: UInt32, offset: UInt32, length: Int) throws(DDCError) -> [UInt8]
}

/// Reads and writes VCP values with the retries real displays need.
///
/// Each request is written several times in a row: some displays (the Philips 346B1C
/// among them) answer with a null message unless the request is repeated. Displays may
/// also stop answering for a few seconds after a change such as a picture format switch,
/// so reads keep retrying for a while before giving up.
public final class DDCClient {
    public struct Timing: Sendable {
        public var writeCycles = 2
        public var writeGap: TimeInterval = 0.01
        public var replyDelay: TimeInterval = 0.05
        public var readAttempts = 20
        public var retryDelay: TimeInterval = 0.2
        public var verifyAttempts = 20
        public var verifyInterval: TimeInterval = 0.25

        public init() {}
    }

    private let transport: I2CTransport
    private let timing: Timing
    private let sleep: (TimeInterval) -> Void

    public init(
        transport: I2CTransport,
        timing: Timing = Timing(),
        sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.transport = transport
        self.timing = timing
        self.sleep = sleep
    }

    public func getVCP(_ code: UInt8) throws(DDCError) -> VCPValue {
        var lastError = DDCError.timeout("no attempts made")
        for attempt in 0..<timing.readAttempts {
            if attempt > 0 { sleep(timing.retryDelay) }
            do {
                return try readOnce(code)
            } catch where error.isRetryable {
                lastError = error
            }
        }
        throw .timeout(
            String(format: "no valid reply for VCP 0x%02X after %d attempts: ", code, timing.readAttempts)
                + lastError.description)
    }

    /// Writes a VCP value and polls until the display reports it back.
    @discardableResult
    public func setVCP(_ code: UInt8, _ value: UInt16) throws(DDCError) -> VCPValue {
        try send(DDC.setVCPRequest(code: code, value: value))
        var lastSeen = "nothing"
        for _ in 0..<timing.verifyAttempts {
            sleep(timing.verifyInterval)
            do {
                let current = try readOnce(code)
                if current.current == value { return current }
                lastSeen = "value \(current.current)"
            } catch where error.isRetryable {
                lastSeen = error.description
            }
        }
        throw .timeout(
            String(format: "VCP 0x%02X did not become %d; last read: ", code, value) + lastSeen)
    }

    private func readOnce(_ code: UInt8) throws(DDCError) -> VCPValue {
        try send(DDC.getVCPRequest(code: code))
        sleep(timing.replyDelay)
        let reply = try transport.read(
            chipAddress: DDC.chipAddress, offset: 0, length: DDC.getVCPReplyLength)
        return try DDC.parseGetVCPReply(code: code, reply: reply)
    }

    private func send(_ request: [UInt8]) throws(DDCError) {
        for cycle in 0..<timing.writeCycles {
            if cycle > 0 { sleep(timing.writeGap) }
            try transport.write(
                chipAddress: DDC.chipAddress, dataAddress: DDC.dataAddress, payload: request)
        }
    }
}
