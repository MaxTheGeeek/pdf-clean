import CoreGraphics
import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U14 (T-031): `WordBuilder` — a zero-width glyph stays inside its word, a gap > 0.25 x
/// size splits a new word, a vertical jump (new line) splits a new word, and a geometry-less
/// word (only zero-width glyphs) attaches to the preceding word.
@Suite("WordBuilder")
struct WordBuilderTests {

    @Test("a zero-width glyph (empty box, non-whitespace) stays inside its word")
    func zeroWidthGlyphStaysInWord() {
        // "Visi<ZWSP>ble" — the zero-width space must not split the word. "ble" starts right
        // where "Visi" ends (x=40): a zero-width character contributes no advance.
        let glyphs = letters("Visi", x: 0, size: 12) + [zeroWidth("\u{200B}")] + letters("ble", x: 40, size: 12)
        let words = WordBuilder.build(glyphs: glyphs)
        #expect(words.count == 1)
        #expect(words[0].text == "Visi\u{200B}ble")
    }

    @Test("whitespace with an empty box is a hard separator")
    func emptyBoxWhitespaceIsASeparator() {
        let glyphs = letters("one", x: 0, size: 12) + [zeroWidth(" ")] + letters("two", x: 30, size: 12)
        let words = WordBuilder.build(glyphs: glyphs)
        #expect(words.map(\.text) == ["one", "two"])
    }

    @Test("a horizontal gap wider than 0.25 x size starts a new word")
    func gapSplitsNewWord() {
        // size 12 -> threshold 3pt. Gap of "ab" (ends at x=20) to "cd" (starts at x=24) is 4pt.
        let glyphs = letters("ab", x: 0, size: 12) + letters("cd", x: 24, size: 12)
        let words = WordBuilder.build(glyphs: glyphs)
        #expect(words.map(\.text) == ["ab", "cd"])
    }

    @Test("a gap within 0.25 x size keeps letters in one word")
    func smallGapKeepsOneWord() {
        let glyphs = letters("ab", x: 0, size: 12) + letters("cd", x: 21, size: 12)  // gap 1pt < 3pt
        let words = WordBuilder.build(glyphs: glyphs)
        #expect(words.map(\.text) == ["abcd"])
    }

    @Test("a vertical centre jump > 0.5 x glyph height starts a new word (new line)")
    func verticalJumpSplitsNewWord() {
        let line1 = letters("ab", x: 0, y: 0, size: 12)
        let line2 = letters("cd", x: 0, y: 20, size: 12)  // jump 20 > 0.5 x 12 (glyph height)
        let words = WordBuilder.build(glyphs: line1 + line2)
        #expect(words.map(\.text) == ["ab", "cd"])
    }

    @Test("a word made only of zero-width glyphs attaches to the preceding word")
    func geometrylessWordAttachesToPrevious() {
        let glyphs =
            letters("before", x: 0, size: 12) + [zeroWidth(" "), zeroWidth("\u{200B}"), zeroWidth(" ")]
            + letters("after", x: 60, size: 12)
        let words = WordBuilder.build(glyphs: glyphs)
        // The whitespace glyphs are hard separators, but the zero-width glyph between them
        // forms its own (geometry-less) word, which attaches to "before" rather than floating.
        #expect(words.map(\.text) == ["before\u{200B}", "after"])
    }

    @Test("bold is a majority vote over the word's geometric glyphs")
    func boldMajority() {
        let bold = letters("AB", x: 0, size: 12, isBold: true)
        let plain = letters("C", x: 20, size: 12, isBold: false)
        let words = WordBuilder.build(glyphs: bold + plain)
        #expect(words.count == 1)
        #expect(words[0].isBold == true)
    }

    @Test("empty input yields no words")
    func emptyInput() {
        #expect(WordBuilder.build(glyphs: []).isEmpty)
    }

    // MARK: - Fixtures

    /// One glyph per character, each `width` wide starting at `x`, advancing by `width`.
    func letters(_ text: String, x: CGFloat, y: CGFloat = 0, size: CGFloat, isBold: Bool = false) -> [Glyph] {
        let width: CGFloat = 10
        return text.enumerated().map { i, char in
            let box = CGRect(x: x + CGFloat(i) * width, y: y, width: width, height: size)
            return Glyph(
                text: String(char), box: box, pageBox: box, fontSize: size, isBold: isBold, fontName: "Helvetica")
        }
    }

    /// A zero-width glyph: empty box, carries only text.
    func zeroWidth(_ text: String) -> Glyph {
        Glyph(text: text, box: .null, pageBox: .null, fontSize: 12, isBold: false, fontName: "Helvetica")
    }
}
