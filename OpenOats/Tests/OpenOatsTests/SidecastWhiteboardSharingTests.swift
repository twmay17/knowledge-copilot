import AppKit
import XCTest

@testable import OpenOatsKit

/// Proves the one non-negotiable property of the whiteboard window: it must
/// never be capturable by screen sharing. Follows the same harness
/// arrangement as Wave-1's `KnowledgeOverlayPresentationTests`
/// (`testPanelsHideFromCaptureAndFreshPanelsAreCapturable` et al.) — plain
/// `@MainActor` synchronous test functions constructing the AppKit type
/// directly and asserting `sharingType` immediately, no app-hosted harness
/// needed.
///
/// Per `grep -rn "sharingType" OpenOats/Tests/`, this is the established
/// pattern in this repo; there is no separate app-hosted arrangement to
/// borrow beyond `@MainActor`.
final class SidecastWhiteboardSharingTests: XCTestCase {

    @MainActor
    func testWindowIsExcludedFromScreenShareImmediatelyAfterCreation() {
        let controller = SidecastWhiteboardWindowController()
        XCTAssertEqual(
            controller.window.sharingType, .none,
            "the whiteboard window must never be capturable — set at creation, before it is ever shown")
    }

    @MainActor
    func testWindowStaysExcludedFromScreenShareAfterAShowHideCycle() {
        let controller = SidecastWhiteboardWindowController()
        controller.show()
        controller.hide()
        XCTAssertEqual(
            controller.window.sharingType, .none,
            "unlike MiniBarPanel/OverlayPanel, this window has no visible-in-share mode — a show/hide cycle must not change it")

        // A second cycle, to rule out a transition-driven false pass — the
        // one-way capture-exclusion ratchet documented on MiniBarPanel means
        // this could only regress by code that explicitly reassigns
        // sharingType, so this also guards against that ever being added.
        controller.show()
        controller.hide()
        XCTAssertEqual(controller.window.sharingType, .none)
    }

    @MainActor
    func testWindowIsTitledResizableAndHasAFrameAutosaveName() {
        let controller = SidecastWhiteboardWindowController()
        XCTAssertEqual(controller.window.title, "Whiteboard")
        XCTAssertTrue(controller.window.styleMask.contains(.resizable))
        XCTAssertTrue(controller.window.styleMask.contains(.titled))
        XCTAssertFalse(controller.window.frameAutosaveName.isEmpty)
    }
}
