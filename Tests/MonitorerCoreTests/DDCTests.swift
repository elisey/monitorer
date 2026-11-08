import Testing

@testable import MonitorerCore

@Test func getVCPRequestMatchesKnownLuminancePacket() {
    // Packet used by m1ddc and MonitorControl to read luminance (VCP 0x10).
    #expect(DDC.getVCPRequest(code: 0x10) == [0x82, 0x01, 0x10, 0xAC])
}

@Test func setVCPRequestLayout() {
    let request = DDC.setVCPRequest(code: 0x86, value: 0x0004)
    #expect(Array(request.prefix(5)) == [0x84, 0x03, 0x86, 0x00, 0x04])
    #expect(request[5] == DDC.checksum(0x6E ^ 0x51, Array(request.prefix(5))))
}

@Test func parsesSupportedValue() throws {
    let value = try DDC.parseGetVCPReply(code: 0x10, reply: vcpReply(code: 0x10, current: 85))
    #expect(value == VCPValue(code: 0x10, maximum: 100, current: 85))
}

@Test func parsesRealPhilipsReply() throws {
    // Reply captured from a Philips 346B1C for VCP 0x12 (contrast 50).
    let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x64, 0x00, 0x32, 0xF0]
    #expect(try DDC.parseGetVCPReply(code: 0x12, reply: reply).current == 50)
}

@Test func unsupportedCodeIsReported() {
    #expect(throws: DDCError.unsupported(code: 0x86)) {
        try DDC.parseGetVCPReply(code: 0x86, reply: vcpReply(code: 0x86, current: 0, result: 1))
    }
}

@Test func nullMessageIsRetryableError() {
    // Reply captured from a Philips 346B1C when the request was written only once.
    let reply: [UInt8] = [0x6E, 0x80, 0xBE, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x55, 0x95]
    do {
        _ = try DDC.parseGetVCPReply(code: 0x10, reply: reply)
        Issue.record("expected an error")
    } catch {
        #expect(error.isRetryable)
    }
}

@Test func replyForOtherCodeIsRejected() {
    #expect(throws: DDCError.self) {
        try DDC.parseGetVCPReply(code: 0x12, reply: vcpReply(code: 0x10, current: 85))
    }
}

@Test func badChecksumIsRejected() {
    var reply = vcpReply(code: 0x10, current: 85)
    reply[reply.count - 1] ^= 0x01
    #expect(throws: DDCError.self) { try DDC.replyBody(reply) }
}
