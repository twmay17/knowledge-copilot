import XCTest
@testable import OpenOatsKit

final class AudioRoutingSafetyTests: XCTestCase {
    func testRecoveryStopsAfterOneRetryAndDoesNotMistakeAnErrorForHealth() {
        for hasFrames in [false, true] {
            for hasError in [false, true] {
                let healthy = hasFrames && !hasError
                XCTAssertEqual(MicrophoneRoutePolicy.recoveryAction(hasFrames: hasFrames,
                    hasError: hasError, hasRetried: false), healthy ? .none : .retry)
                XCTAssertEqual(MicrophoneRoutePolicy.recoveryAction(hasFrames: hasFrames,
                    hasError: hasError, hasRetried: true), healthy ? .none : .needsAttention)
            }
        }
    }

    func testExplicitMicDoesNotFallBackWhenDisconnected() {
        XCTAssertNil(MicrophoneRoutePolicy.resolve(requestedID: 81, savedUID: "usb-mic",
            available: [(74, "built-in")], defaultID: 74))
    }

    func testReconnectedMicResolvesStableUIDAtNewID() {
        XCTAssertEqual(MicrophoneRoutePolicy.resolve(requestedID: 81, savedUID: "usb-mic",
            available: [(74, "built-in"), (99, "usb-mic")], defaultID: 74), 99)
    }

    func testRecycledNumericIDCannotSelectDifferentMicrophone() {
        XCTAssertNil(MicrophoneRoutePolicy.resolve(requestedID: 81, savedUID: "usb-mic",
            available: [(81, "other-persons-mic")], defaultID: 81))
    }

    func testStableUIDWinsEvenWhenOldNumericIDStillExists() {
        XCTAssertEqual(MicrophoneRoutePolicy.resolve(requestedID: 81, savedUID: "usb-mic",
            available: [(81, "different-device"), (99, "usb-mic")], defaultID: 81), 99)
    }

    func testDefaultSelectionFollowsOnlyAvailableDefault() {
        XCTAssertEqual(MicrophoneRoutePolicy.resolve(requestedID: 0, savedUID: "ignored",
            available: [(74, "built-in")], defaultID: 74), 74)
        XCTAssertNil(MicrophoneRoutePolicy.resolve(requestedID: 0, savedUID: nil,
            available: [(74, "built-in")], defaultID: 99))
        XCTAssertNil(MicrophoneRoutePolicy.resolve(requestedID: 0, savedUID: nil,
            available: [], defaultID: nil))
    }

    func testLegacySettingWithoutUIDCanUseAvailableID() {
        XCTAssertEqual(MicrophoneRoutePolicy.resolve(requestedID: 81, savedUID: nil,
            available: [(81, nil)], defaultID: nil), 81)
        XCTAssertNil(MicrophoneRoutePolicy.resolve(requestedID: 81, savedUID: nil,
            available: [], defaultID: 74))
    }

    func testOldStreamCannotDeliverAfterReplacementOrStop() {
        let gate = AudioStreamGeneration()
        let old = gate.begin()
        var delivered = [String]()
        gate.withCurrent(old) { delivered.append("first") }
        let replacement = gate.begin()
        gate.withCurrent(old) { delivered.append("stale") }
        gate.withCurrent(replacement) { delivered.append("replacement") }
        gate.invalidate()
        gate.withCurrent(replacement) { delivered.append("after-stop") }
        XCTAssertEqual(delivered, ["first", "replacement"])
        XCTAssertFalse(gate.accepts(old))
        XCTAssertFalse(gate.accepts(replacement))
    }

    func testMicReplacementDoesNotInvalidateSystemStream() {
        let mic = AudioStreamGeneration()
        let system = AudioStreamGeneration()
        let oldMic = mic.begin()
        let systemID = system.begin()
        mic.begin()
        XCTAssertFalse(mic.accepts(oldMic))
        XCTAssertTrue(system.accepts(systemID))
    }

    func testDelayedCallbackChecksGenerationWhenDelivered() async {
        let gate = AudioStreamGeneration()
        let old = gate.begin()
        let suspended = Task { () -> Bool in
            try? await Task.sleep(for: .milliseconds(20))
            return gate.accepts(old)
        }
        gate.invalidate()
        gate.begin()
        let accepted = await suspended.value
        XCTAssertFalse(accepted)
    }
}
