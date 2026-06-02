import Foundation

/// 녹음 1회에 포함할 입력 소스 구성.
///
/// 규칙:
/// - `screen == false`: 시스템 사운드는 Core Audio 프로세스 탭으로, 마이크는 AVAudioEngine로 개별 캡처.
/// - `screen == true`: ScreenCaptureKit `SCStream`(captureMicrophone: true)이 영상 + 시스템오디오 + 마이크를
///   한 스트림에서 공급하므로, 개별 마이크/시스템 캡처는 사용하지 않는다.
struct CaptureSource: Equatable, Codable, Sendable {
    var microphone: Bool = true
    var systemAudio: Bool = true
    /// 화면 영상 녹화(선택). 켜지면 캡처 경로가 ScreenCaptureKit으로 전환된다.
    var screen: Bool = false

    /// 마이크/시스템을 별도 트랙으로 저장할지 여부(화자 "나/상대" 구분 가능). 기본 true.
    var separateTracks: Bool = true

    var usesScreenCaptureKit: Bool { screen }
    var hasAnyAudio: Bool { microphone || systemAudio }

    static let micOnly = CaptureSource(microphone: true, systemAudio: false, screen: false)
    static let systemOnly = CaptureSource(microphone: false, systemAudio: true, screen: false)
    static let meeting = CaptureSource(microphone: true, systemAudio: true, screen: false)
    static let meetingWithScreen = CaptureSource(microphone: true, systemAudio: true, screen: true)
}

/// 오디오 트랙의 출처. 분리 트랙 전사 시 화자 귀속("나" vs "상대")에 사용.
enum AudioChannel: String, Codable, Sendable {
    case microphone   // "나"
    case system       // "상대"(시스템에서 재생되는 소리)
    case mixed        // 단일 믹스 트랙
}
