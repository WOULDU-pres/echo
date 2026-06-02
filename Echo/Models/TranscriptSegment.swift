import Foundation

/// 전사 한 조각. 라이브 미리보기와 최종(large-v3) 결과 모두 이 타입을 사용한다.
struct TranscriptSegment: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    /// 녹음 시작 기준 시작/끝(초).
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    /// 어느 트랙에서 왔는지 → 화자 귀속.
    var channel: AudioChannel
    /// 확정 여부. 라이브 미리보기는 `false`(흐리게 표시), large-v3 일괄 결과는 `true`.
    var isFinal: Bool
    /// 화자 구분 결과(시스템 트랙에서 여러 화자 분리 시). nil이면 채널 기반 단일 화자.
    /// 시스템 채널에서 0,1,2… → "상대1, 상대2…". 마이크 채널은 항상 "나"(이 값 무시).
    var speakerIndex: Int?

    init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        channel: AudioChannel = .mixed,
        isFinal: Bool = false,
        speakerIndex: Int? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.channel = channel
        self.isFinal = isFinal
        self.speakerIndex = speakerIndex
    }

    /// "나 / 상대 / 상대N" 표시 레이블.
    var speakerLabel: String {
        switch channel {
        case .microphone: return "나"
        case .system: return speakerIndex.map { "상대\($0 + 1)" } ?? "상대"
        case .mixed: return speakerIndex.map { "화자\($0 + 1)" } ?? ""
        }
    }

    var timecode: String {
        let t = Int(start)
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
}
