import SwiftUI

struct RecordingBar: View {
    @Environment(AppState.self) private var app
    let meeting: Meeting

    var body: some View {
        HStack(spacing: 12) {
            Button {
                app.startRecording(meetingID: meeting.id)
            } label: {
                Label("Record", systemImage: "record.circle")
                    .font(.system(size: 13, weight: .semibold))
            }
            .granipaPrimaryControl()
            .disabled(app.recorder.isBusy)
            Spacer()
        }
    }
}

struct LevelMeter: View {
    let label: String
    let level: Float

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fillSubtle)
                Capsule()
                    .fill(Theme.statusDone)
                    .frame(width: CGFloat(min(level * 300, 60)))
            }
            .frame(width: 60, height: 6)
        }
    }
}
