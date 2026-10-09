import XCTest

// Supporting state/refusal fixtures only; compile with Host.swift and ADMISSION_TESTS.
final class WindowAdmissionTests: XCTestCase {
    func testCallbackWithoutCurrentEventRefused() {
        var proof = AdmissionEvidence()
        XCTAssertFalse(proof.action("selected", number: nil, mouseUp: false))
        XCTAssertEqual(proof.state, "idle")
        XCTAssertEqual(proof.actions, 0)
    }
    func testMatchingReceiptAndAction() {
        var proof = AdmissionEvidence()
        proof.expected = 101
        proof.receive(100); proof.receive(101)
        XCTAssertTrue(proof.action("selected", number: 101, mouseUp: true))
        proof.expected = 103
        proof.receive(102); proof.receive(103)
        XCTAssertTrue(proof.action("idle", number: 103, mouseUp: true))
        XCTAssertEqual(proof.actions, 2)
    }
    func testDuplicateAndNegativeActionRefused() {
        var proof = AdmissionEvidence()
        proof.receive(100); proof.receive(100)
        proof.expected = 101; proof.receive(101)
        XCTAssertFalse(proof.action("selected", number: 101, mouseUp: true))
        var padding = AdmissionEvidence()
        padding.receive(102); padding.receive(103)
        XCTAssertFalse(padding.action("selected", number: 103, mouseUp: true))
    }
}
