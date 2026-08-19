import AppKit
import SwiftUI
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

        // Every test in this file hardcodes the same frame-autosave name
        // (matching production, which only ever has one instance). Verified
        // empirically: once a window with that name has been shown, a
        // *different*, never-shown `NSWindow` object's own
        // `setFrameAutosaveName` call for the same name silently fails —
        // `orderOut`/`close`/`isReleasedWhenClosed` alone do not release the
        // claim, but explicitly reassigning an empty name does, keeping
        // these tests independent of run order.
        controller.window.setFrameAutosaveName("")
        controller.window.close()
    }

    @MainActor
    func testWindowIsTitledResizableAndHasAFrameAutosaveName() {
        let controller = SidecastWhiteboardWindowController()
        XCTAssertEqual(controller.window.title, "Whiteboard")
        XCTAssertTrue(controller.window.styleMask.contains(.resizable))
        XCTAssertTrue(controller.window.styleMask.contains(.titled))
        XCTAssertFalse(controller.window.frameAutosaveName.isEmpty)
    }

    // MARK: - Fix round: construction must not trigger the hosted view's work

    /// Regression test for a real launch-time defect a reviewer caught with
    /// an instrumented counter: the whiteboard's `NSHostingView` content
    /// used to be installed in `init`, and SwiftUI runs a hosted view's
    /// `.task` (here: resolving the corpus bookmark and reading a possibly
    /// multi-MB folder) as soon as its content is installed — independent of
    /// whether the window is ever shown. `NSWindow` always has *some*
    /// `contentView` from construction (AppKit auto-creates a blank one), so
    /// the discriminating check is the specific hosted-content type, not
    /// nil-ness: is it our `NSHostingView<SidecastWhiteboardView>` yet, or
    /// still AppKit's placeholder? No timing/async guesswork needed, unlike
    /// trying to prove the disk read itself didn't happen.
    @MainActor
    func testContentIsNotInstalledUntilFirstShow() {
        let controller = SidecastWhiteboardWindowController()
        XCTAssertFalse(
            controller.window.contentView is NSHostingView<SidecastWhiteboardView>,
            "installing SwiftUI content before the window is ever shown would fire its .task early — the exact launch-time corpus-read defect this guards against")

        controller.show()
        XCTAssertTrue(
            controller.window.contentView is NSHostingView<SidecastWhiteboardView>,
            "content must be installed by the time the window is actually shown")
        controller.hide()

        // A second show must not reinstall (which would mean re-triggering
        // whatever the hosted view's .task does, on every reopen).
        let contentViewAfterFirstShow = controller.window.contentView
        controller.show()
        XCTAssertTrue(controller.window.contentView === contentViewAfterFirstShow, "content is installed once, not on every show()")

        // Releases the frame-autosave-name claim before closing — see the
        // matching comment in the show/hide-cycle test above.
        controller.window.setFrameAutosaveName("")
        controller.window.close()
    }

    // MARK: - Fix round: dark-mode contrast robustness layer

    /// The board's palette is a fixed warm-white family, not dark-mode
    /// aware — locking the window's own appearance is the broader
    /// robustness layer (independent of any individual SwiftUI color
    /// choice inside the hosted view) that keeps every dynamic system color
    /// resolving against a light backdrop regardless of the system's
    /// current appearance.
    @MainActor
    func testWindowAppearanceIsLockedToLightRegardlessOfSystemAppearance() {
        let controller = SidecastWhiteboardWindowController()
        XCTAssertEqual(controller.window.appearance?.name, NSAppearance.Name.aqua)
    }
}
