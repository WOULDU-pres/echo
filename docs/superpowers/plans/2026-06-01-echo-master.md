# Echo Implementation Plan — Master

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement the per-phase plans task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This master file is the **spine** — it never gets executed directly; it routes you to the next phase plan.

**Goal:** Ship a native macOS app that records system audio + microphone simultaneously (optional screen video), shows an optional live Korean transcript preview, and produces an authoritative full-Whisper-large-v3 transcript after recording — with a clean, minimal native UI.

**Architecture:** Single Swift 6 / SwiftUI app. `AppState` (@MainActor @Observable) is the only UI-facing state. Capture sources (`MicrophoneCapture`, `SystemAudioCapture`, `ScreenCapture`) feed a `RecordingCoordinator` that writes per-channel track files and forks buffers to an optional live transcriber. The **authoritative transcript is always a post-stop batch pass on full large-v3**; the live preview (Apple SpeechTranscriber) is non-authoritative and overwritten on stop.

**Tech Stack:** Swift 6.3, SwiftUI (macOS 26 Liquid Glass), WhisperKit (CoreML/ANE, large-v3), Apple SpeechAnalyzer/SpeechTranscriber (live preview), Core Audio process taps (system audio), AVAudioEngine (mic), ScreenCaptureKit (screen video), Swift Testing (unit tests).

---

## How to resume (read this first, every session)

1. Open this master file. Find the first phase in **Phase Index** whose box is unchecked.
2. Open that phase's plan file under `docs/superpowers/plans/`.
3. Inside it, find the first unchecked task/step and continue from there.
4. After finishing a phase (all its tasks checked + its Definition of Done met), check its box here and move to the next.

> The scaffold under `Echo/` already exists (created during planning). Phase 0 imports it into an Xcode project rather than re-typing it. Treat existing scaffold files as the starting point; the per-phase plans say exactly what to add/replace.

---

## Phase Index

- [x] **Phase 0 — Foundation** → `2026-06-01-echo-phase0-foundation.md`
  Xcode project + git + WhisperKit dep (0.18.0, large-v3) + design system + **file → large-v3 transcript** end-to-end + unit-test target. **Code complete + build green + 16 unit tests pass.** Real WhisperKit transcription path compiles (`canImport(WhisperKit)` true); first-run model download + Korean accuracy = HUMAN.
- [x] **Phase 1 — Microphone recording** → `2026-06-01-echo-phase1-mic.md`
  AVAudioEngine mic → track file + floating glass control bar (Record/Stop, REC timer, level meter) + auto batch transcribe on stop. **Code complete + build green.** Live mic capture + TCC mic grant + level meter behavior = HUMAN (run & verify).
- [x] **Phase 2 — System audio capture** → `2026-06-01-echo-phase2-system-audio.md`
  Core Audio process tap (system sound) simultaneous with mic, separate track, both batch-transcribed. **Code complete + build green** against MacOSX26.5 CoreAudio headers (CATapDescription / AudioHardwareCreateProcessTap / Aggregate device). Live tap + system-audio TCC prompt + "나/상대" merged transcript = HUMAN.
- [x] **Phase 3 — Live preview + 2-mode view** → `2026-06-01-echo-phase3-live-preview.md`
  Apple SpeechTranscriber (ko_KR) live preview, non-authoritative, Structured ↔ Zen switcher, overwritten by large-v3 on stop. **Code complete + build green** against the macOS 26 Speech swiftinterface (SpeechAnalyzer/SpeechTranscriber, gated `#available(macOS 26)`). ko_KR asset download + live preview quality + gated auto-scroll feel = HUMAN.
- [x] **Phase 4 — Optional screen video** → `2026-06-01-echo-phase4-screen.md`
  ScreenCaptureKit (SCStream, captureMicrophone) + SCRecordingOutput; audio fanned to transcription. **Code complete + build green**; live screen-capture + TCC + thermal verify = HUMAN (Tasks 4.4 Step 3, 4.5). Content-picker UI affordance pending.
- [x] **Phase 5 — Polish, persistence, export, packaging** → `2026-06-01-echo-phase5-polish.md`
  Persistence wired, transcript edit + export (txt/md/srt), playback scrubber, MenuBarExtra + Carbon global hotkey, gated Liquid Glass. **Code complete + build green + 16 unit tests pass**; runtime ▶︎ steps (edit-persist relaunch, export-open, playback follow, hotkey while another app focused), thermal load test (5.7), and signed Archive packaging (5.8) = HUMAN.

---

## Global Conventions (apply to every task)

### Testing strategy (honest split)
- **Pure logic → TDD with Swift Testing** (`import Testing`, `@Test`, `#expect`). Units: `AudioFormat` (downmix/resample), `TranscriptExporter` (txt/md/srt), `TranscriptMerger` (interleave channels by time), model helpers (`timecode`, `plainText`). Write the failing test first, watch it fail, implement, watch it pass.
- **Framework-bound code → run-and-verify** (Core Audio taps, ScreenCaptureKit, WhisperKit, SpeechAnalyzer, SwiftUI views). These cannot be meaningfully unit-tested without hardware/ANE; each such task has explicit **manual acceptance criteria** and a **▶︎ Run & verify** step instead of a unit test. Do not fake unit tests for these.
- Never claim a build/run passed without actually running it and pasting the observed result.

### API-verification rule (first-gen macOS 26 APIs)
Some calls (Liquid Glass modifiers, SpeechAnalyzer/SpeechTranscriber, Core Audio tap structs) are first-generation. The plan gives the best-known concrete code. If the compiler rejects a signature, **consult the swiftui-expert-skill** (`.agents/skills/swiftui-expert-skill/references/`) and current Xcode 26 docs, fix the signature, and note the correction in the phase file. This is expected, not a failure.

### Quality gate — swiftui-expert-skill
The project has the `swiftui-expert-skill` installed (project-local). Before committing any SwiftUI view task, self-check against its **Correctness Checklist** (`.agents/skills/swiftui-expert-skill/SKILL.md`): `@State` private; `@Bindable` for injected observables; `ForEach` stable identity (never `.indices`); constant view count per `ForEach`; `.animation(_:value:)` always has `value`; macOS-26 APIs gated with `#available` + fallback; previews use self-contained mock data.

### Commits
- One commit per completed task (the last step of each task is the commit).
- Conventional prefixes: `feat:`, `test:`, `fix:`, `chore:`, `docs:`.
- Commit message bodies end with the project's Co-Authored-By trailer if configured.

### Branching
- Repo is initialized in Phase 0 Task 0.1. Default branch `main`.
- Each phase on its own branch `phase/N-name`, merged to `main` when the phase's Definition of Done passes. (Solo/personal: fast-forward merges are fine.)

---

## File Structure (target)

```
echo/
├── Echo.xcodeproj/                  (created Phase 0, gitignored DerivedData)
├── Echo/                            (app sources — scaffold already present)
│   ├── App/  Models/  Capture/  Transcription/  DesignSystem/  Views/  Resources/
├── EchoTests/                       (created Phase 0)
│   ├── AudioFormatTests.swift
│   ├── TranscriptExporterTests.swift
│   ├── TranscriptMergerTests.swift
│   └── ModelTests.swift
├── docs/  design/  PLAN.md  README.md  .gitignore   (already present)
```

New source files introduced by later phases (each created in its phase):
- `Echo/Export/TranscriptExporter.swift` (Phase 0)
- `Echo/Transcription/TranscriptMerger.swift` (Phase 0)
- `Echo/Capture/LevelMeter.swift` (Phase 1)
- `Echo/Storage/RecordingStore.swift` (Phase 5)

---

## Definition of Done (whole project)

> Legend: [x] = verified at compile/test level by the autonomous build. [ ] (HUMAN) = requires real hardware, TCC grants, mic/audio, or signing — cannot be verified headlessly.

- [ ] (HUMAN) App launches on macOS 26.x (M4) from a signed local build. *(builds green unsigned; signed Archive launch = human)*
- [ ] (HUMAN) Records mic + system audio simultaneously into separate tracks, no virtual audio device. *(capture code compiles against CoreAudio headers; live capture = human)*
- [ ] (HUMAN) Optional screen video records with audio. *(ScreenCaptureKit code compiles; live record + TCC = human)*
- [ ] (HUMAN) Optional live Korean preview shows during recording (Structured & Zen modes), clearly non-authoritative. *(UI + SpeechTranscriber bridge compile; live ko preview = human)*
- [ ] (HUMAN) On stop, produces a full large-v3 (ko) transcript that replaces the preview and is saved. *(batch pipeline + merge + persist compile; large-v3 download + Korean run = human)*
- [x] Transcript is viewable, editable, and exportable to txt/md/srt. *(EditableTranscriptRow + fileExporter + TranscriptExporter; exporter unit-tested txt/md/srt)*
- [x] History persists across launches. *(RecordingStore JSON load/save wired in AppState; round-trip unit-tested)*
- [x] All Swift Testing unit tests pass (16/16); pure-logic acceptance verified. Framework-bound acceptance criteria are recorded as HUMAN per phase.
- [x] Self-checked clean against the swiftui-expert-skill Correctness Checklist (final verification stage).
- [ ] (HUMAN) A multi-hour session has been load-tested for thermals on the target Air.

---

## Decisions locked (see PLAN.md §확정된 결정)
Model = full large-v3 (`openai_whisper-large-v3-v20240930`), never turbo. Live preview = Apple SpeechTranscriber (ko_KR), throwaway. Min macOS 15.0. App Sandbox OFF (personal). Separate tracks. WhisperKit engine. Free Apple ID signing.
