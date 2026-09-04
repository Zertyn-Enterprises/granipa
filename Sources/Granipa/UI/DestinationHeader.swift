import SwiftUI

struct DestinationHeader: View {
    @Environment(AppState.self) private var app
    @Environment(\.granipaWindowWidth) private var windowWidth
    let title: String

    private var compact: Bool { windowWidth < ShellLayout.inspectorBreakWidth }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.titleFont)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                app.createMeeting()
            } label: {
                if compact {
                    Image(systemName: "plus")
                } else {
                    Label("Quick note", systemImage: "plus")
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.white)
            .help("Quick note")
            .accessibilityLabel("Quick note")

            Button {
                app.startRecording()
            } label: {
                if compact {
                    Image(systemName: "record.circle")
                } else {
                    Label(
                        app.recorder.isBusy ? "Recording…" : "Record",
                        systemImage: "record.circle"
                    )
                    .font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accent)
            .recordGlow()
            .disabled(app.recorder.isBusy)
            .help(app.recorder.isBusy ? "Recording" : "Record")
            .accessibilityLabel(app.recorder.isBusy ? "Recording" : "Record")
        }
    }
}
