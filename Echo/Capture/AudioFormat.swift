import Foundation
import AVFoundation

/// 오디오 포맷 유틸. Whisper 입력 규격(16kHz 모노 float32, [-1,1])으로 변환.
///
/// ⚠️ 중요: 변환은 **실시간 오디오 스레드(IOProc/installTap 콜백) 밖**에서 호출할 것.
/// `AVAudioConverter`가 실시간 스레드에서 EXC_BAD_ACCESS로 크래시한 사례가 있어,
/// 여기서는 의존성 없는 **수동 채널0 다운믹스 + 선형보간 리샘플**을 기본 제공한다.
enum AudioFormat {
    static let whisperSampleRate: Double = 16_000

    /// 임의 PCM 버퍼 → 16kHz 모노 float32 샘플 배열. 백그라운드 큐에서 호출.
    static func toWhisperSamples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let mono = downmixToMono(buffer) else { return [] }
        let srcRate = buffer.format.sampleRate
        guard srcRate > 0 else { return [] }
        if abs(srcRate - whisperSampleRate) < 1 { return mono }
        return resampleLinear(mono, from: srcRate, to: whisperSampleRate)
    }

    /// 다채널 → 모노(채널 평균). float32 가정; 필요 시 int16 경로 추가.
    private static func downmixToMono(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let ch = buffer.floatChannelData else { return nil }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return [] }
        if channels == 1 { return Array(UnsafeBufferPointer(start: ch[0], count: frames)) }
        var out = [Float](repeating: 0, count: frames)
        for c in 0..<channels {
            let p = ch[c]
            for i in 0..<frames { out[i] += p[i] }
        }
        let inv = 1.0 / Float(channels)
        for i in 0..<frames { out[i] *= inv }
        return out
    }

    /// 선형보간 리샘플(품질 충분, 의존성 0). 고품질 필요 시 vDSP/AVAudioConverter(백그라운드)로 교체.
    private static func resampleLinear(_ input: [Float], from src: Double, to dst: Double) -> [Float] {
        guard !input.isEmpty else { return [] }
        let ratio = dst / src
        let outCount = Int(Double(input.count) * ratio)
        guard outCount > 0 else { return [] }
        var out = [Float](repeating: 0, count: outCount)
        let step = src / dst
        var pos = 0.0
        for i in 0..<outCount {
            let i0 = Int(pos)
            let frac = Float(pos - Double(i0))
            let a = input[i0]
            let b = i0 + 1 < input.count ? input[i0 + 1] : a
            out[i] = a + (b - a) * frac
            pos += step
        }
        return out
    }
}
