import Foundation

/// 여러 채널(마이크/시스템)의 세그먼트를 하나의 타임라인으로 병합하는 순수 유틸.
enum TranscriptMerger {
    /// 여러 채널의 세그먼트를 시작 시각 기준으로 합친다. 동일 시작 시각은 입력 순서를 유지(안정 정렬).
    static func merge(_ groups: [[TranscriptSegment]]) -> [TranscriptSegment] {
        groups.flatMap { $0 }
            .enumerated()
            .sorted { a, b in
                a.element.start != b.element.start ? a.element.start < b.element.start : a.offset < b.offset
            }
            .map(\.element)
    }
}
