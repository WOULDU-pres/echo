import Testing
import Foundation
@testable import Echo

/// 실제 large-v3(ko) 전사 통합 테스트.
/// 미리 받은 로컬 모델 폴더 + 한국어 클립이 있을 때만 활성화된다(헤드리스/CI 안전).
/// 빠른 증명을 위해 60초 클립을 쓴다. 전체 파일은 비례해서 더 걸린다.
private let kModelFolder = "/Users/hwjoo/Desktop/workspace/tools/echo/Models/whisperkit-coreml/openai_whisper-large-v3-v20240930"
private let kClip = "/Users/hwjoo/Desktop/workspace/tools/echo/test-assets/sample_ko_60s.wav"

private func fixturesPresent() -> Bool {
    let fm = FileManager.default
    return fm.fileExists(atPath: kModelFolder) && fm.fileExists(atPath: kClip)
}

@Suite(.enabled(if: fixturesPresent()))
struct TranscriptionIntegrationTests {

    @Test func transcribesKoreanClipWithLocalLargeV3() async throws {
        let transcriber = WhisperKitBatchTranscriber(modelFolder: kModelFolder)
        let segments = try await transcriber.transcribe(
            URL(fileURLWithPath: kClip), language: "ko"
        )
        let text = segments.map(\.text).joined(separator: " ")
        print("=== large-v3 KO transcript (60s clip) ===")
        print(text)
        print("=== end (\(segments.count) segments) ===")

        #expect(!segments.isEmpty)
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        // 한글이 한 글자 이상 포함되어야 한다(언어 강제가 동작했는지 약식 확인).
        #expect(text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) })
    }
}
