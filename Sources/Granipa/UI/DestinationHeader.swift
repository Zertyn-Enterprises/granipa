import SwiftUI

/// Shared title + actions row so Home and Dictation share leading x, type,
/// and control height. A subtitle, when present, sits under that row.
struct DestinationChrome<Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 16) {
                Text(title)
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                actions()
                    .layoutPriority(1)
            }
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

struct DestinationHeader: View {
    @Environment(AppState.self) private var app
    let title: String

    var body: some View {
        DestinationChrome(title: title) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    quickNoteButton(labeled: true)
                    recordButton(labeled: true)
                }
                HStack(spacing: 8) {
                    quickNoteButton(labeled: false)
                    recordButton(labeled: true)
                }
                HStack(spacing: 8) {
                    quickNoteButton(labeled: false)
                    recordButton(labeled: false)
                }
            }
        }
    }

    private func quickNoteButton(labeled: Bool) -> some View {
        Button {
            app.createMeeting()
        } label: {
            if labeled {
                Label("Quick note", systemImage: "plus")
                    .font(.system(size: 14, weight: .medium))
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .granipaSecondaryControl()
        .help("Quick note")
        .accessibilityLabel("Quick note")
    }

    private func recordButton(labeled: Bool) -> some View {
        Button {
            app.startRecording()
        } label: {
            if labeled {
                Label(
                    app.recorder.isBusy ? "Recording…" : "Record",
                    systemImage: "record.circle"
                )
                .font(.system(size: 15, weight: .semibold))
            } else {
                Image(systemName: "record.circle")
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .granipaPrimaryControl()
        .disabled(app.recorder.isBusy)
        .help(app.recorder.isBusy ? "Recording" : "Record")
        .accessibilityLabel(app.recorder.isBusy ? "Recording" : "Record")
    }
}
