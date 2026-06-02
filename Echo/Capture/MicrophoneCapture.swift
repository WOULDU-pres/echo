import Foundation
import AVFoundation

/// 마이크 캡처 — `AVAudioEngine.inputNode.installTap`.
/// 실시간 PCM 버퍼를 그대로 onBuffer로 전달(변환은 호출측 백그라운드에서).
final class MicrophoneCapture: AudioSource {
    var onBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    private let engine = AVAudioEngine()

    func start() async throws {
        // 마이크 권한 요청 — 미결정 시 1회 프롬프트, 거부면 친절한 에러.
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            throw TranscriptionError.engineUnavailable("마이크 권한이 거부되었습니다")
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // 주의: Voice-Processing IO를 켜면 입력이 9채널로 바뀌고 시스템오디오를 자동 더킹함 → 필요 없으면 끄기.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, when in
            self?.onBuffer?(buffer, when)   // 실시간 스레드: 복사/전달만
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
