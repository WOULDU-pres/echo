import Foundation

/// 디스크에 저장되는 녹음 1건. 트랙 파일 + 최종(large-v3) 전사 + 메타데이터.
struct Recording: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval

    var source: CaptureSource
    /// 채널별 오디오 트랙 파일(분리 트랙). 화면 녹화 시 비디오 URL도 포함.
    var audioTracks: [AudioChannel: URL]
    var videoURL: URL?

    /// 최종(권위) 전사. 항상 full large-v3 (non-turbo) 일괄 결과.
    var segments: [TranscriptSegment]
    var language: String
    /// 최종 전사에 사용한 모델 식별자. 예: "openai_whisper-large-v3-v20240930".
    var transcriptionModel: String?
    /// 통화/회의 정리본(echo-fix 스킬이 생성). nil이면 정리본 없음 — UI는 전사만 표시한다.
    var summary: CallSummary?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        source: CaptureSource = .meeting,
        audioTracks: [AudioChannel: URL] = [:],
        videoURL: URL? = nil,
        segments: [TranscriptSegment] = [],
        language: String = "ko",
        transcriptionModel: String? = nil,
        summary: CallSummary? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.source = source
        self.audioTracks = audioTracks
        self.videoURL = videoURL
        self.segments = segments
        self.language = language
        self.transcriptionModel = transcriptionModel
        self.summary = summary
    }

    var plainText: String {
        segments.map(\.text).joined(separator: "\n")
    }
}

/// 통화/회의 한 건의 정리본. echo-fix 스킬이 전사 교정 후 생성해 `recordings.json` 에
/// 함께 기록한다. 앱은 이 값이 있을 때만 정리본 탭을 노출한다(없으면 전사만).
struct CallSummary: Codable, Sendable, Equatable {
    /// 전체 맥락·흐름 요약.
    var overview: String
    /// 시간순으로 오간 대화의 핵심 순간들.
    var timeline: [SummaryMoment]
    /// 결론.
    var conclusion: String
    /// 생성에 쓰인 모델 식별자(메모용, 선택).
    var model: String?

    init(overview: String, timeline: [SummaryMoment], conclusion: String, model: String? = nil) {
        self.overview = overview
        self.timeline = timeline
        self.conclusion = conclusion
        self.model = model
    }
}

/// 정리본 타임라인의 한 순간. `at` 은 녹음 시작 기준 초(재생 seek 좌표와 동일).
struct SummaryMoment: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    /// 녹음 시작 기준 시각(초). 클릭하면 이 위치로 재생을 이동한다.
    var at: TimeInterval
    /// 그 시점에 오간 내용 한 줄.
    var text: String

    init(id: UUID = UUID(), at: TimeInterval, text: String) {
        self.id = id
        self.at = at
        self.text = text
    }

    private enum CodingKeys: String, CodingKey { case id, at, text }

    /// 스킬이 쓰는 JSON 은 `{at, text}` 만 담아도 되도록 `id` 디코드를 관대하게 처리한다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.at = try c.decode(TimeInterval.self, forKey: .at)
        self.text = try c.decode(String.self, forKey: .text)
    }

    /// 시:분:초 표시(전사 행 타임코드와 동일 형식).
    var timecode: String {
        let t = Int(at)
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
}
