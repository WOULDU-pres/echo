# Echo — 계획 타당성 보고 & 빌드 플랜

> macOS(Apple Silicon) 네이티브 녹음·녹화 + 한국어 음성→텍스트 앱
> 작성: 2026-06-01 · 리서치 11개 에이전트 + 적대적 검증 워크플로우 기반

---

## 0. 한 줄 결론

**타당함 (FEASIBLE).** 단 한 가지 솔직한 단서만 있음 — *full large-v3를 실시간 라이브로 돌리는 것*은 팬리스 16GB 머신에서 무리. 나머지(시스템+마이크 동시 캡처, 선택적 화면 녹화, 정지 후 full large-v3 일괄 전사, 깔끔한 네이티브 UI)는 전부 성숙한 네이티브 API로 깔끔하게 매핑됨.

**핵심 설계 원칙:** *저장되는 최종 전사본은 항상 정지 후 full large-v3(non-turbo) 일괄 패스다.* 실시간은 마감시간이 없으므로 품질 제약("turbo 금지, 최고 모델만")을 100% 만족시킨다.

---

## ✅ 확정된 결정 (2026-06-01)

1. **실시간 전략 → Apple SpeechTranscriber 미리보기.** macOS 26 내장 SpeechAnalyzer/SpeechTranscriber(ko_KR)로 라이브 화면용 미리보기. 비저장(throwaway), 정지 시 full large-v3 일괄 결과가 덮어씀. → 품질 제약 위반 0.
2. **다음 단계 → 스캐폴드 + 설계 문서 먼저.** Xcode 없이 가능한 것(프로젝트 구조, Swift 인터페이스 골격, DESIGN.md/ARCHITECTURE.md, Xcode 설치 가이드)부터 작성. 실제 .app 빌드는 Xcode 26 설치 후 Phase 0에서.
3. 그 외 §7 권고안 채택: 최소 macOS 15.0, App Sandbox OFF(개인용), 오디오전용=Core Audio 탭/영상시=ScreenCaptureKit, 엔진=WhisperKit, 체크포인트=large-v3-v20240930, 트랙 분리, 화면녹화 라이터=SCRecordingOutput, 무료 Apple ID 서명.

---

## 1. 대상 머신 (실측)

| 항목 | 값 |
|---|---|
| macOS | 26.5 Tahoe (build 25F71) |
| 칩 | **Apple M4** (리서치는 M1/M2 가정 → M4는 더 빠름, ANE 38 TOPS) |
| RAM | 16 GB |
| 폼팩터 | 팬리스 Air 추정 (긴 세션 발열 스로틀링 주의) |
| Swift | 6.3.2 (arm64-apple-macosx26.0) |
| Xcode | **미설치** — 풀 Xcode 26 필요 (App Store, ~15GB). 현재 CLT만 있음 |

> M4는 리서치 가정(M1/M2)보다 빠르므로 실시간 전망이 한 단계 개선됨. 그래도 *full large-v3 라이브 스트리밍 + 팬리스 장시간*은 여전히 리스크 → 실측 부하테스트 권장.

---

## 2. 기능별 타당성

| 기능 | 가능 여부 | 핵심 |
|---|---|---|
| 시스템 + 마이크 **동시 캡처** | ✅ 가능 | 가상 오디오 장치(BlackHole) **불필요**. Core Audio 프로세스 탭(시스템) + AVAudioEngine(마이크), 또는 ScreenCaptureKit 한 스트림(macOS 15+) |
| **화면 녹화**(선택) | ✅ 가능 | ScreenCaptureKit. macOS 15+ `SCRecordingOutput`로 영상+시스템+마이크 자동 먹싱. 팬리스는 1080p/30 권장 |
| 정지 후 **일괄 한국어 STT (full large-v3)** | ✅ 가능 | 가장 깔끔. WhisperKit이 large-v3 CoreML 가중치 제공(~3-4GB, 16GB에 여유). 마감 없음 |
| **실시간** 한국어 STT | ⚠️ 조건부 | full large-v3 라이브는 비현실적. → 가벼운 미리보기(Apple SpeechTranscriber 또는 소형 모델), 저장본은 항상 large-v3가 덮어씀 |
| **깔끔한 네이티브 UI** | ✅ 가능 | SwiftUI on Tahoe (Liquid Glass 자동 적용, Xcode 26 SDK 빌드 시) |

---

## 3. 추천 기술 스택

- **언어/UI:** Swift 6 + SwiftUI (단일 네이티브 코드베이스, 단일 서명/권한). Tahoe의 Liquid Glass 자동 적용. `NavigationSplitView`(기록 사이드바 + 전사 본문 + 설정 인스펙터) + 플로팅 글래스 툴바 + `MenuBarExtra` 퀵캡처.
- **오디오 캡처:**
  - 시스템 사운드 → **Core Audio 프로세스 탭** (`CATapDescription` + `AudioHardwareCreateProcessTap` + `AudioHardwareCreateAggregateDevice`). 화면 녹화 OFF일 때의 기본 경로(가벼운 TCC 권한, Screen Recording 권한 불필요).
  - 마이크 → **`AVAudioEngine.inputNode.installTap`**.
  - 화면 녹화 ON일 때 → **ScreenCaptureKit** `SCStream(captureMicrophone: true)` 한 스트림에서 영상 + `.audio` + `.microphone` 분리 버퍼 수신.
  - **마이크/시스템은 별도 트랙 유지** (화자 구분 "나 vs 상대" 가능, 인식기 동시성 한계 회피).
  - 16kHz 모노 float32 변환은 **반드시 실시간 오디오 스레드 밖**에서 (AVAudioConverter가 IOProc 콜백 안에서 크래시한 사례 있음).
- **STT 엔진:** **WhisperKit** (Argmax, Swift 네이티브 CoreML, ANE/GPU). 폴백: whisper.cpp(Metal). mlx-whisper는 Python 사이드카 필요해서 제외.
- **모델:** 일괄/저장본 = **full large-v3 (non-turbo)**, 체크포인트는 `openai_whisper-large-v3-v20240930`(2024-09 한국어 개선판). 실시간 미리보기(버려짐) = 소형 모델 또는 **Apple SpeechTranscriber(ko_KR)**. 항상 `language="ko"` + Silero VAD로 무음 환각 차단.
- **최소 macOS:** 15.0 (두 캡처 경로 통합). 현재 머신 26.5이므로 제약 없음. **Xcode 26 SDK로 빌드**(Liquid Glass).
- **화면 녹화 파일:** `SCRecordingOutput`(macOS 15+, 턴키) 기본. 코덱/비트레이트 제어 필요 시 `AVAssetWriter`(클럭 오프셋·정지프레임 버그 직접 처리).

---

## 4. 녹음 중 실시간 뷰 — 2가지 모드 (사용자 목업)

메뉴로 전환:
- **모드 A · Structured Stream** (`design/realtime-structured.html`): 좌측 내비 + 상단 REC 타이머 + 타임스탬프/세그먼트 단위 전사 스트림 + 우측 메타패널 + 하단 글래스 컨트롤러. 정보 밀도형.
- **모드 B · Zen Canvas** (`design/realtime-zen.html`): 중앙 대형 타이포로 말이 떠오르는 미니멀형. 코너 상태 라벨 + 하단 파형/컨트롤러.

> **목업 차용 범위:** 레이아웃·타이포·컬러·파형 등 **시각 디자인만** 가져옴.
> 다음 요소는 코어 스펙 밖이거나 로컬-오프라인 컨셉과 안 맞아 라벨/기능 교체:
> - `Cloud Encrypted` → **On-device / Local** (앱은 완전 오프라인)
> - `Premium Plan`·프로필·로그인 → 제거 (개인용 로컬 앱)
> - `정확도 98.4%` → 제거 (Whisper는 신뢰 가능한 % 미제공) / 모델명 표기로 대체
> - `SPEAKER A/B/C` 화자 분리, `자동 요약`, `주요 키워드` → **스트레치 기능**(나중). 마이크/시스템 분리 트랙으로 "나 vs 상대" 2분할은 저비용 가능, 본격 화자분리·요약은 후순위.

---

## 5. 주요 리스크 & 완화

| 리스크 | 심각도 | 완화 |
|---|---|---|
| full large-v3 실시간이 팬리스에서 못 따라감 → 라이브 전사 지연 | 높음 | full v3 라이브 시도 금지. 실시간은 소형/SpeechTranscriber 미리보기(비저장), 저장본은 항상 large-v3 일괄. 10분 한국어 클립으로 실측 |
| 소형/preview 모델의 한국어 정확도 열위 | 중간 | 미리보기에만 사용(어차피 버려짐). 저장본은 large-v3-v20240930. `language=ko` + VAD |
| Core Audio 탭 문서 빈약·설정 까다로움·샌드박스 충돌 | 중간 | Phase 2에서 제일 먼저 디리스킹. `insidegui/AudioCap` 참고. 개인용은 App Sandbox OFF. 런타임에 `kAudioTapPropertyFormat` ASBD 읽기(48k 스테레오 가정 금지) |
| AVAudioConverter 실시간 스레드 크래시 / 마이크·시스템 클럭 불일치 | 중간 | 변환은 백그라운드 큐에서. 트랙 분리 유지, 믹스해야 하면 공통 레이트로 리샘플 후 |
| AVAssetWriter 정지프레임 길이 버그(정적 화면 시 짧게 기록) | 중간 | `SCRecordingOutput` 사용으로 회피, 또는 마지막 프레임 타임스탬프 패딩 |
| 팬리스 장시간 발열 스로틀링(지속 성능 ~25%↓) | 중간 | 화면녹화 1080p/30, 미리보기 모델과 large-v3 동시 점유 금지, large-v3는 정지 후 일괄 |
| TCC 권한 불안정(ad-hoc 서명 재프롬프트, 15+ 주기적 재동의) | 낮음 | 안정적 Apple Development 서명(무료 Apple ID) + 고정 번들 ID. `NSMicrophoneUsageDescription` + `NSAudioCaptureUsageDescription`(Xcode 드롭다운에 없어 수동 추가) |
| 1세대 API 드리프트(WhisperKit 모델 폴더명, Liquid Glass 시그니처) | 낮음 | 패키지 버전 핀. `.buttonStyle(.glassProminent)` 등 Xcode 26 문서 대조. large-v3-v20240930 폴더 존재 확인 |

---

## 6. 단계별 빌드 플랜

| Phase | 산출물 | 예상 |
|---|---|---|
| **0 · 골격 + 파일 일괄 전사** | Xcode 26 프로젝트(SwiftUI, target 15, sandbox OFF, 안정 서명). WhisperKit SPM 추가. NavigationSplitView 셸. "파일 열기 → full large-v3-v20240930, ko → 전사 표시" 동작. 하드 제약 + UI 셸 선검증 | 1-2일 |
| **1 · 마이크 녹음 + Record/Stop UI** | AVAudioEngine 마이크 → .m4a, 플로팅 글래스 툴바(Record `.glassProminent`/Stop), REC 펄스+모노 타이머, 라이브 레벨 스트립. 정지 후 large-v3 일괄 자동 실행 | 1-2일 |
| **2 · 시스템 오디오 캡처 (난코어)** | Core Audio 프로세스 탭으로 시스템 사운드 별도 트랙, 마이크와 동시. 런타임 ASBD, 변환은 스레드 밖. 2트랙 각각 large-v3 전사. `NSAudioCaptureUsageDescription` 수동 추가 | 2-4일 |
| **3 · 실시간 미리보기 (선택, 버려짐)** | 토글식 라이브 전사 패널: 소형 모델 또는 Apple SpeechTranscriber(ko_KR) 스트리밍, 비저장 표시, 정지 시 large-v3로 교체. **모드 A/B 뷰 전환 메뉴** | 2-3일 |
| **4 · 화면 녹화 (선택)** | ScreenCaptureKit(`captureMicrophone`, `SCContentSharingPicker`). macOS 15+ `SCRecordingOutput`로 먹싱. 1080p/30 H.264. 권한 사전 설명 | 2-3일 |
| **5 · 폴리시·기록·내보내기·패키징** | 기록 사이드바, 설정 인스펙터, 정지 후 파형=재생 스크러버, txt/md/srt 내보내기, MenuBarExtra+글로벌 핫키, Reduce Motion/Transparency 폴백, 장시간 발열 실측 | 2-3일 |

**총 예상: 약 1.5–3주 (파트타임, 개인용 폴리시 기준)**

---

## 7. 사용자 결정 필요 항목

1. **실시간 전략(가장 큰 결정):** (a) 실시간 제거, 정지 후 일괄만(가장 단순/정직) / (b) 소형 Whisper 미리보기 / (c) **Apple SpeechTranscriber 미리보기**(네이티브 한국어, 가장 가벼움, Tahoe 최적 — 추천) / (d) full large-v3 라이브 시도(M4 부하테스트). 어느 경우든 저장본은 항상 large-v3.
2. 최소 macOS: **15.0** 권장 (머신 26.5).
3. App Sandbox: 개인용이면 **OFF** 권장 (탭/애그리게이트 장치가 샌드박스와 충돌). App Store 배포 시에만 ON.
4. 오디오 전용 세션 기본 경로: **Core Audio 탭** 권장(가벼운 권한), 영상 시 ScreenCaptureKit. (둘 다 보라색 시스템오디오 점은 표시됨)
5. STT 엔진: **WhisperKit** 권장, whisper.cpp 폴백.
6. large-v3 체크포인트: **v20240930**(한국어 개선판) 권장.
7. 트랙: 마이크/시스템 **분리** 권장.
8. 화면 녹화 파일 라이터: **SCRecordingOutput** 권장(코덱 제어 필요 시 AVAssetWriter).
9. 배포 범위: 개인용 → **무료 Apple ID + 안정 자동 서명**(노터라이즈 불필요).
10. **Xcode 26 설치**: 현재 미설치. Phase 0 전 선행 필수(App Store, ~15GB).

---

## 참고 자료
- 디자인 목업: `design/realtime-structured.html`, `design/realtime-zen.html`
- Core Audio 탭 레퍼런스: Apple "Capturing system audio with Core Audio taps", `insidegui/AudioCap`
- STT: `argmaxinc/argmax-oss-swift` (WhisperKit), Apple SpeechAnalyzer/SpeechTranscriber (macOS 26)
