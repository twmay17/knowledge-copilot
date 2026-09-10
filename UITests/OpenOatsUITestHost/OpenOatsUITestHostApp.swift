import SwiftUI
import OpenOatsKit

@main
enum OpenOatsUITestHostApp {
    @MainActor
    static func main() {
        // This binary must never fall back to the user's live app storage,
        // credentials, or recording services when opened outside XCTest.
        guard ProcessInfo.processInfo.environment["OPENOATS_UI_TEST"] == "1" else { return }
        // Install the App itself so SwiftUI owns its state and delegate.
        // Reading a temporary App's body bypasses that ownership.
        OpenOatsRootApp.run()
    }
}
