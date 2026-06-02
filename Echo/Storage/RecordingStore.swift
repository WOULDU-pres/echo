import Foundation

/// 녹음 목록을 단일 JSON 파일(`recordings.json`)로 영속화한다.
///
/// `Recording` 은 `Codable`, `audioTracks` 의 키 `AudioChannel` 은 `String` raw value 의
/// `Codable` 이므로 JSON 객체로 인코딩된다. 저장은 `.atomic` 으로 부분 쓰기를 방지한다.
struct RecordingStore {
    let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("recordings.json") }
    /// 손상된 목록 파일을 보존하는 백업 경로(디코드 실패 시 덮어쓰기 전에 복사).
    var backupURL: URL { directory.appendingPathComponent("recordings.corrupt.json") }

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Echo", isDirectory: true)) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func save(_ recordings: [Recording]) throws {
        let data = try JSONEncoder().encode(recordings)
        try data.write(to: fileURL, options: .atomic)
    }

    /// 로드 실패 종류. 디코드 실패(손상)만 백업을 시도하며, `backupURL`에 성공 여부를 담는다.
    /// 파일 읽기 실패(권한 등)는 일반 Error로 전파하며 백업을 약속하지 않는다(원본을 건드리지 않으므로).
    enum LoadError: Error {
        /// 목록 파일이 손상됨(디코드 실패). `backedUp`=백업된 위치(백업 실패 시 nil → 호출자가 '백업 못함' 안내).
        case corrupt(backedUp: URL?)
    }

    /// 목록을 로드한다.
    /// - 파일 없음/빈 파일(0바이트): 정상으로 보고 빈 배열.
    /// - 읽기 실패(권한 등): 그대로 throw(원본 보존, 백업 약속 없음).
    /// - 디코드 실패(손상): 원본을 `backupURL`로 **원자적** 백업한 뒤 `LoadError.corrupt(backedUp:)`를 던진다.
    ///   백업 성공 여부를 함께 전달해 호출자(AppState)가 정직하게 경고하도록 한다.
    func load() throws -> [Recording] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)   // 읽기 실패는 백업 약속 없이 그대로 전파
        guard !data.isEmpty else { return [] }     // 빈 파일 = 정상 빈 목록(손상 아님)
        do {
            return try JSONDecoder().decode([Recording].self, from: data)
        } catch {
            throw LoadError.corrupt(backedUp: backupCorrupt(data))
        }
    }

    /// 손상 데이터를 `backupURL`로 백업. 성공 시 URL, 실패 시 nil.
    /// `.atomic`(임시파일→교체)이라 쓰기 실패 시 기존 백업이 파괴되지 않는다(직전 정상 백업 보존).
    private func backupCorrupt(_ data: Data) -> URL? {
        do {
            try data.write(to: backupURL, options: .atomic)
            return backupURL
        } catch {
            return nil
        }
    }
}
