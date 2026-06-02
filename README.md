# Echo

macOS(Apple Silicon) 네이티브 녹음·녹화 + 한국어 음성→텍스트 앱.

- **시스템 사운드 + 마이크 동시 녹음** (가상 오디오 장치 불필요)
- **화면 녹화** (선택 토글)
- **실시간 미리보기 전사** — Apple SpeechTranscriber(ko_KR), 비저장 / 라이브 화면용
- **정지 후 전체 일괄 전사** — full Whisper **large-v3** (non-turbo, 최고 정확도). 저장되는 최종본은 항상 이 결과.
- **깔끔한 네이티브 UI** — SwiftUI + macOS 26 Liquid Glass, 녹음 중 2-모드 뷰(Structured / Zen)

> 완전 오프라인 · 온디바이스. 클라우드 전송 없음.

## 상태

- 대상 머신: macOS 26.5 Tahoe · Apple M4 · 16GB · Swift 6.3.2 · Xcode 26.5
- 현재 단계: **Phase 0~5 코드 구현 완료 · 빌드 그린(unsigned, MacOSX26.5 SDK) · 단위 테스트 16/16 통과 · swiftui-expert-skill 정합성 체크리스트 통과** (개인 빌드).
- 최종 검증(2026-06-02, 자율 빌드): `xcodebuild … build` = `** BUILD SUCCEEDED **`, `xcodebuild … test` = `** TEST SUCCEEDED **` (16/16). WhisperKit 0.18.0(large-v3 `openai_whisper-large-v3-v20240930`) 의존성 해석·링크 완료 → 실제 전사 경로가 컴파일됨(스텁 아님). 프레임워크 결합부(Core Audio 프로세스 탭, ScreenCaptureKit, SpeechAnalyzer/SpeechTranscriber, Carbon 핫키, Liquid Glass)는 macOS 26.5 SDK 헤더 대조로 실제 시그니처 컴파일.
- **남은 항목 = 실기기에서 사람이 직접 확인** (헤드리스 불가):
  - TCC 권한 부여: 마이크 · 시스템 오디오 녹음 · 화면 녹화
  - 실제 마이크/시스템 오디오 캡처 동작, "나/상대" 분리 트랙 + 시간순 병합 전사
  - **large-v3 모델 최초 1회 다운로드(~3-4GB) + 한국어 전사 정확도 평가**
  - ko_KR SpeechTranscriber 라이브 미리보기 품질
  - 글로벌 핫키(다른 앱 포커스 중) · 발열 부하(멀티시간 세션) 테스트
  - 서명 Archive 패키징(무료 Apple ID) 및 실행/권한 영속 확인

## 문서

| 문서 | 내용 |
|---|---|
| [PLAN.md](PLAN.md) | 타당성 보고 · 기술 스택 · 리스크 · 단계별 빌드 플랜 · 확정 결정 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 모듈 구조 · 데이터 흐름 · 동시성 모델 · 인터페이스 |
| [docs/DESIGN.md](docs/DESIGN.md) | 디자인 시스템(컬러/타이포/스페이싱) · 2-모드 UI 스펙 |
| [docs/SETUP-XCODE.md](docs/SETUP-XCODE.md) | Xcode 26 설치 후 프로젝트 생성·의존성·권한·서명 설정 |
| [docs/superpowers/plans/](docs/superpowers/plans/) | **실행 플랜** — 마스터 + Phase 0~5 (개발 완료까지 이어서 진행) |
| [docs/REVIEW-swiftui-2026-06-01.md](docs/REVIEW-swiftui-2026-06-01.md) | swiftui-expert-skill 기준 검토 결과 + 적용한 수정 |
| [design/](design/) | 사용자 제공 UI 목업 (Structured / Zen) |

> **개발을 이어서 진행하려면** `docs/superpowers/plans/2026-06-01-echo-master.md`를 먼저 열어 "How to resume"를 따르세요.

## 소스 구조 (`Echo/`)

Xcode 26 설치 후 이 디렉터리를 macOS App 타깃 소스로 사용. 자세한 트리는 [ARCHITECTURE.md](docs/ARCHITECTURE.md) 참조.

```
Echo/
├── App/            앱 진입점 · 전역 상태(녹음 상태머신)
├── Models/         Recording · TranscriptSegment · CaptureSource
├── Capture/        마이크 · 시스템오디오(Core Audio 탭) · 화면 · 코디네이터
├── Transcription/  Transcriber 프로토콜 · WhisperKit 일괄 · SpeechAnalyzer 라이브
├── DesignSystem/   Theme(컬러/타이포/스페이싱 토큰)
├── Views/          RootView · 컨트롤바 · 라이브 전사(2모드) · 기록 · 설정
└── Resources/      Info.plist · entitlements
```

> `Echo/`의 Swift 파일은 Phase 0~5를 거쳐 모두 구현·컴파일됐습니다. 프레임워크 결합부(Core Audio 프로세스 탭·ScreenCaptureKit·SpeechAnalyzer/SpeechTranscriber·Carbon 핫키·Liquid Glass)는 macOS 26.5 SDK 헤더 대조로 실제 시그니처를 사용하며 빌드 그린입니다. 런타임 캡처/전사 품질은 실기기에서 사람이 확인합니다(위 "상태" 참조).
