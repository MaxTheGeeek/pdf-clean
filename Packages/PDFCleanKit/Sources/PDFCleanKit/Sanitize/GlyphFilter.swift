import CoreGraphics
import Foundation

/// Glyph-level filters, run before word building (sanitisation spec §2): off-page, tiny and
/// rotated-run glyphs are dropped from the content-order glyph sequence. Pure, side-effect free.
enum GlyphFilter {

    struct Result: Equatable, Sendable {
        var glyphs: [Glyph]
        var removedOffPageWords: Int = 0
        var removedTinyGlyphs: Int = 0
        var removedRotatedRuns: Int = 0
    }

    /// `pageSize` is the display-space page size (crop box origin at zero). Filters run in
    /// order: off-page, then tiny, then rotated runs — each on the previous stage's output.
    static func filter(glyphs: [Glyph], pageSize: CGSize, removeRotatedText: Bool = true) -> Result {
        let offPage = filterOffPage(glyphs: glyphs, pageSize: pageSize)
        let tiny = filterTiny(glyphs: offPage.glyphs)
        let rotated = removeRotatedText ? filterRotated(glyphs: tiny.glyphs) : (glyphs: tiny.glyphs, removedRuns: 0)
        return Result(
            glyphs: rotated.glyphs, removedOffPageWords: offPage.removedRuns,
            removedTinyGlyphs: tiny.removedCount, removedRotatedRuns: rotated.removedRuns)
    }

    // MARK: - 2.1 Off-page

    /// Drops a glyph with less than `offPageMinInside` of its area inside the page. Counts one
    /// `removedOffPageWords` per maximal run of consecutive dropped glyphs. A glyph with no
    /// area (zero-width/format character) has nothing to judge "off-page" and is always kept.
    private static func filterOffPage(glyphs: [Glyph], pageSize: CGSize) -> (glyphs: [Glyph], removedRuns: Int) {
        let pageRect = CGRect(origin: .zero, size: pageSize)
        var kept: [Glyph] = []
        var removedRuns = 0
        var inRun = false
        for glyph in glyphs {
            if insideFraction(glyph.box, pageRect) < Constants.offPageMinInside {
                if !inRun {
                    removedRuns += 1
                    inRun = true
                }
            } else {
                inRun = false
                kept.append(glyph)
            }
        }
        return (kept, removedRuns)
    }

    private static func insideFraction(_ box: CGRect, _ pageRect: CGRect) -> Double {
        let area = box.width * box.height
        guard area > 0 else { return 1 }
        let intersectionArea = box.intersection(pageRect).width * box.intersection(pageRect).height
        return Double(intersectionArea / area)
    }

    // MARK: - 2.2 Tiny

    /// Drops every glyph with a real (non-zero-width) box smaller than `minFontSize`, counting
    /// each individually.
    private static func filterTiny(glyphs: [Glyph]) -> (glyphs: [Glyph], removedCount: Int) {
        var kept: [Glyph] = []
        var removed = 0
        for glyph in glyphs {
            if glyph.box.width > 0, glyph.fontSize < Constants.minFontSize {
                removed += 1
            } else {
                kept.append(glyph)
            }
        }
        return (kept, removed)
    }

    // MARK: - 2.3 Rotated runs

    /// Walks consecutive non-space, non-empty-box glyphs; a maximal run of >= `minRotatedRun`
    /// joined by "diagonal" consecutive pairs (angle outside ±`maxBaselineAngle` of horizontal,
    /// centre distance < `diagonalMaxStep × size`) is dropped as a rotated watermark — unless
    /// at least `cjkVerticalExceptionRatio` of the run is CJK/Hangul/Kana (genuine vertical
    /// writing, kept).
    private static func filterRotated(glyphs: [Glyph]) -> (glyphs: [Glyph], removedRuns: Int) {
        let candidates = glyphs.indices.filter { glyphs[$0].box.width > 0 && !isWhitespace(glyphs[$0].text) }
        guard candidates.count >= Constants.minRotatedRun else { return (glyphs, 0) }

        var toDrop = Set<Int>()
        var removedRuns = 0
        var runStart = 0
        while runStart < candidates.count {
            var runEnd = runStart
            while runEnd + 1 < candidates.count,
                isDiagonalPair(glyphs[candidates[runEnd]], glyphs[candidates[runEnd + 1]])
            {
                runEnd += 1
            }
            let runIndices = Array(candidates[runStart...runEnd])
            if runIndices.count >= Constants.minRotatedRun, !isCJKException(runIndices.map { glyphs[$0].text }) {
                toDrop.formUnion(runIndices)
                removedRuns += 1
            }
            runStart = runEnd + 1
        }

        let kept = glyphs.indices.filter { !toDrop.contains($0) }.map { glyphs[$0] }
        return (kept, removedRuns)
    }

    private static func isDiagonalPair(_ a: Glyph, _ b: Glyph) -> Bool {
        let dx = b.box.midX - a.box.midX
        let dy = b.box.midY - a.box.midY
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance < CGFloat(Constants.diagonalMaxStep) * max(a.fontSize, b.fontSize) else { return false }
        let angle = abs(atan2(dy, dx)) * 180 / .pi
        return angle > Constants.maxBaselineAngle && angle < (180 - Constants.maxBaselineAngle)
    }

    private static func isCJKException(_ texts: [String]) -> Bool {
        guard !texts.isEmpty else { return false }
        let cjkCount = texts.filter(isCJKHangulKana).count
        return Double(cjkCount) / Double(texts.count) >= Constants.cjkVerticalExceptionRatio
    }

    private static func isCJKHangulKana(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040...0x30FF:  // Hiragana, Katakana
            return true
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:  // CJK Unified + Compat Ideographs
            return true
        case 0xAC00...0xD7A3:  // Hangul Syllables
            return true
        case 0x1100...0x11FF:  // Hangul Jamo
            return true
        default:
            return false
        }
    }

    private static func isWhitespace(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isWhitespace)
    }
}
