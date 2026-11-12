import SwiftUI

struct SegmentRow: View {
    let segment: TranscriptSegment
    var isCurrent = false
    var isSelected = false
    var onPlay: (() -> Void)? = nil
    var onSelect: (() -> Void)? = nil

    private var speakerColor: Color {
        if segment.channel == .mic { return Theme.channelMe }
        if segment.speaker == "Them" { return Theme.accent }
        return Theme.avatarColor(for: segment.speaker)
    }

    private var usesRecordedChrome: Bool {
        onPlay != nil || onSelect != nil || isCurrent || isSelected
    }

    private var isActive: Bool { isCurrent || isSelected }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let onPlay {
                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isActive ? Theme.textPrimary : Theme.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(isActive ? Theme.accent : Theme.fillSubtle, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Play from \(LiveStageFormat.elapsed(Int(segment.startSeconds)))")
            }

            Text(LiveStageFormat.elapsed(Int(segment.startSeconds.rounded(.down))))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(isActive ? Theme.accent : Theme.textTertiary)
                .frame(minWidth: 38, alignment: .leading)
                .padding(.top, 3)

            if usesRecordedChrome {
                AvatarView(letterSource: segment.speaker, size: 22)
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(segment.speaker)
                        .font(Theme.fontCaption.weight(.semibold))
                        .foregroundStyle(speakerColor)
                    Text(TranscriptSource.label(segment.channel))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.fillSubtle, in: Capsule())
                }
                Text(segment.text)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isActive ? Theme.accent.opacity(0.08) : Theme.card,
            in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
        .overlay {
            if usesRecordedChrome {
                RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous)
                    .stroke(isActive ? Theme.accent : Theme.border, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
    }
}
