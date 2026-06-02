import Foundation
import AVFoundation

/// 일괄(batch) 전사기. 정지 후 오디오 파일 전체를 전사한다.
/// Echo의 **권위 전사**는 항상 이 경로(full large-v3, non-turbo)다.
protocol Transcriber: Sendable {
    /// - Parameters:
    ///   - audio: 전사할 오디오 파일 URL.
    ///   - language: 강제 언어 코드(기본 "ko"). 무음 환각 방지를 위해 항상 지정.
    /// - Returns: 확정 세그먼트(isFinal = true).
    func transcribe(_ audio: URL, language: String) async throws -> [TranscriptSegment]

    /// 진행률(0...1)을 보고하며 전사. `onProgress`는 백그라운드에서 호출될 수 있다(@Sendable).
    /// 기본 구현은 진행률을 무시하고 위 메서드로 위임하므로, 진행률을 지원하지 않는 구현(테스트 목 등)은
    /// 위 메서드만 구현하면 된다.
    func transcribe(_ audio: URL, language: String,
                    onProgress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment]
}

extension Transcriber {
    func transcribe(_ audio: URL, language: String,
                    onProgress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment] {
        try await transcribe(audio, language: language)
    }
}

/// 라이브(streaming) 전사기. 녹음 중 화면 미리보기 전용.
/// 결과는 **비저장·비권위**(isFinal = false). 정지 시 일괄 결과로 교체된다.
///
/// 입력은 `SendableAudioBuffer`(고유 소유 사본을 감싼 래퍼) 스트림이다. `AVAudioPCMBuffer` 는
/// non-Sendable 이라 SpeechAnalyzer actor 경계를 넘길 수 없으므로, `RecordingCoordinator`
/// 가 만들어 주는 사본 래퍼를 그대로 소비한다(Swift 6 동시성 안전).
protocol LiveTranscriber: Sendable {
    /// 오디오 버퍼 스트림을 받아 부분 전사 세그먼트를 흘려보낸다.
    func stream(
        _ buffers: AsyncStream<SendableAudioBuffer>,
        language: String
    ) -> AsyncStream<TranscriptSegment>

    /// ko_KR 등 언어 에셋이 준비됐는지(없으면 1회 다운로드 필요).
    func ensureLanguageAsset(_ language: String) async throws
}

enum TranscriptionError: LocalizedError {
    case engineUnavailable(String)
    case modelMissing(String)
    case audioReadFailed(URL)

    var errorDescription: String? {
        switch self {
        case .engineUnavailable(let s): return "전사 엔진을 사용할 수 없습니다: \(s)"
        case .modelMissing(let s): return "모델을 찾을 수 없습니다: \(s)"
        case .audioReadFailed(let u): return "오디오를 읽지 못했습니다: \(u.lastPathComponent)"
        }
    }
}
