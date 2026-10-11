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
        let lineYRanges = reliableLineYRanges(page: page, pageString: pageString)
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
            // `characterBounds(at:)` occasionally reports the wrong line's Y for the last few
            // characters before a line boundary (observed on real fixture text — a hyphenated
            // word's tail measured at the *next* line's Y even though it textually belongs to
            // the current one). `selectionsByLine()` does not have this bug, so its line bounds
            // override just the vertical extent here; the horizontal measurement, which is
            // reliable, stays from `characterBounds`.
            while lineCursor < lineYRanges.count,
                i >= lineYRanges[lineCursor].range.location + lineYRanges[lineCursor].range.length
            {
                lineCursor += 1
            }
            if lineCursor < lineYRanges.count, NSLocationInRange(i, lineYRanges[lineCursor].range) {
                let line = lineYRanges[lineCursor]
                pageSpaceBox = CGRect(
                    x: pageSpaceBox.minX, y: line.minY, width: pageSpaceBox.width, height: line.maxY - line.minY)
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

    // MARK: - Reliable per-line Y (works around a `characterBounds(at:)` quirk)

    /// Maps each `selectionsByLine()` line to the UTF-16 range it occupies in `pageString`, by
    /// searching for each line's text in turn starting after the previous match. `pageString`
    /// and the lines are both already in reading order, so this is a simple, fast sequential
    /// scan — not a general substring search.
    private static func reliableLineYRanges(
        page: PDFPage, pageString: String
    ) -> [(range: NSRange, minY: CGFloat, maxY: CGFloat)] {
        guard let fullSelection = page.selection(for: page.bounds(for: .cropBox)) else { return [] }
        let nsString = pageString as NSString
        let length = nsString.length
        var cursor = 0
        var result: [(range: NSRange, minY: CGFloat, maxY: CGFloat)] = []
        for lineSelection in fullSelection.selectionsByLine() {
            guard let text = lineSelection.string, !text.isEmpty, cursor < length else { continue }
            let searchRange = NSRange(location: cursor, length: length - cursor)
            let found = nsString.range(of: text, range: searchRange)
            guard found.location != NSNotFound else { continue }
            let bounds = lineSelection.bounds(for: page)
            result.append((found, bounds.minY, bounds.maxY))
            cursor = found.location + found.length
        }
        return result
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
