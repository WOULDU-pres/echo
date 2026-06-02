# Echo — 아키텍처

단일 Swift 6 / SwiftUI 네이티브 앱. 하나의 프로세스, 하나의 서명, 하나의 TCC 권한 세트.

---

## 1. 모듈 맵

```
┌────────────────────────────────────────────────────────────┐
│  Views (SwiftUI)                                            │
│  RootView · RecordingControlBar · LiveTranscriptView        │
│  (StructuredStream / ZenCanvas) · HistorySidebar · Settings │
└───────────────▲───────────────────────────┬────────────────┘
                │ @Observable 상태 바인딩      │ 사용자 액션
┌───────────────┴───────────────────────────▼────────────────┐
│  App/AppState  (녹음 상태머신: idle→recording→processing→done) │
└───────┬───────────────────────────┬───────────────┬─────────┘
        │                           │               │
┌───────▼─────────┐   ┌─────────────▼──────┐  ┌──────▼──────────┐
│ Capture          │   │ Transcription       │  │ Storage/Export  │
│ RecordingCoord.  │   │ Transcriber(proto)  │  │ Recording 저장   │
│ ├ MicrophoneCap. │   │ ├ WhisperKitBatch   │  │ txt/md/srt 출력  │
│ ├ SystemAudioCap.│   │ │   (large-v3, 저장본)│  └─────────────────┘
│ ├ ScreenCapture  │   │ └ LivePreview       │
│ └ AudioFormat    │   │     (SpeechAnalyzer)│
└──────────────────┘   └─────────────────────┘
```

---

## 2. 데이터 흐름

### 녹음 시작
1. `AppState`가 사용자 선택(마이크/시스템/화면 토글)에 따라 `RecordingCoordinator` 구성.
2. 코디네이터가 소스별 캡처 시작:
   - 마이크: `MicrophoneCapture` (`AVAudioEngine.inputNode.installTap`)
   - 시스템: `SystemAudioCapture` (Core Audio 프로세스 탭) — *화면 OFF일 때*
   - 화면 ON이면: `ScreenCapture` (`SCStream`, `captureMicrophone:true`)가 영상 + `.audio` + `.microphone`을 한 스트림에서 공급 (이때 마이크/시스템 개별 캡처는 끔)
3. 각 오디오 소스는 **별도 트랙**으로 디스크에 기록(`.m4a`/CAF) + 실시간 파이프라인으로 분기.

### 실시간 미리보기 (선택)
- 캡처 버퍼 → 16kHz 모노 float32 변환(**백그라운드 큐**, 실시간 스레드 밖) → `LivePreviewTranscriber`(SpeechAnalyzer/SpeechTranscriber, ko_KR) → `AppState.liveSegments` 갱신 → 뷰가 즉시 반영.
- 라이브 텍스트는 **비저장·비권위(non-authoritative)**. UI에서 흐리게/"미리보기" 표시.

### 정지 → 최종 전사
1. 캡처 종료, 트랙 파일 확정.
2. `AppState` → `processing`. `WhisperKitBatchTranscriber`가 각 트랙을 **full large-v3 (ko)** 로 일괄 전사 (백그라운드 actor, 마감 없음).
3. VAD(Silero)로 무음 구간 게이팅, 크로스-청크 컨디셔닝 비활성.
4. 결과 세그먼트가 라이브 미리보기를 **덮어씀** → `Recording`에 저장.
5. `AppState` → `done`. 파형이 재생 스크러버로 전환, 전사 편집/내보내기 가능.

---

## 3. 동시성 모델

| 작업 | 실행 컨텍스트 | 규칙 |
|---|---|---|
| 오디오 캡처 콜백(IOProc/installTap) | 실시간 오디오 스레드 | **할당·변환·락 금지.** 버퍼만 복사해 큐로 넘김 |
| 포맷 변환(→16k 모노 f32) | 백그라운드 `DispatchQueue`/actor | `AVAudioConverter`를 콜백 안에서 호출 금지(크래시 사례). 또는 수동 채널0 다운믹스+선형보간 |
| 라이브 미리보기 전사 | 취소 가능 `Task` (background actor) | 녹음 라이프사이클과 디커플. 정지 시 취소 |
| 일괄 전사(large-v3) | background actor | UI 블로킹 금지. 진행률 `AppState`로 보고 |
| UI 상태 | `@MainActor` `@Observable AppState` | 캡처/전사는 메인액터로 결과만 hop |

---

## 4. 핵심 인터페이스 (스캐폴드)

```swift
// Capture
protocol AudioSource: AnyObject {
    var onBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)? { get set }
    func start() async throws
    func stop()
}
// MicrophoneCapture, SystemAudioCapture 가 채택. ScreenCapture 는 영상+오디오 별도.

// Transcription
protocol Transcriber {
    func transcribe(_ audio: URL, language: String) async throws -> [TranscriptSegment]   // 일괄
}
protocol LiveTranscriber {
    func stream(_ buffers: AsyncStream<AVAudioPCMBuffer>, language: String)
        -> AsyncStream<TranscriptSegment>                                                  // 라이브
}
```

전체 시그니처는 `Echo/Transcription/Transcriber.swift`, `Echo/Capture/*.swift` 참조.

---

## 5. 권한 / 패키징

| 권한 | 키 / 방법 |
|---|---|
| 마이크 | `NSMicrophoneUsageDescription` (Info.plist) |
| 시스템 오디오(Core Audio 탭) | `NSAudioCaptureUsageDescription` (Info.plist, **Xcode 드롭다운에 없음 → 수동 추가**) |
| 화면 녹화(ScreenCaptureKit) | Screen Recording TCC — `SCShareableContent` 접근 시 프롬프트 |
| App Sandbox | **OFF** (개인용; 탭/애그리게이트 장치가 샌드박스와 충돌). TCC는 그대로 보호 |
| 서명 | 무료 Apple ID 자동 서명 + 고정 번들 ID(권한 유지) |

> 보라색 시스템오디오 프라이버시 점은 Core Audio 탭에서도 표시됨(검증 결과). UI는 이를 전제로 설계.

---

## 6. 파일 트리

```
Echo/
├── App/
│   ├── EchoApp.swift              @main, WindowGroup + MenuBarExtra
│   └── AppState.swift             @MainActor @Observable 상태머신
├── Models/
│   ├── Recording.swift            녹음 1건(트랙들·전사·메타)
│   ├── TranscriptSegment.swift    시작/끝/텍스트/소스(나·상대)/확정여부
│   └── CaptureSource.swift        mic/system/screen 토글 + 설정
├── Capture/
│   ├── RecordingCoordinator.swift 소스 구성/시작/정지, 트랙 파일 관리
│   ├── MicrophoneCapture.swift    AVAudioEngine
│   ├── SystemAudioCapture.swift   Core Audio 프로세스 탭(골격)
│   ├── ScreenCapture.swift        ScreenCaptureKit(골격)
│   └── AudioFormat.swift          16k 모노 f32 변환 유틸
├── Transcription/
│   ├── Transcriber.swift          프로토콜
│   ├── WhisperKitBatchTranscriber.swift   large-v3 일괄
│   └── LivePreviewTranscriber.swift       SpeechAnalyzer 라이브
├── DesignSystem/
│   └── Theme.swift                컬러/타이포/스페이싱/라디우스 토큰
├── Views/
│   ├── RootView.swift             NavigationSplitView
│   ├── RecordingControlBar.swift  플로팅 글래스 컨트롤
│   ├── LiveTranscriptView.swift   모드 스위처 + Structured + Zen
│   ├── HistorySidebar.swift       기록 목록
│   └── SettingsInspector.swift    모델/언어/소스/화자
└── Resources/
    ├── Info.plist
    └── Echo.entitlements
```
