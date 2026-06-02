import SwiftUI

@main
struct EchoApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(state)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)

        // 메뉴바 상주 퀵 캡처(Task 5.5). 글로벌 핫키로 빠른 녹음 토글.
        MenuBarExtra("Echo", systemImage: state.isRecording ? "mic.fill" : "mic") {
            MenuBarContent()
                .environment(state)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsInspector()
                .environment(state)
        }
        .defaultSize(width: 400, height: 450)
        .windowResizability(.contentMinSize)
    }
}

/// 메뉴바 팝오버: 퀵 Record/Stop + 최근 기록 + 메인 창 열기.
private struct MenuBarContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.base) {
                Text("Echo").font(Theme.Font.titleSm)
                Spacer()
                if state.isRecording {
                    Label("녹음 중", systemImage: "record.circle.fill")
                        .font(Theme.Font.labelCaps)
                        .foregroundStyle(Theme.Palette.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            Button {
                Task { state.isRecording ? await state.stopRecording() : await state.startRecording() }
            } label: {
                Label(state.isRecording ? "정지" : "녹음 시작",
                      systemImage: state.isRecording ? "stop.fill" : "record.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 앱이 활성일 때 동작하는 단축키. 진짜 시스템 전역 핫키는 GlobalHotKey 스텁 참고.
            .keyboardShortcut("r", modifiers: [.command, .shift])

            if let last = state.recordings.first {
                Divider()
                Button {
                    state.selection = [last.id]
                    openWindow(id: "main")
                } label: {
                    Label("최근: \(last.title)", systemImage: "clock")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                }
            }

            Divider()
            Button {
                openWindow(id: "main")
            } label: {
                Label("메인 창 열기", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("종료") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .padding(Theme.Spacing.md)
        .frame(width: 260)
        .onAppear {
            // 시스템 전역 핫키(다른 앱 포커스 중에도 동작) 등록 시도. 미구현 시 무해한 no-op.
            GlobalHotKey.shared.onTrigger = {
                Task { @MainActor in
                    state.isRecording ? await state.stopRecording() : await state.startRecording()
                }
            }
            GlobalHotKey.shared.register()
        }
    }
}
