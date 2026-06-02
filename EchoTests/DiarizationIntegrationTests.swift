import Testing
import Foundation
@testable import Echo

/// 실제 FluidAudio 화자 구분 통합 테스트(모델 다운로드 + diarize).
/// 한국어 클립이 있을 때만 실행. 첫 실행 시 ~100MB 모델 다운로드(네트워크).
private let kClip = "/Users/hwjoo/Desktop/workspace/tools/echo/test-assets/sample_ko_60s.wav"

@Suite(.enabled(if: FileManager.default.fileExists(atPath: kClip)))
struct DiarizationIntegrationTests {
    @Test func diarizesKoreanClipIntoSpeakers() async throws {
        let service = DiarizationService()
        let spans = try await service.diarize(URL(fileURLWithPath: kClip))
        let speakers = Set(spans.map(\.speakerKey))
        print("=== diarization: \(spans.count) spans, \(speakers.count) distinct speakers ===")
        for s in spans.prefix(8) {
            print(String(format: "  %@  %.2f–%.2f", s.speakerKey, s.start, s.end))
        }
        #expect(!spans.isEmpty)                 // 발화 구간을 찾음
        #expect(spans.allSatisfy { $0.end > $0.start })
    }
}
