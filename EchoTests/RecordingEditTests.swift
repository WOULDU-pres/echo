import Testing
import Foundation
@testable import Echo

/// 전사기를 호출하지 않는 편집/정리 테스트용 noop 전사기.
private final class NoopTranscriber: Transcriber, @unchecked Sendable {
    func transcribe(_ audio: URL, language: String) async throws -> [TranscriptSegment] { [] }
}

/// 전사 텍스트로 입력 파일명을 돌려주는 목(재전사 갱신 검증용).
private final class FilenameMockTranscriber: Transcriber, @unchecked Sendable {
    func transcribe(_ audio: URL, language: String) async throws -> [TranscriptSegment] {
        [TranscriptSegment(start: 0, end: 1, text: audio.lastPathComponent, isFinal: true)]
    }
}

@MainActor
private func freshState() -> AppState {
    let store = RecordingStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("echo-edit-\(UUID())"))
    return AppState(batchTranscriber: NoopTranscriber(), livePreview: nil, store: store)
}

/// 이름 변경: 양끝 공백 정리 + 공백만/없는 id는 무시(기존 제목 유지).
@MainActor
@Test func renameTrimsAndIgnoresBlank() async throws {
    let state = freshState()
    let rec = Recording(title: "old",
                        segments: [TranscriptSegment(start: 0, end: 1, text: "hi", isFinal: true)])
    state.recordings = [rec]

    state.renameRecording(rec.id, to: "  새 제목  ")
    #expect(state.recordings[0].title == "새 제목")   // 양끝 공백 정리됨

    state.renameRecording(rec.id, to: "   ")          // 공백만 → 무시
    #expect(state.recordings[0].title == "새 제목")

    state.renameRecording(UUID(), to: "x")            // 없는 id → 무시(크래시 없음)
    #expect(state.recordings[0].title == "새 제목")
}

/// 재전사: 같은 녹음(id 유지)의 segments만 새 결과로 교체하고 새 녹음을 만들지 않는다.
@MainActor
@Test func retranscribeUpdatesSameRecording() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("echo-rt-\(UUID())")
    let store = RecordingStore(directory: dir)
    let rec = Recording(title: "orig", source: .micOnly,
                        audioTracks: [.microphone: dir.appendingPathComponent("mic.caf")],
                        segments: [TranscriptSegment(start: 0, end: 1, text: "old", channel: .microphone, isFinal: true)])
    let state = AppState(batchTranscriber: FilenameMockTranscriber(), livePreview: nil, store: store)
    state.recordings = [rec]

    state.retranscribe(rec.id)
    for _ in 0..<150 {
        if state.jobs.isEmpty && state.recordings.first?.segments.first?.text == "mic.caf" { break }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    #expect(state.recordings.count == 1)                              // 새로 만들지 않고 갱신
    #expect(state.recordings.first?.id == rec.id)                     // 같은 녹음
    #expect(state.recordings.first?.segments.first?.text == "mic.caf")// 새 결과로 교체됨
    #expect(state.jobs.isEmpty)
}

/// 빈 집합 deleteRecordings는 무시(우발적 전체 삭제 방지). 명시적 id는 정확히 삭제.
@MainActor
@Test func deleteRecordingsIgnoresEmptyAndDeletesExplicit() async throws {
    let state = freshState()
    let a = Recording(title: "a", segments: [TranscriptSegment(start: 0, end: 1, text: "a", isFinal: true)])
    let b = Recording(title: "b", segments: [TranscriptSegment(start: 0, end: 1, text: "b", isFinal: true)])
    state.recordings = [a, b]
    state.selection = [a.id, b.id]

    state.deleteRecordings([])          // 빈 집합 → 무시(selection 전체 삭제 폴백 없음)
    #expect(state.recordings.count == 2)

    state.deleteRecordings([a.id])      // 명시적 → a만 삭제
    #expect(state.recordings.count == 1)
    #expect(state.recordings.first?.title == "b")
}

/// 빈 녹음 정리: segments 없는 항목만 제거, 멱등.
@MainActor
@Test func cleanupRemovesOnlyEmptyRecordings() async throws {
    let state = freshState()
    let full = Recording(title: "full",
                         segments: [TranscriptSegment(start: 0, end: 1, text: "hi", isFinal: true)])
    let empty1 = Recording(title: "e1", segments: [])
    let empty2 = Recording(title: "e2", segments: [])
    state.recordings = [full, empty1, empty2]

    #expect(state.emptyRecordingCount == 2)
    let removed = state.cleanupEmptyRecordings()
    #expect(removed == 2)
    #expect(state.recordings.count == 1)
    #expect(state.recordings.first?.title == "full")
    #expect(state.emptyRecordingCount == 0)
    #expect(state.cleanupEmptyRecordings() == 0)      // 더 지울 게 없으면 0(멱등)
}
