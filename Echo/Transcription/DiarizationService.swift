import Foundation
import AVFoundation

#if canImport(FluidAudio)
import FluidAudio
#endif

/// 화자 구분(diarization) 서비스 — FluidAudio(pyannote CoreML, 온디바이스/ANE).
/// 오디오 파일 → 16kHz 모노 Float → 화자 발화 스팬 `[SpeakerSpan]`.
/// 전사와 마찬가지로 **직렬로** 호출해야 한다(AppState 워커가 보장; ANE 경합 방지).
final class DiarizationService: @unchecked Sendable {

    #if canImport(FluidAudio)
    // AppState 직렬 워커에서만 호출되므로 동시 접근이 없다(잠금 불필요).
    private var manager: DiarizerManager?
    /// 캐시된 매니저의 클러스터링 임계값. 바뀌면 매니저만 새 config로 재생성한다.
    private var cachedThreshold: Float?
    /// 로드한 CoreML 모델(1회). 임계값이 바뀌어도 재로딩하지 않고 재사용한다.
    private var models: DiarizerModels?

    /// 모델 1회 로드(첫 실행 시 ~100MB 다운로드 → 이후 오프라인). 임계값이 바뀌면 매니저만 재생성하고
    /// 모델은 재사용하므로 CoreML 재로딩 비용이 없다. 실패 시 throw.
    /// clusteringThreshold↑ = 화자 적게(비슷한 목소리를 더 합침), ↓ = 화자 많이.
    private func ensureManager(threshold: Float) async throws -> DiarizerManager {
        if let manager, cachedThreshold == threshold { return manager }
        let models = try await loadModels()
        let m = DiarizerManager(config: DiarizerConfig(clusteringThreshold: threshold))
        m.initialize(models: models)
        manager = m
        cachedThreshold = threshold
        return m
    }

    /// CoreML 모델을 1회 로드해 캐시(이후 재사용 — 슬라이더로 임계값을 바꿔도 재로딩 안 함).
    private func loadModels() async throws -> DiarizerModels {
        if let models { return models }
        let loaded = try await DiarizerModels.downloadIfNeeded()
        models = loaded
        return loaded
    }

    /// 오디오 파일을 화자 스팬으로 분리. 16kHz 모노 Float로 변환 후 diarize.
    /// `threshold`(클러스터링 임계값)로 분리 민감도 조절. 기본 0.8(FluidAudio 기본 0.7보다 덜 쪼갬).
    func diarize(_ url: URL, threshold: Float = 0.8) async throws -> [SpeakerSpan] {
        let samples = try Self.loadMono16k(url)
        guard samples.count > 16_000 else { return [] }   // 1초 미만이면 스킵
        let manager = try await ensureManager(threshold: threshold)
        let result = try manager.performCompleteDiarization(samples, sampleRate: 16_000)
        return result.segments.map {
            SpeakerSpan(speakerKey: $0.speakerId,
                        start: TimeInterval($0.startTimeSeconds),
                        end: TimeInterval($0.endTimeSeconds))
        }
    }

    /// 오디오 파일 → 16kHz 모노 Float 배열(AVAudioConverter, 백그라운드).
    private static func loadMono16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                   channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else { return [] }
        let cap = AVAudioFrameCount(target.sampleRate * 4)
        var out: [Float] = []
        var done = false
        while !done {
            guard let buf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { break }
            var err: NSError?
            let status = converter.convert(to: buf, error: &err) { _, inStatus in
                let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: 8192)!
                do {
                    try file.read(into: inBuf)
                } catch { inStatus.pointee = .endOfStream; return nil }
                if inBuf.frameLength == 0 { inStatus.pointee = .endOfStream; return nil }
                inStatus.pointee = .haveData
                return inBuf
            }
            if let ch = buf.floatChannelData, buf.frameLength > 0 {
                out.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength)))
            }
            if status == .endOfStream || status == .error { done = true }
        }
        return out
    }
    #else
    func diarize(_ url: URL, threshold: Float = 0.8) async throws -> [SpeakerSpan] {
        throw TranscriptionError.engineUnavailable("FluidAudio 미통합")
    }
    #endif
}
