import Testing
import Foundation
@testable import Echo

private final class NoopTranscriber2: Transcriber, @unchecked Sendable {
    func transcribe(_ audio: URL, language: String) async throws -> [TranscriptSegment] { [] }
}

/// 손상된 목록 파일: load는 에러를 던지고 원본을 backupURL로 보존한다(조용한 손실 방지).
@Test func corruptFileIsBackedUpAndLoadThrows() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("echo-robust-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let fileURL = dir.appendingPathComponent("recordings.json")
    try Data("not valid json {".utf8).write(to: fileURL)

    let store = RecordingStore(directory: dir)
    var threw = false
    do { _ = try store.load() } catch { threw = true }
    #expect(threw)                                                   // 디코드 실패 → throw
    #expect(FileManager.default.fileExists(atPath: store.backupURL.path))   // 백업 생성
    let bak = try String(contentsOf: store.backupURL, encoding: .utf8)
    #expect(bak == "not valid json {")                              // 원본 그대로 보존
}

/// 손상 파일이 있으면 AppState는 빈 목록으로 시작하고 1회 경고를 세운다(전체 손실 대신).
@MainActor
@Test func appStateStartsEmptyWithWarningOnCorruptFile() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("echo-robust-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("{ broken".utf8).write(to: dir.appendingPathComponent("recordings.json"))

    let state = AppState(batchTranscriber: NoopTranscriber2(), livePreview: nil,
                         store: RecordingStore(directory: dir))
    #expect(state.recordings.isEmpty)
    #expect(state.loadWarning != nil)
}

/// 빈(0바이트) 파일은 손상이 아니라 정상 빈 목록으로 취급한다(백업/경고 없음).
@Test func emptyFileLoadsAsEmptyListWithoutBackup() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("echo-robust-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data().write(to: dir.appendingPathComponent("recordings.json"))

    let store = RecordingStore(directory: dir)
    let loaded = try store.load()
    #expect(loaded.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: store.backupURL.path))   // 백업하지 않음
}

/// 백업 위치에 쓸 수 없으면 load는 corrupt(backedUp: nil)을 던지고, AppState는 '백업 실패' 경고를 세운다.
@MainActor
@Test func backupFailureReportsNoBackup() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("echo-robust-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("broken{".utf8).write(to: dir.appendingPathComponent("recordings.json"))

    let store = RecordingStore(directory: dir)
    // backupURL 자리를 디렉터리로 점유해 atomic write 실패를 유도.
    try FileManager.default.createDirectory(at: store.backupURL, withIntermediateDirectories: true)

    var threwCorrupt = false
    var backupWasNil = false
    do {
        _ = try store.load()
    } catch let RecordingStore.LoadError.corrupt(backedUp) {
        threwCorrupt = true
        backupWasNil = (backedUp == nil)
    } catch { /* 다른 에러는 실패로 둠 */ }
    #expect(threwCorrupt)
    #expect(backupWasNil)

    let state = AppState(batchTranscriber: NoopTranscriber2(), livePreview: nil, store: store)
    #expect(state.recordings.isEmpty)
    #expect(state.loadWarning != nil)
}

/// 정상 파일은 그대로 로드되고 경고가 없다(회귀 가드).
@MainActor
@Test func appStateLoadsValidFileWithoutWarning() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("echo-robust-\(UUID())")
    let store = RecordingStore(directory: dir)
    try store.save([Recording(title: "ok",
                              segments: [TranscriptSegment(start: 0, end: 1, text: "hi", isFinal: true)])])

    let state = AppState(batchTranscriber: NoopTranscriber2(), livePreview: nil, store: store)
    #expect(state.recordings.count == 1)
    #expect(state.recordings.first?.title == "ok")
    #expect(state.loadWarning == nil)
}
