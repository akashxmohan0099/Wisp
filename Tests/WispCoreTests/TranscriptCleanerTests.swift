import Testing
@testable import WispCore

struct TranscriptCleanerTests {
    @Test
    func removesCommonFillersAndNormalizesSentence() {
        #expect(TranscriptCleaner.cleaned(" um, hey you know can you send this ") == "Hey can you send this.")
    }

    @Test
    func keepsExistingTerminalPunctuation() {
        #expect(TranscriptCleaner.cleaned("uh are we ready?") == "Are we ready?")
    }

    @Test
    func removesSpacingBeforePunctuation() {
        #expect(TranscriptCleaner.cleaned("hello , world !") == "Hello, world!")
    }

    @Test
    func returnsEmptyWhenOnlyFillers() {
        #expect(TranscriptCleaner.cleaned("um uh you know") == "")
    }
}
