import Testing
@testable import Echo

@Test func rmsOfSilenceIsZero() {
    #expect(LevelMeter.rms([0, 0, 0, 0]) == 0)
}

@Test func rmsOfConstantIsMagnitude() {
    #expect(abs(LevelMeter.rms([0.5, -0.5, 0.5, -0.5]) - 0.5) < 1e-6)
}

@Test func normalizedLevelClampsToUnit() {
    #expect(LevelMeter.normalized([1, 1, 1]) <= 1)
    #expect(LevelMeter.normalized([0, 0, 0]) == 0)
}
