# Echo Phase 2 — System Audio Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Read the master file first. Branch: `git checkout -b phase/2-system-audio`. This is the gnarliest dependency — build and verify it in isolation.

**Goal:** Capture all system sound via a Core Audio process tap (no virtual device), running simultaneously with the Phase 1 mic, written to a separate `system.caf` track, and batch-transcribed with the mic as two channels merged into one transcript.

**Architecture:** `SystemAudioCapture` creates a global process tap (excluding Echo itself), wraps it in a private aggregate device, reads the runtime ASBD, and emits `AVAudioPCMBuffer`s from the IO block to `onBuffer`. `RecordingCoordinator` already routes that to a `system.caf` `TrackWriter` and to the (Phase 3) live stream. Conversion to 16k mono happens off the IO thread.

**Tech Stack:** CoreAudio (CATapDescription, AudioHardware* process-tap APIs), AVFoundation.

**References:** Apple "Capturing system audio with Core Audio taps"; `insidegui/AudioCap` (macOS 14.4+). **API-verification rule applies** — confirm every Core Audio symbol/signature against Xcode 26 headers; fix and note divergences.

---

### Task 2.1: Permission plumbing

**Files:** Confirm `NSAudioCaptureUsageDescription` is in the target Info (added Phase 0 Task 0.3).

- [ ] **Step 1:** Verify the key exists. There is **no public pre-check API**; the prompt fires on first capture. Add a user-facing note in `SettingsInspector` footer (optional) that system-audio recording needs permission on first use.
- [ ] **Step 2: Commit** if Info changed. `git commit -am "chore: confirm system-audio usage string"`

---

### Task 2.2: Implement the process tap

**Files:** Modify `Echo/Capture/SystemAudioCapture.swift`.

- [ ] **Step 1: Implement `start()`** with the documented sequence. (Concrete code below; verify symbol names against Xcode 26.)

```swift
import CoreAudio
import AVFoundation

func start() async throws {
    // 1) 전체 시스템 탭, 자기 자신 제외
    let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
    desc.uuid = UUID()
    desc.muteBehavior = .unmuted

    var tap = AudioObjectID(kAudioObjectUnknown)
    var status = AudioHardwareCreateProcessTap(desc, &tap)
    guard status == noErr else { throw TranscriptionError.engineUnavailable("ProcessTap 생성 실패: \(status)") }
    self.tapID = tap

    // 2) 탭을 담는 비공개 애그리게이트 장치
    let aggUID = UUID().uuidString
    let aggDict: [String: Any] = [
        kAudioAggregateDeviceNameKey as String: "Echo-SystemTap",
        kAudioAggregateDeviceUIDKey as String: aggUID,
        kAudioAggregateDeviceIsPrivateKey as String: true,
        kAudioAggregateDeviceIsStackedKey as String: false,
        kAudioAggregateDeviceTapAutoStartKey as String: true,
        kAudioAggregateDeviceTapListKey as String: [
            [kAudioSubTapUIDKey as String: desc.uuid.uuidString]
        ],
    ]
    var agg = AudioObjectID(kAudioObjectUnknown)
    status = AudioHardwareCreateAggregateDevice(aggDict as CFDictionary, &agg)
    guard status == noErr else { throw TranscriptionError.engineUnavailable("Aggregate 생성 실패: \(status)") }
    self.aggregateID = agg

    // 3) 런타임 ASBD 읽기 (48k 스테레오 가정 금지)
    var asbd = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    status = AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, &asbd)
    guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
        throw TranscriptionError.engineUnavailable("탭 포맷 읽기 실패: \(status)")
    }

    // 4) IO 블록 등록 — 콜백 안에서는 복사/전달만
    let onBuffer = self.onBuffer
    status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, agg, nil) {
        _, inInputData, _, _, _ in
        guard let onBuffer,
              let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         bufferListNoCopy: inInputData,
                                         deallocator: nil) else { return }
        onBuffer(buf, AVAudioTime(hostTime: mach_absolute_time()))
    }
    guard status == noErr, let ioProcID else {
        throw TranscriptionError.engineUnavailable("IOProc 생성 실패: \(status)")
    }
    status = AudioDeviceStart(agg, ioProcID)
    guard status == noErr else { throw TranscriptionError.engineUnavailable("AudioDeviceStart 실패: \(status)") }
}
```

(`stop()` from the scaffold already tears down IOProc → aggregate → tap in order.)

- [ ] **Step 2:** If any symbol/signature is rejected by the compiler, consult `insidegui/AudioCap` and Xcode 26 CoreAudio headers; correct and **note the exact divergence here** (e.g. `bufferListNoCopy` availability, `CATapDescription` initializer name).

- [ ] **Step 3: ▶︎ Run & verify (isolation harness):** temporarily wire a debug button that creates `SystemAudioCapture`, sets `onBuffer` to print `LevelMeter.rms(AudioFormat.toWhisperSamples(buf))`, starts it, then play any audio (YouTube/music). Expected: the system-audio permission prompt fires once; console prints non-zero RMS that tracks the playing audio; **no purple? — note: the purple system-audio privacy indicator WILL appear (verified), this is expected.** Remove harness after.

- [ ] **Step 4: Commit.** `git commit -am "feat: system audio capture via Core Audio process tap"`

---

### Task 2.3: Simultaneous mic + system into separate tracks

**Files:** No new code — `RecordingCoordinator.start(source:into:)` already creates both `MicrophoneCapture` and `SystemAudioCapture` when `source.microphone && source.systemAudio` and writes `mic.caf` + `system.caf`.

- [ ] **Step 1: ▶︎ Run & verify:** set source = mic + system (default `.meeting`). Record while playing Korean audio AND speaking into the mic for ~15s. Stop. Expected: session directory contains both `mic.caf` and `system.caf`, each non-empty (check `AVAudioFile.length > 0` or file size).
- [ ] **Step 2:** Confirm `AppState.stopRecording` (Phase 1) transcribes BOTH tracks and `TranscriptMerger.merge` interleaves them: transcript shows "나" (mic) and "상대" (system) rows ordered by time. Paste evidence.
- [ ] **Step 3: Commit** any fixes. `git commit -am "feat: simultaneous mic+system separate-track recording"`

---

### Task 2.4: Robustness — format & clock

**Files:** Modify `Echo/Capture/SystemAudioCapture.swift` / `AudioFormat.swift` if needed.

- [ ] **Step 1:** Confirm conversion happens off the IO thread: the `onBuffer` consumer (TrackWriter/level) must not call `AudioFormat.toWhisperSamples` inside the IO block. TrackWriter uses its own serial queue (OK). The level update must hop: `Task { @MainActor in state.currentLevel = ... }` — verify it's not computing on the IO thread synchronously; if it is, move the `toWhisperSamples` call into the MainActor hop or a background queue.
- [ ] **Step 2:** Add a guard: if `tapID`/`aggregateID` creation fails, surface a friendly `phase = .failed("시스템 오디오 권한 또는 장치 생성 실패")` rather than crashing.
- [ ] **Step 3: Commit.** `git commit -am "fix: keep audio conversion off the realtime IO thread"`

---

### Task 2.5: Phase 2 Definition of Done

- [ ] System audio captured with no virtual device; permission prompt observed once.
- [ ] mic + system record simultaneously to separate tracks; both non-empty.
- [ ] Merged transcript shows both speakers ("나"/"상대") ordered by time (evidence pasted).
- [ ] All Phase 0/1 unit tests still PASS.
- [ ] Any Core Audio API divergences from this plan are noted in Task 2.2 Step 2.
- [ ] Merge `phase/2-system-audio` → `main`; check the Phase 2 box in the master file.

**Next:** `2026-06-01-echo-phase3-live-preview.md`.
