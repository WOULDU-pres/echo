# Echo P0 Implementation Plan — Cancel + Add-File Button

> **다음 세션 실행용.** 위에서부터 순서대로. 각 태스크: 구현 → 빌드 그린 → 테스트 → 재배포 → 커밋.
> 빌드: `xcodebuild -project Echo.xcodeproj -scheme Echo -configuration Debug -derivedDataPath build build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES`
> 테스트: `xcodebuild -project Echo.xcodeproj -scheme Echo -destination 'platform=macOS,arch=arm64' test CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-`

**Goal:** 전사 진행/대기 작업을 취소할 수 있고, 녹음이 있어도 항상 '오디오 추가' 버튼으로 파일을 넣을 수 있다.

---

### Task 1: 전사 취소 (AppState) — ★사용자요청

**Files:** `Echo/App/AppState.swift`

- [ ] **Step 1:** `JobStatus`에 cancelled 추가(있어도 무방, UI에선 제거로 처리).
  현재: `enum JobStatus { case pending; case processing; case failed(String) }`
  → 취소는 큐에서 제거로 처리하므로 새 case 불필요. 대신 cancel 플래그 집합 사용.

- [ ] **Step 2:** AppState에 취소 상태 + 메서드 추가. `worker`/`jobs` 근처에:

```swift
/// 취소 요청된 작업 ID(진행 중 패스는 중단 불가 → 반환 후 결과 폐기).
private var cancelledIDs: Set<UUID> = []

/// 작업 1건 취소: 대기면 즉시 제거, 진행 중이면 완료 후 폐기.
func cancelJob(_ id: UUID) {
    guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
    if jobs[i].status == .processing {
        cancelledIDs.insert(id)          // 진행 중 → 반환 시 폐기
    } else {
        jobs.remove(at: i)               // 대기/실패 → 즉시 제거
    }
}

/// 전체 취소: 대기 모두 제거 + 현재 진행 중 폐기 + 워커 종료.
func cancelAllJobs() {
    for j in jobs where j.status == .processing { cancelledIDs.insert(j.id) }
    jobs.removeAll { $0.status != .processing }
    worker?.cancel()
}
```

- [ ] **Step 3:** `process(_:)` 안에서 각 `transcribe` await **이후** 취소 확인. file 케이스:

```swift
let segs0 = try await batchTranscriber.transcribe(url, language: language)
if cancelledIDs.remove(job.id) != nil { jobs.removeAll { $0.id == job.id }; return }
var segs = segs0
```

recording 케이스의 채널 루프 안에서도 매 채널 후:

```swift
for (channel, url) in tracks {
    if cancelledIDs.contains(job.id) { break }   // 2·3번째 채널 단락
    if var segs = try? await batchTranscriber.transcribe(url, language: language) {
        ...
    }
}
// 루프 후
if cancelledIDs.remove(job.id) != nil { jobs.removeAll { $0.id == job.id }; return }
```

- [ ] **Step 4:** 단위 테스트 — `EchoTests/CancelTests.swift`. mock transcriber(느린)로 enqueue 후 `cancelJob`/`cancelAllJobs` → jobs 비워지고 recordings에 안 들어가는지. (QueueSerializationTests의 SlowMockTranscriber 패턴 재사용)

```swift
@MainActor @Test func cancelAllClearsQueueAndProducesNoRecording() async throws {
    let dir = FileManager.default.temporaryDirectory
    let urls = (0..<4).map { dir.appendingPathComponent("c\($0).wav") }
    for u in urls { FileManager.default.createFile(atPath: u.path, contents: Data([0])) }
    let state = AppState(batchTranscriber: SlowMockTranscriber(), livePreview: nil,
                         diarizer: DiarizationService(),
                         store: RecordingStore(directory: dir.appendingPathComponent("ct-\(UUID())")))
    state.enqueueFiles(urls)
    try? await Task.sleep(nanoseconds: 30_000_000)
    state.cancelAllJobs()
    try? await Task.sleep(nanoseconds: 200_000_000)
    #expect(state.activeJobCount == 0)
}
```
(SlowMockTranscriber를 QueueSerializationTests에서 공유하거나 복제.)

- [ ] **Step 5:** 빌드 + 테스트 그린. 커밋: `feat: 전사 작업 취소(cancelJob/cancelAllJobs)`

---

### Task 2: 취소 버튼 UI (RootView)

**Files:** `Echo/Views/RootView.swift`

- [ ] **Step 1:** `JobRow`에서 processing/pending에 취소 버튼 추가. 현재 failed에만 재시도/닫기 있는 HStack에:

```swift
switch job.status {
case .processing, .pending:
    Button { state.cancelJob(job.id) } label: { Image(systemName: "xmark.circle") }
        .buttonStyle(.plain).foregroundStyle(Theme.Palette.outline)
        .help("취소")
case .failed:
    Button("재시도") { state.retryJob(job.id) }.controlSize(.small)
    Button { state.dismissJob(job.id) } label: { Image(systemName: "xmark") }
        .buttonStyle(.plain).foregroundStyle(Theme.Palette.outline)
}
```

- [ ] **Step 2:** `TranscriptionProgressSheet` footer에 '모두 취소'(activeJobCount > 1):

```swift
HStack {
    if state.activeJobCount > 1 {
        Button("모두 취소", role: .destructive) { state.cancelAllJobs() }
    }
    if state.jobs.contains(where: { if case .failed = $0.status { return true }; return false }) {
        Button("실패 항목 지우기") { state.dismissFailedJobs() }
    }
    Spacer()
    Button("닫기") { onClose() }.keyboardShortcut(.defaultAction)
}
```

- [ ] **Step 3:** 빌드 그린(테스트 무영향). ▶︎ 실행 검증(사람): 큰 파일 여러 개 드롭 → 모달에서 개별/전체 취소되는지. 커밋: `feat: 전사 진행 모달 취소 버튼(개별/전체)`

---

### Task 3: 상시 '오디오 추가' 버튼 (RootView) — ★사용자요청

**Files:** `Echo/Views/RootView.swift`

- [ ] **Step 1:** `RootView`에 상태 + 툴바 버튼 + importer 추가.

```swift
struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false
    @State private var isDropTargeted = false
    @State private var showProgress = false
    @State private var importing = false     // 추가
```

기존 detail `.toolbar` 안(설정 버튼 위)에:

```swift
ToolbarItem(placement: .primaryAction) {
    Button { importing = true } label: { Label("오디오 추가", systemImage: "plus") }
        .help("오디오 파일 추가 (여러 개 가능)")
}
```

`.sheet(isPresented: $showProgress)` 체이닝 근처에:

```swift
.fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
    if case .success(let urls) = result { state.enqueueFiles(urls) }
}
```

- [ ] **Step 2:** 빌드 그린. ▶︎ 실행 검증(사람): 녹음이 있는 상태에서 툴바 '+'로 여러 파일 선택 → 전사 큐에 들어가는지.
- [ ] **Step 3:** 커밋: `feat: 상시 오디오 추가 버튼(툴바)`

---

### Task 4: P0 마무리
- [ ] 전체 빌드 그린 + 단위 테스트 통과(취소 테스트 포함).
- [ ] 앱 재배포(`~/Applications/Echo.app`) + 런치 크래시 없음 확인.
- [ ] `docs/ROADMAP.md`의 P0 3개 박스 체크.
- [ ] 이어서 P1(삭제 확인 → 이름 변경 → 복사 → 메타데이터 → Finder → 빈 녹음 정리) 진행.
