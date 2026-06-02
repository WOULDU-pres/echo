# Echo — Xcode 26 셋업 가이드

> 현재 머신: macOS 26.5 · M4 · Swift 6.3.2 · Xcode **다운로드 중**(`/Applications/Xcode.appdownload`).
> 완료되면 아래 순서로 진행.

---

## 0. Xcode 활성화 (다운로드 완료 후)

```bash
# 다운로드 완료 확인 (Xcode.app 존재해야 함)
ls -d /Applications/Xcode*.app

# 개발자 디렉터리를 CLT → Xcode 로 전환 (sudo 필요)
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer

# 라이선스 동의 + 첫 컴포넌트 설치
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch

# 확인
xcodebuild -version    # Xcode 26.x 떠야 함
```

> App Store 다운로드가 248KB에서 멈춰 있으면: App Store 앱 → 계정/다운로드에서 일시정지·로그인 상태 확인. 대안: developer.apple.com/download 에서 `.xip` 직접 받기.

---

## 1. 프로젝트 생성

Xcode → File ▸ New ▸ Project ▸ **macOS ▸ App**

| 항목 | 값 |
|---|---|
| Product Name | `Echo` |
| Interface | SwiftUI |
| Language | Swift |
| Bundle ID | 예: `com.hwjoo.echo` (고정 유지 → TCC 권한 지속) |
| Minimum Deployments | **macOS 15.0** |
| Storage | None (또는 SwiftData, 추후) |

생성 후, 기본 생성 파일 대신 **이 저장소의 `Echo/` 하위 소스를 그룹째 추가**(File ▸ Add Files to "Echo"…, "Create groups"). `Resources/Info.plist`·`Echo.entitlements`는 타깃 설정에 연결.

> Xcode 26 SDK로 빌드하면 SwiftUI 기본 컨트롤이 **Liquid Glass**를 자동 채택.

---

## 2. 의존성 (Swift Package Manager)

File ▸ Add Package Dependencies… 에 추가:

| 패키지 | URL | 비고 |
|---|---|---|
| **WhisperKit** | `https://github.com/argmaxinc/WhisperKit` | 일괄 전사(large-v3). 버전 **핀** 권장. 패키지/프로덕트 이름 최신 확인(`argmax-oss-swift`로 통합됐을 수 있음) |
| (선택) Silero VAD | WhisperKit 내장 VAD 사용 가능 | 무음 환각 게이팅 |

- Apple **SpeechAnalyzer/SpeechTranscriber**(라이브 미리보기)와 **ScreenCaptureKit / CoreAudio / AVFoundation**은 OS 내장 → 별도 패키지 불필요.

### 모델
- WhisperKit 첫 실행 시 CoreML 가중치 자동 다운로드. 체크포인트 **`openai_whisper-large-v3-v20240930`**(한국어 개선판) 지정. 핀한 리비전에 폴더 존재 여부 확인.
- SpeechTranscriber는 ko_KR 언어 에셋을 `AssetInventory`로 1회 다운로드 → "한국어 모델 준비 중" 상태 UI 1회 표기.

---

## 3. Info.plist 사용 설명 (필수)

타깃 ▸ Info 에 추가 (`Resources/Info.plist`에 초안 포함):

```xml
<key>NSMicrophoneUsageDescription</key>
<string>녹음 시 마이크 입력을 캡처합니다.</string>

<!-- ⚠️ Xcode 드롭다운에 없음 — 키를 직접 입력 -->
<key>NSAudioCaptureUsageDescription</key>
<string>시스템에서 재생되는 소리를 녹음합니다.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>실시간 미리보기 전사를 위해 음성 인식을 사용합니다.</string>
```

화면 녹화(Screen Recording)는 별도 Info.plist 키가 없고 `SCShareableContent` 접근 시 TCC 프롬프트가 뜸.

---

## 4. 서명 · App Sandbox

- Signing & Capabilities ▸ **Automatically manage signing** ▸ 개인 무료 Apple ID 팀 선택.
- **App Sandbox: OFF (개인용)** — Core Audio 탭/애그리게이트 장치가 샌드박스와 충돌. TCC는 여전히 마이크·시스템오디오·화면을 보호. (App Store 배포 시에만 ON 고려)
- 화면 녹화/시스템오디오용 추가 entitlement는 비샌드박스에선 불필요. `Resources/Echo.entitlements` 참고.

---

## 5. 첫 빌드 (Phase 0)

`Echo/` 소스가 추가된 상태에서 ⌘R:
1. 빈 `NavigationSplitView` 셸 + "파일 열기" 버튼.
2. 오디오 파일 선택 → `WhisperKitBatchTranscriber`로 **large-v3, ko** 전사 → 전사 표시.

이 단계가 통과하면 하드 제약(full large-v3 일괄)과 UI 셸이 검증됨. 이후 Phase 1(마이크) → 2(시스템오디오) → 3(라이브) → 4(화면) → 5(폴리시) 순.

> 빌드 검증 전까지 `Echo/`의 프레임워크 결합부는 **미검증 골격**. API 시그니처(Liquid Glass, SpeechAnalyzer, Core Audio 탭)는 Xcode 26 실문서와 대조하며 확정.
