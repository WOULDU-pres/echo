# Echo Phase 3 — Live Preview + 2-Mode View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Read the master file first. Branch: `git checkout -b phase/3-live-preview`.

**Goal:** During recording, show an optional **non-authoritative** live Korean transcript using Apple SpeechTranscriber (ko_KR), switchable between Structured and Zen modes, replaced by the large-v3 batch result on stop.

**Architecture:** `LivePreviewTranscriber` (SpeechAnalyzer + SpeechTranscriber) consumes the mic buffer stream from `RecordingCoordinator.liveBufferStream` and yields `TranscriptSegment`s (isFinal=false) into `AppState.liveSegments`. The existing `LiveTranscriptView` renders Structured/Zen. On stop, Phase 1's batch path overwrites `liveSegments` via the saved recording.

**Tech Stack:** Speech (SpeechAnalyzer/SpeechTranscriber, AssetInventory — macOS 26), AVFoundation, SwiftUI.

**API-verification rule applies** — SpeechAnalyzer/SpeechTranscriber are first-gen macOS 26 APIs; confirm signatures against Xcode 26 docs and correct/note divergences.

---

### Task 3.1: Korean asset availability

**Files:** Modify `Echo/Transcription/LivePreviewTranscriber.swift`.

- [ ] **Step 1: Implement `ensureLanguageAsset`** (download ko_KR model once if needed):

```swift
func ensureLanguageAsset(_ language: String) async throws {
    let locale = Locale(identifier: "ko-KR")
    let supported = await SpeechTranscriber.supportedLocales
    guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
        throw TranscriptionError.engineUnavailable("ko-KR 미지원")
    }
    let installed = await SpeechTranscriber.installedLocales
    if !installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
        if let req = try await AssetInventory.assetInstallationRequest(
            supporting: [SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])]) {
            try await req.downloadAndInstall()
        }
    }
}
```

- [ ] **Step 2:** Surface a one-time UI state. In `AppState`, add `var preparingModel = false`; set it around `ensureLanguageAsset`. (Wire a small "한국어 모델 준비 중…" label in `LiveTranscriptView` when true.)
- [ ] **Step 3: Commit.** `git commit -am "feat: ensure ko_KR SpeechTranscriber asset"`

---

### Task 3.2: Implement the live stream

**Files:** Modify `Echo/Transcription/LivePreviewTranscriber.swift`.

- [ ] **Step 1: Implement `stream(_:language:)`** bridging mic buffers → SpeechAnalyzer results:

```swift
func stream(_ buffers: AsyncStream<AVAudioPCMBuffer>, language: String) -> AsyncStream<TranscriptSegment> {
    AsyncStream { continuation in
        let task = Task {
            do {
                let locale = Locale(identifier: "ko-KR")
                let transcriber = SpeechTranscriber(locale: locale,
                                                    transcriptionOptions: [],
                                                    reportingOptions: [.volatileResults],
                                                    attributeOptions: [.audioTimeRange])
                let analyzer = SpeechAnalyzer(modules: [transcriber])

                let (inputSeq, inputCont) = AsyncStream<AnalyzerInput>.makeStream()
                try await analyzer.start(inputSequence: inputSeq)

                // 마이크 버퍼 → analyzer 입력
                let feeder = Task {
                    for await buf in buffers { inputCont.yield(AnalyzerInput(buffer: buf)) }
                    inputCont.finish()
                }

                // analyzer 결과 → TranscriptSegment
                for try await result in transcriber.results {
                    let range = result.range   // CMTimeRange (audioTimeRange 옵션)
                    let seg = TranscriptSegment(
                        start: range.start.seconds,
                        end: range.end.seconds,
                        text: String(result.text.characters),
                        channel: .microphone,
                        isFinal: result.isFinal)
                    continuation.yield(seg)
                }
                feeder.cancel()
                continuation.finish()
            } catch {
                continuation.finish()
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
```

- [ ] **Step 2:** Fix signature divergences against Xcode 26 (likely candidates: `AnalyzerInput(buffer:)`, `result.range`, `reportingOptions`/`attributeOptions` enum cases, `analyzer.start`/`finalizeAndFinish`). Note corrections here.
- [ ] **Step 3: Commit.** `git commit -am "feat: SpeechTranscriber live stream → segments"`

---

### Task 3.3: Wire live preview into the recording lifecycle

**Files:** Modify `Echo/App/AppState.swift`.

- [ ] **Step 1:** In `startRecording()`, after `coordinator.start` succeeds, subscribe when enabled:

```swift
if livePreviewEnabled, let live = livePreview, let stream = coordinator.liveBufferStream {
    liveTask = Task { [weak self] in
        guard let self else { return }
        try? await live.ensureLanguageAsset(language)
        for await seg in live.stream(stream, language: language) {
            await MainActor.run { self.upsertLive(seg) }
        }
    }
}
```

Add `private var liveTask: Task<Void, Never>?` and an `upsertLive` that replaces the last volatile segment or appends a final one:

```swift
private func upsertLive(_ seg: TranscriptSegment) {
    if let last = liveSegments.last, !last.isFinal {
        liveSegments[liveSegments.count - 1] = seg
    } else {
        liveSegments.append(seg)
    }
}
```

- [ ] **Step 2:** In `stopRecording()`, cancel the live task before batch: `liveTask?.cancel(); liveTask = nil`. The batch path already sets `liveSegments = []` then saves the large-v3 recording (authoritative).
- [ ] **Step 3: Commit.** `git commit -am "feat: wire live preview into record lifecycle"`

---

### Task 3.4: 2-mode view + non-authoritative affordance

**Files:** `Echo/Views/LiveTranscriptView.swift` (mode switcher already present).

- [ ] **Step 1:** Add a clear "미리보기 · 저장 안 됨" badge at the top of `LiveTranscriptView` so the live text reads as non-authoritative:

```swift
Label("실시간 미리보기 · 최종본은 정지 후 large-v3", systemImage: "eye")
    .font(Theme.Font.labelCaps).textCase(.uppercase)
    .foregroundStyle(Theme.Palette.onSurfaceVariant)
    .padding(.horizontal, Theme.Spacing.md)
```

- [ ] **Step 2: ▶︎ Run & verify:** toggle modes via the segmented picker; both Structured and Zen render live segments while recording. Confirm dimmed (isFinal=false) styling.
- [ ] **Step 3: Commit.** `git commit -am "feat: non-authoritative live preview badge + 2-mode verify"`

---

### Task 3.5: Gated auto-scroll (review SHOULD-fix)

**Files:** Modify `Echo/Views/LiveTranscriptView.swift` (`StructuredStreamView`).

- [ ] **Step 1:** Only auto-scroll when the user is near the bottom (don't yank the view while they read up). Use `ScrollPosition` (macOS 15+):

```swift
struct StructuredStreamView: View {
    let segments: [TranscriptSegment]
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var atBottom = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) { ForEach(segments) { TranscriptRow(segment: $0) } }
            .scrollTargetLayout()
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y >= geo.contentSize.height - geo.containerSize.height - 24
        } action: { _, nowAtBottom in atBottom = nowAtBottom }
        .onChange(of: segments.count) { _, _ in
            if atBottom { withAnimation { position.scrollTo(edge: .bottom) } }
        }
    }
}
```

- [ ] **Step 2:** Verify against `.agents/skills/swiftui-expert-skill/references/scroll-patterns.md`; adjust API names if needed (`onScrollGeometryChange` is macOS 15+).
- [ ] **Step 3: ▶︎ Run & verify:** while recording, scroll up — stream keeps appending without yanking; scroll back to bottom — auto-scroll resumes.
- [ ] **Step 4: Commit.** `git commit -am "fix: gated auto-scroll (resume only near bottom)"`

---

### Task 3.6: Phase 3 Definition of Done

- [ ] Live Korean preview appears during recording (both modes); clearly marked non-authoritative.
- [ ] On stop, preview is replaced by the saved large-v3 transcript.
- [ ] ko_KR asset download handled with a one-time "준비 중" state.
- [ ] Auto-scroll no longer yanks when the user scrolls up.
- [ ] SpeechAnalyzer API divergences noted in Tasks 3.1–3.2.
- [ ] Unit tests still PASS; self-check views vs swiftui-expert-skill.
- [ ] Merge `phase/3-live-preview` → `main`; check the Phase 3 box.

**Next:** `2026-06-01-echo-phase4-screen.md`.
