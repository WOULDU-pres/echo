# Echo — 디자인 시스템

사용자 제공 목업(`design/realtime-structured.html`, `design/realtime-zen.html`)에서 추출한 토큰을 SwiftUI / macOS 26(Liquid Glass) 기준으로 정리. 구현은 `Echo/DesignSystem/Theme.swift`.

---

## 1. 컬러 토큰

목업은 Material 스타일 라이트 팔레트(다크 지원). 핵심만:

| 역할 | 토큰 | Light HEX | 용도 |
|---|---|---|---|
| Primary | `primary` | `#0058BC` | 강조·액션·활성 |
| Primary container | `primaryContainer` | `#0070EB` | 강조 배경 |
| **Secondary (REC)** | `secondary` | `#BC000A` | **녹음 빨강**·정지 버튼 |
| Tertiary | `tertiary` | `#4C4ACA` | 보조 화자·태그 |
| Error | `error` | `#BA1A1A` | 오류 |
| Background | `background` | `#FAF9FE` | 앱 배경 |
| Surface lowest | `surfaceContainerLowest` | `#FFFFFF` | 카드·본문 |
| Surface low | `surfaceContainerLow` | `#F4F3F8` | 입력·칩 배경 |
| On surface | `onSurface` | `#1A1B1F` | 본문 텍스트 |
| On surface variant | `onSurfaceVariant` | `#414755` | 보조 텍스트 |
| Outline | `outline` | `#717786` | 구분선·플레이스홀더 |
| Outline variant | `outlineVariant` | `#C1C6D7` | 약한 구분선 |

> macOS 26에서는 **시맨틱 색**(`Color.accentColor`, `.primary`, `.secondary`, 시스템 머티리얼)을 우선 쓰고, 위 브랜드 토큰은 강조/REC 등 한정 사용 권장. 다크 모드는 시스템 자동 + 토큰별 다크 값 별도 정의(추후).

---

## 2. 타이포그래피

- **본문/UI:** Pretendard (한국어), Inter 폴백. → SwiftUI에선 **Pretendard 번들** 또는 시스템 폰트(SF Pro). 한글 비중 높으면 Pretendard 번들 권장.
- **데이터/타이머:** JetBrains Mono → SF Mono(`.monospaced`)로 대체 가능.

| 스타일 | 크기/굵기 | 자간/행간 | 용도 |
|---|---|---|---|
| `displayLg` | 48 / 700 | -0.04em / 1.1 | Zen 모드 대형 전사 텍스트 |
| `headlineMd` | 24 / 600 | -0.01em / 32 | 화면 타이틀 |
| `titleSm` | 18 / 600 | / 24 | 섹션 타이틀 |
| `bodyReading` | 20 / 400 | -0.02em / 1.5 | 전사 본문(읽기용) |
| `bodyUI` | 13 / 400 | / 18 | 일반 UI |
| `labelCaps` | 10 / 600 | 0.1em / 16, **UPPERCASE** | 라벨·상태칩 |
| `monoData` | 12 / 400 | / 16 | 타임스탬프·타이머 |

---

## 3. 스페이싱 · 라디우스

| 토큰 | 값 |
|---|---|
| `xs` | 4 |
| `base` | 8 |
| `sm` | 12 |
| `md` | 16 |
| `lg` | 24 |
| `xl` | 32 |

| 라디우스 | 값 |
|---|---|
| `radius` | 4 |
| `radiusLg` | 8 |
| `radiusXl` | 12 |
| `radiusFull` | 9999 (pill) |

---

## 4. 녹음 중 라이브 뷰 — 2 모드

상단/설정 메뉴로 전환. 둘 다 동일한 `AppState.liveSegments`를 다른 레이아웃으로 렌더.

### 모드 A · Structured Stream (정보 밀도형)
- 좌측 `NavigationSplitView` 사이드바(기록/전사/즐겨찾기/설정).
- 상단 바: 화면 타이틀 + **REC 펄스 점 + 모노 타이머**(`secondary`), 검색.
- 본문: **세그먼트 행** — 좌측 24pt 칸에 타임스탬프(`monoData`) + 화자 칩(나/상대), 우측 `bodyReading` 텍스트. 활성 세그먼트는 `primary/5` 배경 + 미니 파형.
- 우측 메타패널: (스트레치) 키워드·요약 → **초기엔 생략/숨김**.
- 하단 중앙 플로팅 글래스 컨트롤러: Record / Pause / Stop.

### 모드 B · Zen Canvas (미니멀형)
- 화면 중앙 `displayLg` 대형 텍스트가 **blur-in 페이드**로 떠오름(최근 발화 강조, 지난 줄은 `opacity 0.3`).
- 코너 상태 라벨(`labelCaps`): 세션 ID·타이머 / 설정 / "On-device" / 포맷.
- 하단: 얇은 파형(40바) + 알약형 글래스 컨트롤러(Record/Pause/Stop, 호버 시 라벨).
- "Listening for voice patterns" 류 무음 상태 표시.

---

## 5. 목업 → 로컬 기준 라벨 교정

| 목업 요소 | 처리 |
|---|---|
| `Cloud Encrypted` | → **On-device / Local** (완전 오프라인) |
| `Premium Plan`, 프로필, 로그인 | **제거** (개인용 로컬 앱) |
| `정확도 98.4%` | **제거** (Whisper는 신뢰 가능한 신뢰도% 미제공). 대신 모델명(`large-v3`) 표기 |
| `SPEAKER A/B/C` 화자 분리 | **스트레치.** 초기엔 마이크/시스템 분리 트랙으로 "나 / 상대" 2분할만 |
| `자동 요약`, `주요 키워드` | **스트레치(후순위).** 온디바이스/오프라인 원칙 유지 |

---

## 6. 모션 · 접근성

- REC 펄스: 2s ease 깜빡임. **Reduce Motion 시 정적 점**.
- Zen blur-in: `Reduce Motion` 시 페이드만/즉시.
- Liquid Glass: **Reduce Transparency 시 불투명 폴백**.
- 프롬프트 글래스 버튼: `.buttonStyle(.glassProminent)` (※ `.glass(.prominent)` 아님 — 검증 교정).
- 라이브 전사는 단일 `TextEditor` 금지 → **세그먼트 행 + 오토스크롤**(사용자가 위로 스크롤하면 정지).

---

## 7. 컴포넌트 인벤토리 (초기)

- `RecordPill` — REC 점 + 모노 타이머
- `GlassControlBar` — Record/Pause/Stop 플로팅
- `SourceToggles` — 마이크/시스템/화면
- `LevelMeterStrip` / `WaveformStrip` — 라이브 레벨 → 정지 후 스크러버
- `TranscriptRow` — 타임스탬프 + 화자칩 + 텍스트 (Structured)
- `ZenLine` — blur-in 대형 라인 (Zen)
- `HistoryRow` — 날짜·소스 아이콘·제목
- `ModelLanguagePicker` — large-v3 고정 표기 + 언어(ko 기본)

---

## 8. 로고 / 앱 아이콘

사용자 제공 로고: **파란색(#7DA2F7 계열) 마이크 + 사운드 웨이브**, 밝은 배경. 사이드바 브랜드 컬러(`primary`)와 잘 어울림.

- 원본: `design/echo_logo.png` (1254×1254) · 인앱 사용본: `Echo/Resources/echo_logo.png`
- 앱 아이콘 카탈로그: `Echo/Resources/Assets.xcassets/AppIcon.appiconset/` (mac 16~1024 전 사이즈 `sips`로 생성)
- **연결 마무리(워크플로우 완료 후)**: `project.yml`의 Echo 타깃 settings에 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` 추가 → `xcodegen generate` → 빌드. (Assets.xcassets는 `sources: Echo`에 이미 포함됨)
- 사이드바/메뉴바의 기존 `mic` SF Symbol을 이 로고로 교체할지는 선택(헤더 브랜드 영역에 `Image("echo_logo")` 사용 가능).
