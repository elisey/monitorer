import Testing

@testable import MonitorerCore

@Test func picksDisplayByName() throws {
    let index = try ExternalDisplays.indexOfOnlyDisplay(
        named: "PHL 346B1C", among: [nil, "DELL U2720Q", "PHL 346B1C"])
    #expect(index == 2)
}

@Test func reportsFoundDisplaysWhenNameIsMissing() {
    #expect(throws: DDCError.display("display \"PHL 346B1C\" not found (found: DELL U2720Q, unknown)")) {
        try ExternalDisplays.indexOfOnlyDisplay(named: "PHL 346B1C", among: ["DELL U2720Q", nil])
    }
}

@Test func reportsMissingExternalDisplays() {
    #expect(throws: DDCError.display("display \"PHL 346B1C\" not found (found: no external displays)")) {
        try ExternalDisplays.indexOfOnlyDisplay(named: "PHL 346B1C", among: [])
    }
}

@Test func refusesToChooseBetweenDisplaysWithSameName() {
    #expect(throws: DDCError.display("2 displays named \"PHL 346B1C\" found; cannot choose one")) {
        try ExternalDisplays.indexOfOnlyDisplay(
            named: "PHL 346B1C", among: ["PHL 346B1C", "PHL 346B1C"])
    }
}
