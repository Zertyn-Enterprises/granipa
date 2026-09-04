import SwiftUI

struct CaptionsOverlayView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.statusListening)
                    .frame(width: 6, height: 6)
                Text("Captions")
                    .font(Theme.fontCaption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            if let live = app.transcription {
                if let warning = live.systemWarning {
                    Text(warning)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.statusFailed)
                        .lineLimit(2)
                }
                let snippet = LiveTranscriptSnippet(
                    lastSegment: live.liveSegments.last,
                    volatileSystem: live.volatileSystem,
                    volatileMic: live.volatileMic,
                    style: .captions)
                snippet
                if snippet.isEmpty {
                    Text(placeholder(for: live.phase))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .italic()
                }
            }
        }
        .padding(.horizontal, Theme.spaceL)
        .padding(.vertical, Theme.spaceM)
        .frame(width: 640, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.radiusOverlay, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusOverlay, style: .continuous)
                .stroke(Theme.accent.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        // The panel is a fixed transparent bounding box; the card keeps its
        // content size, pinned to the top (the anchoring relayoutNow used to do).
        .frame(maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    private func placeholder(for phase: TranscriptionCoordinator.Phase) -> String {
        switch phase {
        case .preparing: "Preparing speech model…"
        case .failed(let message): "Transcription failed: \(message)"
        default: "Listening…"
        }
    }
}
