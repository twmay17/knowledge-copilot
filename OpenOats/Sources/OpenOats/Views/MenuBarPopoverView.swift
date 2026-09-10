import SwiftUI

struct MenuBarPopoverView: View {
    let coordinator: AppCoordinator
    let settings: AppSettings
    let onToggleMeeting: () -> Void
    let onShowMainWindow: () -> Void
    let onCheckForUpdates: () -> Void
    let onShowSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusLine
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            primaryAction
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            Button(action: onShowMainWindow) {
                HStack {
                    Text("Show \(AppBuildIdentity.displayName)")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if AppUpdaterController.updatesEnabled {
                Button(action: onCheckForUpdates) {
                    HStack {
                        Text("Check for Updates…")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Button(action: onShowSettings) {
                HStack {
                    Text("Settings…")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            Button(action: onQuit) {
                HStack {
                    Text("Quit \(AppBuildIdentity.displayName)")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .padding(.bottom, 4)
        }
        .frame(width: 280)
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            if coordinator.isRecording {
                Circle()
                    .fill(coordinator.liveSessionController?.state.capturePhase == .live ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(coordinator.liveSessionController?.state.capturePhase.title ?? "Preparing")
                    .font(.system(size: 13, weight: .medium))
            } else if settings.meetingAutoDetectEnabled {
                Circle()
                    .fill(.secondary)
                    .frame(width: 8, height: 8)
                Text("Meeting detection on")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text("Idle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if coordinator.isRecording {
            Button(action: onToggleMeeting) {
                Text("Stop Recording")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OpenOatsProminentButtonStyle(color: .red))
            .controlSize(.regular)
        } else {
            Button(action: {
                guard settings.hasAcknowledgedRecordingConsent else {
                    onShowMainWindow()
                    return
                }
                onToggleMeeting()
            }) {
                Text("Start Recording")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OpenOatsProminentButtonStyle())
            .controlSize(.regular)
        }
    }

}
