# Echo Phase 1 — Microphone Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Read `2026-06-01-echo-master.md` first. Branch: `git checkout -b phase/1-mic`.

**Goal:** Record the microphone to a track file via the floating glass control bar (Record/Stop, REC timer, live level meter), then auto-run the full large-v3 (ko) batch transcript on stop and save it to history.

**Architecture:** `MicrophoneCapture` (AVAudioEngine) → `RecordingCoordinator` (writes a `.caf` via `TrackWriter`) → on stop, `AppState` batch-transcribes the track with `WhisperKitBatchTranscriber` and saves a `Recording`. A pure `LevelMeter` computes RMS for the meter.

**Tech Stack:** AVAudioEngine, AVAudioFile, SwiftUI, WhisperKit, Swift Testing.

---

### Task 1.1: LevelMeter (TDD)

**Files:**
- Create: `Echo/Capture/LevelMeter.swift`
- Test: `EchoTests/LevelMeterTests.swift`

- [ ] **Step 1: Write the failing test.**

```swift
import Testing
@testable import Echo

@Test func rmsOfSilenceIsZero() {
    #expect(LevelMeter.rms([0, 0, 0, 0]) == 0)
}

@Test func rmsOfConstantIsMagnitude() {
    #expect(abs(LevelMeter.rms([0.5, -0.5, 0.5, -0.5]) - 0.5) < 1e-6)
}

@Test func normalizedLevelClampsToUnit() {
    #expect(LevelMeter.normalized([1, 1, 1]) <= 1)
    #expect(LevelMeter.normalized([0, 0, 0]) == 0)
}
```

- [ ] **Step 2: Run, verify FAIL** (`cannot find 'LevelMeter'`).

```bash
xcodebuild test -scheme Echo -destination 'platform=macOS' -only-testing:EchoTests/LevelMeterTests 2>&1 | tail -20
```

- [ ] **Step 3: Implement.**

```swift
import Foundation

enum LevelMeter {
    /// Root-mean-square of samples in [-1, 1].
    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// 0...1 미터 값(약간의 헤드룸 게인). UI 레벨 스트립용.
    static func normalized(_ samples: [Float], gain: Float = 1.4) -> Float {
        min(1, rms(samples) * gain)
    }
}
```

- [ ] **Step 4: Run, verify PASS.** Same command.
- [ ] **Step 5: Commit.** `git commit -am "feat: LevelMeter RMS with TDD"`

---

### Task 1.2: TrackWriter real implementation

**Files:**
- Modify: `Echo/Capture/RecordingCoordinator.swift` (the `TrackWriter` class)
- Test: `EchoTests/TrackWriterTests.swift`

- [ ] **Step 1: Write the test** (write a buffer, read back frame count).

```swift
import Testing
import AVFoundation
@testable import Echo

@Test func trackWriterPersistsFrames() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tw-\(UUID()).caf")
    let fmt = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1600)!
    buf.frameLength = 1600
    for i in 0..<1600 { buf.floatChannelData![0][Int(i)] = 0 }

    let writer = TrackWriter(url: url)
    writer.append(buf)
    let out = writer.finish()

    let read = try AVAudioFile(forReading: out)
    #expect(read.length == 1600)
    try? FileManager.default.removeItem(at: url)
}
```

- [ ] **Step 2: Run, verify FAIL** (current `TrackWriter.append` is a no-op, so `read.length == 0`).
- [ ] **Step 3: Implement** — replace the scaffold `TrackWriter` with:

```swift
final class TrackWriter {
    let url: URL
    private var file: AVAudioFile?
    private let queue = DispatchQueue(label: "echo.trackwriter")

    init(url: URL) { self.url = url }

    func append(_ buffer: AVAudioPCMBuffer) {
        queue.sync {
            do {
                if file == nil {
                    file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
                }
                try file?.write(from: buffer)
            } catch {
                // 첫 write에서만 throw 가능; 로깅만 하고 계속
            }
        }
    }

    func finish() -> URL { queue.sync { file = nil }; return url }
}
```

- [ ] **Step 4: Run, verify PASS.**
- [ ] **Step 5: Commit.** `git commit -am "feat: TrackWriter writes AVAudioFile (tested)"`

---

### Task 1.3: Microphone permission + capture verify

**Files:** Modify `Echo/Capture/MicrophoneCapture.swift`.

- [ ] **Step 1:** Add an explicit permission request before starting the engine:

```swift
func start() async throws {
    let granted = await AVCaptureDevice.requestAccess(for: .audio)
    guard granted else { throw TranscriptionError.engineUnavailable("마이크 권한이 거부되었습니다") }
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, when in
        self?.onBuffer?(buffer, when)
    }
    engine.prepare()
    try engine.start()
}
```

- [ ] **Step 2: ▶︎ Run & verify** with a throwaway harness: temporarily add a "Mic test" button (or a `#Preview`-free debug menu) that creates a `MicrophoneCapture`, sets `onBuffer` to print `LevelMeter.rms(AudioFormat.toWhisperSamples(buffer))`, calls `start()`, and after 3s `stop()`. Expected: macOS shows the mic permission prompt once; console prints non-zero RMS while you speak. Remove the harness after verifying.
- [ ] **Step 3: Commit.** `git commit -am "feat: mic permission request + verified capture"`

---

### Task 1.4: RecordingCoordinator mic-only path returns a track URL

**Files:** Modify `Echo/Capture/RecordingCoordinator.swift`.

- [ ] **Step 1:** The scaffold already wires mic → `TrackWriter` + live continuation. Add a recordings directory helper and confirm `start(source:into:)` is called with a real directory. Add to `RecordingCoordinator`:

```swift
static func newSessionDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Echo/Recordings", isDirectory: true)
    let dir = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```

- [ ] **Step 2:** No unit test (file/engine bound). Verified via Task 1.7 E2E.
- [ ] **Step 3: Commit.** `git commit -am "feat: session directory for recording tracks"`

---

### Task 1.5: AppState wires record → stop → batch transcribe

**Files:** Modify `Echo/App/AppState.swift`.

- [ ] **Step 1:** Add a session directory field and implement the lifecycle. Replace the scaffold `startRecording`/`stopRecording`:

```swift
private var sessionDir: URL?
private var startedAt: Date?

func startRecording() async {
    let dir = RecordingCoordinator.newSessionDirectory()
    sessionDir = dir
    startedAt = Date()
    liveSegments = []
    do {
        try await coordinator.start(source: source, into: dir)
        phase = .recording(since: startedAt!)
        // TODO(Phase 3): if livePreviewEnabled, subscribe coordinator.liveBufferStream → livePreview.stream
    } catch {
        phase = .failed(error.localizedDescription)
    }
}

func stopRecording() async {
    let tracks = await coordinator.stop()
    let dur = startedAt.map { Date().timeIntervalSince($0) } ?? 0
    phase = .processing(progress: 0)

    var perChannel: [[TranscriptSegment]] = []
    var trackMap: [AudioChannel: URL] = [:]
    for (channel, url) in tracks {
        trackMap[channel] = url
        if let segs = try? await batchTranscriber.transcribe(url, language: language) {
            perChannel.append(segs.map { var s = $0; s.channel = channel; return s })
        }
    }
    let merged = TranscriptMerger.merge(perChannel)

    let rec = Recording(
        title: "녹음 \(merged.first?.timecode ?? "")",
        createdAt: startedAt ?? Date(),
        duration: dur,
        source: source,
        audioTracks: trackMap,
        segments: merged,
        language: language,
        transcriptionModel: WhisperKitBatchTranscriber.modelIdentifier
    )
    recordings.insert(rec, at: 0)
    selectedRecordingID = rec.id
    liveSegments = []
    phase = .done
}
```

- [ ] **Step 2:** Self-check against swiftui-expert-skill (state mutations on `@MainActor`, no view-owned state passed in). 
- [ ] **Step 3: Commit.** `git commit -am "feat: record→stop→large-v3 batch→save lifecycle"`

---

### Task 1.6: Control bar — live timer + level meter

**Files:** Modify `Echo/Views/RecordingControlBar.swift`.

- [ ] **Step 1:** Drive the REC timer from the recording start date with `TimelineView` instead of `state.elapsed` (avoids storing/incrementing). Replace `recPill`:

```swift
private var recPill: some View {
    Group {
        if case .recording(let since) = state.phase {
            TimelineView(.periodic(from: since, by: 1)) { ctx in
                let secs = Int(ctx.date.timeIntervalSince(since))
                HStack(spacing: Theme.Spacing.base) {
                    Circle().fill(Theme.Palette.secondary).frame(width: 8, height: 8)
                        .opacity(reduceMotion ? 1 : 0.5)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 1).repeatForever(autoreverses: true), value: secs)
                    Text(String(format: "REC %02d:%02d:%02d", secs/3600, (secs%3600)/60, secs%60))
                        .font(Theme.Font.monoData).foregroundStyle(Theme.Palette.secondary)
                }
            }
        }
    }
}
```

- [ ] **Step 2:** Add a slim level strip bound to `state.currentLevel` (the coordinator's mic `onBuffer` should set `state.currentLevel = LevelMeter.normalized(AudioFormat.toWhisperSamples(buf))` hopped to `@MainActor`). Add a `LevelStrip` view:

```swift
struct LevelStrip: View {
    let level: Float   // 0...1
    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.Palette.primary)
                .frame(width: geo.size.width * CGFloat(level))
                .frame(maxHeight: .infinity, alignment: .leading)
                .animation(.linear(duration: 0.05), value: level)
        }
        .frame(height: 4)
        .background(Theme.Palette.surfaceLow, in: RoundedRectangle(cornerRadius: 2))
    }
}
```

Add `import AVFoundation` to `AppState.swift` if needed for the `@MainActor` level hop in the coordinator callback (set `currentLevel` via `Task { @MainActor in ... }`).

- [ ] **Step 3: ▶︎ Run & verify** — UI shows REC timer counting and level strip moving while speaking.
- [ ] **Step 4: Commit.** `git commit -am "feat: live REC timer + level meter strip"`

---

### Task 1.7: Phase 1 end-to-end verify + DoD

- [ ] **Step 1: ▶︎ Run & verify:** set source = mic only; press Record; speak Korean ~10s; press Stop. Expected: `processing` spinner → a saved recording with a Korean large-v3 transcript appears in history and detail. Paste the transcript as evidence.
- [ ] **Step 2:** `xcodebuild test -scheme Echo -destination 'platform=macOS'` → all tests PASS (paste tail).
- [ ] **Step 3:** Self-check changed views against swiftui-expert-skill checklist.
- [ ] **Step 4:** Merge `phase/1-mic` → `main`; check the Phase 1 box in the master file.

**Next:** `2026-06-01-echo-phase2-system-audio.md`.
