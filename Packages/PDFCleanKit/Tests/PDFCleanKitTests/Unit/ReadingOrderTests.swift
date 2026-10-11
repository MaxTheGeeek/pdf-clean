import CoreGraphics
import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U19 (T-021): `ReadingOrder` recursive XY-cut — title + 2 columns + full-width footer
/// ordering, 3 columns, and no false split on justified text.
@Suite("ReadingOrder")
struct ReadingOrderTests {

    @Test("title, two columns (independently wrapped) and a full-width footer read in order")
    func titleTwoColumnsFooter() {
        let title = line("Title", x: 0, y: 0, width: 500, height: 20)

        // Left column: 3 short lines with real gaps between them (54–70, 84–100).
        let l1 = line("L1", x: 0, y: 40, width: 200, height: 14)
        let l2 = line("L2", x: 0, y: 70, width: 200, height: 14)
        let l3 = line("L3", x: 0, y: 100, width: 200, height: 14)

        // Right column: wraps independently, filling the left column's gaps so the combined
        // region has no full-width horizontal band — only the column gutter remains.
        let r1 = line("R1", x: 280, y: 40, width: 200, height: 20)
        let r2 = line("R2", x: 280, y: 58, width: 200, height: 20)
        let r3 = line("R3", x: 280, y: 76, width: 200, height: 20)
        let r4 = line("R4", x: 280, y: 94, width: 200, height: 24)

        let footer = line("Footer", x: 0, y: 140, width: 500, height: 20)

        let lines = [title, r3, l1, footer, r1, l2, r4, l3, r2]
        let ordered = ReadingOrder.order(lines: lines)

        #expect(ordered.map(\.text) == ["Title", "L1", "L2", "L3", "R1", "R2", "R3", "R4", "Footer"])
    }

    @Test("three columns read left to right")
    func threeColumns() {
        let col1 = line("AAA", x: 0, y: 0, width: 60, height: 14)
        let col2 = line("BBB", x: 150, y: 0, width: 60, height: 14)
        let col3 = line("CCC", x: 400, y: 0, width: 60, height: 14)

        let ordered = ReadingOrder.order(lines: [col3, col1, col2])

        #expect(ordered.map(\.text) == ["AAA", "BBB", "CCC"])
    }

    @Test("varying line widths in one column (justified text) are not split into columns")
    func noFalseSplitOnJustifiedText() {
        let line1 = line("one", x: 20, y: 0, width: 200, height: 14)
        let line2 = line("two", x: 0, y: 20, width: 180, height: 14)
        let line3 = line("three", x: 0, y: 40, width: 195, height: 14)
        let line4 = line("four", x: 0, y: 60, width: 90, height: 14)

        let ordered = ReadingOrder.order(lines: [line4, line2, line1, line3])

        #expect(ordered.map(\.text) == ["one", "two", "three", "four"])
    }

    @Test("a narrow gap below the minimum gutter width does not split columns")
    func narrowGapIsNotAGutter() {
        let left = line("left", x: 0, y: 0, width: 100, height: 14)
        // Gap of 5pt, well under Constants.minGutter (12pt).
        let right = line("right", x: 105, y: 0, width: 100, height: 14)

        let ordered = ReadingOrder.order(lines: [right, left])

        #expect(ordered.map(\.text) == ["left", "right"])
    }

    @Test("empty and single-line input pass through unchanged")
    func trivialInputs() {
        #expect(ReadingOrder.order(lines: []).isEmpty)
        let only = line("solo", x: 0, y: 0, width: 50, height: 14)
        #expect(ReadingOrder.order(lines: [only]).map(\.text) == ["solo"])
    }

    // MARK: - Fixtures

    func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> Line {
        let box = CGRect(x: x, y: y, width: width, height: height)
        let word = Word(text: text, box: box, pageBox: .zero, glyphs: [], fontSize: 12, isBold: false)
        return Line(page: 0, words: [word], box: box, fontSize: 12, isBold: false, source: .textLayer)
    }
}
