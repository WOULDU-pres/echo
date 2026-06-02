import Foundation
import AVFoundation

/// 단일 오디오 입력 소스의 공통 인터페이스. 콜백은 실시간 스레드에서 호출되므로
/// 버퍼를 복사해 빠르게 빠져나올 것(할당/변환/락 금지).
protocol AudioSource: AnyObject {
    var onBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)? { get set }
    func start() async throws
    func stop()
}

/// `AVAudioPCMBuffer`(non-Sendable)를 격리 경계 너머로 안전하게 전달하기 위한 래퍼.
/// 항상 **새로 할당된 고유 소유 사본**(`RecordingCoordinator.copyBuffer`)만 담으므로
/// 별칭이 없어 `@unchecked Sendable` 이 안전하다. Phase 3 라이브 전사기가 소비한다.
struct SendableAudioBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// 녹음 전체를 조율: 소스 구성·시작·정지, 채널별 트랙 파일 기록, 라이브 버퍼 분기.
///
/// - `source.screen == false`: `MicrophoneCapture` + `SystemAudioCapture`(분리 트랙).
/// - `source.screen == true`: `ScreenCapture`(SCStream)가 영상+시스템+마이크를 한 스트림에서 공급.
///
/// `@unchecked Sendable`: `@MainActor AppState` 가 소유하지만 `start`/`stop` 는 nonisolated
/// async 라 액터 경계를 넘는다. 가변 상태(`sources`/`writers`/`liveContinuation`)는 메인 액터
/// 호출자(AppState)가 `start`/`stop` 를 직렬로만 부르고, 실시간 콜백은 `TrackWriter`(내부 직렬 큐)·
/// `liveContinuation.yield`(스레드 세이프)·`onMicLevel`(@Sendable, 백그라운드 큐) 로만 위임하므로
/// 데이터 레이스가 없다. 따라서 안전.
final class RecordingCoordinator: @unchecked Sendable {

    private var sources: [AudioChannel: AudioSource] = [:]
    private var screen: ScreenCapture?
    private var writers: [AudioChannel: TrackWriter] = [:]

    /// 일시정지 게이트. true면 들어오는 버퍼를 파일/라이브로 흘리지 않고 버린다(캡처는 유지, teardown 없음).
    /// 실시간 콜백과 메인액터(pause/resume)에서 접근하나, Bool 토글이라 레이스는 경계에서
    /// 버퍼 한두 개를 더/덜 기록하는 무해한 수준이다(RT 스레드에 락을 두지 않는다).
    private var paused = false

    /// 캡처를 유지한 채 기록만 멈춘다(일시정지). 메인액터에서 호출.
    func pause() { paused = true }
    /// 기록 재개.
    func resume() { paused = false }

    /// 화면 녹화 시 SCRecordingOutput 이 기록하는 영상 파일 URL. stop() 후 AppState 가 읽는다.
    private(set) var videoURL: URL?

    /// 라이브 미리보기로 보낼 마이크(="나") 버퍼 스트림. Phase 3에서 LiveTranscriber에 연결.
    /// non-Sendable 버퍼를 `SendableAudioBuffer` 사본으로 감싸 전달한다.
    private(set) var liveBufferStream: AsyncStream<SendableAudioBuffer>?
    private var liveContinuation: AsyncStream<SendableAudioBuffer>.Continuation?

    /// 마이크 레벨(0...1) 콜백. **백그라운드 큐**에서 호출되므로 소비자(AppState)가
    /// `@MainActor` 로 hop 해야 한다. RMS 계산은 IO 스레드가 아닌 이 큐에서 수행.
    var onMicLevel: (@Sendable (Float) -> Void)?
    private let levelQueue = DispatchQueue(label: "echo.levelmeter", qos: .userInitiated)

    /// 새 녹음 세션용 디렉터리(Application Support/Echo/Recordings/<UUID>) 생성.
    /// 트랙 파일(mic.caf / system.caf)과 (Phase 4) 영상이 여기에 저장된다.
    static func newSessionDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Echo/Recordings", isDirectory: true)
        let dir = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start(source: CaptureSource, into directory: URL) async throws {
        paused = false
        let (stream, cont) = AsyncStream<SendableAudioBuffer>.makeStream()
        liveBufferStream = stream
        liveContinuation = cont

        if source.usesScreenCaptureKit {
            // 화면 녹화: ScreenCaptureKit 한 스트림이 영상 + 시스템오디오(.audio) + 마이크(.microphone)를
            // 분리 버퍼로 공급한다. 오디오는 비-화면 경로와 동일하게 채널별 트랙 + 라이브 스트림으로 분기.
            writers[.microphone] = TrackWriter(url: directory.appending(path: "mic.caf"))
            writers[.system] = TrackWriter(url: directory.appending(path: "system.caf"))
            let sc = ScreenCapture()
            sc.onMicrophone = { [weak self] buf, _ in self?.handleMicBuffer(buf) }
            sc.onSystemAudio = { [weak self] buf, _ in
                guard let self, !self.paused else { return }
                self.writers[.system]?.append(buf)
            }
            screen = sc
            try await sc.start(into: directory)
            videoURL = sc.videoURL
            return
        }

        if source.microphone {
            let mic = MicrophoneCapture()
            mic.onBuffer = { [weak self] buf, _ in self?.handleMicBuffer(buf) }
            sources[.microphone] = mic
            writers[.microphone] = TrackWriter(url: directory.appending(path: "mic.caf"))
        }
        if source.systemAudio {
            let sys = SystemAudioCapture()
            sys.onBuffer = { [weak self] buf, _ in
                guard let self, !self.paused else { return }
                self.writers[.system]?.append(buf)
            }
            sources[.system] = sys
            writers[.system] = TrackWriter(url: directory.appending(path: "system.caf"))
        }

        for src in sources.values { try await src.start() }
    }

    /// "나"(마이크) 버퍼 1개 처리: 트랙 기록 + 라이브 미리보기 + 레벨 미터.
    /// 마이크/화면 두 경로가 공유한다. 실시간 콜백(IO/샘플 스레드)에서 호출되므로
    /// 고유 소유 사본을 만들어 격리 경계 너머로 안전하게 전달한다(복사 후 빠르게 빠져나온다는 규칙).
    private func handleMicBuffer(_ buf: AVAudioPCMBuffer) {
        guard !paused else { return }   // 일시정지 중에는 기록/라이브/레벨 모두 건너뜀
        writers[.microphone]?.append(buf)
        guard let dup = RecordingCoordinator.copyBuffer(buf) else { return }
        liveContinuation?.yield(SendableAudioBuffer(buffer: dup))
        // 레벨(RMS) 계산은 IO 스레드가 아닌 백그라운드 큐에서. (Task 2.4 Step 1)
        if let onLevel = onMicLevel {
            let wrapped = SendableAudioBuffer(buffer: dup)
            levelQueue.async {
                let level = LevelMeter.normalized(AudioFormat.toWhisperSamples(wrapped.buffer))
                onLevel(level)
            }
        }
    }

    /// PCM 버퍼의 고유 소유 깊은 사본을 만든다. 실시간 콜백에서 라이브 스트림으로
    /// non-Sendable 버퍼를 안전하게 전달하기 위해 사용. float32/int16/int32 채널 데이터를 복사.
    /// 새로 할당된 사본은 어디에도 별칭되지 않으므로 `SendableAudioBuffer` 로 감싸 전달해도 안전하다.
    static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let dup = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else { return nil }
        dup.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        if let src = buffer.floatChannelData, let dst = dup.floatChannelData {
            for c in 0..<channels { memcpy(dst[c], src[c], frames * MemoryLayout<Float>.size) }
        } else if let src = buffer.int16ChannelData, let dst = dup.int16ChannelData {
            for c in 0..<channels { memcpy(dst[c], src[c], frames * MemoryLayout<Int16>.size) }
        } else if let src = buffer.int32ChannelData, let dst = dup.int32ChannelData {
            for c in 0..<channels { memcpy(dst[c], src[c], frames * MemoryLayout<Int32>.size) }
        }
        return dup
    }

    /// 정지 → 확정된 채널별 트랙 파일 URL 반환. (화면 영상 URL 은 `videoURL` 로 노출.)
    func stop() async -> [AudioChannel: URL] {
        await screen?.stop()
        for src in sources.values { src.stop() }
        liveContinuation?.finish()
        var urls: [AudioChannel: URL] = [:]
        for (ch, w) in writers { urls[ch] = w.finish() }
        sources.removeAll(); writers.removeAll(); screen = nil
        paused = false
        return urls
    }
}

/// 채널 1개를 파일로 기록. 실시간 콜백에서 들어온 버퍼를 전용 직렬 큐에서 AVAudioFile에 write.
/// 첫 write 시점에 버퍼 포맷으로 파일을 생성한다(런타임 ASBD가 48k 스테레오/16k 모노 등으로 다양하므로).
final class TrackWriter {
    let url: URL
    private var file: AVAudioFile?
    private let queue = DispatchQueue(label: "echo.trackwriter")

    init(url: URL) { self.url = url }

    func append(_ buffer: AVAudioPCMBuffer) {
        queue.sync {
            do {
                if file == nil {
                    file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
                }
                try file?.write(from: buffer)
            } catch {
                // 첫 write에서만 throw 가능(파일 생성/포맷). 로깅만 하고 계속 — 실시간 경로를 막지 않는다.
            }
        }
    }

    func finish() -> URL {
        queue.sync { file = nil }
        return url
    }
}
