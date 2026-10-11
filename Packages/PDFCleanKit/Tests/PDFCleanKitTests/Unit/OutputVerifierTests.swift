import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U11 (T-014).
@Suite("OutputVerifier")
struct OutputVerifierTests {
    @Test("clean text passes with no violations")
    func cleanTextPasses() {
        #expect(OutputVerifier.verify("Plain visible text.\nSecond line.").isEmpty)
    }

    @Test("allowed ZWNJ/ZWJ contexts pass")
    func allowedContextsPass() {
        // Persian ZWNJ between Arabic-script letters, and an emoji ZWJ sequence.
        #expect(OutputVerifier.verify("\u{0645}\u{06CC}\u{200C}\u{062E}\u{0648}").isEmpty)
        #expect(OutputVerifier.verify("\u{1F468}\u{200D}\u{1F469}").isEmpty)
    }

    @Test("TAB and LF are always allowed")
    func tabAndNewlineAllowed() {
        #expect(OutputVerifier.verify("a\tb\nc").isEmpty)
    }

    @Test("flags a forbidden invisible code point")
    func flagsForbiddenCodepoint() {
        let violations = OutputVerifier.verify("a\u{200B}b")
        #expect(violations == [.forbiddenCodepoint(scalar: 0x200B)])
    }

    @Test("flags a ZWNJ in a Latin (non-exempt) context")
    func flagsZWNJInLatinContext() {
        let violations = OutputVerifier.verify("a\u{200C}b")
        #expect(violations == [.forbiddenCodepoint(scalar: 0x200C)])
    }

    @Test("flags a non-ASCII space")
    func flagsNonASCIISpace() {
        let violations = OutputVerifier.verify("a\u{00A0}b")
        #expect(violations == [.nonASCIISpace(scalar: 0x00A0)])
    }

    @Test("flags a C0 control other than LF/TAB")
    func flagsC0Control() {
        let violations = OutputVerifier.verify("a\u{0001}b")
        #expect(violations == [.c0Control(scalar: 0x0001)])
    }

    @Test("flags a C1 control")
    func flagsC1Control() {
        let violations = OutputVerifier.verify("a\u{0085}b")
        #expect(violations == [.c0Control(scalar: 0x0085)])
    }

    @Test("flags a surviving soft hyphen")
    func flagsSoftHyphen() {
        let violations = OutputVerifier.verify("a\u{00AD}b")
        #expect(violations == [.forbiddenCodepoint(scalar: 0x00AD)])
    }

    @Test("flags a metadata value that leaked into the rendered text")
    func flagsMetadataLeak() {
        let violations = OutputVerifier.verify(
            "Visible content with Secret-Internal-Code embedded.",
            inventoryValues: ["Secret-Internal-Code"]
        )
        #expect(violations == [.metadataValueLeak])
    }

    @Test("a metadata value absent from the text is not flagged")
    func doesNotFlagAbsentMetadataValue() {
        let violations = OutputVerifier.verify(
            "The title is Quarterly Report here.",
            inventoryValues: ["Confidential"]
        )
        #expect(violations.isEmpty)
    }

    @Test("metadata values shorter than 6 characters are never checked")
    func ignoresShortMetadataValues() {
        let violations = OutputVerifier.verify("abc", inventoryValues: ["abc"])
        #expect(violations.isEmpty)
    }
}
