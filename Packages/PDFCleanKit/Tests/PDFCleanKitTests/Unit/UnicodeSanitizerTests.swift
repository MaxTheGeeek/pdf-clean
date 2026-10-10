import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U01…TC-U04 (T-010).
@Suite("UnicodeSanitizer")
struct UnicodeSanitizerTests {
    // MARK: TC-U01 — removal table, one case per range edge

    @Test(
        "removes every §6 step 3 code point and counts it",
        arguments: [
            // C0 controls (excluding LF/TAB) and DEL/C1.
            "\u{0001}", "\u{001F}", "\u{007F}", "\u{0080}", "\u{009F}",
            // CGJ, ALM.
            "\u{034F}", "\u{061C}",
            // Hangul fillers.
            "\u{115F}", "\u{1160}", "\u{3164}", "\u{FFA0}",
            // Khmer inherent vowels.
            "\u{17B4}", "\u{17B5}",
            // Mongolian variation selectors.
            "\u{180B}", "\u{180F}",
            // ZWSP.
            "\u{200B}",
            // LRM/RLM.
            "\u{200E}", "\u{200F}",
            // Embeddings/overrides, isolates.
            "\u{202A}", "\u{202E}", "\u{2066}", "\u{2069}",
            // Word joiner / invisible operators, deprecated format characters.
            "\u{2060}", "\u{2064}", "\u{206A}", "\u{206F}",
            // BOM.
            "\u{FEFF}",
            // Interlinear annotation / object replacement.
            "\u{FFF9}", "\u{FFFC}",
            // Variation selectors (unconditional) and supplement.
            "\u{FE00}", "\u{FE0D}", "\u{E0100}", "\u{E01EF}",
            // TAG block.
            "\u{E0001}", "\u{E007F}",
            // Unassigned (Cn).
            "\u{2065}",
        ] as [Unicode.Scalar]
    )
    func removesInvisibleCodepoint(_ scalar: Unicode.Scalar) {
        let (text, counts) = UnicodeSanitizer.sanitize("a\(scalar)b")
        #expect(text == "ab")
        #expect(counts.removedInvisibleCodepoints == 1)
    }

    @Test("private use code points are counted separately")
    func removesPrivateUse() {
        for scalar: Unicode.Scalar in ["\u{E000}", "\u{F8FF}", "\u{F0000}", "\u{10FFFD}"] {
            let (text, counts) = UnicodeSanitizer.sanitize("a\(scalar)b")
            #expect(text == "ab")
            #expect(counts.removedPrivateUseCodepoints == 1)
            #expect(counts.removedInvisibleCodepoints == 0)
        }
    }

    @Test("replacement character is removed and flagged")
    func replacementCharacterFlagged() {
        let (text, counts) = UnicodeSanitizer.sanitize("a\u{FFFD}b")
        #expect(text == "ab")
        #expect(counts.removedInvisibleCodepoints == 1)
        #expect(counts.sawReplacementCharacter)
    }

    @Test("soft hyphen mid-word is removed; at end of word becomes a hyphen")
    func softHyphen() {
        let midWord = UnicodeSanitizer.sanitize("a\u{00AD}b")
        #expect(midWord.text == "ab")
        #expect(midWord.counts.removedInvisibleCodepoints == 1)

        let endOfWord = UnicodeSanitizer.sanitize("foo\u{00AD}")
        #expect(endOfWord.text == "foo-")
        #expect(endOfWord.counts.removedInvisibleCodepoints == 0)

        let beforeSpace = UnicodeSanitizer.sanitize("foo\u{00AD} bar")
        #expect(beforeSpace.text == "foo- bar")
        #expect(beforeSpace.counts.removedInvisibleCodepoints == 0)
    }

    // MARK: TC-U02 — ZWNJ/ZWJ context exceptions

    @Test("Persian ZWNJ between Arabic-script letters is kept")
    func zwnjPersianKept() {
        let (text, counts) = UnicodeSanitizer.sanitize(
            "\u{0645}\u{06CC}\u{200C}\u{062E}\u{0648}\u{0627}\u{0647}\u{0645}")
        #expect(text.unicodeScalars.contains(Unicode.Scalar(0x200C)!))
        #expect(counts.removedInvisibleCodepoints == 0)
    }

    @Test("Devanagari ZWJ conjunct is kept")
    func zwjDevanagariKept() {
        let (text, counts) = UnicodeSanitizer.sanitize("\u{0915}\u{200D}\u{0937}")
        #expect(text.unicodeScalars.contains(Unicode.Scalar(0x200D)!))
        #expect(counts.removedInvisibleCodepoints == 0)
    }

    @Test("emoji ZWJ sequence is kept")
    func zwjEmojiSequenceKept() {
        let (text, counts) = UnicodeSanitizer.sanitize("\u{1F468}\u{200D}\u{1F469}")
        #expect(text.unicodeScalars.contains(Unicode.Scalar(0x200D)!))
        #expect(counts.removedInvisibleCodepoints == 0)
    }

    @Test("ZWNJ between Latin letters is removed")
    func zwnjLatinRemoved() {
        let (text, counts) = UnicodeSanitizer.sanitize("a\u{200C}b")
        #expect(text == "ab")
        #expect(counts.removedInvisibleCodepoints == 1)
    }

    // MARK: TC-U03 — ligatures, PUA bullets, NFC, unaffected characters

    @Test("ligatures decompose and are counted")
    func ligaturesDecompose() {
        let (text, counts) = UnicodeSanitizer.sanitize("\u{FB01}sh")
        #expect(text == "fish")
        #expect(counts.normalizedLigatures == 1)
    }

    @Test("PUA bullets map to a plain bullet")
    func puaBulletMapped() {
        let (text, _) = UnicodeSanitizer.sanitize("\u{F0B7} Item")
        #expect(text == "• Item")
    }

    @Test("NFC composes decomposed accents")
    func nfcComposes() {
        let (text, _) = UnicodeSanitizer.sanitize("e\u{0301}")
        #expect(text == "\u{00E9}")
        #expect(text.count == 1)
    }

    @Test("umlauts, ß, accents and ² ½ ™ are unaffected")
    func unaffectedCharacters() {
        #expect(UnicodeSanitizer.sanitize("Größe").text == "Größe")
        #expect(UnicodeSanitizer.sanitize("café").text == "café")
        #expect(UnicodeSanitizer.sanitize("Straße").text == "Straße")
        #expect(UnicodeSanitizer.sanitize("x²=½™").text == "x²=½™")
    }

    // MARK: TC-U04 — whitespace normalisation

    @Test("every Zs character becomes a space and is counted")
    func zsBecomesSpace() {
        let (text, counts) = UnicodeSanitizer.sanitize("a\u{00A0}\u{2003}b")
        #expect(text == "a b")
        #expect(counts.normalizedWhitespace == 2)
    }

    @Test("runs of spaces collapse to one")
    func collapsesRuns() {
        #expect(UnicodeSanitizer.sanitize("a   b").text == "a b")
    }

    @Test("TAB outside preformatted becomes a space; inside preformatted stays a TAB")
    func tabHandling() {
        let outside = UnicodeSanitizer.sanitize("a\tb", isPreformatted: false)
        #expect(outside.text == "a b")
        #expect(outside.counts.normalizedWhitespace == 1)

        let inside = UnicodeSanitizer.sanitize("a\tb", isPreformatted: true)
        #expect(inside.text == "a\tb")
        #expect(inside.counts.normalizedWhitespace == 0)
    }

    @Test("leading and trailing whitespace is trimmed")
    func trims() {
        #expect(UnicodeSanitizer.sanitize("  text  ").text == "text")
    }
}
