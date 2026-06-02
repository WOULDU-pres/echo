import Testing
@testable import Echo

@MainActor
@Test func appStateStartsIdle() async {
    let state = AppState()
    #expect(state.phase == .idle)
}
