import CoreGraphics
import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U18 (T-020): `LineAssembler` clusters words into lines by vertical overlap (centre distance
/// < 0.5 × median word height), splits a line at column gutters (> `columnGapFactor` × font size),
/// and orders words on a line (right-to-left when the line is RTL-dominant).
@Suite("LineAssembler")
struct LineAssemblerTests {

    @Test("clusters words into separate lines by vertical overlap")
    func clustersByVerticalOverlap() {
        // Two bands: line 1 centred at y = 50, line 2 centred at y = 150. Median height = 20,
        // so the overlap threshold = 0.5 × 20 = 10 either side of the band's mean centre.
        let words = [
            word("alpha", x: 0, y: 40),
            word("beta", x: 30, y: 42),
            word("gamma", x: 55, y: 38),
            word("delta", x: 0, y: 140),
            word("epsilon", x: 30, y: 142),
        ]
        let assembly = LineAssembler.assemble(page: 0, words: words)
        #expect(assembly.lines.count == 2)
        #expect(assembly.lines[0].text == "alpha beta gamma")
        #expect(assembly.lines[1].text == "delta epsilon")
        #expect(assembly.hasRTL == false)
    }

    @Test("splits a vertical band at a column gutter wider than 2 × font size")
    func splitsAtColumnGutter() {
        // Same band (all centred at y = 50). Gap "bbb"->"ccc" is 200 - 70 = 130
        // vs threshold = 2.0 × 12 = 24 -> new line. Gap "aaa"->"bbb" is 40-30 = 10 < 24.
        let words = [
            word("aaa", x: 0, y: 40),
            word("bbb", x: 40, y: 42),
            word("ccc", x: 200, y: 40),
        ]
        let assembly = LineAssembler.assemble(page: 0, words: words)
        #expect(assembly.lines.count == 2)
        #expect(assembly.lines[0].text == "aaa bbb")
        #expect(assembly.lines[1].text == "ccc")
    }

    @Test("keeps words on one line when the gutter is within the threshold")
    func keepsRunningTextOnOneLine() {
        let words = [
            word("a", x: 0, y: 40),
            word("b", x: 20, y: 42),
            word("c", x: 50, y: 40),
        ]
        let assembly = LineAssembler.assemble(page: 0, words: words)
        #expect(assembly.lines.count == 1)
        #expect(assembly.lines[0].text == "a b c")
    }

    @Test("orders RTL-dominant line right-to-left and flags hasRTL")
    func ordersRTLRightToLeft() {
        // Arabic-letter words; gaps are small so they stay on one line (not a gutter split).
        let words = [
            word("السلام", x: 0, y: 40),
            word("عليكم", x: 25, y: 42),
            word("مرحبا", x: 60, y: 40),
        ]
        let assembly = LineAssembler.assemble(page: 0, words: words)
        #expect(assembly.lines.count == 1)
        #expect(assembly.hasRTL == true)
        // RTL line orders by descending x (rightmost first).
        #expect(assembly.lines[0].words.map(\.text) == ["مرحبا", "عليكم", "السلام"])
    }

    @Test("keeps LTR order and does not flag hasRTL for Latin text")
    func keepsLTROrder() {
        let words = [
            word("one", x: 0, y: 40),
            word("two", x: 30, y: 42),
            word("three", x: 60, y: 40),
        ]
        let assembly = LineAssembler.assemble(page: 0, words: words)
        #expect(assembly.lines.count == 1)
        #expect(assembly.hasRTL == false)
        #expect(assembly.lines[0].words.map(\.text) == ["one", "two", "three"])
    }

    @Test("computes line box union, font size and bold majority")
    func lineMetadata() {
        let bold1 = word("bold1", x: 0, y: 40, fontSize: 14, isBold: true)
        let bold2 = word("bold2", x: 24, y: 42, fontSize: 14, isBold: true)
        let plain = word("plain", x: 50, y: 40, fontSize: 11, isBold: false)
        let words = [bold1, bold2, plain]
        let source: Line.Source = .ocr
        let assembly = LineAssembler.assemble(page: 3, words: words, source: source)
        #expect(assembly.lines.count == 1)
        let line = assembly.lines[0]
        #expect(line.page == 3)
        #expect(line.source == .ocr)
        #expect(line.isBold == true)  // 2 of 3 words bold
        #expect(line.fontSize == 14)  // max font size
        #expect(line.box == CGRect(x: 0, y: 40, width: 70, height: 22))
        #expect(line.text == "bold1 bold2 plain")
    }

    @Test("empty words produce an empty assembly")
    func emptyWords() {
        let assembly = LineAssembler.assemble(page: 0, words: [])
        #expect(assembly.lines.isEmpty)
        #expect(assembly.hasRTL == false)
    }

    @Test("assemble passes through the text-layer source by default")
    func defaultSourceIsTextLayer() {
        let assembly = LineAssembler.assemble(page: 1, words: [word("hello", x: 0, y: 40)])
        #expect(assembly.lines.count == 1)
        #expect(assembly.lines[0].source == .textLayer)
    }

    // MARK: - Fixtures

    func word(
        _ text: String, x: CGFloat, y: CGFloat, h: CGFloat = 20, fontSize: CGFloat = 12, isBold: Bool = false
    ) -> Word {
        Word(
            text: text, box: CGRect(x: x, y: y, width: 20, height: h), pageBox: .zero, glyphs: [], fontSize: fontSize,
            isBold: isBold)
    }
}
