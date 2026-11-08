import Testing

@testable import MonitorerCore

@Test func getWritesRequestTwiceAndReadsValue() throws {
    let display = FakeDisplay(values: [0x10: 85])
    #expect(try makeClient(display).getVCP(0x10).current == 85)
    let request = DDC.getVCPRequest(code: 0x10)
    #expect(display.writes == [request, request])
}

@Test func getRetriesWhileDisplayIsBusy() throws {
    let display = FakeDisplay(values: [0x86: 8], busyReads: 5)
    #expect(try makeClient(display).getVCP(0x86).current == 8)
}

@Test func getGivesUpWhenDisplayStaysBusy() {
    let display = FakeDisplay(values: [0x86: 8], busyReads: 1000)
    #expect {
        try makeClient(display).getVCP(0x86)
    } throws: { error in
        guard case DDCError.timeout = error else { return false }
        return true
    }
}

@Test func getDoesNotRetryUnsupportedCode() {
    let display = FakeDisplay(values: [:])
    #expect(throws: DDCError.unsupported(code: 0x86)) { try makeClient(display).getVCP(0x86) }
    #expect(display.writes.count == 2)
}

@Test func setWritesAndVerifiesValue() throws {
    let display = FakeDisplay(values: [0x86: 8])
    #expect(try makeClient(display).setVCP(0x86, 4).current == 4)
    #expect(display.values[0x86] == 4)
    #expect(display.setRequests == [DDC.setVCPRequest(code: 0x86, value: 4)].flatMap { [$0, $0] })
}

@Test func setToleratesBusyDisplayWhileVerifying() throws {
    let display = FakeDisplay(values: [0x86: 8], busyReads: 6)
    #expect(try makeClient(display).setVCP(0x86, 4).current == 4)
}

@Test func setFailsWhenDisplayKeepsOldValue() {
    let display = FakeDisplay(values: [0x86: 8], ignoresSets: true)
    #expect {
        try makeClient(display).setVCP(0x86, 4)
    } throws: { error in
        guard case DDCError.timeout(let message) = error else { return false }
        return message.contains("did not become 4")
    }
}
