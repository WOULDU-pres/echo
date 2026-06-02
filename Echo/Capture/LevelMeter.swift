import Foundation

/// 오디오 레벨(RMS) 계산 순수 유틸. UI 레벨 미터 스트립용.
enum LevelMeter {
    /// Root-mean-square of samples in [-1, 1].
    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// 0...1 미터 값(약간의 헤드룸 게인). UI 레벨 스트립용.
    static func normalized(_ samples: [Float], gain: Float = 1.4) -> Float {
        min(1, rms(samples) * gain)
    }
}
