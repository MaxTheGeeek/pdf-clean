import CoreGraphics

/// Computes the document's body font size and body line spacing (tech spec §6.7.3), the
/// baseline every later layout heuristic (title/heading size factors, paragraph gap) is
/// measured against. Pure, side-effect free.
enum FontStatistics {

    struct Stats: Equatable, Sendable {
        var bodySize: CGFloat
        var bodyLineSpacing: CGFloat
    }

    /// `lines` must already be assembled (`LineAssembler`) and, ideally, in per-page reading
    /// order (`ReadingOrder`) so that array-adjacent lines on the same page are true visual
    /// neighbours — `bodyLineSpacing` is measured between such neighbours.
    static func compute(lines: [Line]) -> Stats {
        guard !lines.isEmpty else { return Stats(bodySize: 0, bodyLineSpacing: 0) }
        let textLayerLines = lines.filter { $0.source == .textLayer }
        let sizingLines = textLayerLines.isEmpty ? lines : textLayerLines
        let bodySize = dominantSize(in: sizingLines)
        let spacing = bodyLineSpacing(lines: lines, bodySize: bodySize)
        return Stats(bodySize: bodySize, bodyLineSpacing: spacing)
    }

    /// Font size (rounded to 0.5 pt) with the most glyphs among `lines`. Ties favour the
    /// smaller size, since body text is rarely the single largest size on a page.
    private static func dominantSize(in lines: [Line]) -> CGFloat {
        var glyphsBySize: [CGFloat: Int] = [:]
        for line in lines {
            for word in line.words {
                glyphsBySize[roundedSize(word.fontSize), default: 0] += glyphCount(of: word)
            }
        }
        guard !glyphsBySize.isEmpty else { return 0 }
        let maxCount = glyphsBySize.values.max() ?? 0
        return glyphsBySize.filter { $0.value == maxCount }.keys.min() ?? 0
    }

    /// A word's glyph count, falling back to its character count when no glyphs were recorded
    /// (synthetic layout-only input, or OCR lines, carry no `Glyph` detail).
    private static func glyphCount(of word: Word) -> Int {
        word.glyphs.isEmpty ? word.text.count : word.glyphs.count
    }

    /// Median vertical distance between array-adjacent body-size lines, on the same page, whose
    /// horizontal extents overlap (same column). Falls back to `1.2 × bodySize` when no such
    /// pair exists (e.g. a single-line document).
    private static func bodyLineSpacing(lines: [Line], bodySize: CGFloat) -> CGFloat {
        guard lines.count > 1 else { return bodySize > 0 ? bodySize * 1.2 : 0 }
        var deltas: [CGFloat] = []
        for i in 1..<lines.count {
            let previous = lines[i - 1]
            let current = lines[i]
            guard previous.page == current.page else { continue }
            guard isBodySize(previous, bodySize), isBodySize(current, bodySize) else { continue }
            guard previous.box.minX < current.box.maxX, current.box.minX < previous.box.maxX else { continue }
            let delta = current.box.minY - previous.box.minY
            guard delta > 0 else { continue }
            deltas.append(delta)
        }
        guard !deltas.isEmpty else { return bodySize > 0 ? bodySize * 1.2 : 0 }
        return median(deltas)
    }

    private static func isBodySize(_ line: Line, _ bodySize: CGFloat) -> Bool {
        roundedSize(line.fontSize) == bodySize
    }

    private static func roundedSize(_ size: CGFloat) -> CGFloat {
        (size * 2).rounded() / 2
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        let n = sorted.count
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }
}
