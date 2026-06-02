import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// 최상위 레이아웃: NavigationSplitView(기록 사이드바 · 본문 · 설정 인스펙터) + 플로팅 컨트롤바.
struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false
    @State private var isDropTargeted = false
    @State private var showProgress = false
    @State private var importing = false

    var body: some View {
        NavigationSplitView {
            HistorySidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            DetailContentRouter()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 컨트롤바를 detail 영역 하단에 고정(콘텐츠 크기와 무관).
                .safeAreaInset(edge: .bottom) {
                    RecordingControlBar()
                        .padding(.bottom, Theme.Spacing.lg)
                }
                // 오디오 파일(여러 개 가능)을 끌어다 놓으면 전사 큐에 넣는다. 전사 중에 또 놓으면 큐에 추가.
                .dropDestination(for: URL.self) { urls, _ in
                    state.enqueueFiles(urls)
                    return true
                } isTargeted: { isDropTargeted = $0 }
                .overlay { if isDropTargeted { DropOverlay() } }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            importing = true
                        } label: {
                            Label("오디오 추가", systemImage: "plus")
                        }
                        .help("오디오 파일 추가 (여러 개 가능)")
                    }
                    ToolbarItem(placement: .automatic) {
                        Button {
                            showSettings.toggle()
                        } label: {
                            Label("설정", systemImage: "slider.horizontal.3")
                        }
                        .help("설정")
                    }
                }
        }
        .inspector(isPresented: $showSettings) {
            SettingsInspector()
        }
        .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        // 전사 진행 모달: 새 전사(활성 작업)가 등장하면 자동으로 띄운다.
        .onChange(of: state.activeJobCount) { _, count in
            if count > 0 { showProgress = true }
        }
        // 큐가 완전히 빌 때만 자동으로 닫는다. 활성 작업이 0이어도 실패 작업이 남아 있으면
        // 모달을 유지해 재시도/'실패 항목 지우기' 접근을 보장한다(실패가 조용히 숨겨지지 않도록).
        .onChange(of: state.jobs.isEmpty) { _, empty in
            if empty { showProgress = false }
        }
        .sheet(isPresented: $showProgress) {
            TranscriptionProgressSheet(onClose: { showProgress = false })
        }
        // 녹음 유무와 무관하게 항상 파일 추가 가능(툴바 '오디오 추가'). 드래그앤드롭과 동일 경로.
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { state.enqueueFiles(urls) }
        }
        // 목록 파일 손상 시 1회 경고(원본은 백업됨).
        .alert("녹음 목록 로드 경고", isPresented: Binding(
            get: { state.loadWarning != nil },
            set: { if !$0 { state.loadWarning = nil } }
        )) {
            Button("확인", role: .cancel) { state.loadWarning = nil }
        } message: {
            if let w = state.loadWarning { Text(w) }
        }
        // 모달을 닫아도 전사 진행 상황을 우측 하단에 실시간 게이지로 노출(탭하면 모달 재오픈).
        .overlay(alignment: .bottomTrailing) {
            if state.activeJobCount > 0 && !showProgress {
                TranscriptionMiniGauge(onTap: { showProgress = true })
                    .padding(Theme.Spacing.lg)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.activeJobCount > 0 && !showProgress)
    }
}

/// 모달을 닫았을 때 우측 하단에 떠 있는 전사 진행 미니 게이지(원형 + 라벨). 탭하면 진행 모달을 다시 연다.
struct TranscriptionMiniGauge: View {
    @Environment(AppState.self) private var state
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.sm) {
                if let p = state.currentJobProgress {
                    ZStack {
                        Circle()
                            .stroke(Theme.Palette.outlineVariant.opacity(0.4), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: p)
                            .stroke(Theme.Palette.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: p)
                    }
                    .frame(width: 22, height: 22)
                } else {
                    ProgressView().controlSize(.small)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("전사 중").font(Theme.Font.bodyUI).foregroundStyle(Theme.Palette.onSurface)
                    Text(state.miniProgressLabel)
                        .font(Theme.Font.monoData).foregroundStyle(Theme.Palette.onSurfaceVariant)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Palette.outlineVariant.opacity(0.3)))
        .shadow(radius: 10, y: 3)
        .help("전사 진행 상황 보기")
    }
}

/// detail 영역 라우팅. 전사 진행은 모달이 담당하므로 여기서는 녹음/선택/빈상태만 분기.
struct DetailContentRouter: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if state.phase != .idle || !state.liveSegments.isEmpty {
            // 녹음/일시정지 중: 라이브 미리보기 화면 유지(일시정지여도 과거 녹음/빈 화면으로 빠지지 않음).
            LiveTranscriptView()
        } else if let rec = state.selectedRecording {
            // 1개 선택: 자막 표시
            RecordingDetailView(recording: rec)
        } else if state.selection.count > 1 {
            // 다중 선택: 일괄 삭제 안내
            MultiSelectionView(count: state.selection.count)
        } else {
            EmptyStateView()
        }
    }
}

/// 여러 녹음이 선택됐을 때(Shift/Cmd) 일괄 삭제 안내.
struct MultiSelectionView: View {
    @Environment(AppState.self) private var state
    let count: Int
    /// 삭제 확인 대상(버튼 누른 시점의 selection 스냅샷 — 확정까지 selection이 바뀌어도 대상 고정).
    @State private var deleteTargets: Set<Recording.ID>?
    var body: some View {
        ContentUnavailableView {
            Label("\(count)개 선택됨", systemImage: "checklist")
        } description: {
            Text("선택한 녹음을 한 번에 삭제할 수 있습니다.")
        } actions: {
            Button(role: .destructive) {
                deleteTargets = state.selection
            } label: {
                Label("\(count)개 삭제", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.secondary)
        }
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
}

/// 선택된 녹음의 최종(large-v3) 전사 + 재생 스크러버 + 편집 + 내보내기.
struct RecordingDetailView: View {
    @Environment(AppState.self) private var state
    let recording: Recording
    @State private var playback = PlaybackController()
    @State private var exporting = false
    @State private var exportDoc: TranscriptDocument?
    @State private var exportName = "transcript"
    @State private var userScrolling = false
    /// 본문 탭. 정리본이 있을 때만 토글로 전환 가능(없으면 항상 전사).
    @State private var tab: DetailTab = .transcript

    var body: some View {
        VStack(spacing: 0) {
            if recording.summary != nil {
                Picker("표시", selection: $tab) {
                    Text("전사").tag(DetailTab.transcript)
                    Text("정리본").tag(DetailTab.summary)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
                .padding(.top, Theme.Spacing.md)
            }

            if tab == .summary, let summary = recording.summary {
                SummaryView(summary: summary) { playback.seek(to: $0) }
            } else {
                transcriptView
            }

            PlaybackBar(controller: playback)
                .padding(Theme.Spacing.md)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { state.retranscribe(recording.id) } label: {
                    Label("재전사", systemImage: "arrow.clockwise")
                }
                .help("현재 설정(언어·화자 구분 민감도)으로 다시 전사")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { copyTranscript() } label: {
                    Label("복사", systemImage: "doc.on.doc")
                }
                .help("전사 텍스트를 클립보드에 복사")
                .disabled(recording.segments.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(TranscriptFormat.allCases, id: \.self) { fmt in
                        Button(fmt.fileExtension.uppercased()) { startExport(fmt) }
                    }
                } label: {
                    Label("내보내기", systemImage: "square.and.arrow.up")
                }
            }
        }
        .fileExporter(
            isPresented: $exporting,
            document: exportDoc,
            contentType: exportDoc?.contentType ?? .plainText,
            defaultFilename: exportName
        ) { _ in }
        .onAppear { playback.load(recording) }
        // 다른 녹음으로 바뀌면 재생을 다시 로드하고 탭을 전사로 되돌린다(정리본 없는 녹음 대비).
        .onChange(of: recording.id) { _, _ in
            playback.load(recording)
            tab = .transcript
        }
        .onDisappear { playback.stop() }
    }

    /// 저장 전사 목록(기존 화면). 정리본 토글에서 '전사'일 때 표시.
    private var transcriptView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    // 목업: 흰 카드(좌우 보더) + 최대폭 가운데, 행마다 구분선.
                    LazyVStack(spacing: 0) {
                        ForEach(recording.segments) { seg in
                            EditableTranscriptRow(
                                recordingID: recording.id,
                                segment: seg,
                                isActive: seg.id == activeID,
                                onSeek: { playback.seek(to: seg.start) }
                            )
                            .id(seg.id)
                        }
                    }
                    .frame(maxWidth: Theme.Layout.contentWidth)
                    .background(Theme.Palette.surfaceLowest)
                    .overlay {
                        Rectangle()
                            .strokeBorder(Theme.Palette.outlineVariant.opacity(0.4), lineWidth: 0.5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.lg)
                }
                .background(Theme.Palette.background)
                // 활성 줄 자동 추적(#9): 재생 중 활성 줄을 중앙으로. 사용자가 스크롤하면 양보.
                .onChange(of: activeID) { _, id in
                    guard playback.isPlaying, !userScrolling, let id else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
                }
                .onScrollPhaseChange { _, phase in
                    userScrolling = (phase == .interacting || phase == .decelerating)
                }
            }
        }
    }

    /// 현재 재생 시각이 속한 세그먼트(활성 하이라이트 대상).
    private var activeID: TranscriptSegment.ID? {
        guard playback.isPlaying else { return nil }
        return recording.segments.first {
            playback.currentTime >= $0.start && playback.currentTime < $0.end
        }?.id
    }

    private func startExport(_ fmt: TranscriptFormat) {
        let text = TranscriptExporter.export(recording.segments, as: fmt)
        exportDoc = TranscriptDocument(text: text, format: fmt)
        exportName = "\(recording.title).\(fmt.fileExtension)"
        exporting = true
    }

    /// 전사 전체를 일반 텍스트로 클립보드에 복사(빠른 복사 — 파일 피커 없이).
    private func copyTranscript() {
        let text = TranscriptExporter.export(recording.segments, as: .txt)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// detail 본문 탭. 정리본이 있을 때만 전환 가능.
enum DetailTab { case transcript, summary }

/// 정리본 화면: 맥락·흐름(overview) → 시간순 타임라인(클릭하면 그 시점으로 재생 이동) → 결론.
/// `recording.summary` 가 있을 때만 표시된다.
struct SummaryView: View {
    let summary: CallSummary
    /// 타임라인 항목 클릭 → 그 초로 재생 이동.
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if !summary.overview.isEmpty {
                    section("맥락 · 흐름") {
                        Text(summary.overview)
                            .font(Theme.Font.bodyReading)
                            .foregroundStyle(Theme.Palette.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !summary.timeline.isEmpty {
                    section("시간순 흐름") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(summary.timeline) { moment in
                                Button { onSeek(moment.at) } label: {
                                    HStack(alignment: .top, spacing: Theme.Spacing.md) {
                                        Text(moment.timecode)
                                            .font(Theme.Font.monoData)
                                            .foregroundStyle(Theme.Palette.primary)
                                            .monospacedDigit()
                                            .frame(width: Theme.Layout.timeGutter, alignment: .leading)
                                        Text(moment.text)
                                            .font(Theme.Font.bodyReading)
                                            .foregroundStyle(Theme.Palette.onSurface)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.vertical, Theme.Spacing.sm)
                                }
                                .buttonStyle(.plain)
                                .help("이 시점으로 이동")
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Theme.Palette.outlineVariant.opacity(0.4)).frame(height: 0.5)
                                }
                            }
                        }
                    }
                }
                if !summary.conclusion.isEmpty {
                    section("결론") {
                        Text(summary.conclusion)
                            .font(Theme.Font.bodyReading)
                            .foregroundStyle(Theme.Palette.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: Theme.Layout.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Palette.background)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Font.titleSm)
                .foregroundStyle(Theme.Palette.onSurfaceVariant)
            content()
        }
    }
}

/// 화자칩(목업): 화자 라벨을 화자 색으로. 마이크="나"(파랑), 시스템 화자는 인덱스별 색.
struct SpeakerChip: View {
    let segment: TranscriptSegment
    var body: some View {
        Text(segment.speakerLabel)
            .font(Theme.Font.speakerCaps)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.base))
            .foregroundStyle(tint)
    }
    private var tint: Color {
        if segment.channel == .microphone { return Theme.Palette.speakerMe }
        return Theme.Palette.speakerColor(for: segment.speakerIndex)
    }
}

/// 편집 가능한 저장 전사 행(목업): 좌측 칸(타임스탬프 + 화자칩, 세로 보더) + 텍스트, 행 구분선.
/// 활성 줄은 옅은 파랑 배경. 탭하면 시킹, 텍스트는 인라인 편집 후 영속화.
struct EditableTranscriptRow: View {
    let recordingID: Recording.ID
    let segment: TranscriptSegment
    let isActive: Bool
    let onSeek: () -> Void
    @Environment(AppState.self) private var state
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Button(action: onSeek) {
                    Text(segment.timecode)
                        .font(Theme.Font.monoData)
                        .foregroundStyle(isActive ? Theme.Palette.primary : Theme.Palette.outline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("이 위치로 이동")
                if !segment.speakerLabel.isEmpty {
                    SpeakerChip(segment: segment)
                }
            }
            .frame(width: Theme.Layout.timeGutter, alignment: .leading)
            .padding(Theme.Spacing.md)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Theme.Palette.outlineVariant.opacity(0.4)).frame(width: 0.5)
            }

            TextField("전사 내용", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.Font.bodyReading)
                .foregroundStyle(Theme.Palette.onSurface)
                .focused($focused)
                .onSubmit(commit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
        }
        .background(isActive ? Theme.Palette.primary.opacity(0.05) : Theme.Palette.surfaceLowest)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Palette.outlineVariant.opacity(0.4)).frame(height: 0.5)
        }
        .onAppear { draft = segment.text }
        .onChange(of: segment.text) { _, new in if !focused { draft = new } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        guard draft != segment.text else { return }
        state.updateSegmentText(recordingID: recordingID, segmentID: segment.id, text: draft)
    }
}

/// 전사 진행 팝업 모달: 처리 중(스피너)·대기·실패(재시도) 작업을 목록으로 보여준다.
/// 완료된 작업은 큐에서 빠지고 좌측 목록(사이드바)에 결과로 나타난다.
struct TranscriptionProgressSheet: View {
    @Environment(AppState.self) private var state
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("전사 중").font(Theme.Font.titleSm)
                    Text("모델: large-v3 · 한국어")   // 정직한 상태 표시(가짜 진행률 없음)
                        .font(Theme.Font.monoData)
                        .foregroundStyle(Theme.Palette.outline)
                }
                Spacer()
                if state.activeJobCount > 0 {
                    Text("\(state.activeJobCount)개 남음")
                        .font(Theme.Font.monoData)
                        .foregroundStyle(Theme.Palette.onSurfaceVariant)
                }
            }

            if state.jobs.isEmpty {
                Label("모두 완료", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Palette.primary)
                    .padding(.vertical, Theme.Spacing.sm)
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(state.jobs) { JobRow(job: $0) }
                    }
                }
                .frame(maxHeight: 260)
            }

            HStack {
                if state.activeJobCount > 1 {
                    Button("모두 취소", role: .destructive) { state.cancelAllJobs() }
                }
                if state.jobs.contains(where: { if case .failed = $0.status { return true }; return false }) {
                    Button("실패 항목 지우기") { state.dismissFailedJobs() }
                }
                Spacer()
                Button("닫기") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 420)
    }
}

/// 전사 작업 한 줄: 상태별 아이콘 + 파일명 (+ 실패 시 재시도/닫기).
struct JobRow: View {
    @Environment(AppState.self) private var state
    let job: TranscriptionJob

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            switch job.status {
            case .processing:
                ProgressView().controlSize(.small)
            case .pending:
                Image(systemName: "clock").foregroundStyle(Theme.Palette.outline)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.Palette.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(job.name).font(Theme.Font.bodyUI).lineLimit(1).truncationMode(.middle)
                if case .failed(let msg) = job.status {
                    Text(msg).font(Theme.Font.monoData).foregroundStyle(Theme.Palette.secondary).lineLimit(2)
                } else if case .processing = job.status {
                    if let p = job.progress {
                        HStack(spacing: Theme.Spacing.xs) {
                            ProgressView(value: p).frame(maxWidth: 150)
                            Text("\(Int((p * 100).rounded()))%")
                                .font(Theme.Font.monoData).foregroundStyle(Theme.Palette.onSurfaceVariant).monospacedDigit()
                        }
                    } else {
                        Text("large-v3 전사 중…").font(Theme.Font.monoData).foregroundStyle(Theme.Palette.onSurfaceVariant)
                    }
                } else {
                    Text("대기 중").font(Theme.Font.monoData).foregroundStyle(Theme.Palette.outline)
                }
            }
            Spacer()

            switch job.status {
            case .processing, .pending:
                Button { state.cancelJob(job.id) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain).foregroundStyle(Theme.Palette.outline)
                    .help("취소")
            case .failed:
                Button("재시도") { state.retryJob(job.id) }.controlSize(.small)
                Button { state.dismissJob(job.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(Theme.Palette.outline)
                    .help("닫기")
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Palette.surfaceLow, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }
}

/// 드래그 오버 시 detail 영역에 표시되는 드롭 안내 오버레이.
struct DropOverlay: View {
    var body: some View {
        ZStack {
            Theme.Palette.primary.opacity(0.06)
            RoundedRectangle(cornerRadius: Theme.Radius.xl)
                .strokeBorder(Theme.Palette.primary, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(Theme.Spacing.md)
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 40, weight: .light))
                Text("오디오 파일을 놓으면 전사합니다 (여러 개 가능)")
                    .font(Theme.Font.titleSm)
            }
            .foregroundStyle(Theme.Palette.primary)
        }
        .allowsHitTesting(false)
    }
}

struct EmptyStateView: View {
    @Environment(AppState.self) private var state
    @State private var importing = false

    var body: some View {
        ContentUnavailableView {
            Label("녹음을 시작하세요", systemImage: "mic")
        } description: {
            Text("오디오 파일을 끌어다 놓거나 아래 버튼으로 선택하면 large-v3로 전사합니다. 시스템 사운드와 마이크 녹음도 가능합니다.")
        } actions: {
            Button("오디오 파일 전사…") { importing = true }
                .buttonStyle(.borderedProminent)
        }
        // 여러 파일 선택 가능. 드래그앤드롭과 동일하게 전사 큐(enqueueFiles)로 순차 전사.
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                state.enqueueFiles(urls)
            }
        }
    }
}

#if DEBUG
#Preview("RootView") {
    RootView().environment(AppState.preview)
}
#endif
