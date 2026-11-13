import Testing

@testable import MonitorerCore

private func controller(_ display: FakeDisplay) -> VolumeController {
    VolumeController(client: makeClient(display))
}

@Test func readsLevelAndRange() throws {
    let display = FakeDisplay(values: [0x62: 40])
    #expect(try controller(display).current() == Volume(level: 40, maximum: 100))
}

@Test func setsLevel() throws {
    let display = FakeDisplay(values: [0x62: 40])
    #expect(try controller(display).set(65) == Volume(level: 65, maximum: 100))
    #expect(display.values[0x62] == 65)
    #expect(display.setRequests.first == DDC.setVCPRequest(code: 0x62, value: 65))
}

@Test func setClampsToMonitorRange() throws {
    let display = FakeDisplay(values: [0x62: 40])
    #expect(try controller(display).set(250).level == 100)
    #expect(display.values[0x62] == 100)
    #expect(try controller(display).set(-5).level == 0)
    #expect(display.values[0x62] == 0)
}

@Test func setFailsWhenDisplayKeepsOldLevel() {
    let display = FakeDisplay(values: [0x62: 40], ignoresSets: true)
    #expect(throws: DDCError.self) { try controller(display).set(50) }
}
