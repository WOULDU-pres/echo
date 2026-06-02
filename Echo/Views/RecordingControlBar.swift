import SwiftUI

/// 하단 중앙 플로팅 컨트롤러: Record / Pause / Stop + REC 펄스·타이머.
/// macOS 26: 컨테이너에 `.glassEffect()`, 주 버튼에 `.buttonStyle(.glassProminent)` 적용.
struct RecordingControlBar: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            if !isIdle {
                recPill
                LevelStrip(level: state.currentLevel)
                    .frame(width: 64)
                    .accessibilityHidden(true)
            }
            // 목업: Record / Pause / Stop 3버튼을 항상 노출(상황에 맞지 않으면 비활성).
            recordButton(label: isPaused ? "Resume" : "Record") {
                if isPaused { state.resumeRecording() } else { Task { await state.startRecording() } }
            }
            .disabled(state.isRecording)
            controlButton(system: "pause.fill", label: "Pause") { state.pauseRecording() }
                .disabled(!state.isRecording)
            controlButton(system: "stop.fill", label: "Stop", tint: Theme.Palette.secondary) {
                Task { await state.stopRecording() }
            }
            .disabled(isIdle)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .modifier(GlassContainer(cornerRadius: Theme.Radius.xl))
    }

    private var isPaused: Bool { if case .paused = state.phase { return true }; return false }
    private var isIdle: Bool { if case .idle = state.phase { return true }; return false }

    /// 주 액션(Record/Resume). macOS 26 에서는 `.glassProminent`, 그 이하는 커스텀 버튼.
    @ViewBuilder
    private func recordButton(label: String, action: @escaping () -> Void) -> some View {
        if #available(macOS 26, *) {
            Button(action: action) {
                Label(label, systemImage: "record.circle.fill")
                    .font(Theme.Font.bodyUI)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.Palette.secondary)
            .help(label)
            .accessibilityLabel(label)
            .accessibilityHint("누르면 \(label)")
        } else {
            controlButton(system: "record.circle.fill", label: label, tint: Theme.Palette.secondary, action: action)
        }
    }

    @ViewBuilder
    private var recPill: some View {
        if !isIdle {
            // 매초 갱신. 경과는 일시정지 시간을 제외한 '유효 경과'(저장 length와 동일 공식).
            // 일시정지 중엔 펄스를 멈추고 색을 죽여 'PAUSE'로 표시.
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let secs = Int(state.recordingElapsed(asOf: ctx.date))
                HStack(spacing: Theme.Spacing.base) {
                    Circle()
                        .fill(isPaused ? Theme.Palette.outline : Theme.Palette.secondary)
                        .frame(width: 8, height: 8)
                        .opacity(isPaused ? 0.5 : (reduceMotion ? 1 : (secs % 2 == 0 ? 1 : 0.4)))
                        .animation(reduceMotion || isPaused ? nil : .easeInOut(duration: 1), value: secs)
                    Text(timecode(secs, paused: isPaused))
                        .font(Theme.Font.monoData)
                        .foregroundStyle(isPaused ? Theme.Palette.outline : Theme.Palette.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isPaused ? "일시정지됨" : "녹음 중")
                .accessibilityValue(timecode(secs, paused: isPaused))
            }
        }
    }

    private func controlButton(
        system: String, label: String, tint: Color = Theme.Palette.onSurfaceVariant,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: system).font(.system(size: 24)).foregroundStyle(tint)
                Text(label).font(Theme.Font.labelCaps).textCase(.uppercase)
            }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint("누르면 \(label)")
    }

    private func timecode(_ s: Int, paused: Bool) -> String {
        String(format: "%@ %02d:%02d:%02d", paused ? "PAUSE" : "REC", s / 3600, (s % 3600) / 60, s % 60)
    }
}

/// 컨테이너 배경: macOS 26 Liquid Glass(`.glassEffect`), 그 이하 또는 투명도 감소 시 머티리얼 폴백.
/// 참조: .agents/skills/swiftui-expert-skill/references/liquid-glass.md (#available + material fallback).
/// glassEffect 는 레이아웃(padding) 뒤에 적용한다(modifier order 규칙).
private struct GlassContainer: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency {
            // 글래스가 자체 외곽·그림자를 그린다.
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            // 폴백: 머티리얼 + 옅은 그림자로 떠 있는 느낌(글래스 미적용 시).
            content
                .background(
                    reduceTransparency ? AnyShapeStyle(.thickMaterial) : AnyShapeStyle(.regularMaterial),
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
                .shadow(radius: 12, y: 4)
        }
    }
}

/// 슬림 레벨 미터 스트립(0...1). 마이크 RMS에 연동.
struct LevelStrip: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.Palette.primary)
                .frame(width: geo.size.width * CGFloat(min(max(level, 0), 1)))
                .frame(maxHeight: .infinity, alignment: .leading)
                .animation(.linear(duration: 0.05), value: level)
        }
        .frame(height: 4)
        .background(Theme.Palette.surfaceLow, in: RoundedRectangle(cornerRadius: 2))
    }
}

#if DEBUG
#Preview("ControlBar") {
    RecordingControlBar()
        .environment(AppState.preview)
        .padding(Theme.Spacing.xl)
}
#endif
