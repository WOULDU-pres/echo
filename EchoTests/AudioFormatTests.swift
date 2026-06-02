import Testing
import AVFoundation
@testable import Echo

private func buffer(_ samples: [[Float]], sampleRate: Double) -> AVAudioPCMBuffer {
    let channels = AVAudioChannelCount(samples.count)
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                               channels: channels, interleaved: false)!
    let frames = AVAudioFrameCount(samples[0].count)
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buf.frameLength = frames
    for c in 0..<samples.count {
        for i in 0..<samples[c].count { buf.floatChannelData![c][i] = samples[c][i] }
    }
    return buf
}

@Test func downmixesStereoToMonoAverage() {
    // 16kHz already → no resample, just downmix average of L/R.
    let buf = buffer([[0.0, 1.0], [1.0, 1.0]], sampleRate: 16_000)
    let out = AudioFormat.toWhisperSamples(buf)
    #expect(out.count == 2)
    #expect(abs(out[0] - 0.5) < 1e-6)   // (0+1)/2
    #expect(abs(out[1] - 1.0) < 1e-6)   // (1+1)/2
}

@Test func resamplesDownTo16k() {
    // 32kHz mono, 100 frames → ~50 frames at 16kHz.
    let mono = (0..<100).map { Float($0) / 100 }
    let out = AudioFormat.toWhisperSamples(buffer([mono], sampleRate: 32_000))
    #expect(out.count == 50)
    #expect(abs(out.first! - 0.0) < 1e-6)
}
