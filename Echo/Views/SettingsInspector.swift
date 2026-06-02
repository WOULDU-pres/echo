import SwiftUI

/// 설정: 소스 토글 · 언어 · 라이브 미리보기 · 모델(고정 표기).
struct SettingsInspector: View {
    @Environment(AppState.self) private var state
    @State private var confirmingCleanup = false

    var body: some View {
        @Bindable var state = state
        Form {
            Section("입력 소스") {
                Toggle("마이크", isOn: $state.source.microphone)
                Toggle("시스템 사운드", isOn: $state.source.systemAudio)
                Toggle("화면 녹화", isOn: $state.source.screen)
                Toggle("트랙 분리 (나 / 상대)", isOn: $state.source.separateTracks)
            }

            Section("전사") {
                LabeledContent("언어", value: "한국어 (ko)")
                LabeledContent("최종 모델", value: "large-v3")   // 고정: turbo 미사용
                Toggle("라이브 미리보기", isOn: $state.livePreviewEnabled)
                Picker("라이브 뷰", selection: $state.liveViewMode) {
                    ForEach(LiveViewMode.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("화자 구분") {
                Toggle("화자 구분 (실험적)", isOn: $state.diarizationEnabled)
                if state.diarizationEnabled {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("더 나눔")
                        Slider(value: $state.diarizationThreshold, in: 0.6...0.9, step: 0.05)
                        Text("덜 나눔")
                    }
                    .font(Theme.Font.monoData)
                    .foregroundStyle(Theme.Palette.outline)
                }
            }

            Section("데이터 정리") {
                if state.emptyRecordingCount > 0 {
                    Button(role: .destructive) {
                        confirmingCleanup = true
                    } label: {
                        Label("빈 녹음 \(state.emptyRecordingCount)개 정리", systemImage: "trash")
                    }
                } else {
                    LabeledContent("빈 녹음", value: "없음")
                }
            }

            Section {
                LabeledContent("처리", value: "온디바이스 / 오프라인")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 280, minHeight: 320)
        .confirmationDialog("빈 녹음 정리", isPresented: $confirmingCleanup, titleVisibility: .visible) {
            Button("\(state.emptyRecordingCount)개 정리", role: .destructive) { state.cleanupEmptyRecordings() }
            Button("취소", role: .cancel) { }
        } message: {
            Text("전사 결과가 없는 빈 녹음 \(state.emptyRecordingCount)개를 영구 삭제합니다.")
        }
    }
}

#if DEBUG
#Preview("SettingsInspector") {
    SettingsInspector().environment(AppState.preview)
}
#endif
