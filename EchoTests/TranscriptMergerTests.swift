import Testing
@testable import Echo

@Test func mergesChannelsByStartTime() {
    let mic = [
        TranscriptSegment(start: 0, end: 1, text: "나1", channel: .microphone, isFinal: true),
        TranscriptSegment(start: 4, end: 5, text: "나2", channel: .microphone, isFinal: true),
    ]
    let sys = [
        TranscriptSegment(start: 2, end: 3, text: "상대1", channel: .system, isFinal: true),
    ]
    let merged = TranscriptMerger.merge([mic, sys])
    #expect(merged.map(\.text) == ["나1", "상대1", "나2"])
}
