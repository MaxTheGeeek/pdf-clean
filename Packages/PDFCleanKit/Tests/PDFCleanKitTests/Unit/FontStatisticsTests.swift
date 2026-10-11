import CoreGraphics
import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U20 (T-022): `FontStatistics` — body size by glyph count (with a deterministic tie-break)
/// and median body line spacing restricted to same-page, same-column neighbours.
@Suite("FontStatistics")
struct FontStatisticsTests {

    @Test("body size is the font size with the most glyphs (character-count fallback)")
    func bodySizeByGlyphCount() {
        // Size 12 has far more characters overall than the size-20 heading.
        let lines = [
            line("A Heading", x: 0, y: 0, size: 20),
            line("This is the body text of the document, repeated for weight.", x: 0, y: 30, size: 12),
            line("More body text continues the paragraph down here as well.", x: 0, y: 50, size: 12),
        ]
        #expect(FontStatistics.compute(lines: lines).bodySize == 12)
    }

    @Test("a tie in glyph count favours the smaller size")
    func tieBreaksTowardSmallerSize() {
        let lines = [
            line("abcde", x: 0, y: 0, size: 14),  // 5 chars
            line("fghij", x: 0, y: 30, size: 10),  // 5 chars, tied
        ]
        #expect(FontStatistics.compute(lines: lines).bodySize == 10)
    }

    @Test("body line spacing is the median gap between same-column body-size neighbours")
    func bodyLineSpacingMedian() {
        let lines = [
            line("one", x: 0, y: 0, size: 12),
            line("two", x: 0, y: 20, size: 12),  // gap 20
            line("three", x: 0, y: 44, size: 12),  // gap 24
            line("four", x: 0, y: 66, size: 12),  // gap 22 (median of 20,24,22 = 22)
        ]
        #expect(FontStatistics.compute(lines: lines).bodyLineSpacing == 22)
    }

    @Test("the boundary pair between two columns is excluded from the spacing sample")
    func columnBoundaryPairExcluded() {
        // Post-`ReadingOrder` input: the whole left column, then the whole right column — only
        // the last-left/first-right boundary pair has no x-overlap and must be skipped.
        let lines = [
            line("left-one", x: 0, y: 0, size: 12),
            line("left-two", x: 0, y: 20, size: 12),  // gap 20
            line("left-three", x: 0, y: 40, size: 12),  // gap 20
            line("right-one", x: 300, y: 0, size: 12),  // boundary pair with left-three: excluded
        ]
        #expect(FontStatistics.compute(lines: lines).bodyLineSpacing == 20)
    }

    @Test("falls back to 1.2 x body size when no same-column body-size pair exists")
    func fallbackSpacing() {
        let lines = [line("solo", x: 0, y: 0, size: 12)]
        let stats = FontStatistics.compute(lines: lines)
        #expect(stats.bodySize == 12)
        #expect(stats.bodyLineSpacing == 12 * 1.2)
    }

    @Test("an OCR-only document uses OCR lines for sizing since there is no text layer")
    func ocrOnlyDocumentUsesOCRLines() {
        let lines = [
            line("Scanned body copy here for the page.", x: 0, y: 0, size: 11, source: .ocr),
            line("More scanned copy continues below the first line.", x: 0, y: 20, size: 11, source: .ocr),
        ]
        #expect(FontStatistics.compute(lines: lines).bodySize == 11)
    }

    @Test("empty input yields zeroed stats")
    func emptyInput() {
        let stats = FontStatistics.compute(lines: [])
        #expect(stats.bodySize == 0)
        #expect(stats.bodyLineSpacing == 0)
    }

    // MARK: - Fixtures

    func line(
        _ text: String, x: CGFloat, y: CGFloat, size: CGFloat, source: Line.Source = .textLayer
    ) -> Line {
        let box = CGRect(x: x, y: y, width: CGFloat(text.count) * size * 0.5, height: size * 1.2)
        let word = Word(text: text, box: box, pageBox: .zero, glyphs: [], fontSize: size, isBold: false)
        return Line(page: 0, words: [word], box: box, fontSize: size, isBold: false, source: source)
    }
}
