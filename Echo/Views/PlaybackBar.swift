import SwiftUI
import AVFoundation
import Observation

/// 저장된 녹음의 믹스/마이크 트랙을 재생하는 컨트롤러(Task 5.4).
/// `AVAudioPlayer` 백엔드 + 0.1s 타이머로 `currentTime` 을 갱신해 전사 행 하이라이트를 구동한다.
/// 모든 변경은 메인 액터에서. 뷰는 `currentTime`/`isPlaying`/`duration`/`rate` 에만 바인딩한다.
@MainActor
@Observable
final class PlaybackController {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// 재생 배속(0.75~2.0). 즉시 반영.
    private(set) var rate: Float = 1.0
    /// 재생 가능한 트랙이 없으면(파일 없음/디코드 실패) true → 컨트롤을 비활성.
    private(set) var unavailable = false

    /// 배속 순환 목록.
    private static let rates: [Float] = [1.0, 1.25, 1.5, 2.0, 0.75]

    private var player: AVAudioPlayer?
    private var ticker: Timer?

    /// 녹음에서 재생할 트랙을 선택해 로드한다(믹스 우선, 없으면 마이크, 그다음 아무 트랙).
    func load(_ recording: Recording) {
        stop()
        let url = recording.audioTracks[.mixed]
            ?? recording.audioTracks[.microphone]
            ?? recording.audioTracks.values.first
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            unavailable = true
            duration = 0
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.enableRate = true          // 배속 지원
            p.rate = rate
            p.prepareToPlay()
            player = p
            duration = p.duration
            currentTime = 0
            unavailable = false
        } catch {
            unavailable = true
            duration = 0
        }
    }

    func togglePlay() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTicker()
        } else {
            player.play()
            player.rate = rate           // 재생 시작 시 현재 배속 적용
            isPlaying = true
            startTicker()
        }
    }

    /// 스크러버/행 탭에서 호출. 0...duration 으로 클램프.
    func seek(to time: TimeInterval) {
        guard let player else { return }
        let t = min(max(time, 0), duration)
        player.currentTime = t
        currentTime = t
    }

    /// 현재 위치에서 delta초 만큼 이동(±건너뛰기).
    func skip(_ delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    /// 배속을 다음 단계로 순환(1x→1.25→1.5→2x→0.75x→1x).
    func cycleRate() {
        let i = Self.rates.firstIndex(of: rate) ?? 0
        rate = Self.rates[(i + 1) % Self.rates.count]
        player?.rate = isPlaying ? rate : rate   // 재생 중이면 즉시, 아니면 다음 play에 반영
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        unavailable = false
        stopTicker()
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime
        if !player.isPlaying {
            isPlaying = false
            stopTicker()
        }
    }
}

/// 재생 컨트롤: 건너뛰기(±10초) · 재생/일시정지 · 커스텀 스크러버 · 시간 · 배속.
struct PlaybackBar: View {
    @Bindable var controller: PlaybackController

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // 10초 뒤로
            controlButton("gobackward.10", size: 15) { controller.skip(-10) }
                .disabled(controller.unavailable)
                .accessibilityLabel("10초 뒤로")

            // 재생/일시정지(강조)
            Button(action: { controller.togglePlay() }) {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.Palette.primary, in: Circle())
                    .opacity(controller.unavailable ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(controller.unavailable)
            .accessibilityLabel(controller.isPlaying ? "일시정지" : "재생")

            // 10초 앞으로
            controlButton("goforward.10", size: 15) { controller.skip(10) }
                .disabled(controller.unavailable)
                .accessibilityLabel("10초 앞으로")

            Text(timecode(controller.currentTime))
                .font(Theme.Font.monoData)
                .foregroundStyle(Theme.Palette.onSurface)
                .monospacedDigit()

            Scrubber(current: controller.currentTime,
                     duration: controller.duration,
                     enabled: !controller.unavailable && controller.duration > 0) {
                controller.seek(to: $0)
            }
            .frame(maxWidth: .infinity)

            Text(timecode(controller.duration))
                .font(Theme.Font.monoData)
                .foregroundStyle(Theme.Palette.outline)
                .monospacedDigit()

            // 배속
            Button(action: { controller.cycleRate() }) {
                Text(rateLabel(controller.rate))
                    .font(Theme.Font.monoData)
                    .monospacedDigit()
                    .foregroundStyle(controller.rate == 1.0 ? Theme.Palette.onSurfaceVariant : Theme.Palette.primary)
                    .frame(width: 44, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg)
                            .fill(controller.rate == 1.0 ? Color.clear : Theme.Palette.primary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg)
                            .strokeBorder(Theme.Palette.outlineVariant.opacity(0.5), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .disabled(controller.unavailable)
            .help("재생 배속")
            .accessibilityLabel("재생 배속 \(rateLabel(controller.rate))")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(glassPanel)
        .overlay(alignment: .leading) {
            if controller.unavailable {
                Text("재생할 오디오 트랙이 없습니다")
                    .font(Theme.Font.bodyUI)
                    .foregroundStyle(Theme.Palette.outline)
                    .padding(.leading, Theme.Spacing.xl + 120)
            }
        }
    }

    /// 글래스 패널(평평하게): 입체감 없이 투명한 프로스트 유리만.
    /// 가장 얇은 프로스트 블러 + 회색기만 살짝 덜어주는 균일한 화이트 + 얇은 유리 테두리.
    /// 그림자·광택 그라데이션·베벨 없음(떠 있는 듯한 입체감 제거).
    private var glassPanel: some View {
        let shape = Capsule(style: .continuous)
        return shape
            .fill(.ultraThinMaterial)                       // 뒤가 비치는 투명 프로스트
            .overlay {
                // 균일한 옅은 화이트 — 방향성 없는 평평한 톤(회색 슬랩 방지).
                shape.fill(.white.opacity(0.12))
            }
            .overlay {
                // 얇고 균일한 유리 가장자리(하이라이트·베벨 없음 → 평평).
                shape.strokeBorder(.white.opacity(0.5), lineWidth: 1)
            }
            .overlay {
                // 밝은 배경에서 윤곽만 살짝 잡아주는 중립 헤어라인.
                shape.strokeBorder(Theme.Palette.outlineVariant.opacity(0.25), lineWidth: 0.5)
            }
    }

    private func controlButton(_ icon: String, size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(Theme.Palette.onSurfaceVariant)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }

    private func rateLabel(_ r: Float) -> String {
        // 1.0 → "1x", 1.25 → "1.25x", 1.5 → "1.5x", 0.75 → "0.75x"
        let s = (r == r.rounded()) ? String(Int(r)) : String(format: "%g", r)
        return "\(s)x"
    }

    /// 1시간 이상이면 H:MM:SS, 아니면 MM:SS.
    private func timecode(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%02d:%02d", (s % 3600) / 60, s % 60)
    }
}

/// 채워진 트랙 + 드래그 핸들의 커스텀 재생 스크러버(기본 Slider보다 또렷·정확).
struct Scrubber: View {
    let current: TimeInterval
    let duration: TimeInterval
    let enabled: Bool
    let onSeek: (TimeInterval) -> Void
    /// 드래그 중에는 손가락 위치를 즉시 따라가게 하는 임시 비율.
    @State private var dragFrac: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frac = dragFrac ?? (duration > 0 ? min(max(current / duration, 0), 1) : 0)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.outlineVariant.opacity(0.45))
                    .frame(height: 5)
                Capsule().fill(enabled ? Theme.Palette.primary : Theme.Palette.outline)
                    .frame(width: max(0, w * frac), height: 5)
                Circle().fill(enabled ? Theme.Palette.primary : Theme.Palette.outline)
                    .frame(width: 13, height: 13)
                    .shadow(radius: 1, y: 0.5)
                    .offset(x: min(max(w * frac - 6.5, -1), w - 12))
            }
            .frame(height: 16)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard enabled, w > 0 else { return }
                        dragFrac = min(max(v.location.x / w, 0), 1)
                    }
                    .onEnded { v in
                        guard enabled, w > 0 else { dragFrac = nil; return }
                        let f = min(max(v.location.x / w, 0), 1)
                        onSeek(f * duration)
                        dragFrac = nil
                    }
            )
        }
        .frame(height: 16)
    }
}

#if DEBUG
#Preview("PlaybackBar") {
    ZStack {
        // 유리 효과가 보이도록 컬러풀한 배경 위에 얹어 미리보기.
        LinearGradient(colors: [Theme.Palette.primary.opacity(0.25),
                                Theme.Palette.tertiary.opacity(0.20),
                                Theme.Palette.background],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        PlaybackBar(controller: PlaybackController())
            .padding(Theme.Spacing.xl)
            .frame(width: 640)
    }
    .frame(width: 720, height: 160)
}
#endif
