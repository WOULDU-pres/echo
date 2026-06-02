import Foundation
import AVFoundation
import CoreMedia

#if canImport(Speech)
import Speech
#endif

/// 라이브 미리보기 전사기 — Apple **SpeechAnalyzer / SpeechTranscriber** (macOS 26).
///
/// 선택 이유: 네이티브 한국어(ko_KR), 온디바이스, 라이브 스트리밍용으로 설계됨, Whisper보다 훨씬 가벼움.
/// 결과는 **비저장·비권위**(isFinal=false). 정지 시 large-v3 일괄 결과가 덮어쓴다.
/// → 사용자 하드 제약("저장본은 항상 large-v3")을 위반하지 않는다.
///
/// First-gen API 검증(Xcode 26.5 / macOS 26.5 SDK swiftinterface 기준):
///   - `SpeechTranscriber(locale:transcriptionOptions:reportingOptions:attributeOptions:)`:
///     convenience init 존재. 인자는 `Set<...>` 이며 배열 리터럴(`[]`, `[.volatileResults]`,
///     `[.audioTimeRange]`)은 `Set` 의 `ExpressibleByArrayLiteral` 로 그대로 컴파일됨.
///   - `SpeechAnalyzer(modules:)`: convenience init 존재.
///   - `analyzer.start(inputSequence:)`: `AsyncSequence<AnalyzerInput>` 제네릭. `AsyncStream` OK.
///   - `AnalyzerInput(buffer:)`: 존재(`bufferStartTime` 기본값 없는 두 번째 init 도 있음).
///   - `transcriber.results`: `AsyncSequence<SpeechTranscriber.Result, Error>`.
///   - `SpeechTranscriber.Result`: `range: CMTimeRange`, `text: AttributedString`.
///     **`isFinal` 은 Result 자체가 아니라 `SpeechModuleResult` 프로토콜 익스텐션 멤버**다(존재).
///   - `AssetInventory.assetInstallationRequest(supporting:)` / `req.downloadAndInstall()`: 존재.
///   모든 심볼이 macOS 26 한정이므로 전 경로를 `#available(macOS 26, *)` 로 게이팅한다(타깃 15.0).
final class LivePreviewTranscriber: LiveTranscriber {

    #if canImport(Speech)

    func ensureLanguageAsset(_ language: String) async throws {
        guard #available(macOS 26, *) else {
            throw TranscriptionError.engineUnavailable("SpeechTranscriber는 macOS 26 이상이 필요합니다")
        }
        let locale = Locale(identifier: "ko-KR")
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            throw TranscriptionError.engineUnavailable("ko-KR 미지원")
        }
        let installed = await SpeechTranscriber.installedLocales
        if !installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: []
            )
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await req.downloadAndInstall()
            }
        }
    }

    func stream(
        _ buffers: AsyncStream<SendableAudioBuffer>,
        language: String
    ) -> AsyncStream<TranscriptSegment> {
        AsyncStream { continuation in
            guard #available(macOS 26, *) else {
                continuation.finish()
                return
            }
            let task = Task {
                do {
                    let locale = Locale(identifier: "ko-KR")
                    // 에셋이 실제 설치된 경우에만 analyzer를 시작한다. 미설치 상태로 시작하면
                    // SpeechRecognizerWorker.preRunRecognition() 에서 SIGTRAP(앱 크래시)이 난다.
                    let installed = await SpeechTranscriber.installedLocales
                    guard installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
                        continuation.finish()
                        return
                    }
                    let transcriber = SpeechTranscriber(
                        locale: locale,
                        transcriptionOptions: [],
                        reportingOptions: [.volatileResults],
                        attributeOptions: [.audioTimeRange]
                    )
                    let analyzer = SpeechAnalyzer(modules: [transcriber])

                    // 마이크 버퍼 → analyzer 입력 시퀀스.
                    let (inputSeq, inputCont) = AsyncStream<AnalyzerInput>.makeStream()
                    try await analyzer.start(inputSequence: inputSeq)

                    // 피더: SendableAudioBuffer 래퍼를 풀어 AnalyzerInput 으로 공급.
                    let feeder = Task {
                        for await wrapped in buffers {
                            inputCont.yield(AnalyzerInput(buffer: wrapped.buffer))
                        }
                        inputCont.finish()
                    }

                    // analyzer 결과 → TranscriptSegment.
                    // `result.range` 는 CMTimeRange(.audioTimeRange 옵션), `result.isFinal` 은
                    // SpeechModuleResult 익스텐션 멤버(볼라타일 결과는 false, 확정 시 true).
                    for try await result in transcriber.results {
                        let range = result.range
                        let seg = TranscriptSegment(
                            start: range.start.seconds,
                            end: range.end.seconds,
                            text: String(result.text.characters),
                            channel: .microphone,
                            isFinal: result.isFinal
                        )
                        continuation.yield(seg)
                    }
                    feeder.cancel()
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    #else
    func ensureLanguageAsset(_ language: String) async throws {
        throw TranscriptionError.engineUnavailable("Speech 프레임워크를 사용할 수 없습니다")
    }
    func stream(
        _ buffers: AsyncStream<SendableAudioBuffer>,
        language: String
    ) -> AsyncStream<TranscriptSegment> {
        AsyncStream { $0.finish() }
    }
    #endif
}
