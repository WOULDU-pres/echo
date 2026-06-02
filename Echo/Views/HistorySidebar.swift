import SwiftUI
import AppKit

/// 좌측 기록 목록. 두 정렬 모드:
/// - 날짜순(기본): 생성일별 섹션으로 그룹핑, 최신순.
/// - 수동: 단일 목록 + 드래그앤드롭(.onMove)으로 순서 변경.
struct HistorySidebar: View {
    @Environment(AppState.self) private var state
    @AppStorage("historyManualSort") private var manualSort = false
    /// 이름 변경 시트 대상(우클릭 '이름 변경…'). nil이면 닫힘.
    @State private var renameTarget: Recording?
    /// 삭제 확인 대상(영구 삭제 전 .confirmationDialog 가드). nil이면 닫힘.
    @State private var deleteTargets: Set<Recording.ID>?
    /// 제목·전사 내용 검색어(.searchable). 빈 문자열이면 전체 표시.
    @State private var searchText = ""

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            // Shift/Cmd 다중 선택 지원. Delete 키로 선택 일괄 삭제.
            List(selection: $state.selection) {
                if manualSort {
                    if !visibleRecordings.isEmpty {
                        Section("수동 정렬 (드래그로 이동)") {
                            ForEach(visibleRecordings) { row($0) }
                                .onMove { offsets, dest in
                                    // 검색 중엔 인덱스가 필터 기준이라 재배치를 막는다(오매핑 방지).
                                    guard !isFiltering else { return }
                                    state.moveRecordings(from: offsets, to: dest)
                                }
                        }
                    }
                } else {
                    ForEach(groupedRecordings, id: \.day) { group in
                        Section(Self.dateLabel(group.day)) {
                            ForEach(group.items) { row($0) }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "제목·내용 검색")
            .onDeleteCommand { requestDelete(state.selection) }
        }
        .toolbar {
            if state.selection.count > 1 {
                ToolbarItem {
                    Button(role: .destructive) {
                        requestDelete(state.selection)
                    } label: {
                        Label("\(state.selection.count)개 삭제", systemImage: "trash")
                    }
                    .help("선택한 녹음 삭제")
                }
            }
            ToolbarItem {
                Menu {
                    Picker("정렬", selection: $manualSort) {
                        Label("날짜순", systemImage: "calendar").tag(false)
                        Label("수동(드래그)", systemImage: "hand.draw").tag(true)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help("정렬 방식")
            }
        }
        .overlay {
            if state.recordings.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "waveform")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Theme.Palette.outline)
                    Text("아직 녹음이 없습니다")
                        .font(Theme.Font.bodyUI)
                        .foregroundStyle(Theme.Palette.onSurfaceVariant)
                    Text("녹음하거나 오디오 파일을 전사하세요")
                        .font(Theme.Font.monoData)
                        .foregroundStyle(Theme.Palette.outline)
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.Spacing.lg)
            } else if visibleRecordings.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Theme.Palette.outline)
                    Text("검색 결과 없음")
                        .font(Theme.Font.bodyUI)
                        .foregroundStyle(Theme.Palette.onSurfaceVariant)
                    Text("제목·전사 내용에서 찾지 못했습니다")
                        .font(Theme.Font.monoData)
                        .foregroundStyle(Theme.Palette.outline)
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .sheet(item: $renameTarget) { rec in
            RenameRecordingSheet(recording: rec)
        }
        // 영구 삭제 가드: 모든 삭제 진입점(Delete 키·스와이프·우클릭·툴바)을 거쳐 확인을 받는다.
        .confirmationDialog(
            "녹음 삭제",
            isPresented: Binding(get: { deleteTargets != nil },
                                 set: { if !$0 { deleteTargets = nil } }),
            titleVisibility: .visible,
            presenting: deleteTargets
        ) { ids in
            Button("\(ids.count)개 삭제", role: .destructive) { state.deleteRecordings(ids) }
            Button("취소", role: .cancel) { }
        } message: { ids in
            Text("선택한 \(ids.count)개 녹음과 전사가 영구 삭제됩니다. 되돌릴 수 없습니다.")
        }
    }

    /// 삭제 요청 → 확인 다이얼로그를 띄운다(빈 집합은 무시).
    private func requestDelete(_ ids: Set<Recording.ID>) {
        guard !ids.isEmpty else { return }
        deleteTargets = ids
    }

    /// 녹음의 트랙/영상 중 디스크에 실제 존재하는 파일들.
    private func existingFiles(_ rec: Recording) -> [URL] {
        var urls = Array(rec.audioTracks.values)
        if let v = rec.videoURL { urls.append(v) }
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 녹음의 파일을 Finder에서 선택해 보여준다(존재하는 파일만).
    private func revealInFinder(_ rec: Recording) {
        let files = existingFiles(rec)
        guard !files.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }

    @ViewBuilder
    private func row(_ rec: Recording) -> some View {
        // 선택된 행이 여러 개면 우클릭/스와이프 삭제가 선택 전체에 적용된다.
        let multi = state.selection.count > 1 && state.selection.contains(rec.id)
        HistoryRow(recording: rec)
            .tag(rec.id)
            .swipeActions(edge: .trailing) {
                Button("삭제", role: .destructive) {
                    requestDelete(multi ? state.selection : [rec.id])
                }
            }
            .contextMenu {
                if multi {
                    Button("\(state.selection.count)개 삭제", role: .destructive) { requestDelete(state.selection) }
                } else {
                    Button("이름 변경…") { renameTarget = rec }
                    Button("Finder에서 보기") { revealInFinder(rec) }
                        .disabled(existingFiles(rec).isEmpty)
                    Button("삭제", role: .destructive) { requestDelete([rec.id]) }
                }
            }
    }

    /// 검색 중 여부(공백만 입력도 비검색으로 취급). onMove 게이트와 필터가 같은 술어를 쓰도록 공유.
    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 검색어로 필터된 녹음(제목 또는 전사 세그먼트 텍스트에 부분일치, 대소문자 무시).
    /// range(of:options:.caseInsensitive)로 대상 문자열 복제(lowercased 할당) 없이 비교한다.
    private var visibleRecordings: [Recording] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return state.recordings }
        return state.recordings.filter { rec in
            rec.title.range(of: q, options: .caseInsensitive) != nil
                || rec.segments.contains { $0.text.range(of: q, options: .caseInsensitive) != nil }
        }
    }

    /// 생성일(일 단위)로 그룹핑, 그룹·항목 모두 최신순. 검색 필터 반영.
    private var groupedRecordings: [(day: Date, items: [Recording])] {
        let cal = Calendar.current
        let sorted = visibleRecordings.sorted { $0.createdAt > $1.createdAt }
        let groups = Dictionary(grouping: sorted) { cal.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { (day: $0, items: groups[$0] ?? []) }
    }

    /// 섹션 헤더: 오늘 / 어제 / 그 외 한국어 날짜.
    static func dateLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "오늘" }
        if cal.isDateInYesterday(day) { return "어제" }
        return day.formatted(.dateTime.year().month().day().weekday(.abbreviated)
            .locale(Locale(identifier: "ko_KR")))
    }
}

struct HistoryRow: View {
    let recording: Recording
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon).foregroundStyle(Theme.Palette.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title).font(Theme.Font.bodyUI).lineLimit(1)
                HStack(spacing: 4) {
                    Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if speakerCount > 1 { Text("· \(speakerCount)명") }
                }
                .font(Theme.Font.monoData)
                .foregroundStyle(Theme.Palette.outline)
                .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.xs)
            if recording.duration > 0 {
                Text(durationText)
                    .font(Theme.Font.monoData)
                    .foregroundStyle(Theme.Palette.outline)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    /// 구별되는 화자 수("나"·"상대1"·"상대2"… 중 비어있지 않은 라벨).
    private var speakerCount: Int {
        Set(recording.segments.map(\.speakerLabel)).subtracting([""]).count
    }

    /// 길이 배지: 1시간 미만은 m:ss, 이상은 h:mm:ss.
    private var durationText: String {
        let s = Int(recording.duration.rounded())
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    private var icon: String {
        if recording.source.screen { return "rectangle.on.rectangle" }
        if recording.source.systemAudio && recording.source.microphone { return "person.wave.2" }
        if recording.source.systemAudio { return "speaker.wave.2" }
        return "mic"
    }
}

/// 녹음 이름 변경 시트: 현재 제목으로 채운 텍스트필드 + 저장/취소.
/// 빈 이름은 저장 비활성(AppState.renameRecording도 이중 가드).
struct RenameRecordingSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let recording: Recording
    @State private var title: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("이름 변경").font(Theme.Font.titleSm)
            TextField("녹음 이름", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("저장") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 360)
        .onAppear { title = recording.title; focused = true }
    }

    private func commit() {
        // 빈/공백 이름이면 닫지 않고 입력을 유지('저장' 버튼 비활성 조건과 일치, onSubmit 경로도 동일 가드).
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state.renameRecording(recording.id, to: title)
        dismiss()
    }
}

#if DEBUG
#Preview("HistorySidebar") {
    HistorySidebar()
        .environment(AppState.preview)
        .frame(width: 260, height: 400)
}
#endif
