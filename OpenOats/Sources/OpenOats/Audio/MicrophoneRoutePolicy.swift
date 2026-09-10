import CoreAudio

enum MicrophoneRoutePolicy {
    enum RecoveryAction { case none, retry, needsAttention }

    static func recoveryAction(hasFrames: Bool, hasError: Bool, hasRetried: Bool) -> RecoveryAction {
        if hasFrames && !hasError { return .none }
        return hasRetried ? .needsAttention : .retry
    }

    /// Explicit selection never silently falls back to a different microphone.
    /// Stable UIDs take precedence because CoreAudio can recycle numeric IDs.
    static func resolve(
        requestedID: AudioDeviceID, savedUID: String?,
        available: [(id: AudioDeviceID, uid: String?)], defaultID: AudioDeviceID?
    ) -> AudioDeviceID? {
        if requestedID == 0 {
            return defaultID.flatMap { id in available.contains(where: { $0.id == id }) ? id : nil }
        }
        if let savedUID, !savedUID.isEmpty {
            return available.first(where: { $0.uid == savedUID })?.id
        }
        return available.contains(where: { $0.id == requestedID }) ? requestedID : nil
    }
}
