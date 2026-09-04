import SwiftUI

struct InspectorPane: View {
    @Environment(AppState.self) private var app
    let kind: InspectorContentKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceL) {
                switch kind {
                case .none:
                    EmptyView()
                case .dictationIdle:
                    DictationInspectorView(dictation: app.dictation, isLive: false)
                case .dictationLive:
                    DictationInspectorView(dictation: app.dictation, isLive: true)
                }
            }
            .padding(Theme.spaceL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgSidebar)
    }
}

private struct DictationInspectorView: View {
    @Bindable var dictation: DictationController
    let isLive: Bool

    var body: some View {
        Group {
            if isLive {
                liveContent
            } else {
                idleContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dictation off")
                .font(Theme.sectionFont)
                .foregroundStyle(Theme.textPrimary)
            Text("Hold \(DictationController.shortcutLabel) to dictate.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictation off")
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: Theme.spaceL) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            Text(bodyText)
                .font(.system(size: 15))
                .foregroundStyle(
                    dictation.preview.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if case .failed = dictation.phase, dictation.lastFailureRetryable {
                Button("Retry") { dictation.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live dictation")
    }

    private var statusTitle: String {
        switch dictation.phase {
        case .preparing: "Preparing"
        case .listening: "Listening"
        case .processing: dictation.isRewriting ? "Rewriting" : "Processing"
        case .done: "Pasted"
        case .failed: "Needs attention"
        case .idle: "Dictation off"
        }
    }

    private var bodyText: String {
        if case .failed(let message) = dictation.phase { return message }
        if !dictation.preview.isEmpty { return dictation.preview }
        switch dictation.phase {
        case .preparing: return "Getting the microphone ready…"
        case .listening: return dictation.isToggle ? "Speak — press again to finish" : "Speak now…"
        case .processing: return "Finishing your dictation…"
        case .done: return dictation.preview
        default: return statusTitle
        }
    }

    private var dotColor: Color {
        switch dictation.phase {
        case .preparing: Theme.statusLoading
        case .listening: Theme.statusListening
        case .processing: Theme.statusProcessing
        case .done: Theme.statusDone
        case .failed: Theme.statusFailed
        case .idle: Theme.textTertiary
        }
    }
}
