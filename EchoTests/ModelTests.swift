import Testing
@testable import Echo

@Test func timecodeFormatsHMS() {
    #expect(TranscriptSegment(start: 5, end: 6, text: "x").timecode == "00:00:05")
    #expect(TranscriptSegment(start: 3661, end: 3662, text: "x").timecode == "01:01:01")
}

@Test func speakerLabelsByChannel() {
    #expect(TranscriptSegment(start: 0, end: 1, text: "x", channel: .microphone).speakerLabel == "나")
    #expect(TranscriptSegment(start: 0, end: 1, text: "x", channel: .system).speakerLabel == "상대")
    #expect(TranscriptSegment(start: 0, end: 1, text: "x", channel: .mixed).speakerLabel == "")
}

@Test func recordingPlainTextJoinsSegments() {
    let rec = Recording(title: "t", segments: [
        TranscriptSegment(start: 0, end: 1, text: "a"),
        TranscriptSegment(start: 1, end: 2, text: "b"),
    ])
    #expect(rec.plainText == "a\nb")
}
