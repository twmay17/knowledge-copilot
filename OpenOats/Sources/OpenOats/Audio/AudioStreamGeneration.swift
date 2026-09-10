import Foundation
import os

/// Rejects callbacks from a replaced or stopped stream, including callbacks queued
/// on another executor. The callback must not re-enter this gate.
final class AudioStreamGeneration: Sendable {
    private let current = OSAllocatedUnfairLock<UUID?>(initialState: nil)

    @discardableResult func begin() -> UUID {
        current.withLock { value in
            let id = UUID()
            value = id
            return id
        }
    }

    func invalidate() { current.withLock { $0 = nil } }
    func accepts(_ id: UUID) -> Bool { current.withLock { $0 == id } }

    func withCurrent(_ id: UUID, perform action: () -> Void) {
        // The closure is synchronous, does not escape, and never crosses executors.
        current.withLockUnchecked { value in
            guard value == id else { return }
            action()
        }
    }
}
