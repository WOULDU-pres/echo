import Testing
@testable import Echo

@Test func exportsPlainText() {
    let segs = [
        TranscriptSegment(start: 0, end: 2, text: "안녕하세요", channel: .microphone, isFinal: true),
        TranscriptSegment(start: 2, end: 4, text: "반갑습니다", channel: .system, isFinal: true),
    ]
    #expect(TranscriptExporter.export(segs, as: .txt) == "안녕하세요\n반갑습니다")
}

@Test func exportsSRTWithTimecodes() {
    let segs = [TranscriptSegment(start: 1.5, end: 3.25, text: "테스트", isFinal: true)]
    let expected = "1\n00:00:01,500 --> 00:00:03,250\n테스트\n"
    #expect(TranscriptExporter.export(segs, as: .srt) == expected)
}

@Test func exportsMarkdownWithSpeaker() {
    let segs = [TranscriptSegment(start: 5, end: 7, text: "내용", channel: .microphone, isFinal: true)]
    #expect(TranscriptExporter.export(segs, as: .markdown) == "**[00:00:05] 나**\n\n내용")
}
