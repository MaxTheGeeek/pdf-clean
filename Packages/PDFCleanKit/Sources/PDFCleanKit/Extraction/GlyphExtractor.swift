import CoreGraphics
import Foundation
@preconcurrency import PDFKit

#if os(macOS)
    import AppKit
    typealias PlatformFont = NSFont
#else
    import UIKit
    typealias PlatformFont = UIFont
#endif

/// Extracts one `Glyph` per UTF-16 character of a page's text layer, in content order (tech
/// spec §6.2). A surrogate pair forms one glyph whose box unions both UTF-16 offsets' bounds.
/// `box` is display space (crop-box origin, `/Rotate` applied); `pageBox` is the raw,
/// unrotated page-space box `characterBounds(at:)` returns.
enum GlyphExtractor {

    /// `nil` when the page's `attributedString` disagrees with `string` (the UTF-16 offsets
    /// `characterBounds(at:)` and the font lookup both rely on would not line up) — the caller
    /// falls back to `extractFallbackWords`.
    static func extract(page: PDFPage) -> [Glyph]? {
        guard let pageString = page.string, !pageString.isEmpty else { return [] }
        guard let attributed = page.attributedString, attributed.string == pageString else {
            Log.event("glyph.fallback")
            return nil
        }

        let cropBox = page.bounds(for: .cropBox)
        let rotation = page.rotation
        let nsString = pageString as NSString
        let length = nsString.length
        let lines = reliableLines(page: page, pageString: pageString)
        var lineCursor = 0

        var glyphs: [Glyph] = []
        glyphs.reserveCapacity(length)
        var i = 0
        while i < length {
            let unit = nsString.character(at: i)
            let isSurrogatePair =
                Unicode.UTF16.isLeadSurrogate(unit) && i + 1 < length
                && Unicode.UTF16.isTrailSurrogate(nsString.character(at: i + 1))
            let charLength = isSurrogatePair ? 2 : 1
            let text = nsString.substring(with: NSRange(location: i, length: charLength))

            var pageSpaceBox = page.characterBounds(at: i)
            if isSurrogatePair {
                pageSpaceBox = pageSpaceBox.union(page.characterBounds(at: i + 1))
            }
            while lineCursor < lines.count,
                i >= lines[lineCursor].range.location + lines[lineCursor].range.length
            {
                lineCursor += 1
            }
            if lineCursor < lines.count, NSLocationInRange(i, lines[lineCursor].range) {
                let line = lines[lineCursor]
                if let diagonal = line.syntheticDiagonalBoxes {
                    // `characterBounds(at:)` is unreliable across this whole rotated-CTM run
                    // (observed on real fixture text: large, correctly positioned boxes for
                    // some characters, then wildly wrong — seemingly unrelated-glyph — boxes
                    // for the rest). `selectionsByLine()`'s one bounding box for the run is
                    // reliable; synthesize evenly spaced boxes stepping along its diagonal so
                    // the rotated-run detector (sanitisation spec §2.3) still sees the
                    // "axis-aligned boxes stepping diagonally" pattern it expects.
                    pageSpaceBox = diagonal[i - line.range.location]
                } else {
                    // `characterBounds(at:)` occasionally reports the wrong line's Y for the
                    // last few characters before a line boundary (observed on real fixture
                    // text — a hyphenated word's tail measured at the *next* line's Y even
                    // though it textually belongs to the current one). `selectionsByLine()`
                    // does not have this bug, so its line bounds override just the vertical
                    // extent here; the horizontal measurement, which is reliable, stays from
                    // `characterBounds`.
                    pageSpaceBox = CGRect(
                        x: pageSpaceBox.minX, y: line.minY, width: pageSpaceBox.width,
                        height: line.maxY - line.minY)
                }
            }

            let font = attributed.attribute(.font, at: i, effectiveRange: nil) as? PlatformFont
            let pointSize = font?.pointSize ?? 0
            // Guards against scaled text matrices — but only when the measured box is at least
            // roughly glyph-sized. PDFKit occasionally reports a degenerate (near-zero-height)
            // ink box for an ordinary, fully visible character; capping against that would
            // corrupt this glyph's size instead of correcting it.
            let effectiveSize: CGFloat
            if pointSize > 0, pageSpaceBox.height / 0.7 >= pointSize * 0.5 {
                effectiveSize = min(pointSize, pageSpaceBox.height / 0.7)
            } else {
                effectiveSize = pointSize
            }
            let displayBox = PageGeometry.pageToDisplay(pageSpaceBox, cropBox: cropBox, rotation: rotation)

            glyphs.append(
                Glyph(
                    text: text, box: displayBox, pageBox: pageSpaceBox, fontSize: effectiveSize,
                    isBold: isBoldFont(font), fontName: font?.fontName ?? ""))
            i += charLength
        }
        return glyphs
    }

    /// Fallback for the rare page where `attributedString` and `string` disagree (tech spec
    /// §6.2): one pseudo-word per line selection, with no per-glyph detail.
    static func extractFallbackWords(page: PDFPage) -> [Word] {
        guard let fullSelection = page.selection(for: page.bounds(for: .cropBox)) else { return [] }
        let cropBox = page.bounds(for: .cropBox)
        let rotation = page.rotation
        return fullSelection.selectionsByLine().compactMap { lineSelection in
            guard let text = lineSelection.string, !text.isEmpty else { return nil }
            let pageSpaceBox = lineSelection.bounds(for: page)
            let displayBox = PageGeometry.pageToDisplay(pageSpaceBox, cropBox: cropBox, rotation: rotation)
            return Word(text: text, box: displayBox, pageBox: pageSpaceBox, glyphs: [], fontSize: 0, isBold: false)
        }
    }

    // MARK: - Reliable per-line geometry (works around `characterBounds(at:)` quirks)

    private struct ReliableLine {
        var range: NSRange
        var minY: CGFloat
        var maxY: CGFloat
        /// Set only for a line that looks rotated (tall relative to its width and length):
        /// one synthetic box per UTF-16 unit in `range`, stepping along the line's diagonal.
        var syntheticDiagonalBoxes: [CGRect]?
    }

    /// Minimum text length before the "looks rotated" check applies, so a short, naturally
    /// near-square line (e.g. a single digit) is never misclassified.
    private static let rotatedLineMinLength = 4
    /// A line taller than this fraction of its own width is "looks rotated" — normal running
    /// text of any real length is far wider than it is tall.
    private static let rotatedLineHeightToWidthRatio: CGFloat = 0.5
    /// Minimum absolute height (points) before "looks rotated" applies, ruling out ordinary
    /// short lines that are merely a little taller than wide.
    private static let rotatedLineMinHeight: CGFloat = 20

    /// Maps each `selectionsByLine()` line to the UTF-16 range it occupies in `pageString`, by
    /// searching for each line's text in turn starting after the previous match (`pageString`
    /// and the lines are both already in reading order, so this is a simple, fast sequential
    /// scan, not a general substring search) — plus, for a line whose bounding box looks
    /// rotated, synthetic per-character boxes stepping along its diagonal.
    private static func reliableLines(page: PDFPage, pageString: String) -> [ReliableLine] {
        guard let fullSelection = page.selection(for: page.bounds(for: .cropBox)) else { return [] }
        let nsString = pageString as NSString
        let length = nsString.length
        var cursor = 0
        var result: [ReliableLine] = []
        for lineSelection in fullSelection.selectionsByLine() {
            guard let text = lineSelection.string, !text.isEmpty, cursor < length else { continue }
            let searchRange = NSRange(location: cursor, length: length - cursor)
            let found = nsString.range(of: text, range: searchRange)
            guard found.location != NSNotFound else { continue }
            let bounds = lineSelection.bounds(for: page)
            let diagonal =
                looksRotated(bounds: bounds, length: found.length)
                ? diagonalBoxes(bounds: bounds, count: found.length) : nil
            result.append(
                ReliableLine(range: found, minY: bounds.minY, maxY: bounds.maxY, syntheticDiagonalBoxes: diagonal))
            cursor = found.location + found.length
        }
        return result
    }

    private static func looksRotated(bounds: CGRect, length: Int) -> Bool {
        length >= rotatedLineMinLength && bounds.height > rotatedLineMinHeight
            && bounds.height > rotatedLineHeightToWidthRatio * bounds.width
    }

    /// `count` boxes evenly spaced along the bounding box's diagonal, each roughly
    /// glyph-sized — reproduces the "axis-aligned boxes stepping diagonally" shape genuine
    /// rotated text would have, for a run whose individual `characterBounds` cannot be trusted.
    private static func diagonalBoxes(bounds: CGRect, count: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let boxSize = max(min(bounds.width, bounds.height) / CGFloat(count), 1)
        return (0..<count).map { k in
            let t = count > 1 ? CGFloat(k) / CGFloat(count - 1) : 0
            let cx = bounds.minX + t * bounds.width
            let cy = bounds.minY + t * bounds.height
            return CGRect(x: cx - boxSize / 2, y: cy - boxSize / 2, width: boxSize, height: boxSize)
        }
    }

    // MARK: - Font traits

    private static func isBoldFont(_ font: PlatformFont?) -> Bool {
        guard let font else { return false }
        let traits = font.fontDescriptor.symbolicTraits
        #if os(macOS)
            if traits.contains(.bold) { return true }
        #else
            if traits.contains(.traitBold) { return true }
        #endif
        let name = font.fontName
        return ["Bold", "Black", "Heavy", "Semibold", "Demi"].contains { name.localizedCaseInsensitiveContains($0) }
    }
}
