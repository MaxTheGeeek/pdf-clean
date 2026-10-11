import CoreGraphics
import Foundation
@preconcurrency import PDFKit
import Testing

@testable import PDFCleanKit

/// TC-U13 (T-032): `GlyphFilter` — off-page glyphs (< 50% inside the page), tiny glyphs
/// (< 2 pt), rotated runs (>= 3 diagonal glyphs), the vertical CJK/Hangul/Kana exception, and
/// `removeRotatedText = false` keeping rotated runs.
@Suite("GlyphFilter")
struct GlyphFilterTests {

    let pageSize = CGSize(width: 600, height: 800)

    @Test("an off-page glyph (< 50% inside) is dropped, counted once per maximal run")
    func offPageGlyphsDropped() {
        let kept1 = glyph("A", x: 100, y: 100, width: 20, height: 20, size: 12)
        let offPage1 = glyph("B", x: 595, y: 100, width: 20, height: 20, size: 12)  // 5/20 = 25% inside
        let offPage2 = glyph("C", x: 615, y: 100, width: 20, height: 20, size: 12)  // fully outside, same run
        let kept2 = glyph("D", x: 200, y: 200, width: 20, height: 20, size: 12)
        let offPage3 = glyph("E", x: -15, y: 200, width: 20, height: 20, size: 12)  // separate run

        let result = GlyphFilter.filter(glyphs: [kept1, offPage1, offPage2, kept2, offPage3], pageSize: pageSize)
        #expect(result.glyphs.map(\.text) == ["A", "D"])
        #expect(result.removedOffPageWords == 2)
    }

    @Test("a glyph smaller than 2pt is dropped as tiny, each one counted individually")
    func tinyGlyphsDropped() {
        let normal = glyph("A", x: 0, y: 0, width: 10, height: 10, size: 12)
        let tiny1 = glyph("B", x: 20, y: 0, width: 2, height: 2, size: 1.5)
        let tiny2 = glyph("C", x: 30, y: 0, width: 2, height: 2, size: 1.9)
        let result = GlyphFilter.filter(glyphs: [normal, tiny1, tiny2], pageSize: pageSize)
        #expect(result.glyphs.map(\.text) == ["A"])
        #expect(result.removedTinyGlyphs == 2)
    }

    @Test("3+ glyphs stepping diagonally form a rotated run and are dropped")
    func rotatedRunDropped() {
        let before = glyph("X", x: 0, y: 0, width: 2, height: 2, size: 12)
        let diagonal = (0..<4).map { i in
            glyph("R\(i)", x: CGFloat(i) * 3, y: CGFloat(i) * 3, width: 2, height: 2, size: 12)
        }
        let after = glyph("Y", x: 300, y: 300, width: 2, height: 2, size: 12)
        let result = GlyphFilter.filter(glyphs: [before] + diagonal + [after], pageSize: pageSize)
        #expect(result.glyphs.map(\.text) == ["X", "Y"])
        #expect(result.removedRotatedRuns == 1)
    }

    @Test("fewer than 3 diagonal glyphs is not a rotated run")
    func twoGlyphDiagonalRunIsKept() {
        let a = glyph("A", x: 0, y: 0, width: 2, height: 2, size: 12)
        let b = glyph("B", x: 3, y: 3, width: 2, height: 2, size: 12)
        let result = GlyphFilter.filter(glyphs: [a, b], pageSize: pageSize)
        #expect(result.glyphs.map(\.text) == ["A", "B"])
        #expect(result.removedRotatedRuns == 0)
    }

    @Test("a vertical run that is >= 80% CJK/Hangul/Kana is kept, not treated as rotated")
    func cjkVerticalExceptionKeepsRun() {
        let vertical = ["一", "二", "三"].enumerated().map { i, char in
            glyph(char, x: 0, y: CGFloat(i) * 14, width: 10, height: 12, size: 12)
        }
        let result = GlyphFilter.filter(glyphs: vertical, pageSize: pageSize)
        #expect(result.glyphs.map(\.text) == ["一", "二", "三"])
        #expect(result.removedRotatedRuns == 0)
    }

    @Test("removeRotatedText = false keeps a diagonal run")
    func optionOffKeepsRotatedRun() {
        let diagonal = (0..<4).map { i in
            glyph("R\(i)", x: CGFloat(i) * 3, y: CGFloat(i) * 3, width: 2, height: 2, size: 12)
        }
        let result = GlyphFilter.filter(glyphs: diagonal, pageSize: pageSize, removeRotatedText: false)
        #expect(result.glyphs.count == 4)
        #expect(result.removedRotatedRuns == 0)
    }

    @Test("empty input yields an empty result")
    func emptyInput() {
        let result = GlyphFilter.filter(glyphs: [], pageSize: pageSize)
        #expect(result.glyphs.isEmpty)
        #expect(result.removedOffPageWords == 0)
        #expect(result.removedTinyGlyphs == 0)
        #expect(result.removedRotatedRuns == 0)
    }

    @Test("hidden-content: the CANARY-ROTATED run is removed as one run per page")
    func canaryRotatedRemovedFromFixture() throws {
        let url = try #require(
            Bundle.module.url(forResource: "hidden-content", withExtension: "pdf", subdirectory: "Fixtures"))
        let document = try #require(PDFDocument(url: url))

        var totalRotatedRuns = 0
        var survivingText = ""
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i), let glyphs = GlyphExtractor.extract(page: page) else { continue }
            let cropBox = page.bounds(for: .cropBox)
            let pageSize = PageGeometry.displaySize(cropBox: cropBox, rotation: page.rotation)
            let result = GlyphFilter.filter(glyphs: glyphs, pageSize: pageSize)
            totalRotatedRuns += result.removedRotatedRuns
            survivingText += result.glyphs.map(\.text).joined()
        }
        #expect(totalRotatedRuns >= 1)
        #expect(!survivingText.contains("CANARY-ROTATED"))
    }

    // MARK: - Fixtures

    func glyph(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, size: CGFloat) -> Glyph {
        let box = CGRect(x: x, y: y, width: width, height: height)
        return Glyph(text: text, box: box, pageBox: box, fontSize: size, isBold: false, fontName: "Helvetica")
    }
}
