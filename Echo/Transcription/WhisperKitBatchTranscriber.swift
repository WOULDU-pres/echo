import Foundation
import AVFoundation

#if canImport(WhisperKit)
import WhisperKit
#endif

/// 권위 전사기: full Whisper **large-v3 (non-turbo)** 일괄 패스.
/// turbo/distil은 사용하지 않는다(사용자 하드 제약: 최고 정확도 우선).
///
/// `Transcriber: Sendable` 을 만족해야 하지만 무거운 파이프라인(`WhisperKit`, non-Sendable)을
/// 지연 캐시한다. `WhisperKit.transcribe` 는 nonisolated 메서드라 actor 격리 안에서 receiver를
/// 보낼 수 없으므로(`sending` 에러), 캐시를 잠금으로 보호하는 `@unchecked Sendable` 클래스로 둔다.
/// `WhisperKit` 객체는 생성 후 불변으로 취급하며 잠금 밖에서 호출한다(트랜스크립션은 동시 안전).
final class WhisperKitBatchTranscriber: Transcriber, @unchecked Sendable {

    /// 한국어 개선판 체크포인트(2024-09 refresh). 핀한 리비전에 폴더 존재 확인 필요.
    static let modelIdentifier = "openai_whisper-large-v3-v20240930"

    /// 로컬 모델 폴더 오버라이드(미리 받은 CoreML 폴더). nil이면 기본 다운로드 동작(앱 기본값).
    /// 테스트/오프라인에서 재다운로드 없이 쓰려고 주입한다.
    private let modelFolderOverride: String?

    init(modelFolder: String? = nil) {
        self.modelFolderOverride = modelFolder
    }

    /// Whisper 특수 토큰(`<|startoftranscript|>`, `<|ko|>`, `<|5.86|>` 등)을 제거하고
    /// 공백을 정리한다. WhisperKit 의 `segment.text` 는 이 토큰들을 포함하므로 저장·표시 전 정리.
    static func cleanText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    #if canImport(WhisperKit)
    private let lock = NSLock()
    private var pipe: WhisperKit?

    private func cachedPipe() -> WhisperKit? {
        lock.lock(); defer { lock.unlock() }
        return pipe
    }

    private func cachePipe(_ p: WhisperKit) {
        lock.lock(); defer { lock.unlock() }
        if pipe == nil { pipe = p }
    }

    private func pipeline() async throws -> WhisperKit {
        if let p = cachedPipe() { return p }
        // TODO(Phase 0): WhisperKitConfig 로 large-v3-v20240930 로드.
        //   - model: Self.modelIdentifier
        //   - 첫 실행 시 CoreML 가중치 자동 다운로드(~3-4GB active, 16GB에 여유)
        //   - compute units: ANE/GPU 우선
        let config: WhisperKitConfig
        if let folder = modelFolderOverride {
            // 미리 받은 로컬 모델 사용(모델 재다운로드 없음). 토크나이저(~2MB)는 필요 시 받음.
            config = WhisperKitConfig(model: Self.modelIdentifier, modelFolder: folder)
        } else {
            config = WhisperKitConfig(model: Self.modelIdentifier)
        }
        let p = try await WhisperKit(config)
        cachePipe(p)
        // 잠금 동안 누군가 먼저 캐시했을 수 있으니 캐시된 인스턴스를 우선 반환(idempotent).
        return cachedPipe() ?? p
    }

    func transcribe(_ audio: URL, language: String) async throws -> [TranscriptSegment] {
        try await transcribe(audio, language: language, onProgress: { _ in })
    }

    func transcribe(_ audio: URL, language: String,
                    onProgress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment] {
        let p = try await pipeline()
        // DecodingOptions 확정(WhisperKit 0.18.0 swiftinterface 검증):
        //   - language = language("ko" 강제) + detectLanguage=false → 무음 구간에서 잘못된
        //     언어 자동검출/환각 방지.
        //   - task = .transcribe(번역 아님).
        //   - chunkingStrategy = .vad → 에너지 VAD로 무음 청크를 건너뛰어 환각 차단.
        //   - wordTimestamps=false, withoutTimestamps=false(세그먼트 시작/끝 시간 필요).
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            detectLanguage: false,
            chunkingStrategy: .vad
        )
        // 레이스 없는 진행률: WhisperKit이 segmentDiscoveryCallback으로 '발견된 세그먼트'를 값으로
        // 넘겨주므로(소유 사본), 공유 가변 Progress 객체를 다른(워커) 스레드에서 들여다보지 않는다.
        // 진행률 = 발견된 세그먼트의 최대 end / 오디오 전체 길이. 0.99로 캡(마무리·화자 구분 단계 여지).
        // 직렬 워커라 한 번에 하나의 transcribe만 이 콜백을 설정/사용한다.
        let duration = Self.audioDuration(audio)
        let lock = NSLock()
        nonisolated(unsafe) var maxEnd = 0.0   // lock으로 보호(콜백이 워커 스레드에서 동시 호출될 수 있음)
        if duration > 0 {
            p.segmentDiscoveryCallback = { segments in
                let m = segments.reduce(0.0) { max($0, Double($1.end)) }
                lock.lock(); let advanced = m > maxEnd; if advanced { maxEnd = m }; lock.unlock()
                if advanced { onProgress(min(m / duration, 0.99)) }
            }
        }
        defer { p.segmentDiscoveryCallback = nil }
        let results = try await p.transcribe(audioPath: audio.path, decodeOptions: options)
        return results
            .flatMap { $0.segments }
            .map { seg in
                TranscriptSegment(
                    start: TimeInterval(seg.start),
                    end: TimeInterval(seg.end),
                    text: Self.cleanText(seg.text),
                    channel: .mixed,
                    isFinal: true
                )
            }
            .filter { !$0.text.isEmpty }   // 토큰만 있던 빈 세그먼트 제거
    }

    /// 오디오 파일 길이(초). 진행률 분모용(실패 시 0 → 진행률 미보고).
    private static func audioDuration(_ url: URL) -> Double {
        guard let f = try? AVAudioFile(forReading: url), f.fileFormat.sampleRate > 0 else { return 0 }
        return Double(f.length) / f.fileFormat.sampleRate
    }
    #else
    // WhisperKit 패키지 추가 전 컴파일용 스텁.
    func transcribe(_ audio: URL, language: String) async throws -> [TranscriptSegment] {
        throw TranscriptionError.engineUnavailable("WhisperKit 패키지가 아직 추가되지 않았습니다 (docs/SETUP-XCODE.md §2)")
    }
    #endif
}
