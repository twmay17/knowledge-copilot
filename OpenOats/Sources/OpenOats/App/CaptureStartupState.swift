import Foundation

enum CaptureStartupPhase: String, Equatable, Sendable {
    case idle, preparing, awaitingPermission, loadingModels, startingAudio
    case waitingForAudio, live, partialAudio, failed, stopping

    var title: String {
        switch self {
        case .idle: "Idle"
        case .preparing: "Preparing"
        case .awaitingPermission: "Awaiting microphone permission"
        case .loadingModels: "Loading speech models"
        case .startingAudio: "Starting audio"
        case .waitingForAudio: "Waiting for audio"
        case .live: "Live"
        case .partialAudio: "Partial audio"
        case .failed: "Startup needs attention"
        case .stopping: "Stopping"
        }
    }

    var isCapturing: Bool { self == .live || self == .partialAudio }

    static func resolve(
        stage: Self, engineRunning: Bool, hasError: Bool,
        micFrames: Bool, systemFrames: Bool, micMuted: Bool, scripted: Bool
    ) -> Self {
        if scripted && engineRunning { return .live }
        if stage == .awaitingPermission || stage == .loadingModels || stage == .preparing {
            return hasError ? .failed : stage
        }
        guard engineRunning else { return hasError ? .failed : .preparing }
        if systemFrames && (micFrames || micMuted) && !hasError { return .live }
        if micFrames || systemFrames { return .partialAudio }
        if hasError { return .failed }
        return stage == .startingAudio ? .startingAudio : .waitingForAudio
    }
}

/// MainActor-owned startup lease. Invalidating it prevents late async completions
/// from activating capture or overwriting a newer session's startup state.
struct CaptureStartupGate {
    private(set) var attempt: UUID?
    private(set) var phase: CaptureStartupPhase = .idle

    mutating func begin() -> UUID {
        let id = UUID()
        attempt = id
        phase = .preparing
        return id
    }

    func accepts(_ id: UUID, cancelled: Bool = Task.isCancelled) -> Bool {
        attempt == id && !cancelled
    }

    mutating func advance(_ phase: CaptureStartupPhase, for id: UUID) {
        guard accepts(id) else { return }
        self.phase = phase
    }

    mutating func invalidate() {
        attempt = nil
        phase = .idle
    }
}
