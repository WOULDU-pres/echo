import Foundation
import Observation

/// 녹음 캡처 라이프사이클(전사 진행은 transcription 큐가 따로 관리).
enum RecordingPhase: Equatable, Sendable {
    case idle
    case recording(since: Date)
    case paused
}

/// 라이브 전사 미리보기 모드(녹음 중 화면).
enum LiveViewMode: String, CaseIterable, Identifiable, Sendable {
    case structured   // 모드 A: 정보 밀도형
    case zen          // 모드 B: 미니멀형
    var id: String { rawValue }
    var label: String { self == .structured ? "Structured" : "Zen" }
}

/// 전사 작업 상태.
enum JobStatus: Equatable, Sendable {
    case pending      // 대기(큐)
    case processing   // 처리 중
    case failed(String)
}

/// 전사 작업의 입력 종류.
enum JobKind: Sendable {
    case file(URL)
    case recording(tracks: [AudioChannel: URL], source: CaptureSource, createdAt: Date, duration: TimeInterval, videoURL: URL?)
    /// 기존 녹음을 현재 설정(언어·화자 구분 민감도)으로 다시 전사 → 그 녹음을 갱신(새로 만들지 않음).
    case reTranscribe(recordingID: UUID, tracks: [AudioChannel: URL])
}

/// 전사 큐의 한 작업. 완료되면 큐에서 제거되고 결과가 recordings에 추가된다.
struct TranscriptionJob: Identifiable, Sendable {
    let id: UUID
    var name: String
    var status: JobStatus
    let kind: JobKind
    /// 현재 전사 진행률(0...1). nil이면 불확정(시작 전·진행률 미지원). 처리 중에만 갱신.
    var progress: Double?

    init(id: UUID = UUID(), name: String, status: JobStatus = .pending, kind: JobKind) {
        self.id = id
        self.name = name
        self.status = status
        self.kind = kind
        self.progress = nil
    }
}

/// 앱 전역 상태. UI는 여기에만 바인딩한다. 모든 변경은 메인 액터에서.
///
/// 전사는 **단일 직렬 워커**가 큐(`jobs`)를 하나씩 처리한다. 동시 전사는 WhisperKit의
/// ANE 경합(ANEProgramProcessRequestDirect 실패 → 빈 결과)을 유발하므로 절대 병렬 호출하지 않는다.
/// 전사 중에 새 파일이 들어오면 큐 뒤에 쌓이고(큐잉), 완료되는 즉시 recordings에 추가된다.
@MainActor
@Observable
final class AppState {
    // 설정
    var source: CaptureSource = .meeting
    var language: String = "ko"
    var liveViewMode: LiveViewMode = .structured
    /// 라이브 미리보기(Apple SpeechTranscriber). 기본 끔(에셋 미설치 시 크래시 방지, 옵트인).
    var livePreviewEnabled: Bool = false
    /// 화자 구분(FluidAudio). 옵트인. 켜면 시스템 트랙(녹음)/전체 트랙(파일)에서 화자 분리.
    /// 마이크 트랙은 항상 "나"로 유지(물리적으로 정확). 설정에 영속.
    var diarizationEnabled: Bool = UserDefaults.standard.bool(forKey: "diarizationEnabled") {
        didSet { UserDefaults.standard.set(diarizationEnabled, forKey: "diarizationEnabled") }
    }
    /// 화자 구분 민감도(클러스터링 임계값 0.6~0.9). 높을수록 화자 적게(비슷한 목소리를 합침). 기본 0.8. 영속.
    var diarizationThreshold: Double = (UserDefaults.standard.object(forKey: "diarizationThreshold") as? Double) ?? 0.8 {
        didSet { UserDefaults.standard.set(diarizationThreshold, forKey: "diarizationThreshold") }
    }

    // 녹음 캡처 상태
    var phase: RecordingPhase = .idle
    var liveSegments: [TranscriptSegment] = []
    var currentLevel: Float = 0

    // 전사 큐(대기/진행/실패). 완료 항목은 제거되고 recordings로 이동.
    var jobs: [TranscriptionJob] = []

    // 영속
    var recordings: [Recording] = []
    /// 사이드바 선택(Shift/Cmd 다중 선택 지원). 1개일 때만 detail에 자막 표시.
    var selection: Set<Recording.ID> = []
    /// 목록 파일 로드 실패(손상) 시 1회 경고. RootView가 alert로 표시 후 nil로 비운다.
    var loadWarning: String?

    /// 단일 선택 시 그 녹음(detail 표시용). 0개 또는 여러 개면 nil.
    var selectedRecording: Recording? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return recordings.first { $0.id == id }
    }

    // 협력자
    private let coordinator: RecordingCoordinator
    private let batchTranscriber: any Transcriber
    private let livePreview: (any LiveTranscriber)?
    private let diarizer: DiarizationService
    private let store: RecordingStore

    init(
        coordinator: RecordingCoordinator = RecordingCoordinator(),
        batchTranscriber: any Transcriber = WhisperKitBatchTranscriber(),
        livePreview: (any LiveTranscriber)? = LivePreviewTranscriber(),
        diarizer: DiarizationService = DiarizationService(),
        store: RecordingStore = RecordingStore()
    ) {
        self.coordinator = coordinator
        self.batchTranscriber = batchTranscriber
        self.livePreview = livePreview
        self.diarizer = diarizer
        self.store = store
        do {
            recordings = try store.load()
        } catch let RecordingStore.LoadError.corrupt(backedUp) {
            // 손상(디코드 실패): 빈 목록으로 시작. 백업 성공 여부에 따라 정직하게 안내.
            recordings = []
            if let bak = backedUp {
                loadWarning = "녹음 목록 파일이 손상되어 빈 목록으로 시작합니다.\n원본은 다음 위치에 백업했습니다:\n\(bak.path)"
            } else {
                loadWarning = "녹음 목록 파일이 손상되어 빈 목록으로 시작합니다.\n자동 백업에 실패했습니다 — recordings.json을 직접 보관하세요."
            }
        } catch {
            // 읽기 실패 등(원본은 그대로일 수 있음): 빈 시작 + 백업을 약속하지 않는 경고.
            recordings = []
            loadWarning = "녹음 목록 파일을 읽지 못했습니다. 빈 목록으로 시작합니다.\n(\(error.localizedDescription))"
        }
        if let first = recordings.first { selection = [first.id] }
    }

    private func persist() { try? store.save(recordings) }

    // MARK: - 파생 상태

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }
    /// 진행/대기 중인 전사 작업 수(모달 자동 표시 트리거).
    var activeJobCount: Int { jobs.filter { $0.status == .pending || $0.status == .processing }.count }
    var hasJobs: Bool { !jobs.isEmpty }

    /// 현재 처리 중인 작업의 진행률(0...1). 없거나 불확정이면 nil.
    var currentJobProgress: Double? { jobs.first { $0.status == .processing }?.progress }

    /// 모달을 닫았을 때 띄우는 미니 게이지 라벨.
    var miniProgressLabel: String {
        let n = activeJobCount
        if let p = currentJobProgress { return "\(Int((p * 100).rounded()))% · \(n)개" }
        return "\(n)개 처리 중"
    }

    /// 진행 중 작업의 진행률 갱신(백그라운드 콜백 → 메인액터). 처리 중일 때만 반영.
    /// 단조 증가만 허용 — 매 틱이 별도 `Task { @MainActor }`로 hop 하므로 도착 순서가 보장되지
    /// 않는다. 낮은 값이 늦게 도착해도 게이지가 뒤로 가지 않도록 현재값보다 작으면 무시한다.
    func setJobProgress(_ id: UUID, _ value: Double) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].status == .processing else { return }
        let clamped = min(max(value, 0), 1)
        if let cur = jobs[i].progress, clamped < cur { return }
        jobs[i].progress = clamped
    }

    /// 현재 녹음 경과(초, 일시정지 시간 제외). REC 타이머 표시용 — stopRecording의 저장 길이와 같은 공식.
    func recordingElapsed(asOf now: Date) -> TimeInterval {
        guard let s = startedAt else { return 0 }
        let inProgressPause = pausedAt.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(s) - pausedTotal - inProgressPause)
    }

    // MARK: - 기록 편집/삭제

    func updateSegmentText(recordingID: Recording.ID, segmentID: TranscriptSegment.ID, text: String) {
        guard let ri = recordings.firstIndex(where: { $0.id == recordingID }),
              let si = recordings[ri].segments.firstIndex(where: { $0.id == segmentID }) else { return }
        recordings[ri].segments[si].text = text
        persist()
    }

    func deleteRecording(_ id: Recording.ID) {
        recordings.removeAll { $0.id == id }
        selection.remove(id)
        if selection.isEmpty, let first = recordings.first { selection = [first.id] }
        persist()
    }

    /// 지정한 녹음들을 일괄 삭제(영구). 빈 집합은 무시한다 — 호출자는 항상 삭제 대상을
    /// 명시적으로 스냅샷해 넘긴다(빈 인자=현재 selection 삭제 식의 함정 폴백 없음).
    func deleteRecordings(_ ids: Set<Recording.ID>) {
        guard !ids.isEmpty else { return }
        recordings.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        if selection.isEmpty, let first = recordings.first { selection = [first.id] }
        persist()
    }

    /// 사이드바 수동 재배치(드래그앤드롭). 같은 날짜 그룹/전체 순서 반영을 위해 인덱스로 이동.
    func moveRecordings(from offsets: IndexSet, to destination: Int) {
        recordings.move(fromOffsets: offsets, toOffset: destination)
        persist()
    }

    /// 녹음 제목 변경. 공백만/빈 문자열은 무시(기존 제목 유지). 양끝 공백 정리 후 영속.
    func renameRecording(_ id: Recording.ID, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        guard recordings[i].title != trimmed else { return }
        recordings[i].title = trimmed
        persist()
    }

    /// 빈 전사(segments 없음) 녹음 개수. 옛 버그로 남은 항목 정리 버튼 노출/문구용.
    var emptyRecordingCount: Int { recordings.lazy.filter { $0.segments.isEmpty }.count }

    /// 빈 전사 녹음을 모두 제거(영구). 제거한 개수를 반환.
    @discardableResult
    func cleanupEmptyRecordings() -> Int {
        let removed = Set(recordings.filter { $0.segments.isEmpty }.map(\.id))
        guard !removed.isEmpty else { return 0 }
        recordings.removeAll { removed.contains($0.id) }
        selection.subtract(removed)
        if selection.isEmpty, let first = recordings.first { selection = [first.id] }
        persist()
        return removed.count
    }

    // MARK: - 전사 큐

    /// 드롭/파일선택으로 들어온 URL들(오디오만, 폴더는 1단계 확장)을 큐에 넣고 워커를 깨운다.
    func enqueueFiles(_ urls: [URL]) {
        let files = Self.expandAudioURLs(urls)
        guard !files.isEmpty else { return }
        for f in files {
            jobs.append(TranscriptionJob(name: f.lastPathComponent, kind: .file(f)))
        }
        startWorker()
    }

    func retryJob(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].status = .pending
        startWorker()
    }

    /// 기존 녹음을 현재 설정(언어·화자 구분 민감도)으로 다시 전사. 결과는 같은 녹음을 갱신한다.
    /// 긴 녹음은 시간이 걸리며 진행 모달에서 취소할 수 있다.
    func retranscribe(_ id: Recording.ID) {
        guard let rec = recordings.first(where: { $0.id == id }), !rec.audioTracks.isEmpty else { return }
        // 같은 녹음의 재전사가 이미 큐에 있으면 중복 실행을 막는다(긴 녹음 재전사 낭비 방지).
        let alreadyQueued = jobs.contains {
            if case .reTranscribe(let rid, _) = $0.kind { return rid == id }
            return false
        }
        guard !alreadyQueued else { return }
        jobs.append(TranscriptionJob(name: "재전사 · \(rec.title)",
                                     kind: .reTranscribe(recordingID: id, tracks: rec.audioTracks)))
        startWorker()
    }

    func dismissJob(_ id: UUID) { jobs.removeAll { $0.id == id } }

    /// 모든 실패 작업 닫기(모달 정리).
    func dismissFailedJobs() { jobs.removeAll { if case .failed = $0.status { return true }; return false } }

    /// 취소 요청된 진행 중 작업 ID. WhisperKit이 Task 취소를 인지(checkCancellation)하므로
    /// 워커 Task를 취소하면 in-flight 전사가 CancellationError로 중단된다. 그 에러/결과를
    /// "실패"가 아니라 "폐기"로 처리하기 위한 표식이며, 폐기 시 집합에서 제거한다.
    private var cancelledIDs: Set<UUID> = []

    /// 진행 중 작업이 취소 표시됐으면 큐에서 제거하고 표식을 지운다(결과/에러 폐기). 폐기했으면 true.
    private func discardIfCancelled(_ id: UUID) -> Bool {
        guard cancelledIDs.contains(id) else { return false }
        cancelledIDs.remove(id)
        jobs.removeAll { $0.id == id }
        return true
    }

    /// 작업 1건 취소.
    /// - 대기/실패: 즉시 큐에서 제거.
    /// - 진행 중: 워커 Task 취소(in-flight 전사를 중단) + 폐기 표식. 워커는 자동으로 새로 떠
    ///   나머지 대기 작업을 이어 처리한다(취소된 Task는 재사용하지 않음).
    func cancelJob(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        if jobs[i].status == .processing {
            cancelledIDs.insert(id)
            worker?.cancel()
        } else {
            jobs.remove(at: i)
        }
    }

    /// 전체 취소: 대기 작업을 모두 제거하고, 진행 중 작업은 폐기 표식 + 워커 취소.
    /// 실패 작업은 건드리지 않는다('실패 항목 지우기'가 따로 담당).
    func cancelAllJobs() {
        let processingIDs = jobs.filter { $0.status == .processing }.map(\.id)
        cancelledIDs.formUnion(processingIDs)
        jobs.removeAll { $0.status == .pending }
        if !processingIDs.isEmpty { worker?.cancel() }
    }

    private static let audioExts: Set<String> =
        ["mp3", "m4a", "wav", "caf", "aiff", "aif", "flac", "mp4", "mov", "aac"]

    private static func expandAudioURLs(_ urls: [URL]) -> [URL] {
        var files: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let kids = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                files.append(contentsOf: kids.filter { audioExts.contains($0.pathExtension.lowercased()) })
            } else if audioExts.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }
        return files
    }

    /// 단일 직렬 워커. 이미 돌고 있으면 새로 만들지 않는다(큐잉).
    private var worker: Task<Void, Never>?

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drainQueue()
            guard let self else { return }
            self.worker = nil
            // 취소(cancelJob/cancelAllJobs → worker.cancel)로 빠져나왔지만 아직 대기 작업이
            // 남아 있으면 새 워커로 이어 처리한다. 취소된 Task를 재사용하면 다음 transcribe가
            // 즉시 CancellationError로 실패하므로 반드시 새 Task를 만든다.
            if self.jobs.contains(where: { $0.status == .pending }) { self.startWorker() }
        }
    }

    /// 대기 작업이 없을 때까지 하나씩 직렬 처리(동시 전사 금지 → ANE 경합 방지).
    /// 취소되면(worker.cancel) 즉시 루프를 빠져나가 새 워커가 나머지를 잇게 한다.
    private func drainQueue() async {
        while !Task.isCancelled, let i = jobs.firstIndex(where: { $0.status == .pending }) {
            jobs[i].status = .processing
            jobs[i].progress = nil          // 재시도 등에서 진행률 초기화(처리 시작)
            await process(jobs[i])
        }
    }

    private func process(_ job: TranscriptionJob) async {
        switch job.kind {
        case .file(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                var segs = try await batchTranscriber.transcribe(url, language: language,
                    onProgress: { [weak self] f in Task { @MainActor in self?.setJobProgress(job.id, f) } })
                if discardIfCancelled(job.id) { return }   // 취소 → in-flight 결과 폐기
                guard !segs.isEmpty else {
                    failJob(job.id, "전사 결과가 비어 있습니다 (무음이거나 인식 실패)")
                    return
                }
                // 파일은 채널 정보가 없으므로(mixed) 켜져 있으면 전체 트랙 화자 구분.
                if diarizationEnabled, let spans = try? await diarizer.diarize(url, threshold: Float(diarizationThreshold)) {
                    segs = SpeakerAssigner.assign(segments: segs, spans: spans)
                }
                if discardIfCancelled(job.id) { return }   // 화자 구분 중 취소 반영
                finishJob(job.id, Recording(
                    title: url.deletingPathExtension().lastPathComponent,
                    duration: segs.last?.end ?? 0,   // 가져온 파일은 마지막 세그먼트 끝 ≈ 길이
                    source: .micOnly,
                    audioTracks: [.mixed: url],
                    segments: segs,
                    language: language,
                    transcriptionModel: WhisperKitBatchTranscriber.modelIdentifier))
            } catch {
                if discardIfCancelled(job.id) { return }   // 취소로 인한 CancellationError → 폐기(실패 아님)
                failJob(job.id, error.localizedDescription)
            }

        case .recording(let tracks, let src, let createdAt, let dur, let videoURL):
            var perChannel: [[TranscriptSegment]] = []
            let total = max(tracks.count, 1)
            for (idx, (channel, url)) in tracks.enumerated() {
                if Task.isCancelled || cancelledIDs.contains(job.id) { break }   // 취소 → 남은 채널 단락
                let base = Double(idx)   // 멀티트랙: 트랙별 0...1을 전체 0...1로 스케일
                if var segs = try? await batchTranscriber.transcribe(url, language: language,
                    onProgress: { [weak self] f in Task { @MainActor in self?.setJobProgress(job.id, (base + f) / Double(total)) } }) {
                    segs = segs.map { var s = $0; s.channel = channel; return s }
                    // 하이브리드: 시스템 트랙만 화자 구분(마이크 = "나" 불변, 물리적으로 정확).
                    // diarize는 취소를 인지하지 못하므로, 이미 취소됐으면 시작 자체를 건너뛴다(결과 폐기 예정).
                    if diarizationEnabled, channel == .system,
                       !Task.isCancelled, !cancelledIDs.contains(job.id),
                       let spans = try? await diarizer.diarize(url, threshold: Float(diarizationThreshold)) {
                        segs = SpeakerAssigner.assign(segments: segs, spans: spans)
                    }
                    perChannel.append(segs)
                }
            }
            if discardIfCancelled(job.id) { return }   // 취소 → 폐기(실패 아님)
            let merged = TranscriptMerger.merge(perChannel)
            guard !merged.isEmpty else {
                failJob(job.id, "전사 결과가 비어 있습니다 (무음이거나 권한 문제)")
                return
            }
            finishJob(job.id, Recording(
                title: "녹음 \(merged.first?.timecode ?? "")",
                createdAt: createdAt,
                duration: dur,
                source: src,
                audioTracks: tracks,
                videoURL: videoURL,
                segments: merged,
                language: language,
                transcriptionModel: WhisperKitBatchTranscriber.modelIdentifier))

        case .reTranscribe(let recID, let tracks):
            // 기존 트랙을 현재 설정으로 다시 전사 → 그 녹음의 segments만 갱신(메타·트랙 파일 유지).
            var perChannel: [[TranscriptSegment]] = []
            let total = max(tracks.count, 1)
            for (idx, (channel, url)) in tracks.enumerated() {
                if Task.isCancelled || cancelledIDs.contains(job.id) { break }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let base = Double(idx)
                if var segs = try? await batchTranscriber.transcribe(url, language: language,
                    onProgress: { [weak self] f in Task { @MainActor in self?.setJobProgress(job.id, (base + f) / Double(total)) } }) {
                    segs = segs.map { var s = $0; s.channel = channel; return s }
                    // 마이크(="나")는 화자 불변. 시스템/믹스 트랙에만 현재 민감도로 화자 구분.
                    if diarizationEnabled, channel != .microphone,
                       !Task.isCancelled, !cancelledIDs.contains(job.id),
                       let spans = try? await diarizer.diarize(url, threshold: Float(diarizationThreshold)) {
                        segs = SpeakerAssigner.assign(segments: segs, spans: spans)
                    }
                    perChannel.append(segs)
                }
            }
            if discardIfCancelled(job.id) { return }
            let merged = TranscriptMerger.merge(perChannel)
            guard !merged.isEmpty else {
                failJob(job.id, "재전사 결과가 비어 있습니다 (트랙 파일 접근 불가이거나 무음)")
                return
            }
            updateRecordingSegments(recID, merged)
            jobs.removeAll { $0.id == job.id }
        }
    }

    /// 완료 → recordings에 즉시 추가(목록에서 바로 보임) + 선택 + 영속 + 큐에서 제거.
    private func finishJob(_ jobID: UUID, _ recording: Recording) {
        recordings.insert(recording, at: 0)
        selection = [recording.id]
        persist()
        jobs.removeAll { $0.id == jobID }
    }

    private func failJob(_ jobID: UUID, _ message: String) {
        guard let i = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[i].status = .failed(message)
    }

    /// 재전사 완료 → 기존 녹음의 segments만 교체(메타·트랙·정렬 위치 유지) + 영속.
    private func updateRecordingSegments(_ id: Recording.ID, _ segments: [TranscriptSegment]) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[i].segments = segments
        persist()
    }

    // MARK: - 녹음

    private var startedAt: Date?
    /// 일시정지 누적 시간(녹음 길이에서 제외). 일시정지 중이면 pausedAt에 그 시작 시각.
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private var liveTask: Task<Void, Never>?

    func startRecording() async {
        let dir = RecordingCoordinator.newSessionDirectory()
        let now = Date()
        startedAt = now
        pausedAt = nil
        pausedTotal = 0
        liveSegments = []
        coordinator.onMicLevel = { [weak self] level in
            Task { @MainActor in self?.currentLevel = level }
        }
        do {
            try await coordinator.start(source: source, into: dir)
            phase = .recording(since: now)
            if livePreviewEnabled, let live = livePreview, let stream = coordinator.liveBufferStream {
                let lang = language
                liveTask = Task { [weak self] in
                    guard let self else { return }
                    try? await live.ensureLanguageAsset(lang)
                    for await seg in live.stream(stream, language: lang) {
                        self.upsertLive(seg)
                    }
                }
            }
        } catch {
            phase = .idle
            // 캡처 시작 실패는 실패 작업으로 노출(모달에서 확인).
            jobs.append(TranscriptionJob(name: "녹음", status: .failed(error.localizedDescription),
                                         kind: .file(URL(fileURLWithPath: "/dev/null"))))
        }
    }

    private func upsertLive(_ seg: TranscriptSegment) {
        if let last = liveSegments.last, !last.isFinal {
            liveSegments[liveSegments.count - 1] = seg
        } else {
            liveSegments.append(seg)
        }
    }

    /// 일시정지: 캡처는 유지하되 기록 게이트를 닫아 이 구간은 녹음/길이에서 제외한다.
    func pauseRecording() {
        guard case .recording = phase else { return }
        coordinator.pause()
        pausedAt = Date()
        currentLevel = 0          // 일시정지=무입력. 레벨 미터를 0으로(마지막 값 고정 방지).
        phase = .paused
    }

    /// 재개: 일시정지 누적 시간을 더하고 게이트를 연다.
    func resumeRecording() {
        guard case .paused = phase, let s = startedAt else { return }
        if let p = pausedAt { pausedTotal += Date().timeIntervalSince(p); pausedAt = nil }
        coordinator.resume()
        phase = .recording(since: s)
    }

    /// 정지 → 캡처 종료 → 전사 작업을 큐에 추가(직렬 워커가 처리). 캡처와 전사를 분리.
    func stopRecording() async {
        // 정지 시점에 즉시 측정하고 .idle로 전이한다 → await coordinator.stop() 동안 Pause/Stop이
        // 비활성(재진입 방지)이고, 길이는 정지를 누른 순간 기준으로 고정된다.
        if let p = pausedAt { pausedTotal += Date().timeIntervalSince(p); pausedAt = nil }
        let started = startedAt ?? Date()
        let dur = max(0, Date().timeIntervalSince(started) - pausedTotal)
        phase = .idle
        liveSegments = []
        liveTask?.cancel(); liveTask = nil
        let tracks = await coordinator.stop()
        coordinator.onMicLevel = nil
        currentLevel = 0
        jobs.append(TranscriptionJob(
            name: "녹음 \(Date().formatted(date: .omitted, time: .shortened))",
            kind: .recording(tracks: tracks, source: source, createdAt: started,
                             duration: dur, videoURL: coordinator.videoURL)))
        startWorker()
    }
}

#if DEBUG
extension AppState {
    @MainActor static var preview: AppState {
        let s = AppState()
        s.recordings = [
            Recording(
                title: "샘플 회의",
                duration: 142,
                source: .meeting,
                segments: [
                    TranscriptSegment(start: 0, end: 3, text: "안녕하세요, 회의를 시작하겠습니다.", channel: .microphone, isFinal: true),
                    TranscriptSegment(start: 3, end: 7, text: "네, 자료 공유드릴게요.", channel: .system, isFinal: true),
                ],
                transcriptionModel: WhisperKitBatchTranscriber.modelIdentifier
            )
        ]
        if let first = s.recordings.first { s.selection = [first.id] }
        return s
    }
}
#endif
