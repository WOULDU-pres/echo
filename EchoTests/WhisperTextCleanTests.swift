import Testing
@testable import Echo

@Test func stripsWhisperSpecialTokens() {
    let raw = "<|startoftranscript|><|ko|><|transcribe|><|0.00|> 안녕하세요<|5.86|>"
    #expect(WhisperKitBatchTranscriber.cleanText(raw) == "안녕하세요")
}

@Test func collapsesWhitespaceAndTrims() {
    #expect(WhisperKitBatchTranscriber.cleanText("  네   그러면은  \n 시작하겠습니다 ") == "네 그러면은 시작하겠습니다")
}

@Test func tokenOnlySegmentBecomesEmpty() {
    #expect(WhisperKitBatchTranscriber.cleanText("<|startoftranscript|><|ko|>").isEmpty)
}
