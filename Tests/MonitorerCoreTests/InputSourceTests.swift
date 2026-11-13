import Testing

@testable import MonitorerCore

private func controller(_ display: FakeDisplay) -> InputSourceController {
    InputSourceController(client: makeClient(display))
}

@Test func observedInputValues() {
    #expect(InputSource.vcpCode == 0x60)
    #expect(InputSource.hdmi1.rawValue == 0x11)
    #expect(InputSource.usbC.rawValue == 0x15)
}

@Test func currentIgnoresVendorHighByte() throws {
    #expect(try controller(makeDisplayWithInput(0x15)).current() == .usbC)
    #expect(try controller(makeDisplayWithInput(0x11)).current() == .hdmi1)
}

@Test func currentIsNilForUnmanagedInput() throws {
    // 0x0F is DisplayPort 1, which the monitor declares but this tool does not switch to.
    #expect(try controller(makeDisplayWithInput(0x0F)).current() == nil)
}

@Test func setSwitchesToHDMI() throws {
    let display = makeDisplayWithInput(0x15)
    try controller(display).set(.hdmi1)
    #expect(display.values[0x60] == 0x2111)
    #expect(display.setRequests.first == DDC.setVCPRequest(code: 0x60, value: 0x11))
}

@Test func setSwitchesToUSBC() throws {
    let display = makeDisplayWithInput(0x11)
    try controller(display).set(.usbC)
    #expect(display.values[0x60] == 0x3515)
}

@Test func setSkipsWriteWhenAlreadyOnInput() throws {
    let display = makeDisplayWithInput(0x11)
    try controller(display).set(.hdmi1)
    #expect(display.setRequests.isEmpty)
}

@Test func setFailsWhenDisplayKeepsOldInput() {
    let display = makeDisplayWithInput(0x11)
    display.ignoresSets = true
    #expect {
        try controller(display).set(.usbC)
    } throws: { error in
        guard case DDCError.timeout = error else { return false }
        return true
    }
}
