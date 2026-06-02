import Testing
import AVFoundation
@testable import Echo

@Test func trackWriterPersistsFrames() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tw-\(UUID()).caf")
    let fmt = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1600)!
    buf.frameLength = 1600
    for i in 0..<1600 { buf.floatChannelData![0][Int(i)] = 0 }

    let writer = TrackWriter(url: url)
    writer.append(buf)
    let out = writer.finish()

    let read = try AVAudioFile(forReading: out)
    #expect(read.length == 1600)
    try? FileManager.default.removeItem(at: url)
}

@Test func trackWriterAccumulatesMultipleAppends() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tw-\(UUID()).caf")
    let fmt = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let writer = TrackWriter(url: url)

    for _ in 0..<3 {
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 800)!
        buf.frameLength = 800
        for i in 0..<800 { buf.floatChannelData![0][Int(i)] = 0.25 }
        writer.append(buf)
    }
    let out = writer.finish()

    let read = try AVAudioFile(forReading: out)
    #expect(read.length == 2400)   // 3 × 800
    try? FileManager.default.removeItem(at: url)
}
