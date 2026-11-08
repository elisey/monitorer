import Testing

@testable import MonitorerCore

private func edid(descriptors: [[UInt8]]) -> [UInt8] {
    var block = [UInt8](repeating: 0, count: 128)
    for (index, descriptor) in descriptors.enumerated() {
        let offset = 54 + index * 18
        block.replaceSubrange(offset..<(offset + 18), with: descriptor)
    }
    return block
}

private func textDescriptor(tag: UInt8, _ text: String) -> [UInt8] {
    var payload = Array(text.utf8) + [0x0A]
    payload += [UInt8](repeating: 0x20, count: 13 - payload.count)
    return [0x00, 0x00, 0x00, tag, 0x00] + payload
}

private let timingDescriptor: [UInt8] = [0x56, 0x5E] + [UInt8](repeating: 0x11, count: 16)

@Test func readsDisplayName() {
    let block = edid(descriptors: [
        timingDescriptor,
        textDescriptor(tag: 0xFF, "UK0203501234"),
        textDescriptor(tag: 0xFC, "PHL 346B1C"),
    ])
    #expect(EDID.displayName(block) == "PHL 346B1C")
}

@Test func nameWithoutTerminatorUsesAllThirteenBytes() {
    let descriptor: [UInt8] = [0x00, 0x00, 0x00, 0xFC, 0x00] + Array("ABCDEFGHIJKLM".utf8)
    #expect(EDID.displayName(edid(descriptors: [descriptor])) == "ABCDEFGHIJKLM")
}

@Test func missingNameReturnsNil() {
    #expect(EDID.displayName(edid(descriptors: [timingDescriptor])) == nil)
}

@Test func truncatedEDIDReturnsNil() {
    #expect(EDID.displayName([0x00, 0xFF]) == nil)
}
