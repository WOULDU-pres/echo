# Echo Phase 4 — Optional Screen Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Read the master file first. Branch: `git checkout -b phase/4-screen`.

**Goal:** When the "화면 녹화" toggle is on, record screen video + system audio + microphone via ScreenCaptureKit into one file, while still fanning audio to the transcription pipeline.

**Architecture:** `ScreenCapture` runs an `SCStream` with `captureMicrophone = true`, delivering `.screen`, `.audio`, `.microphone` outputs. Video is written with `SCRecordingOutput` (macOS 15+). The `.audio`/`.microphone` sample buffers are also forwarded (as `AVAudioPCMBuffer`) to `onSystemAudio`/`onMicrophone` so `RecordingCoordinator` can still build per-channel transcripts. When screen is on, `RecordingCoordinator` uses `ScreenCapture` instead of the separate mic/system captures.

**Tech Stack:** ScreenCaptureKit (SCStream, SCContentFilter, SCContentSharingPicker, SCRecordingOutput), AVFoundation.

**API-verification rule applies.** Fanless M4 Air: cap at 1080p/30.

---

### Task 4.1: Source selection + stream configuration

**Files:** Modify `Echo/Capture/ScreenCapture.swift`.

- [ ] **Step 1: Implement `start()`**:

```swift
import ScreenCaptureKit
import AVFoundation

func start() async throws {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let display = content.displays.first else {
        throw TranscriptionError.engineUnavailable("디스플레이를 찾을 수 없습니다")
    }
    let filter = SCContentFilter(display: display, excludingWindows: [])

    let config = SCStreamConfiguration()
    config.capturesAudio = true
    config.captureMicrophone = true          // macOS 15+
    config.width = 1920; config.height = 1080
    config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    config.sampleRate = 48_000
    config.channelCount = 2

    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
    try stream.addStreamOutput(audioHandler, type: .audio, sampleHandlerQueue: .global())
    try stream.addStreamOutput(micHandler, type: .microphone, sampleHandlerQueue: .global())

    // 영상 파일: macOS 15+ SCRecordingOutput
    let url = RecordingCoordinator.newSessionDirectory().appendingPathComponent("screen.mp4")
    let recCfg = SCRecordingOutputConfiguration()
    recCfg.outputURL = url
    recCfg.outputFileType = .mov     // 또는 .mp4
    let recOutput = SCRecordingOutput(configuration: recCfg, delegate: nil)
    try stream.addRecordingOutput(recOutput)
    self.videoURL = url

    try await stream.startCapture()
    self.stream = stream
}
```

- [ ] **Step 2:** Implement two `SCStreamOutput` handler objects (`audioHandler`, `micHandler`) that convert `CMSampleBuffer` → `AVAudioPCMBuffer` and call `onSystemAudio`/`onMicrophone`. Use `CMSampleBuffer` → `AVAudioPCMBuffer` via the buffer's format description (`try? sampleBuffer.withAudioBufferList { ... }` or `AVAudioPCMBuffer(pcmFormat:bufferListNoCopy:)`).
- [x] **Step 3:** Signature divergences verified against MacOSX26.5.sdk ScreenCaptureKit Headers + applied:
  - `SCRecordingOutput(configuration:delegate:)` — delegate is **non-null** (`id<SCRecordingOutputDelegate>`); plan's `delegate: nil` would not compile. Implemented `RecordingOutputDelegate` (optional methods).
  - `stream.addStreamOutput(_:type:sampleHandlerQueue:)` and `stream.addRecordingOutput(_:)` **throw** (BOOL+NSError**) → `try`.
  - `captureMicrophone` / `.microphone` output are macOS 15+ → gated `#available(macOS 15.0,*)`.
  - `SCShareableContent.excludingDesktopWindows(_:onScreenWindowsOnly:)` async getter; `SCContentFilter(display:excludingWindows:)` confirmed.
  - `SCStreamOutput` protocol method is `stream(_:didOutputSampleBuffer:of:)`.
  - CMSampleBuffer→PCM via `CMSampleBufferCopyPCMDataIntoAudioBufferList(_:at:frameCount:into:)` + `AVAudioFormat(streamDescription:)`.
  - Changed `start()` → `start(into:)` so the coordinator passes the session directory.
- [x] **Step 4: Commit.** `feat: ScreenCaptureKit stream + recording output + route audio to transcription (5efcdaf)`

---

### Task 4.2: Optional content picker

**Files:** Modify `Echo/Capture/ScreenCapture.swift` + a settings affordance.

- [~] **Step 1:** `ScreenCapture.setFilter(_:)` lets a caller inject a pre-built `SCContentFilter` (e.g. from `SCContentSharingPicker`); default remains the whole main display. The picker-presentation UI affordance is not yet wired into Settings (no UI surface for it) — left as a small follow-up. Compiles.
- [ ] **Step 2: Commit.** picker UI affordance pending (recorded in unresolved).

---

### Task 4.3: Route screen path through the coordinator

**Files:** Modify `Echo/Capture/RecordingCoordinator.swift`.

- [x] **Step 1:** Screen branch creates mic+system `TrackWriter`s, wires `onMicrophone`→shared `handleMicBuffer` (track + live stream + level), `onSystemAudio`→system track. `coordinator.videoURL` exposes `screen.videoURL` after `start(into:)`. `stop()` is now `async` (awaits `screen.stop()` for clean `SCStream.stopCapture()`).
- [x] **Step 2:** `AppState.stopRecording` sets `rec.videoURL = coordinator.videoURL`.
- [x] **Step 3: Commit.** (folded into 5efcdaf)

---

### Task 4.4: Permission UX + thermal guard

**Files:** `Echo/Views/SettingsInspector.swift` or a pre-record explainer.

- [~] **Step 1:** Failure path covered: any `SCStream`/permission throw from `coordinator.start` lands in `AppState.startRecording`'s `catch` → `phase = .failed(error.localizedDescription)` (ScreenCapture throws localized Korean `engineUnavailable`). A dedicated pre-record inline explainer view is a runtime-UX nicety, not yet added.
- [x] **Step 2:** Config capped at 1920×1080 / 30fps with an explicit code comment about fanless-Air thermal throttling under concurrent transcription.
- [ ] **Step 3: ▶︎ Run & verify (HUMAN):** requires TCC Screen Recording grant + real audio/screen — cannot be done headlessly. See humanTODO.
- [ ] **Step 4: Commit.** thermal/perm UX commit pending human verification.

---

### Task 4.5: Phase 4 Definition of Done

- [ ] Screen toggle records video + system + mic to one file; file plays with audio.
- [ ] Transcript still produced from the screen-path audio (mic + system rows).
- [ ] Screen Recording permission handled gracefully (cold prompt + failure path).
- [ ] ScreenCaptureKit API divergences noted in Tasks 4.1–4.2.
- [ ] Unit tests still PASS; self-check vs swiftui-expert-skill.
- [ ] Merge `phase/4-screen` → `main`; check the Phase 4 box.

**Next:** `2026-06-01-echo-phase5-polish.md`.
