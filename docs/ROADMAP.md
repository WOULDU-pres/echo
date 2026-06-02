# Echo — 다음 작업 로드맵

> 작성: 2026-06-02 · 다음 세션에서 위에서부터 순서대로 진행.
> 출처: 4개 렌즈(UX·미완성·안정성·데이터관리)로 실제 코드를 감사 → 우선순위 종합.
> 상세 단계별 코드는 `docs/superpowers/plans/2026-06-02-echo-roadmap-p0.md` 참조.

## 진행 방법 (다음 세션 시작 시)
1. 이 파일의 **P0**부터. 각 항목은 `왜 / 어떻게 / 파일`을 포함.
2. P0 코드 스니펫은 별도 플랜 파일(`...-p0.md`)에 실행 단위로 정리됨 — 그걸 따라 구현.
3. 각 기능: 구현 → 빌드 그린 → 단위/통합 테스트 → 앱 재배포 → 커밋. (기존 워크플로우와 동일)
4. 완료 항목은 체크.

---

## P0 — 지금 (사용자 명시 + 핵심)

> 51분 파일은 직렬 워커를 ~17분 점유하는데 빠져나갈 방법이 없음 → 취소가 최대 갭. 추가 버튼은 한 화면 발견성 수정. 취소 버튼이 같은 모달에 필요하므로 함께 출시.

- [x] **① 전사 실행 중 취소 + 대기열 비우기** ★사용자요청 · 난이도 M ✅ 2026-06-02
  > 구현 시 한 단계 강화: WhisperKit이 `Task.checkCancellation()`을 전사 경로에서 호출함을 소스로 확인 → 워커 Task 취소로 **in-flight 전사를 즉시 중단**(플랜의 '반환 후 폐기'보다 우수, 긴 파일 탈출 가능). 취소 Task 재사용 오염은 `while !Task.isCancelled` 드레인 가드 + 신규 워커 재시작으로 차단(직렬성 유지). 커밋 2a82210.
  - 왜: job이 `.processing`/`.pending`이면 멈출 방법이 전혀 없음. 직렬 워커가 파일 전체 시간 동안 WhisperKit을 점유(51분 ≈ M4에서 ~17분) → 다른 큐 작업 전부 블록. `cancelJob`/`cancelAllJobs` 없음.
  - 어떻게: `JobStatus`에 `.cancelled` 추가. `AppState`에 `private var cancelledIDs: Set<UUID>`. `cancelJob(_:)` — pending이면 즉시 jobs에서 제거, processing이면 cancelledIDs에 추가(진행 중 WhisperKit 패스는 중단 불가 → 반환 후 폐기). `drainQueue`/`process`에서 각 `transcribe` await **이후** `guard !cancelledIDs.contains(job.id)` → 폐기+continue(녹음 케이스의 2·3번째 채널 루프도 단락). `cancelAllJobs()` = pending 전부 제거 + 현재 processing 표시 + `worker?.cancel()`. `activeJobCount`가 모달 자동 닫힘을 이미 구동.
  - 파일: `Echo/App/AppState.swift`

- [x] **② 진행 중 job에 취소 버튼 + 모달 '모두 취소'** · 난이도 S ✅ 2026-06-02
  - 왜: ①의 노출 UI. 현재 `JobRow`는 실패 job에만 재시도/닫기. processing/pending엔 컨트롤 없음.
  - 어떻게: `JobRow`에서 `.processing`/`.pending`에 trailing 버튼(`xmark.circle`, destructive) → `state.cancelJob(job.id)`. `TranscriptionProgressSheet` footer에 `activeJobCount > 1`일 때 '모두 취소' → `state.cancelAllJobs()`.
  - 파일: `Echo/Views/RootView.swift`

- [x] **③ 상시 '오디오 추가' 버튼** ★사용자요청 · 난이도 S ✅ 2026-06-02
  - 왜: `.fileImporter`가 `EmptyStateView`에만 있음. 녹음이 있으면 빈 화면이 사라져 드래그앤드롭(발견 어려움)만 남음. 툴바에 추가 버튼 없음.
  - 어떻게: `RootView`에 `@State private var importing = false`. `ToolbarItem(.primaryAction)` 버튼(`Label("오디오 추가", systemImage:"plus")`) → `importing = true` + `.fileImporter(...allowsMultipleSelection:true)` → 성공 시 `state.enqueueFiles(urls)`(EmptyStateView 로직과 동일). EmptyStateView 버튼은 유지. 중복 줄이려면 importer를 작은 ViewModifier로 추출(선택).
  - 파일: `Echo/Views/RootView.swift`

---

## P1 — 곧 (가치 높음·저비용, 기존 데이터/유틸 재사용)

- [x] **삭제 확인 다이얼로그** · S ✅ 2026-06-02 — 모든 삭제 진입점을 `.confirmationDialog`로 가드. 추가로 `deleteRecordings` 빈집합 폴백 제거 + MultiSelectionView를 selection 스냅샷으로 통일(우발적 전체삭제 방지, 리뷰 반영). 커밋 a69487c.
- [x] **녹음 이름 변경** · S ✅ 2026-06-02 (사용자 요청으로 P0와 함께 선반영) — `AppState.renameRecording(_:_:)`(빈/공백/동일값 가드 + persist) + 사이드바 우클릭 '이름 변경…' → `RenameRecordingSheet`(빈 이름 저장 비활성, onSubmit도 동일 가드). 커밋 2a82210.
- [x] **전사 클립보드 복사** · S ✅ 2026-06-02 — 상세 툴바 '복사' → `NSPasteboard`(.txt). 빈 전사 시 비활성. 커밋 a69487c.
- [x] **사이드바 행 메타데이터(길이·화자수)** · S ✅ 2026-06-02 — 행에 길이(mono 배지) + 화자수(distinct `speakerLabel`, 1 초과 시 'N명'). import 파일도 길이 표시되도록 전사 시 마지막 세그먼트 end를 duration으로 채움. 커밋 a69487c.
- [x] **Finder에서 보기** · S ✅ 2026-06-02 — 우클릭 → `NSWorkspace.activateFileViewerSelecting`(존재 파일만, 없으면 메뉴 비활성). 커밋 a69487c.
- [x] **(정리) 기존 빈 녹음 제거** · S ✅ 2026-06-02 — 설정 '빈 녹음 N개 정리' 버튼 → `cleanupEmptyRecordings`(멱등) + 확인 다이얼로그. 커밋 a69487c.

---

## P2 — 나중 (유용하나 크거나 빈도 낮음)

- [x] **녹음 검색/필터** · M ✅ 2026-06-02 — `.searchable`로 제목+전사 세그먼트 부분일치(`range(of:options:)`). 검색 중 수동 재배치 차단, 빈 결과 오버레이. 커밋 a9de771.
- [ ] **화면 녹화 영상 재생** · M — ⏸️ **보류**: `PlaybackController`가 `AVAudioPlayer`(오디오 전용)라 AVPlayer 재설계 필요. **ScreenCaptureKit 런타임 미검증**(재생할 녹화 영상이 아직 없음)이라 검증 대상 부재 + 동작하는 오디오 재생 회귀 위험. 화면 캡처 실기기 검증 후 진행. 파일: `RootView.swift`, `PlaybackBar.swift`
- [ ] **Whisper 모델 선택(large-v3/turbo)** · M — ⏸️ **보류(하드 제약 충돌)**: 사용자 하드 제약 'turbo 금지, 최고 정확도'(README/PLAN/ARCHITECTURE 명시)와 정면 충돌. 자율 도입하지 않음 — 사용자 결정 필요.
- [x] **recordings.json 견고한 로드** · M ✅ 2026-06-02 — 디코드 실패 시 원자적 백업(`recordings.corrupt.json`) + 빈 시작 + 정직한 경고(백업 성공/실패·읽기실패·빈파일 구분). 조용한 전체 손실 + 거짓 '백업했음' 제거. 커밋 a9de771.
- [x] **Pause가 실제로 캡처 일시정지** · L ✅ 2026-06-02 — 코디네이터 버퍼 게이트(캡처 유지·teardown 없음)로 일시정지 구간을 녹음/길이에서 제외. 타이머·라이브화면·레벨미터 일시정지 반영. (실기기 캡처 검증은 사람 몫.) 커밋 a9de771.

---

## 별도 — 런타임 사람 검증(기능 아님, 실기기 확인 필요)
- 화면 녹화(ScreenCaptureKit) 실제 캡처·파일 재생 / 글로벌 핫키(다른 앱 포커스 중) / 라이브 미리보기(ko_KR 에셋) / 마이크·시스템 동시 캡처 / 화자 구분 한국어 정확도 평가.
- 이건 코드 작업이 아니라 사용자가 앱에서 직접 확인하는 항목.

---

## 의도적으로 제외(과함/저가치)
지역화, 즐겨찾기/태그, 온보딩, 배치 zip 내보내기, 녹음 중 드래그 힌트, 큐 위치 라벨, 앱 아이콘 추가 작업 등 — 개인용 단일 사용자 앱에 비해 비용 대비 가치 낮아 제외.
