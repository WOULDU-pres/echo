import Testing
import Foundation
import AVFoundation
@testable import Echo

/// 전사 큐가 절대 동시 전사를 호출하지 않는지(직렬성) 검증.
/// 느린 목 transcriber로 동시 진입 수를 측정 — 1을 넘으면 직렬성 위반(= 버그 재발).
private actor Counter {
    var current = 0
    var maxObserved = 0
    func enter() { current += 1; maxObserved = max(maxObserved, current) }
    func leave() { current -= 1 }
}

private final class SlowMockTranscriber: Transcriber, @unchecked Sendable {
    let counter = Counter()
    func transcribe(_ audio: URL, language: String) async throws -> [TranscriptSegment] {
        await counter.enter()
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms 처리 흉내
        await counter.leave()
        return [TranscriptSegment(start: 0, end: 1, text: audio.lastPathComponent, isFinal: true)]
    }
}

@MainActor
@Test func queueProcessesFilesSeriallyNeverConcurrent() async throws {
    // 실제 오디오 파일이 아니어도 확장자만 맞으면 큐에 들어간다(목 transcriber라 내용 무관).
    let dir = FileManager.default.temporaryDirectory
    let urls = (0..<5).map { dir.appendingPathComponent("clip_\($0).wav") }
    for u in urls { FileManager.default.createFile(atPath: u.path, contents: Data([0])) }

    let mock = SlowMockTranscriber()
    let store = RecordingStore(directory: dir.appendingPathComponent("echo-test-\(UUID())"))
    let state = AppState(batchTranscriber: mock, livePreview: nil, store: store)

    // 한 번에 3개 + 처리 중 추가 2개(큐잉) → 총 5개가 직렬로 처리돼야 함.
    state.enqueueFiles(Array(urls.prefix(3)))
    try? await Task.sleep(nanoseconds: 20_000_000)
    state.enqueueFiles(Array(urls.suffix(2)))   // 처리 중 추가 → 큐 뒤에 붙음

    // 모든 작업이 끝날 때까지 대기(최대 3초).
    for _ in 0..<150 {
        if state.jobs.isEmpty && state.recordings.count == 5 { break }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    let maxConcurrent = await mock.counter.maxObserved
    #expect(maxConcurrent == 1)              // 동시 진입 1 = 직렬
    #expect(state.recordings.count == 5)     // 5개 모두 완료되어 목록에 추가
    #expect(state.jobs.isEmpty)              // 큐 비워짐
}
