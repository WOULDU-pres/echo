import SwiftUI

/// 디자인 토큰. 사용자 제공 목업(design/realtime-structured.html, realtime-zen.html)에 충실.
/// 파란 강조(#0058BC) + REC 빨강 + 화자 보조색을 고정해 목업의 룩을 재현한다.
/// (가짜 데이터·클라우드 라벨·메타패널은 의도적으로 제외 — docs/DESIGN.md)
enum Theme {

    // MARK: Colors — 목업 팔레트 고정
    enum Palette {
        static let primary = Color(hex: 0x0058BC)          // 브랜드 파랑(강조/활성/화자 "나")
        static let primaryContainer = Color(hex: 0x0070EB)
        static let secondary = Color(hex: 0xBC000A)        // REC 빨강 / Stop
        static let tertiary = Color(hex: 0x4C4ACA)         // 화자 "상대" / 보조
        static let error = Color(hex: 0xBA1A1A)

        static let background = Color(hex: 0xFAF9FE)
        static let surfaceLowest = Color(hex: 0xFFFFFF)
        static let surfaceLow = Color(hex: 0xF4F3F8)
        static let surfaceContainer = Color(hex: 0xEEEDF3)

        static let onSurface = Color(hex: 0x1A1B1F)
        static let onSurfaceVariant = Color(hex: 0x414755)
        static let outline = Color(hex: 0x717786)
        static let outlineVariant = Color(hex: 0xC1C6D7)

        /// 화자 구분: 나=파랑, 상대=보라(목업 SPEAKER 색).
        static let speakerMe = primary
        static let speakerOther = tertiary

        /// 시스템 트랙 화자 인덱스별 색(화자 구분 켰을 때). 보라 계열 변주 + 보조색.
        private static let speakerPalette: [Color] = [
            tertiary,               // 상대1 보라
            Color(hex: 0x2E7D32),   // 상대2 초록
            Color(hex: 0xB8860B),   // 상대3 황금
            Color(hex: 0x00838F),   // 상대4 청록
            Color(hex: 0x6A1B9A),   // 상대5 자주
        ]
        static func speakerColor(for index: Int?) -> Color {
            guard let i = index else { return speakerOther }
            return speakerPalette[i % speakerPalette.count]
        }
    }

    // MARK: Layout
    enum Layout {
        static let contentWidth: CGFloat = 1000   // 본문 전사 스트림 최대 폭(목업 max-w-[1000px])
        static let timeGutter: CGFloat = 92        // 좌측 타임스탬프+화자칩 칸
    }

    // MARK: Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let base: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: Radius
    enum Radius {
        static let base: CGFloat = 4
        static let lg: CGFloat = 8
        static let xl: CGFloat = 12
        static let full: CGFloat = 9999
    }

    // MARK: Typography — 목업 스케일
    enum Font {
        static let displayLg = SwiftUI.Font.system(size: 44, weight: .bold)        // Zen 대형(48→44, 한글 안전)
        static let headlineMd = SwiftUI.Font.system(size: 24, weight: .bold)
        static let titleSm = SwiftUI.Font.system(size: 18, weight: .semibold)
        static let bodyReading = SwiftUI.Font.system(size: 20, weight: .regular)
        static let bodyUI = SwiftUI.Font.system(size: 13, weight: .regular)
        static let labelCaps = SwiftUI.Font.system(size: 10, weight: .semibold)
        static let speakerCaps = SwiftUI.Font.system(size: 9, weight: .bold)        // 화자칩
        static let monoData = SwiftUI.Font.system(size: 12, weight: .regular).monospaced()
    }
}

extension Color {
    /// 0xRRGGBB 정수 리터럴로 색 생성.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
