import Foundation

/// 화자 한 명의 발화 구간(diarizer 출력). speakerKey는 diarizer의 문자열 화자 ID.
struct SpeakerSpan: Equatable, Sendable {
    let speakerKey: String
    let start: TimeInterval
    let end: TimeInterval
}

/// diarizer 화자 스팬을 전사 세그먼트에 할당하는 순수 로직(테스트 가능).
/// 각 세그먼트에 시간 overlap이 가장 큰 화자를 매기고, 화자 ID는 등장 순서대로 0,1,2…로 정규화.
enum SpeakerAssigner {
    static func assign(segments: [TranscriptSegment], spans: [SpeakerSpan]) -> [TranscriptSegment] {
        guard !spans.isEmpty else { return segments }

        // 등장 순서 기준 안정적 인덱스(speaker_2 → 0, speaker_7 → 1 …).
        var keyToIndex: [String: Int] = [:]
        for span in spans where keyToIndex[span.speakerKey] == nil {
            keyToIndex[span.speakerKey] = keyToIndex.count
        }

        return segments.map { seg in
            // overlap이 가장 큰 화자 선택. 동률이면 더 작은 인덱스(먼저 등장) 유지.
            var best: (index: Int, overlap: TimeInterval)? = nil
            for span in spans {
                let ov = min(seg.end, span.end) - max(seg.start, span.start)
                guard ov > 0, let idx = keyToIndex[span.speakerKey] else { continue }
                if let b = best {
                    if ov > b.overlap || (ov == b.overlap && idx < b.index) {
                        best = (idx, ov)
                    }
                } else {
                    best = (idx, ov)
                }
            }
            var copy = seg
            copy.speakerIndex = best?.index
            return copy
        }
    }
}
