# Echo Phase 0 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Steps use checkbox (`- [ ]`) syntax. Read `2026-06-01-echo-master.md` first.

**Goal:** A runnable Echo.app shell that transcribes a chosen audio file with full large-v3 (ko) end-to-end, plus a unit-test target with passing TDD tests for the pure-logic core.

**Architecture:** Import the existing `Echo/` scaffold into a new Xcode macOS App project, add WhisperKit, add two new pure-logic units (`TranscriptExporter`, `TranscriptMerger`) via TDD, and wire a file-open → batch-transcribe path through `AppState.transcribeFile`.

**Tech Stack:** Xcode 26, Swift 6, SwiftUI, WhisperKit, Swift Testing.

**Prerequisite:** Full Xcode 26 installed and selected (`xcodebuild -version` works). See `docs/SETUP-XCODE.md §0`. If `xcode-select -p` still points at CommandLineTools, run `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` first.

---

### Task 0.1: Initialize git

**Files:** repo root (`.gitignore` already present).

- [ ] **Step 1:** Initialize and make the first commit.

```bash
cd /Users/hwjoo/Desktop/workspace/tools/echo
git init
git add .
git commit -m "chore: initial scaffold, design docs, and plans"
```

- [ ] **Step 2:** Create the phase branch.

```bash
git checkout -b phase/0-foundation
```

Expected: `Switched to a new branch 'phase/0-foundation'`.

---

### Task 0.2: Create the Xcode app project

**Files:** Create `Echo.xcodeproj` (Xcode GUI).

- [ ] **Step 1:** Xcode ▸ File ▸ New ▸ Project ▸ **macOS ▸ App**. Set:
  - Product Name: `Echo`
  - Interface: SwiftUI · Language: Swift
  - Bundle ID: `com.hwjoo.echo`
  - Minimum Deployments: **macOS 15.0**
  - **Save into the existing `echo/` folder** (so `Echo.xcodeproj` sits next to the existing `Echo/` sources). When Xcode offers to create a group folder named `Echo`, you will reconcile with the existing one in Step 2.

- [ ] **Step 2:** Xcode creates `Echo/EchoApp.swift` + `ContentView.swift`. **Delete** Xcode's generated `EchoApp.swift` and `ContentView.swift` (Move to Trash), then **Add Files to "Echo"…** and add the existing `Echo/` subfolders (`App`, `Models`, `Capture`, `Transcription`, `DesignSystem`, `Views`, `Resources`) with "Create groups" selected and the Echo target checked.

- [ ] **Step 3:** Target ▸ Build Settings: confirm Swift Language Version = Swift 6, macOS Deployment Target = 15.0.

- [ ] **Step 4: ▶︎ Run & verify.** ⌘R. 
  Expected: app launches showing the `NavigationSplitView` shell with the empty-state ("녹음을 시작하세요"). No window content from the deleted `ContentView`.
  If it fails to compile because Liquid Glass / macOS-26 modifiers are referenced unguarded, note the file+line and fix per the API-verification rule (most glass usage in the scaffold is in comments, so this should build).

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat: Xcode macOS app project wrapping the Echo scaffold"
```

---

### Task 0.3: Configure Info.plist usage strings, entitlements, signing

**Files:** Modify target settings; reference `Echo/Resources/Info.plist`, `Echo/Resources/Echo.entitlements`.

- [ ] **Step 1:** Target ▸ Info: add the three usage keys (copy values from `Echo/Resources/Info.plist`). Add `NSAudioCaptureUsageDescription` by typing the raw key (not in the dropdown).
- [ ] **Step 2:** Signing & Capabilities ▸ Automatically manage signing ▸ select your free Apple ID team. Set **App Sandbox = OFF** (remove the capability if present; or set `com.apple.security.app-sandbox` to NO via `Echo/Resources/Echo.entitlements` referenced in Build Settings → Code Signing Entitlements).
- [ ] **Step 3: ▶︎ Run & verify.** ⌘R still launches.
- [ ] **Step 4: Commit.**

```bash
git add -A
git commit -m "chore: usage strings, sandbox off, local signing"
```

---

### Task 0.4: Add WhisperKit dependency

**Files:** project package dependencies.

- [ ] **Step 1:** File ▸ Add Package Dependencies… URL `https://github.com/argmaxinc/WhisperKit`. Pin to the latest stable **Up to Next Major**. Add the `WhisperKit` library product to the Echo target.
- [ ] **Step 2: ▶︎ Run & verify.** Build succeeds. `WhisperKitBatchTranscriber.swift` now compiles its `#if canImport(WhisperKit)` branch.
  If the API names differ (e.g. `WhisperKitConfig`, `DecodingOptions`, `transcribe(audioPath:decodeOptions:)`, `segments`/`.start`/`.end`/`.text`), fix `Echo/Transcription/WhisperKitBatchTranscriber.swift` to match the installed version's API and note the corrections here.
- [ ] **Step 3: Commit.**

```bash
git add -A
git commit -m "feat: add WhisperKit dependency"
```

---

### Task 0.5: Add the unit-test target

**Files:** Create `EchoTests/` target.

- [ ] **Step 1:** File ▸ New ▸ Target ▸ **Unit Testing Bundle** named `EchoTests`. Confirm it uses **Swift Testing** (Xcode 26 default) and links the Echo target with `@testable import Echo`.
- [ ] **Step 2:** Add a smoke test file `EchoTests/SmokeTests.swift`:

```swift
import Testing
@testable import Echo

@Test func appStateStartsIdle() async {
    let state = await AppState()
    await #expect(state.phase == .idle)
}
```

- [ ] **Step 3: Run tests.** `⌘U` (or below). Expected: PASS.

```bash
xcodebuild test -scheme Echo -destination 'platform=macOS' -only-testing:EchoTests/SmokeTests 2>&1 | tail -20
```

- [ ] **Step 4: Commit.**

```bash
git add -A
git commit -m "test: add EchoTests target with Swift Testing smoke test"
```

---

### Task 0.6: TranscriptExporter (TDD)

**Files:**
- Create: `Echo/Export/TranscriptExporter.swift`
- Test: `EchoTests/TranscriptExporterTests.swift`

- [ ] **Step 1: Write the failing test.**

```swift
import Testing
@testable import Echo

@Test func exportsPlainText() {
    let segs = [
        TranscriptSegment(start: 0, end: 2, text: "안녕하세요", channel: .microphone, isFinal: true),
        TranscriptSegment(start: 2, end: 4, text: "반갑습니다", channel: .system, isFinal: true),
    ]
    #expect(TranscriptExporter.export(segs, as: .txt) == "안녕하세요\n반갑습니다")
}

@Test func exportsSRTWithTimecodes() {
    let segs = [TranscriptSegment(start: 1.5, end: 3.25, text: "테스트", isFinal: true)]
    let expected = "1\n00:00:01,500 --> 00:00:03,250\n테스트\n"
    #expect(TranscriptExporter.export(segs, as: .srt) == expected)
}

@Test func exportsMarkdownWithSpeaker() {
    let segs = [TranscriptSegment(start: 5, end: 7, text: "내용", channel: .microphone, isFinal: true)]
    #expect(TranscriptExporter.export(segs, as: .markdown) == "**[00:00:05] 나**\n\n내용")
}
```

- [ ] **Step 2: Run to verify it fails.**

```bash
xcodebuild test -scheme Echo -destination 'platform=macOS' -only-testing:EchoTests/TranscriptExporterTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'TranscriptExporter' in scope`.

- [ ] **Step 3: Implement.**

```swift
import Foundation

enum TranscriptFormat: String, CaseIterable { case txt, markdown, srt
    var fileExtension: String { self == .markdown ? "md" : rawValue }
}

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

    private static func srt(_ t: TimeInterval) -> String {
        let ms = Int((t * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d",
                      ms / 3_600_000, (ms % 3_600_000) / 60_000, (ms % 60_000) / 1000, ms % 1000)
    }
}
```

- [ ] **Step 4: Run to verify it passes.** Same command as Step 2. Expected: PASS (3 tests).
- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat: TranscriptExporter (txt/md/srt) with TDD"
```

---

### Task 0.7: TranscriptMerger (TDD)

**Files:**
- Create: `Echo/Transcription/TranscriptMerger.swift`
- Test: `EchoTests/TranscriptMergerTests.swift`

- [ ] **Step 1: Write the failing test.**

```swift
import Testing
@testable import Echo

@Test func mergesChannelsByStartTime() {
    let mic = [
        TranscriptSegment(start: 0, end: 1, text: "나1", channel: .microphone, isFinal: true),
        TranscriptSegment(start: 4, end: 5, text: "나2", channel: .microphone, isFinal: true),
    ]
    let sys = [
        TranscriptSegment(start: 2, end: 3, text: "상대1", channel: .system, isFinal: true),
    ]
    let merged = TranscriptMerger.merge([mic, sys])
    #expect(merged.map(\.text) == ["나1", "상대1", "나2"])
}
```

- [ ] **Step 2: Run to verify it fails.**

```bash
xcodebuild test -scheme Echo -destination 'platform=macOS' -only-testing:EchoTests/TranscriptMergerTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'TranscriptMerger'`.

- [ ] **Step 3: Implement.**

```swift
import Foundation

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
```

- [ ] **Step 4: Run to verify it passes.** Same command. Expected: PASS.
- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat: TranscriptMerger by start time with TDD"
```

---

### Task 0.8: AudioFormat characterization tests

**Files:**
- Modify (if a bug is found): `Echo/Capture/AudioFormat.swift`
- Test: `EchoTests/AudioFormatTests.swift`

- [ ] **Step 1: Write the tests** (AudioFormat already exists; assert known behavior).

```swift
import Testing
import AVFoundation
@testable import Echo

private func buffer(_ samples: [[Float]], sampleRate: Double) -> AVAudioPCMBuffer {
    let channels = AVAudioChannelCount(samples.count)
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                               channels: channels, interleaved: false)!
    let frames = AVAudioFrameCount(samples[0].count)
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buf.frameLength = frames
    for c in 0..<samples.count {
        for i in 0..<samples[c].count { buf.floatChannelData![c][i] = samples[c][i] }
    }
    return buf
}

@Test func downmixesStereoToMonoAverage() {
    // 16kHz already → no resample, just downmix average of L/R.
    let buf = buffer([[0.0, 1.0], [1.0, 1.0]], sampleRate: 16_000)
    let out = AudioFormat.toWhisperSamples(buf)
    #expect(out.count == 2)
    #expect(abs(out[0] - 0.5) < 1e-6)   // (0+1)/2
    #expect(abs(out[1] - 1.0) < 1e-6)   // (1+1)/2
}

@Test func resamplesDownTo16k() {
    // 32kHz mono, 100 frames → ~50 frames at 16kHz.
    let mono = (0..<100).map { Float($0) / 100 }
    let out = AudioFormat.toWhisperSamples(buffer([mono], sampleRate: 32_000))
    #expect(out.count == 50)
    #expect(abs(out.first! - 0.0) < 1e-6)
}
```

- [ ] **Step 2: Run.**

```bash
xcodebuild test -scheme Echo -destination 'platform=macOS' -only-testing:EchoTests/AudioFormatTests 2>&1 | tail -25
```

Expected: PASS. If `resamplesDownTo16k` returns 49/51 due to rounding at the boundary, adjust the assertion to `#expect((49...50).contains(out.count))` and note it — the linear-interpolation count is `Int(input.count * dst/src)`.

- [ ] **Step 3: Commit.**

```bash
git add -A
git commit -m "test: AudioFormat downmix + resample characterization tests"
```

---

### Task 0.9: Model helper tests

**Files:** Test: `EchoTests/ModelTests.swift`

- [ ] **Step 1: Write the tests.**

```swift
import Testing
@testable import Echo

@Test func timecodeFormatsHMS() {
    #expect(TranscriptSegment(start: 5, end: 6, text: "x").timecode == "00:00:05")
    #expect(TranscriptSegment(start: 3661, end: 3662, text: "x").timecode == "01:01:01")
}

@Test func speakerLabelsByChannel() {
    #expect(TranscriptSegment(start: 0, end: 1, text: "x", channel: .microphone).speakerLabel == "나")
    #expect(TranscriptSegment(start: 0, end: 1, text: "x", channel: .system).speakerLabel == "상대")
    #expect(TranscriptSegment(start: 0, end: 1, text: "x", channel: .mixed).speakerLabel == "")
}

@Test func recordingPlainTextJoinsSegments() {
    let rec = Recording(title: "t", segments: [
        TranscriptSegment(start: 0, end: 1, text: "a"),
        TranscriptSegment(start: 1, end: 2, text: "b"),
    ])
    #expect(rec.plainText == "a\nb")
}
```

- [ ] **Step 2: Run.** `-only-testing:EchoTests/ModelTests`. Expected: PASS.
- [ ] **Step 3: Commit.**

```bash
git add -A
git commit -m "test: model helper tests (timecode, speaker, plainText)"
```

---

### Task 0.10: Wire file → large-v3 transcript (end-to-end)

**Files:** Modify `Echo/Views/RootView.swift` (add a file importer + button).

- [ ] **Step 1:** Replace `EmptyStateView` in `Echo/Views/RootView.swift` with a version that opens a file and calls `state.transcribeFile`:

```swift
struct EmptyStateView: View {
    @Environment(AppState.self) private var state
    @State private var importing = false

    var body: some View {
        ContentUnavailableView {
            Label("녹음을 시작하세요", systemImage: "mic")
        } description: {
            Text("시스템 사운드와 마이크를 함께 녹음하고, 정지하면 large-v3로 전사합니다.")
        } actions: {
            Button("오디오 파일 전사…") { importing = true }
                .buttonStyle(.borderedProminent)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result {
                Task { await state.transcribeFile(url) }
            }
        }
    }
}
```

Add `import UniformTypeIdentifiers` at the top of the file (for `.audio`).

- [ ] **Step 2:** The `processing` overlay is already implemented in `DetailContentRouter` (scaffold, post-review) — it shows `ProgressView("large-v3로 전사 중…")` for `.processing`. Just verify it renders during transcription; no code change needed here.

- [ ] **Step 3: ▶︎ Run & verify (end-to-end, the key Phase 0 gate).**
  - ⌘R. Click "오디오 파일 전사…", pick a short (~10s) Korean audio file (m4a/wav).
  - First run downloads the large-v3 CoreML model (one-time, several GB) — expect a delay.
  - Expected: a `RecordingDetailView` appears with Korean transcript rows; the new recording shows in the history sidebar; `transcriptionModel == "openai_whisper-large-v3-v20240930"`.
  - Record the observed transcript text in this file as evidence.

- [ ] **Step 4: Commit.**

```bash
git add -A
git commit -m "feat: file → large-v3 (ko) transcript end-to-end"
```

---

### Task 0.11: Phase 0 Definition of Done

- [ ] App builds and launches.
- [ ] `xcodebuild test -scheme Echo -destination 'platform=macOS'` → all tests PASS (paste tail output here).
- [ ] File → large-v3 Korean transcript works end-to-end (evidence pasted in Task 0.10).
- [ ] Self-check `RootView`/`EmptyStateView` against swiftui-expert-skill Correctness Checklist (`@State private`, `@Bindable`, ForEach identity, `#available` gating).
- [ ] Merge: `git checkout main && git merge --ff-only phase/0-foundation`.
- [ ] Check the Phase 0 box in `2026-06-01-echo-master.md`.

**Next:** `2026-06-01-echo-phase1-mic.md`.
