import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// 전사 내보내기 포맷.
enum TranscriptFormat: String, CaseIterable {
    case txt
    case markdown
    case srt

    /// 저장 시 사용할 파일 확장자. markdown 만 `md` 로 매핑.
    var fileExtension: String { self == .markdown ? "md" : rawValue }

    /// `.fileExporter` 가 요구하는 UTType. srt 는 등록된 UTI 가 없으므로 plainText 로 본다.
    var contentType: UTType {
        switch self {
        case .txt: return .plainText
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .srt: return .plainText
        }
    }
}

/// `.fileExporter` 용 텍스트 문서. 직렬화된 전사 문자열을 그대로 파일로 쓴다.
struct TranscriptDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String
    var contentType: UTType

    init(text: String, format: TranscriptFormat) {
        self.text = text
        self.contentType = format.contentType
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(decoding: data, as: UTF8.self)
        contentType = .plainText
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// 세그먼트 배열을 txt/md/srt 문자열로 직렬화하는 순수 유틸.
enum TranscriptExporter {
    static func export(_ segments: [TranscriptSegment], as format: TranscriptFormat) -> String {
        switch format {
        case .txt:
            return segments.map(\.text).joined(separator: "\n")
        case .markdown:
            return segments.map { seg in
                let speaker = seg.speakerLabel.isEmpty ? "" : " \(seg.speakerLabel)"
                return "**[\(seg.timecode)]\(speaker)**\n\n\(seg.text)"
            }.joined(separator: "\n\n")
        case .srt:
            let blocks = segments.enumerated().map { i, seg in
                "\(i + 1)\n\(srt(seg.start)) --> \(srt(seg.end))\n\(seg.text)"
            }
            return blocks.joined(separator: "\n\n") + "\n"
        }
    }

    /// SRT 타임코드: `HH:MM:SS,mmm` (밀리초까지).
    private static func srt(_ t: TimeInterval) -> String {
        let ms = Int((t * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d",
                      ms / 3_600_000, (ms % 3_600_000) / 60_000, (ms % 60_000) / 1000, ms % 1000)
    }
}
