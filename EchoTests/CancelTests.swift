import Testing
import Foundation
@testable import Echo

/// 전사 작업 취소 동작 검증.
/// - cancelAllJobs: 대기 큐를 비우고 진행 중 결과를 폐기(녹음 0건).
/// - cancelJob(진행 중): in-flight 전사를 중단하고 폐기하되, 워커가 새로 떠 나머지 대기 작업을 이어 처리.
///
/// WhisperKit은 Task 취소를 인지(checkCancellation)하므로, 취소를 존중하는 mock으로 실제 경로를 흉내낸다.
private final class CancellableMockTranscriber: Transcriber, @unchecked Sendable {
    /// 취소를 존중하는 긴 처리 흉내(WhisperKit처럼 중간중간 취소 확인).
    func transcribe(_ audio: URL, language: String) async throws -> [TranscriptSegment] {
        for _ in 0..<40 {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 5_000_000)   // 5ms × 40 = 200ms
        }
        return [TranscriptSegment(start: 0, end: 1, text: audio.lastPathComponent, isFinal: true)]
    }
}

/// 항상 빈 결과를 반환해 failJob('전사 결과가 비어 있습니다') 경로를 태운다.
private final class EmptyResultMockTranscriber: Transcriber, @unchecked Sendable {
    func transcribe(_ audio: URL, language: String) async throws -> [TranscriptSegment] { [] }
}

private func makeTempFiles(_ prefix: String, _ n: Int) -> [URL] {
    let dir = FileManager.default.temporaryDirectory
    let urls = (0..<n).map { dir.appendingPathComponent("\(prefix)\($0).wav") }
    for u in urls { FileManager.default.createFile(atPath: u.path, contents: Data([0])) }
    return urls
}

@MainActor
private func makeState(_ mock: CancellableMockTranscriber) -> AppState {
    let store = RecordingStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("echo-cancel-\(UUID())"))
    return AppState(batchTranscriber: mock, livePreview: nil, store: store)
}

/// 모두 취소 → 큐가 비고 녹음이 생기지 않는다.
@MainActor
@Test func cancelAllClearsQueueAndProducesNoRecording() async throws {
    let urls = makeTempFiles("ca", 4)
    let state = makeState(CancellableMockTranscriber())

    state.enqueueFiles(urls)
    try? await Task.sleep(nanoseconds: 30_000_000)   // 첫 작업이 처리 중이 되도록
    state.cancelAllJobs()

    // 진행 중이던 작업이 CancellationError로 풀리고 폐기될 때까지 대기.
    for _ in 0..<150 {
        if state.jobs.isEmpty && state.activeJobCount == 0 { break }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    #expect(state.activeJobCount == 0)
    #expect(state.jobs.isEmpty)
    #expect(state.recordings.isEmpty)   // 어떤 결과도 저장되지 않음
}

/// 진행 중 작업 1건 취소 → 그 작업은 폐기되고, 나머지 대기 작업은 정상 처리된다(워커 복구).
@MainActor
@Test func cancelInFlightDiscardsButWorkerContinues() async throws {
    let urls = makeTempFiles("ci", 3)   // ci0, ci1, ci2
    let state = makeState(CancellableMockTranscriber())

    state.enqueueFiles(urls)
    try? await Task.sleep(nanoseconds: 40_000_000)   // ci0가 처리 중이 되도록

    // 처리 중(또는 첫) 작업을 취소.
    if let processing = state.jobs.first(where: { $0.status == .processing }) ?? state.jobs.first {
        state.cancelJob(processing.id)
    }

    // 나머지 두 작업이 완료될 때까지 대기.
    for _ in 0..<200 {
        if state.jobs.isEmpty && state.recordings.count == 2 { break }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    #expect(state.recordings.count == 2)             // 취소된 1건 빼고 2건 완료
    #expect(state.jobs.isEmpty)                      // 큐 비워짐
    #expect(!state.recordings.contains { $0.title == "ci0" })   // 취소된 작업은 저장 안 됨
}

/// 대기 중 작업 취소는 즉시 큐에서 제거된다.
@MainActor
@Test func cancelPendingRemovesImmediately() async throws {
    let urls = makeTempFiles("cp", 3)
    let state = makeState(CancellableMockTranscriber())

    state.enqueueFiles(urls)
    // enqueue 직후 마지막 작업은 대기 상태.
    let before = state.jobs.count
    guard let lastPending = state.jobs.last(where: { $0.status == .pending }) else {
        Issue.record("대기 작업이 없음")
        return
    }
    state.cancelJob(lastPending.id)

    #expect(state.jobs.count == before - 1)
    #expect(!state.jobs.contains { $0.id == lastPending.id })

    // 정리: 나머지 취소.
    state.cancelAllJobs()
    for _ in 0..<150 {
        if state.jobs.isEmpty && state.activeJobCount == 0 { break }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

/// 빈 전사 결과로 실패한 작업은 큐에 남아야 한다(activeJobCount=0이지만 hasJobs=true).
/// 모달 자동닫힘이 activeJobCount가 아니라 jobs.isEmpty 기준이어야 실패가 숨겨지지 않는다는
/// View 수정의 전제 불변식을 잠근다.
@MainActor
@Test func failedJobStaysInQueueAfterActiveCountZero() async throws {
    let urls = makeTempFiles("fj", 1)
    let store = RecordingStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("echo-cancel-\(UUID())"))
    let state = AppState(batchTranscriber: EmptyResultMockTranscriber(), livePreview: nil, store: store)

    state.enqueueFiles(urls)
    for _ in 0..<100 {
        if state.activeJobCount == 0 && !state.jobs.isEmpty { break }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    #expect(state.activeJobCount == 0)   // 더 이상 활성(대기/진행) 작업 없음
    #expect(!state.jobs.isEmpty)         // 그러나 실패 작업은 큐에 남음(모달이 숨기면 안 됨)
    #expect(state.hasJobs)
    #expect(state.jobs.contains { if case .failed = $0.status { return true }; return false })
    #expect(state.recordings.isEmpty)    // 빈 결과는 저장하지 않음
}
