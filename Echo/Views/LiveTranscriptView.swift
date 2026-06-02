import SwiftUI

/// 녹음 중 라이브 미리보기. 메뉴로 모드 A(Structured) ↔ 모드 B(Zen) 전환.
/// 데이터는 `AppState.liveSegments`(비저장, isFinal=false). 정지 시 large-v3 결과로 교체.
struct LiveTranscriptView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            // 비권위 미리보기 표식: 라이브 텍스트는 저장되지 않으며, 정지 후 large-v3가 최종본.
            HStack(spacing: Theme.Spacing.base) {
                Label("실시간 미리보기 · 최종본은 정지 후 large-v3", systemImage: "eye")
                    .font(Theme.Font.labelCaps)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.onSurfaceVariant)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.base)

            // 모드 전환 메뉴
            Picker("뷰", selection: $state.liveViewMode) {
                ForEach(LiveViewMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)
            .padding(Theme.Spacing.md)

            switch state.liveViewMode {
            case .structured: StructuredStreamView(segments: state.liveSegments)
            case .zen: ZenCanvasView(segments: state.liveSegments)
            }
        }
        .background(Theme.Palette.surfaceLowest)
    }
}

// MARK: - 모드 A · Structured Stream (정보 밀도형)
/// 게이트된 오토스크롤: 사용자가 바닥 근처에 있을 때만 새 세그먼트로 따라간다(위로 스크롤해
/// 읽는 중이면 화면을 끌어내리지 않음). `ScrollPosition`/`onScrollGeometryChange`(macOS 15+).
///
/// API 검증(MacOSX26.5.sdk swiftinterface):
///   - `ScrollPosition(edge:)`: 실제 시그니처는 `init(idType:edge:)` 이고 `idType` 기본값이
///     `Never.self` 라 `ScrollPosition(edge: .bottom)` 그대로 컴파일됨.
///   - `position.scrollTo(edge:)`, `.scrollPosition(_:)`, `.onScrollGeometryChange(for:of:action:)` 모두 존재.
struct StructuredStreamView: View {
    let segments: [TranscriptSegment]
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var atBottom = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(segments) { TranscriptRow(segment: $0) }
            }
            .scrollTargetLayout()
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y >= geo.contentSize.height - geo.containerSize.height - 24
        } action: { _, nowAtBottom in
            atBottom = nowAtBottom
        }
        .onChange(of: segments.count) { _, _ in
            if atBottom { withAnimation { position.scrollTo(edge: .bottom) } }
        }
    }
}

/// 목업 행: 좌측 칸(타임스탬프 + 화자칩, 세로 보더) + 텍스트, 행 구분선(라이브 미리보기, 읽기 전용).
struct TranscriptRow: View {
    let segment: TranscriptSegment
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(segment.timecode).font(Theme.Font.monoData).foregroundStyle(Theme.Palette.outline)
                if !segment.speakerLabel.isEmpty {
                    SpeakerChip(segment: segment)
                }
            }
            .frame(width: Theme.Layout.timeGutter, alignment: .leading)
            .padding(Theme.Spacing.md)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Theme.Palette.outlineVariant.opacity(0.4)).frame(width: 0.5)
            }

            Text(segment.text)
                .font(Theme.Font.bodyReading)
                .foregroundStyle(Theme.Palette.onSurface.opacity(segment.isFinal ? 1 : 0.6))   // 미리보기는 흐리게
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
        }
        .background(segment.isFinal ? Theme.Palette.surfaceLowest : Theme.Palette.primary.opacity(0.04))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Palette.outlineVariant.opacity(0.4)).frame(height: 0.5)
        }
    }
}

// MARK: - 모드 B · Zen Canvas (미니멀형)
struct ZenCanvasView: View {
    let segments: [TranscriptSegment]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            // 최근 발화 강조, 지난 줄은 흐리게.
            VStack(spacing: Theme.Spacing.md) {
                ForEach(recent) { seg in
                    Text(seg.text)
                        .font(Theme.Font.displayLg)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.Palette.onSurface.opacity(seg.id == recent.last?.id ? 1 : 0.3))
                        .transition(segmentTransition())
                }
                if segments.isEmpty {
                    Text("Listening for voice patterns")
                        .font(Theme.Font.bodyReading).italic()
                        .foregroundStyle(Theme.Palette.outline.opacity(0.4))
                }
            }
            .frame(maxWidth: 800)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("실시간 전사")
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: segments.count)
    }

    private var recent: [TranscriptSegment] { Array(segments.suffix(3)) }

    /// macOS 26 전용 blur-replace를 #available로 게이팅(타깃 15.0). reduceMotion이면 페이드만.
    /// `AnyTransition` 에는 `.blurReplace` 정적 멤버가 없으므로 `BlurReplaceTransition` 을
    /// 직접 래핑한다(`.blurReplace` 는 `Transition` 프로토콜 네임스페이스 전용).
    private func segmentTransition() -> AnyTransition {
        if reduceMotion { return .opacity }
        if #available(macOS 26, *) {
            return .opacity.combined(with: AnyTransition(BlurReplaceTransition(configuration: .downUp)))
        }
        return .opacity
    }
}

#if DEBUG
#Preview("LiveTranscript") {
    LiveTranscriptView().environment(AppState.preview)
}
#endif
