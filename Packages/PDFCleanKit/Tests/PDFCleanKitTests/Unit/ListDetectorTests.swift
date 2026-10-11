import CoreGraphics
import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U22 (T-024): `ListDetector` — the bullet glyph set, ordered markers, continuation-line
/// alignment (± 3 pt), nesting levels by indentation cluster, and the documented "A. Smith"
/// false positive.
@Suite("ListDetector")
struct ListDetectorTests {

    @Test("bullet glyphs from the full bullet set start list items")
    func bulletSet() {
        let lines = [
            makeLine(page: 0, y: 0, words: [("•", 0, 10), ("First", 15, 40)]),
            makeLine(page: 0, y: 20, words: [("–", 0, 10), ("Second", 15, 50)]),
            makeLine(page: 0, y: 40, words: [("*", 0, 10), ("Third", 15, 40)]),
        ]
        let result = ListDetector.classify(lines: lines)
        #expect(
            result == [
                .listItem(ListItem(ordered: false, marker: "•", level: 0, text: "First")),
                .listItem(ListItem(ordered: false, marker: "–", level: 0, text: "Second")),
                .listItem(ListItem(ordered: false, marker: "*", level: 0, text: "Third")),
            ])
    }

    @Test("ordered markers (digit, letter, roman, parenthesised) start list items")
    func orderedMarkers() {
        let lines = [
            makeLine(page: 0, y: 0, words: [("1.", 0, 15), ("One", 20, 30)]),
            makeLine(page: 0, y: 20, words: [("(a)", 0, 20), ("Two", 25, 30)]),
            makeLine(page: 0, y: 40, words: [("iv)", 0, 20), ("Three", 25, 40)]),
        ]
        let result = ListDetector.classify(lines: lines)
        #expect(
            result == [
                .listItem(ListItem(ordered: true, marker: "1.", level: 0, text: "One")),
                .listItem(ListItem(ordered: true, marker: "(a)", level: 0, text: "Two")),
                .listItem(ListItem(ordered: true, marker: "iv)", level: 0, text: "Three")),
            ])
    }

    @Test("a continuation line within the alignment tolerance merges; one outside it does not")
    func continuationAlignment() {
        let lines = [
            makeLine(page: 0, y: 0, words: [("1.", 0, 15), ("Wrapped", 20, 55)]),
            makeLine(page: 0, y: 20, words: [("item", 20, 35)]),  // aligned at x=20: merges
            makeLine(page: 0, y: 40, words: [("Misaligned", 30, 60)]),  // x=30, 10pt off: does not
        ]
        let result = ListDetector.classify(lines: lines)
        #expect(
            result == [
                .listItem(ListItem(ordered: true, marker: "1.", level: 0, text: "Wrapped item")),
                .other(lines[2]),
            ])
    }

    @Test("indentation clusters assign nesting levels")
    func nestingLevels() {
        let lines = [
            makeLine(page: 0, y: 0, words: [("-", 0, 8), ("Top", 12, 30), ("one", 45, 25)]),
            makeLine(page: 0, y: 20, words: [("-", 20, 8), ("Nested", 32, 40), ("one", 75, 25)]),
            makeLine(page: 0, y: 40, words: [("-", 20, 8), ("Nested", 32, 40), ("two", 75, 25)]),
            makeLine(page: 0, y: 60, words: [("-", 0, 8), ("Top", 12, 30), ("two", 45, 25)]),
        ]
        let result = ListDetector.classify(lines: lines)
        #expect(
            result == [
                .listItem(ListItem(ordered: false, marker: "-", level: 0, text: "Top one")),
                .listItem(ListItem(ordered: false, marker: "-", level: 1, text: "Nested one")),
                .listItem(ListItem(ordered: false, marker: "-", level: 1, text: "Nested two")),
                .listItem(ListItem(ordered: false, marker: "-", level: 0, text: "Top two")),
            ])
    }

    @Test("documented false positive: a single-letter initial and period reads as an ordered marker")
    func singleLetterInitialFalsePositive() {
        let lines = [makeLine(page: 0, y: 0, words: [("A.", 0, 15), ("Smith,", 20, 45), ("Esq.", 70, 30)])]
        let result = ListDetector.classify(lines: lines)
        #expect(result == [.listItem(ListItem(ordered: true, marker: "A.", level: 0, text: "Smith, Esq."))])
    }

    @Test("lines with no marker at all pass through unchanged")
    func noMarkersPassThrough() {
        let lines = [
            makeLine(page: 0, y: 0, words: [("Just", 0, 20), ("a", 25, 10), ("paragraph.", 40, 50)])
        ]
        #expect(ListDetector.classify(lines: lines) == [.other(lines[0])])
    }

    // MARK: - Fixtures

    func makeLine(
        page: Int, y: CGFloat, size: CGFloat = 12, words: [(String, CGFloat, CGFloat)]
    ) -> Line {
        let builtWords = words.map { text, wx, width in
            Word(
                text: text, box: CGRect(x: wx, y: y, width: width, height: 14), pageBox: .zero, glyphs: [],
                fontSize: size, isBold: false)
        }
        let box = builtWords.reduce(CGRect.null) { $0.union($1.box) }
        return Line(page: page, words: builtWords, box: box, fontSize: size, isBold: false, source: .textLayer)
    }
}
