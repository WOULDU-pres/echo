# Echo Phase 5 — Polish, Persistence, Export, Packaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Read the master file first. Branch: `git checkout -b phase/5-polish`. This is the last phase; finishing it satisfies the whole-project Definition of Done in the master file.

**Goal:** Make Echo a finished personal tool: persistent history, editable + exportable transcripts (txt/md/srt), a playback scrubber synced to the transcript, a MenuBarExtra quick-capture with a global hotkey, accessibility passes, a thermal load test, and a signed local build.

**Tech Stack:** Codable persistence, SwiftUI `.fileExporter`/`ShareLink`, AVAudioPlayer, MenuBarExtra, a global hotkey, Swift Testing.

---

### Task 5.1: RecordingStore persistence (TDD)

**Files:**
- Create: `Echo/Storage/RecordingStore.swift`
- Test: `EchoTests/RecordingStoreTests.swift`

- [ ] **Step 1: Write the failing test** (save → load round-trip).

```swift
import Testing
import Foundation
@testable import Echo

@Test func storeRoundTripsRecordings() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("echo-store-\(UUID())")
    let store = RecordingStore(directory: dir)
    let rec = Recording(title: "t", segments: [TranscriptSegment(start: 0, end: 1, text: "안녕")])
    try store.save([rec])
    let loaded = try store.load()
    #expect(loaded.count == 1)
    #expect(loaded[0].segments.first?.text == "안녕")
    try? FileManager.default.removeItem(at: dir)
}
```

- [ ] **Step 2: Run, verify FAIL** (`cannot find 'RecordingStore'`).

```bash
xcodebuild test -scheme Echo -destination 'platform=macOS' -only-testing:EchoTests/RecordingStoreTests 2>&1 | tail -20
```

- [ ] **Step 3: Implement.**

```swift
import Foundation

struct RecordingStore {
    let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("recordings.json") }

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Echo", isDirectory: true)) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func save(_ recordings: [Recording]) throws {
        let data = try JSONEncoder().encode(recordings)
        try data.write(to: fileURL, options: .atomic)
    }

    func load() throws -> [Recording] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([Recording].self, from: try Data(contentsOf: fileURL))
    }
}
```

(Note: `Recording.audioTracks` is `[AudioChannel: URL]`; `AudioChannel` is `Codable` with `String` raw values, so JSON encodes it as an object. Verified by the round-trip test.)

- [ ] **Step 4: Run, verify PASS.**
- [x] **Step 5:** DONE — `AppState.init` loads via `store.load()`, `persist()` after stop/transcribe/edit/delete; `private let store = RecordingStore()`. Wire into `AppState`: load on init (`recordings = (try? store.load()) ?? []`), save after each `stopRecording`/`transcribeFile`/edit. Add `private let store = RecordingStore()`.
- [x] **Step 6: Commit.** RecordingStore + round-trip test pre-existed; AppState wiring committed in 5efcdaf.

---

### Task 5.2: Transcript editing

**Files:** Modify `Echo/Views/RootView.swift` (`RecordingDetailView`).

- [x] **Step 1:** `EditableTranscriptRow` (TextField, axis:.vertical) commits via `AppState.updateSegmentText` → `persist()`; live `TranscriptRow` stays read-only. (commit 2117587). Make each `TranscriptRow` editable for saved recordings (tap to edit text via a `TextField` bound to the segment). Persist edits through `AppState` → `store.save`. Keep the live preview read-only.
- [ ] **Step 2: ▶︎ Run & verify (HUMAN):** edit a transcript line; relaunch the app; the edit persists.
- [x] **Step 3: Commit.** 2117587.

---

### Task 5.3: Export (txt/md/srt)

**Files:** Modify `Echo/Views/RootView.swift` (toolbar) — uses `TranscriptExporter` (Phase 0).

- [x] **Step 1:** Toolbar export `Menu` over `TranscriptFormat.allCases` → `TranscriptDocument`(FileDocument) via `.fileExporter` with correct `contentType`/extension (commit 2117587). Add a toolbar export menu to `RecordingDetailView`:

```swift
.toolbar {
    Menu("내보내기") {
        ForEach(TranscriptFormat.allCases, id: \.self) { fmt in
            Button(fmt.rawValue.uppercased()) { exportTranscript(recording, as: fmt) }
        }
    }
}
```

`exportTranscript` writes `TranscriptExporter.export(recording.segments, as: fmt)` via `.fileExporter` (or `NSSavePanel`) with the right extension (`fmt.fileExtension`). Optionally add a `ShareLink`.

- [ ] **Step 2: ▶︎ Run & verify (HUMAN):** export a recording to each format; open the files and confirm content (srt has timecodes, md has speaker headers, txt is plain).
- [x] **Step 3: Commit.** 2117587.

---

### Task 5.4: Playback scrubber synced to transcript

**Files:** Create `Echo/Views/PlaybackBar.swift`; modify `RecordingDetailView`.

- [x] **Step 1:** `PlaybackController`(@Observable @MainActor, AVAudioPlayer + 0.1s ticker) + `PlaybackBar`(play/pause, slider, time); `RecordingDetailView` highlights active row from player time and seeks on row/timecode tap (commit 2117587). Add an `AVAudioPlayer`-backed playback bar over the recording's mixed/mic track: play/pause, a scrubber, and current-time highlight of the active `TranscriptRow` (compare player time to `segment.start...end`). Tapping a row seeks the player.
- [ ] **Step 2: ▶︎ Run & verify (HUMAN):** play a saved recording; the active transcript row highlights and follows playback; tapping a row seeks.
- [x] **Step 3: Commit.** 2117587.

---

### Task 5.5: MenuBarExtra quick capture + global hotkey

**Files:** Modify `Echo/App/EchoApp.swift` (`MenuBarContent`).

- [x] **Step 1:** `MenuBarContent` = record/stop + ⌘⇧R + last-recording + open main window (`openWindow(id:"main")`) + quit; `GlobalHotKey` uses Carbon `RegisterEventHotKey` (⌃⌥⌘R) app-wide (commit 83a1196). Flesh out `MenuBarContent`: quick Record/Stop, last-recording shortcut, "open main window". Register a global hotkey (e.g. via `KeyboardShortcut` on a `MenuBarExtra` command, or a small `NSEvent` global monitor / `MASShortcut`-style approach) to toggle recording from anywhere.
- [ ] **Step 2: ▶︎ Run & verify (HUMAN):** hotkey starts/stops recording while another app is focused; menu bar reflects state.
- [x] **Step 3: Commit.** 83a1196.

---

### Task 5.6: Accessibility + design polish pass

**Files:** all views.

- [ ] **Step 1:** Re-run the swiftui-expert-skill Correctness Checklist over the final views. Verify: VoiceOver labels on all custom controls, Dynamic Type doesn't clip, Reduce Motion/Reduce Transparency honored (Liquid Glass falls back to material), focus order sane.
- [x] **Step 2:** DONE — `GlassContainer` (#available(macOS 26) `.glassEffect` + material/thickMaterial fallback honoring Reduce Transparency) on the control bar; Record button `.glassProminent` on macOS 26 (commit 605a515). Apply Liquid Glass where intended now that everything works, gated with `#available(macOS 26, *)` + material fallback (per `references/liquid-glass.md`): `.glassEffect` on the control bar container, `.buttonStyle(.glassProminent)` on Record.
- [ ] **Step 3: ▶︎ Run & verify:** VoiceOver pass; toggle Reduce Transparency → solid fallback; looks clean in light/dark.
- [x] **Step 4: Commit.** 605a515 + bf4f7ba.

---

### Task 5.7: Thermal / long-session load test

- [ ] **Step 1: ▶︎ Run & verify:** record a multi-hour (or your realistic max) session with mic + system on the actual M4 Air. Watch for: live preview keeping up, capture not dropping, memory stable, and the post-stop large-v3 batch completing. Record observed wall-clock for the batch vs recording length.
- [ ] **Step 2:** If live preview falls behind or thermals spike, reduce live preview frequency or disable it for very long sessions (the batch result is authoritative regardless). Note findings.
- [ ] **Step 3: Commit** any tuning. `git commit -am "perf: long-session tuning from thermal load test"`

---

### Task 5.8: Packaging (personal)

- [ ] **Step 1:** Product ▸ Archive. Export with your free Apple Development identity (no notarization needed for personal use). Confirm the exported `Echo.app` launches on the same machine and TCC grants persist (stable bundle ID + identity).
- [ ] **Step 2:** Update `README.md` "상태" to "v1 complete (personal build)". Update `PLAN.md` checkboxes.
- [ ] **Step 3: Commit + tag.** `git commit -am "chore: v1 personal packaging" && git tag v1.0`

---

### Task 5.9: Whole-project Definition of Done

Go through the master file's **Definition of Done (whole project)** checklist and tick every box, pasting evidence where it says "evidence". Then:

- [ ] Merge `phase/5-polish` → `main`; check the Phase 5 box in the master file.
- [ ] All six phase boxes in `2026-06-01-echo-master.md` are checked → development complete.
