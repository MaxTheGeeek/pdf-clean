import CoreGraphics
import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U16 (T-033): `OverlapDeduper` — same text with IoU >= 0.7 is deduplicated (keeping the
/// first), while different text or IoU < 0.7 is kept.
@Suite("OverlapDeduper")
struct OverlapDeduperTests {

    @Test("identical boxes with the same text (fake bold) are deduplicated, keeping the first")
    func sameTextHighIoURemoved() {
        let a = word("Summary", x: 0, y: 0, width: 60, height: 14)
        let b = word("Summary", x: 0, y: 0, width: 60, height: 14)
        let result = OverlapDeduper.dedupe(words: [a, b])
        #expect(result.words.count == 1)
        #expect(result.words[0].box == a.box)
        #expect(result.removedOverlappingDuplicates == 1)
    }

    @Test("three overlapping occurrences collapse to the first, removing two")
    func threeOccurrencesRemoveTwo() {
        let a = word("Summary", x: 0, y: 0, width: 60, height: 14)
        let b = word("Summary", x: 0, y: 0, width: 60, height: 14)
        let c = word("Summary", x: 0, y: 0, width: 60, height: 14)
        let result = OverlapDeduper.dedupe(words: [a, b, c])
        #expect(result.words.count == 1)
        #expect(result.removedOverlappingDuplicates == 2)
    }

    @Test("different text at the same position is not deduplicated")
    func differentTextKept() {
        let a = word("Summary", x: 0, y: 0, width: 60, height: 14)
        let b = word("Details", x: 0, y: 0, width: 60, height: 14)
        let result = OverlapDeduper.dedupe(words: [a, b])
        #expect(result.words.count == 2)
        #expect(result.removedOverlappingDuplicates == 0)
    }

    @Test("same text with IoU below 0.7 is not deduplicated")
    func lowIoUKept() {
        // box1 [0,10]x[0,10] area 100; box2 [5,15]x[0,10] area 100; overlap width 5 -> area 50.
        // IoU = 50 / (100+100-50) = 0.33.
        let a = word("Summary", x: 0, y: 0, width: 10, height: 10)
        let b = word("Summary", x: 5, y: 0, width: 10, height: 10)
        let result = OverlapDeduper.dedupe(words: [a, b])
        #expect(result.words.count == 2)
        #expect(result.removedOverlappingDuplicates == 0)
    }

    @Test("empty input yields an empty result")
    func emptyInput() {
        let result = OverlapDeduper.dedupe(words: [])
        #expect(result.words.isEmpty)
        #expect(result.removedOverlappingDuplicates == 0)
    }

    // MARK: - Fixtures

    func word(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> Word {
        let box = CGRect(x: x, y: y, width: width, height: height)
        return Word(text: text, box: box, pageBox: box, glyphs: [], fontSize: 12, isBold: false)
    }
}
