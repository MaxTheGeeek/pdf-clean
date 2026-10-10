import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U05 (T-011).
@Suite("HomoglyphNormalizer")
struct HomoglyphNormalizerTests {
    @Test("Cyrillic lookalike inside a Latin word is normalised")
    func mixedCyrillicLatinNormalized() {
        // The 'а' here is Cyrillic U+0430, mixed into an otherwise-Latin word.
        let (text, counts) = HomoglyphNormalizer.normalize("p\u{0430}ssword")
        #expect(text == "password")
        #expect(counts.normalizedHomoglyphs == 1)
    }

    @Test("pure Cyrillic word is untouched")
    func pureCyrillicUntouched() {
        let (text, counts) = HomoglyphNormalizer.normalize("Москва")
        #expect(text == "Москва")
        #expect(counts.normalizedHomoglyphs == 0)
    }

    @Test("pure Greek word is untouched")
    func pureGreekUntouched() {
        let (text, counts) = HomoglyphNormalizer.normalize("Αθήνα")
        #expect(text == "Αθήνα")
        #expect(counts.normalizedHomoglyphs == 0)
    }

    @Test("fullwidth ASCII becomes plain ASCII")
    func fullwidthBecomesASCII() {
        let (text, _) = HomoglyphNormalizer.normalize("\u{FF21}\u{FF22}\u{FF23}")
        #expect(text == "ABC")
    }

    @Test("mathematical bold letter becomes a plain letter")
    func mathBoldBecomesPlain() {
        let (text, _) = HomoglyphNormalizer.normalize("\u{1D400}")
        #expect(text == "A")
    }

    @Test("mixed token where not every foreign letter has a mapping is left unchanged")
    func partiallyMappableTokenUnchanged() {
        // 'θ' (Greek theta) has no mapping, so the whole mixed token stays as-is.
        let (text, counts) = HomoglyphNormalizer.normalize("abcθ")
        #expect(text == "abcθ")
        #expect(counts.normalizedHomoglyphs == 0)
    }
}
