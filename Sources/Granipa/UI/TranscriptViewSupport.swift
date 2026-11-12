import SwiftUI

/// Filtered rows and speaker names, recomputed only when the transcript,
/// query or speaker filter change. Array equality short-circuits on shared
/// storage, so recognising an unchanged transcript is cheap.
@MainActor
final class TranscriptRowsCache {
    private var inputs: (segments: [TranscriptSegment], query: String, speaker: String?)?
    private var rows: [TranscriptSegment] = []
    private var speakers: [String] = []

    func rows(for segments: [TranscriptSegment], query: String, speaker: String?)
        -> (rows: [TranscriptSegment], speakers: [String])
    {
        if let inputs, inputs.query == query, inputs.speaker == speaker,
            inputs.segments == segments
        {
            return (rows, speakers)
        }
        inputs = (segments, query, speaker)
        rows = TranscriptQuery.filter(segments: segments, query: query, speaker: speaker)
        speakers = TranscriptQuery.speakers(in: segments)
        return (rows, speakers)
    }
}

/// The only reader of the playback clock in the transcript: the list
/// re-renders when the current line changes, not on every 50 ms tick.
struct TranscriptPlaybackCursor: View {
    let playback: MeetingPlaybackController
    let rows: [TranscriptSegment]
    @Binding var currentIDs: Set<String>

    var body: some View {
        let ids = Set(TranscriptQuery.containing(rows, at: playback.currentTime).map(\.id))
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: ids, initial: true) { currentIDs = ids }
            .accessibilityHidden(true)
    }
}

/// A click on a line from the other channel switches the player to that
/// channel first; play() is ignored while the file prepares, so the seek
/// (and play) wait for the new file to load.
struct TranscriptPendingStart: Equatable {
    let seconds: Double
    let play: Bool
}
