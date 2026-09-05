import SwiftUI

struct DestinationHeader: View {
    @Environment(AppState.self) private var app
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(Theme.titleFont)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
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
            .layoutPriority(1)
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
            }
        }
        .granipaPrimaryControl()
        .disabled(app.recorder.isBusy)
        .help(app.recorder.isBusy ? "Recording" : "Record")
        .accessibilityLabel(app.recorder.isBusy ? "Recording" : "Record")
    }
}
