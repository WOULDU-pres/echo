import Foundation
import AVFoundation
import CoreMedia
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

/// 화면 녹화(선택) — **ScreenCaptureKit** `SCStream`.
/// 영상 + 시스템오디오(.audio) + 마이크(.microphone, macOS 15+ `captureMicrophone`)를
/// 한 스트림에서 분리 버퍼로 공급한다.
///
/// 파일 기록: macOS 15+ `SCRecordingOutput`(턴키, 영상+오디오 먹싱) 기본.
/// 코덱/비트레이트 제어 필요 시 AVAssetWriter(클럭 오프셋·정적프레임 길이 버그 직접 처리).
/// 팬리스 M4 Air: 1080p/30 H.264 권장(동시 전사와 발열 고려).
///
/// API 검증(MacOSX26.5.sdk ScreenCaptureKit Headers):
///   - `SCStreamConfiguration.captureMicrophone` / `.capturesAudio` / `.sampleRate` / `.channelCount`
///     모두 존재(captureMicrophone 은 macOS 15+).
///   - `SCContentFilter(display:excludingWindows:)` — `initWithDisplay:excludingWindows:` 매핑.
///   - `SCShareableContent.excludingDesktopWindows(_:onScreenWindowsOnly:)` async getter.
///   - `stream.addStreamOutput(_:type:sampleHandlerQueue:)` throws (BOOL+NSError**).
///   - `SCRecordingOutput(configuration:delegate:)` — **delegate 가 non-null** 이라 실제 객체를 넘긴다.
///   - `stream.addRecordingOutput(_:)` throws, macOS 15+.
///   - `SCStreamOutput` 프로토콜 메서드: `stream(_:didOutputSampleBuffer:of:)`.
final class ScreenCapture {
    var onSystemAudio: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    var onMicrophone: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    private(set) var videoURL: URL?

    /// 호출자가 미리 선택한 콘텐츠 필터(SCContentSharingPicker). nil 이면 메인 디스플레이 전체.
    private var presetFilter: Any?

    #if canImport(ScreenCaptureKit)
    private var stream: SCStream?
    private var audioOutput: AudioStreamOutput?
    private var micOutput: AudioStreamOutput?
    private var recordingOutput: SCRecordingOutput?
    private var recordingDelegate: RecordingOutputDelegate?
    private let sampleQueue = DispatchQueue(label: "echo.screencapture.samples", qos: .userInitiated)

    /// SCContentSharingPicker 등에서 만든 필터를 주입(Task 4.2). 기본은 메인 디스플레이.
    func setFilter(_ filter: SCContentFilter) { presetFilter = filter }
    #endif

    func start(into directory: URL) async throws {
        #if canImport(ScreenCaptureKit)
        // 1) 디스플레이/윈도우 조회(권한 프롬프트). 콜드 프롬프트 전 인라인 설명은 호출 측 UI가 담당.
        let filter: SCContentFilter
        if let preset = presetFilter as? SCContentFilter {
            filter = preset
        } else {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                throw TranscriptionError.engineUnavailable("디스플레이를 찾을 수 없습니다")
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        // 2) 스트림 구성. 팬리스 M4 Air: 1080p/30 으로 캡. 동시 전사 + 영상 인코딩은
        //    발열 스로틀을 유발하므로 더 높은 해상도/프레임레이트는 의도적으로 피한다.
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        if #available(macOS 15.0, *) {
            config.captureMicrophone = true        // 마이크를 같은 스트림에서 분리 채널로 수신
        }
        config.width = 1920
        config.height = 1080
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.sampleRate = 48_000
        config.channelCount = 2

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)

        // 3) 오디오/마이크 샘플 핸들러: CMSampleBuffer → AVAudioPCMBuffer 변환 후 콜백.
        let audioOut = AudioStreamOutput { [weak self] pcm, when in self?.onSystemAudio?(pcm, when) }
        try stream.addStreamOutput(audioOut, type: .audio, sampleHandlerQueue: sampleQueue)
        self.audioOutput = audioOut

        if #available(macOS 15.0, *) {
            let micOut = AudioStreamOutput { [weak self] pcm, when in self?.onMicrophone?(pcm, when) }
            try stream.addStreamOutput(micOut, type: .microphone, sampleHandlerQueue: sampleQueue)
            self.micOutput = micOut
        }

        // 4) 영상 파일 기록: macOS 15+ SCRecordingOutput(턴키 먹싱). delegate 는 non-null.
        if #available(macOS 15.0, *) {
            let url = directory.appendingPathComponent("screen.mov")
            let recCfg = SCRecordingOutputConfiguration()
            recCfg.outputURL = url
            recCfg.outputFileType = .mov
            recCfg.videoCodecType = .h264
            let delegate = RecordingOutputDelegate()
            let recOutput = SCRecordingOutput(configuration: recCfg, delegate: delegate)
            try stream.addRecordingOutput(recOutput)
            self.recordingOutput = recOutput
            self.recordingDelegate = delegate
            self.videoURL = url
        }

        try await stream.startCapture()
        self.stream = stream
        #else
        throw TranscriptionError.engineUnavailable("ScreenCaptureKit 사용 불가")
        #endif
    }

    func stop() async {
        #if canImport(ScreenCaptureKit)
        if let stream {
            if #available(macOS 15.0, *), let rec = recordingOutput {
                try? stream.removeRecordingOutput(rec)
            }
            try? await stream.stopCapture()
        }
        stream = nil
        audioOutput = nil
        micOutput = nil
        recordingOutput = nil
        recordingDelegate = nil
        #endif
    }
}

#if canImport(ScreenCaptureKit)
/// `.audio` / `.microphone` 샘플을 받아 `AVAudioPCMBuffer` 로 변환해 전달하는 stream output.
/// 콜백은 ScreenCaptureKit의 샘플 큐(백그라운드)에서 호출되므로, 소비자(RecordingCoordinator)는
/// 이를 받아 자체 직렬 큐(TrackWriter)·복사 후 라이브 스트림으로만 위임한다.
final class AudioStreamOutput: NSObject, SCStreamOutput {
    private let onPCM: (AVAudioPCMBuffer, AVAudioTime) -> Void

    init(onPCM: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) {
        self.onPCM = onPCM
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio || type == .microphone else { return }
        guard sampleBuffer.isValid,
              let pcm = ScreenCapture.pcmBuffer(from: sampleBuffer) else { return }
        let pts = sampleBuffer.presentationTimeStamp
        let when = AVAudioTime(sampleTime: AVAudioFramePosition(pts.value), atRate: pcm.format.sampleRate)
        onPCM(pcm, when)
    }
}

/// SCRecordingOutput 은 non-null delegate 를 요구한다. 라이프사이클 로깅용 최소 구현.
final class RecordingOutputDelegate: NSObject, SCRecordingOutputDelegate {
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {}
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {}
}

extension ScreenCapture {
    /// 오디오 `CMSampleBuffer` → 고유 소유 `AVAudioPCMBuffer`(float 또는 int) 변환.
    /// 포맷 설명(ASBD)에서 `AVAudioFormat` 을 만들고, retained AudioBufferList 를 복사한다.
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc) else { return nil }
        var streamDesc = asbd.pointee
        guard let format = AVAudioFormat(streamDescription: &streamDesc) else { return nil }

        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        pcm.frameLength = AVAudioFrameCount(frames)

        // CMSampleBuffer 의 오디오를 pcm.mutableAudioBufferList 로 직접 복사.
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: pcm.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return pcm
    }
}
#endif
