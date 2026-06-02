# SwiftUI 코드 검토 — Echo 스캐폴드 (2026-06-01)

검토 기준: 프로젝트-로컬 설치된 `swiftui-expert-skill` (Topic Router + Correctness Checklist).
방식: 5개 차원 병렬 리뷰 → 적대적 검증(false-positive 제거) → 종합 (워크플로우, 11 에이전트).

---

## 종합 평가

스캐폴드는 스킬 기준에 **대체로 잘 부합**한다. 기반이 모던하고 정확함:
`AppState`는 `@MainActor @Observable`, 루트 상태는 `@State private`, 환경 주입 일관, 모든 `@State` private,
`ForEach`는 전부 안정적 Identifiable(`.indices` 없음), `@Bindable`은 바인딩이 실제 필요한 곳에만,
deprecated API 없음(NavigationSplitView·ContentUnavailableView·2-파라미터 onChange·`.background(.regularMaterial,in:)`·`.foregroundStyle`).
의도된 스캐폴드 스텁(주석 처리된 Liquid Glass, `.constant(false)` inspector, 빈 async 바디)은 정상적으로 수정 대상에서 제외됨.

실제 문제는 시스템적 결함이 아니라 소수의 정확성/패턴 항목이었고, **검증을 통과한 것은 모두 반영**했다.

---

## Correctness Checklist 결과

| 규칙 | 결과 |
|---|---|
| `@State` private | PASS |
| `@Binding` only where child mutates | N/A (Observation 사용) |
| 전달값을 `@State`로 선언 안 함 | PASS (전부 `let`) |
| `@StateObject`/`@ObservedObject` | N/A (`@Observable` 사용) |
| iOS17+: `@State`+`@Observable`, 주입은 `@Bindable` | **FAIL→수정** (RootView 불필요 `@Bindable` 제거) |
| `ForEach` 안정적 identity | PASS |
| `ForEach` 요소당 일정 뷰 수 | PASS |
| `.animation(_:value:)` value 포함 | PASS |
| `@FocusState` private | N/A |
| 26+ API `#available` 게이팅 | **FAIL→수정** (`.blurReplace` 게이팅) |
| `import Charts` | N/A |
| Preview 자족적 목 데이터 | **FAIL→수정** (#Preview + `AppState.preview` 추가) |

---

## 반영한 수정 (스캐폴드에 적용 완료)

**MUST**
- `LiveTranscriptView.swift`: macOS 26 전용 `.blurReplace`를 `segmentTransition()` 헬퍼로 분리하고 `#available(macOS 26, *)` 게이팅(타깃 15.0). reduceMotion이면 페이드.

**SHOULD**
- `RootView.swift`: 미사용 `@Bindable var state = state` 제거(읽기 전용 접근만 존재). 라우팅을 `DetailContentRouter` struct로 추출(컴퓨티드 `@ViewBuilder` 재평가 회피, `.processing` 분기 포함). `.inspectorColumnWidth(min:ideal:max:)` 추가.
- `RecordingControlBar.swift`: REC 펄스를 끊임없이 바뀌는 `state.elapsed`가 아니라 전용 `@State pulse`에 연결(`.repeatForever` 재시작 버그 제거). 컨트롤 버튼 `.accessibilityLabel`/`.accessibilityHint`, REC 펄스 그룹핑(`.accessibilityElement(children:.ignore)` + label/value) 추가.
- `EchoApp.swift`: Settings 씬에 `.defaultSize(width:400,height:450)` + `.windowResizability(.contentMinSize)`.
- `SettingsInspector.swift`: `.frame(minWidth:280, minHeight:320)`.
- 전 뷰(5개): `#Preview` 추가 + `AppState.preview` 자족적 목 헬퍼(`#if DEBUG`).

---

## 플랜으로 이관한 항목 (해당 Phase에서 구현)

- **게이팅된 오토스크롤**(사용자가 위로 스크롤 시 정지): `StructuredStreamView` → **Phase 3 Task 3.5** (`ScrollPosition` + `onScrollGeometryChange`, macOS 15+).
- **Liquid Glass 정식 채택**(`.glassEffect`/`.buttonStyle(.glassProminent)`, `#available` 게이팅 + 머티리얼 폴백): **Phase 5 Task 5.6**.
- **`RecordingControlBar`의 넓은 `@Observable` 의존성 축소**(필요한 2개 값만 전달/경량 상태 홀더): 성능 최적화, Phase 3+ nice-to-have. 현재는 잠재적이며 버그 아님.

---

## 강점 (그대로 유지)

- `@MainActor @Observable` + `RecordingPhase` 상태머신으로 UI 상태 중앙화.
- 루트 상태 소유 정확(`@State private` + `.environment` 주입).
- `@Bindable`을 `$` 바인딩이 실제 필요한 곳(Settings/History/LiveTranscript)에만 정확히 사용.
- deprecated API 0. 의도된 스텁이 명확히 표시되어 스캐폴드 의도가 읽힘.
- reduceMotion 선제 대응, 탭 요소는 `onTapGesture`가 아닌 `Button` 사용.
