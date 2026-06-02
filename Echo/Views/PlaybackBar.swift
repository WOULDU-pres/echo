import SwiftUI
import AVFoundation
import Observation

/// 저장된 녹음의 믹스/마이크 트랙을 재생하는 컨트롤러(Task 5.4).
/// `AVAudioPlayer` 백엔드 + 0.1s 타이머로 `currentTime` 을 갱신해 전사 행 하이라이트를 구동한다.
/// 모든 변경은 메인 액터에서. 뷰는 `currentTime`/`isPlaying`/`duration` 에만 바인딩한다.
@MainActor
@Observable
final class PlaybackController {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// 재생 가능한 트랙이 없으면(파일 없음/디코드 실패) true → 컨트롤을 비활성.
    private(set) var unavailable = false

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
        // 0.1s 폴링. Timer 클로저는 메인 런루프에서 호출되지만 @Sendable 격리를 위해
        // MainActor 로 hop 해 모델 상태를 갱신한다.
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

/// 재생 스크러버: 재생/일시정지 + 슬라이더 + 시간 표시.
struct PlaybackBar: View {
    @Bindable var controller: PlaybackController

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button(action: { controller.togglePlay() }) {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(controller.unavailable)
            .accessibilityLabel(controller.isPlaying ? "일시정지" : "재생")

            Text(timecode(controller.currentTime))
                .font(Theme.Font.monoData)
                .foregroundStyle(Theme.Palette.onSurfaceVariant)
                .monospacedDigit()

            Slider(
                value: Binding(
                    get: { controller.currentTime },
                    set: { controller.seek(to: $0) }
                ),
                in: 0...max(controller.duration, 0.01)
            )
            .disabled(controller.unavailable || controller.duration <= 0)
            .accessibilityLabel("재생 위치")
            .accessibilityValue(timecode(controller.currentTime))

            Text(timecode(controller.duration))
                .font(Theme.Font.monoData)
                .foregroundStyle(Theme.Palette.outline)
                .monospacedDigit()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
        .overlay(alignment: .leading) {
            if controller.unavailable {
                Text("재생할 오디오 트랙이 없습니다")
                    .font(Theme.Font.bodyUI)
                    .foregroundStyle(Theme.Palette.outline)
                    .padding(.leading, Theme.Spacing.xl + 32)
            }
        }
    }

    private func timecode(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%02d:%02d", (s % 3600) / 60, s % 60)
    }
}

#if DEBUG
#Preview("PlaybackBar") {
    PlaybackBar(controller: PlaybackController())
        .padding(Theme.Spacing.xl)
        .frame(width: 600)
}
#endif
