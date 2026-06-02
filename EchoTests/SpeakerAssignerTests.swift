import Testing
@testable import Echo

/// 화자 스팬을 전사 세그먼트에 시간 overlap 최대로 할당하는 순수 로직 검증.
@Test func assignsSpeakerWithMaxOverlap() {
    // 화자 스팬: 0~5초 화자0, 5~10초 화자1
    let spans = [
        SpeakerSpan(speakerKey: "A", start: 0, end: 5),
        SpeakerSpan(speakerKey: "B", start: 5, end: 10),
    ]
    let segs = [
        TranscriptSegment(start: 0, end: 4, text: "first", channel: .system, isFinal: true),   // A
        TranscriptSegment(start: 6, end: 9, text: "second", channel: .system, isFinal: true),   // B
        TranscriptSegment(start: 4, end: 6, text: "edge", channel: .system, isFinal: true),     // A,B 걸침 → 더 큰 쪽
    ]
    let out = SpeakerAssigner.assign(segments: segs, spans: spans)
    #expect(out[0].speakerIndex == 0)   // A → index 0
    #expect(out[1].speakerIndex == 1)   // B → index 1
    // edge(4~6): A와 1초, B와 1초 동률 → 먼저 등장한 화자(0) 선택(안정적)
    #expect(out[2].speakerIndex == 0)
}

@Test func speakerKeysMapToStableZeroBasedIndices() {
    // 등장 순서대로 0,1,2…로 매핑(문자열 ID와 무관하게).
    let spans = [
        SpeakerSpan(speakerKey: "speaker_2", start: 0, end: 2),
        SpeakerSpan(speakerKey: "speaker_7", start: 2, end: 4),
        SpeakerSpan(speakerKey: "speaker_2", start: 4, end: 6),
    ]
    let segs = [
        TranscriptSegment(start: 0, end: 2, text: "a", channel: .system, isFinal: true),
        TranscriptSegment(start: 2, end: 4, text: "b", channel: .system, isFinal: true),
        TranscriptSegment(start: 4, end: 6, text: "c", channel: .system, isFinal: true),
    ]
    let out = SpeakerAssigner.assign(segments: segs, spans: spans)
    #expect(out.map(\.speakerIndex) == [0, 1, 0])   // speaker_2=0, speaker_7=1
}

@Test func noOverlapLeavesSpeakerNil() {
    let spans = [SpeakerSpan(speakerKey: "A", start: 100, end: 110)]
    let segs = [TranscriptSegment(start: 0, end: 5, text: "x", channel: .system, isFinal: true)]
    let out = SpeakerAssigner.assign(segments: segs, spans: spans)
    #expect(out[0].speakerIndex == nil)   // 겹치는 화자 없음
}

@Test func emptySpansReturnsUnchanged() {
    let segs = [TranscriptSegment(start: 0, end: 5, text: "x", channel: .system, isFinal: true)]
    #expect(SpeakerAssigner.assign(segments: segs, spans: []).map(\.speakerIndex) == [nil])
}
