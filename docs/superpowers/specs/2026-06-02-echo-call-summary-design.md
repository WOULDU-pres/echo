# Echo 통화 정리본(Call Summary) — 설계

작성: 2026-06-02 · 상태: 승인됨(구현 진행)

## 목적

echo-fix 스킬로 녹음 전사를 교정할 때, 통화/회의 한 건의 **정리본**까지 생성해
시간순 대화 흐름·전체 맥락·결론을 한눈에 볼 수 있게 한다. Echo 앱 UI는 정리본이
있으면 보여주고, 없으면 기존과 동일하게 전사만 보여준다.

## 데이터 모델 (Echo/Models)

`Recording`에 옵셔널 `summary` 추가 — 기존 `recordings.json`은 필드가 없어도
디코드되며(`nil`), 앱이 녹음을 재저장해도 Codable 라운드트립으로 보존된다.

```swift
struct CallSummary: Codable, Sendable, Equatable {
    var overview: String            // 전체 맥락·흐름
    var timeline: [SummaryMoment]   // 시간순 대화
    var conclusion: String          // 결론
    var model: String?              // 생성 모델(메모)
}

struct SummaryMoment: Codable, Sendable, Equatable, Identifiable {
    var id: UUID = UUID()
    var at: TimeInterval            // 초 단위 = 재생 seek 좌표
    var text: String                // 그 시점 한 줄 요약
}

// Recording 에 추가
var summary: CallSummary?
```

- `at`은 **초(Double)** — 기존 재생(`PlaybackController.seek`)과 바로 연동. Date는
  쓰지 않는다(RecordingStore 기본 JSONEncoder의 Date 전략과 충돌 회피).
- `SummaryMoment.id`는 디코드 시 없으면 새로 생성(스킬 JSON엔 `at`/`text`만 있어도 됨).

## UI (Echo/Views/RootView.swift · RecordingDetailView)

- `recording.summary != nil`일 때만 상단에 세그먼트 토글 `[전사 | 정리본]`(기본 전사).
  없으면 토글을 그리지 않아 기존과 동일.
- 정리본 탭: `overview`(문단) → `timeline`(타임코드 버튼 + 한 줄, 클릭 시
  `playback.seek(at)`) → `conclusion`(문단).
- 전사 탭: 현재 `EditableTranscriptRow` 목록 그대로.
- 재생 바·툴바(재전사/복사/내보내기)는 두 탭 공통 유지.

## 스킬 (echo-fix)

- **교정은 청크 개수만큼 서브에이전트로 팬아웃**(코드 일괄 ❌). 작은 파일도 인라인 금지 —
  항상 청크 단위 서브에이전트가 교정.
- 각 청크 서브에이전트는 교정 결과에 더해 **부분 요약**을 반환한다:
  `chunk_summary: { overview, moments:[{at, text}] }` (at = 그 청크 안 대표 세그먼트 start).
- 모든 청크 교정·부분요약 완료 후 **합성 서브에이전트 1개**가 부분요약들을 모아
  전체 `overview` + 통합/정렬된 `timeline` + `conclusion`을 만든다.
- `merge.py`가 교정 텍스트와 함께 `summary`를 **녹음 id 기준**으로 recordings.json에
  기록한다(메타 보존·atomic). summary 입력은 워크디렉토리의 `summary_<r>.json`.

## 호환·테스트

- summary 옵셔널 → 구버전 recordings.json 디코드 OK(`nil`).
- 앱 재저장 시 summary 보존(Codable 라운드트립).
- 테스트: ① summary 포함 Recording 인코드→디코드 동일(`EchoTests`), ② summary 없는
  JSON 디코드 시 `summary == nil`, ③ SummaryMoment `at`/`text`만 있는 JSON 디코드 OK.

## 범위 밖(YAGNI)

- 앱 내에서 정리본 생성/편집(스킬이 생성, 앱은 표시·보존만).
- 타임라인 클릭 시 전사 탭 자동 전환·해당 줄 스크롤(추후 향상 여지로만 기록).
