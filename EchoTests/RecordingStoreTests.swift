import Testing
import Foundation
@testable import Echo

@Test func storeRoundTripsRecordings() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("echo-store-\(UUID())")
    let store = RecordingStore(directory: dir)
    let rec = Recording(title: "t", segments: [TranscriptSegment(start: 0, end: 1, text: "안녕")])
    try store.save([rec])
    let loaded = try store.load()
    #expect(loaded.count == 1)
    #expect(loaded[0].segments.first?.text == "안녕")
    try? FileManager.default.removeItem(at: dir)
}

/// summary 를 포함한 Recording 이 RecordingStore 라운드트립에서 보존되는지.
@Test func storePreservesSummary() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("echo-summary-\(UUID())")
    let store = RecordingStore(directory: dir)
    let summary = CallSummary(
        overview: "전체 맥락 요약",
        timeline: [SummaryMoment(at: 90, text: "출석 체크"),
                   SummaryMoment(at: 725, text: "n8n 데모")],
        conclusion: "2시까지 수정 전달",
        model: "claude-opus-4-8"
    )
    let rec = Recording(title: "t",
                        segments: [TranscriptSegment(start: 0, end: 1, text: "안녕")],
                        summary: summary)
    try store.save([rec])
    let loaded = try store.load()
    #expect(loaded.count == 1)
    #expect(loaded[0].summary?.overview == "전체 맥락 요약")
    #expect(loaded[0].summary?.timeline.count == 2)
    #expect(loaded[0].summary?.timeline.first?.at == 90)
    #expect(loaded[0].summary?.timeline.first?.text == "출석 체크")
    #expect(loaded[0].summary?.conclusion == "2시까지 수정 전달")
    try? FileManager.default.removeItem(at: dir)
}

/// 정리본이 없는 Recording 은 summary 키가 생략되어 라운드트립에서 nil 보존(하위호환).
/// 키가 생략되므로, summary 가 없는 구버전 recordings.json 도 그대로 디코드된다.
@Test func recordingWithoutSummaryIsNil() throws {
    let rec = Recording(title: "t", segments: [TranscriptSegment(start: 0, end: 1, text: "x")])
    let data = try JSONEncoder().encode(rec)
    let json = String(decoding: data, as: UTF8.self)
    #expect(!json.contains("summary"))           // nil 옵셔널은 키 자체가 생략됨
    let decoded = try JSONDecoder().decode(Recording.self, from: data)
    #expect(decoded.summary == nil)
}

/// 스킬이 쓰는 timeline 항목은 {at, text} 만 있어도 디코드(id 자동 생성).
@Test func summaryMomentDecodesWithoutID() throws {
    let json = #"{"at": 12.5, "text": "핵심 순간"}"#
    let m = try JSONDecoder().decode(SummaryMoment.self, from: Data(json.utf8))
    #expect(m.at == 12.5)
    #expect(m.text == "핵심 순간")
}

/// SummaryMoment 타임코드 포맷(전사 행과 동일 HH:MM:SS).
@Test func summaryMomentTimecode() {
    #expect(SummaryMoment(at: 5, text: "x").timecode == "00:00:05")
    #expect(SummaryMoment(at: 3661, text: "x").timecode == "01:01:01")
}
