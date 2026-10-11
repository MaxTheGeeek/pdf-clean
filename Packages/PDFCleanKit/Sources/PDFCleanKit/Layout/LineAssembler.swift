import CoreGraphics

/// Working glyph/word/line types (tech spec §5). `box` is **display space** (origin at the crop
/// box's top-left, y downward, `/Rotate` applied); `pageBox` is unrotated PDF page space and is
/// used only by the raster visibility test. These are the pure, `Sendable` value types the
/// layout and export stages operate on — nothing after stage 2 touches PDFKit.
struct Glyph: Equatable, Sendable {
    var text: String
    var box: CGRect  // display space
    var pageBox: CGRect  // unrotated PDF page space
    var fontSize: CGFloat
    var isBold: Bool
    var fontName: String
}

struct Word: Equatable, Sendable {
    var text: String
    var box: CGRect  // display space
    var pageBox: CGRect  // unrotated PDF page space
    var glyphs: [Glyph]
    var fontSize: CGFloat
    var isBold: Bool
}

struct Line: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case textLayer
        case ocr
    }

    var page: Int
    var words: [Word]
    var box: CGRect  // display space
    var fontSize: CGFloat
    var isBold: Bool
    var source: Source

    /// The line rendered as text: its words joined with single spaces (output rules).
    var text: String { words.map(\.text).joined(separator: " ") }
}
/// Assembles display-space words into lines (tech spec §6.7.1): cluster words into vertical
/// bands, split each band at column gutters, then order the words on the line (right-to-left
/// when the line is RTL-dominant). Pure and side-effect free.
enum LineAssembler {

    /// The outcome of assembling one page's words.
    struct Assembly: Equatable, Sendable {
        var lines: [Line]
        /// True when at least one line has > 50 % RTL letters -> surfaces `rtlBasicSupport`.
        var hasRTL: Bool
    }

    static func assemble(page: Int, words: [Word], source: Line.Source = .textLayer) -> Assembly {
        guard !words.isEmpty else { return Assembly(lines: [], hasRTL: false) }

        var lines: [Line] = []
        var hasRTL = false
        for band in cluster(words: words) {
            for segment in splitAtGutters(words: band) {
                let line = buildLine(words: segment, page: page, source: source)
                if isRTLDominant(words: segment) { hasRTL = true }
                lines.append(line)
            }
        }
        return Assembly(lines: lines, hasRTL: hasRTL)
    }

    // MARK: - Vertical clustering

    /// Groups words whose vertical centres lie within `0.5 x median word height` of the band's
    /// running mean centre, after sorting by vertical centre.
    private static func cluster(words: [Word]) -> [[Word]] {
        let threshold = 0.5 * medianSorted(words.map { $0.box.height })
        let sorted = words.sorted { $0.box.midY < $1.box.midY }
        var bands: [[Word]] = []
        var current: [Word] = []
        var centreSum: CGFloat = 0
        for word in sorted {
            if current.isEmpty {
                current = [word]
                centreSum = word.box.midY
            } else {
                let mean = centreSum / CGFloat(current.count)
                if abs(word.box.midY - mean) < threshold {
                    current.append(word)
                    centreSum += word.box.midY
                } else {
                    bands.append(current)
                    current = [word]
                    centreSum = word.box.midY
                }
            }
        }
        if !current.isEmpty { bands.append(current) }
        return bands
    }
    // MARK: - Column-gutter splitting

    /// Splits a vertical band into lines where the horizontal gap between consecutive
    /// (x-ascending) words exceeds `columnGapFactor` (2.0) x the larger of the two font sizes.
    private static func splitAtGutters(words: [Word]) -> [[Word]] {
        let sorted = words.sorted { $0.box.minX < $1.box.minX }
        var segments: [[Word]] = []
        var segment: [Word] = []
        for word in sorted {
            if let last = segment.last {
                let gap = word.box.minX - last.box.maxX
                let threshold = CGFloat(Constants.columnGapFactor) * max(last.fontSize, word.fontSize)
                if gap > threshold {
                    segments.append(segment)
                    segment = [word]
                    continue
                }
            }
            segment.append(word)
        }
        if !segment.isEmpty { segments.append(segment) }
        return segments
    }

    // MARK: - Line metadata

    private static func buildLine(words: [Word], page: Int, source: Line.Source) -> Line {
        let rtl = isRTLDominant(words: words)
        let ordered = words.sorted {
            rtl ? $0.box.minX > $1.box.minX : $0.box.minX < $1.box.minX
        }
        var box = CGRect.null
        var fontSize: CGFloat = 0
        var boldCount = 0
        for word in ordered {
            box = box.union(word.box)
            fontSize = max(fontSize, word.fontSize)
            if word.isBold { boldCount += 1 }
        }
        return Line(
            page: page,
            words: ordered,
            box: box,
            fontSize: fontSize,
            isBold: boldCount * 2 > ordered.count,  // strict majority
            source: source
        )
    }
    // MARK: - RTL detection

    /// True when > 50 % of a line's letters are RTL (Arabic/Hebrew) scripts.
    static func isRTLDominant(words: [Word]) -> Bool {
        var rtl = 0
        var total = 0
        for word in words {
            for scalar in word.text.unicodeScalars {
                total += 1
                if isRTLScalar(scalar) { rtl += 1 }
            }
        }
        return total > 0 && rtl > total / 2
    }

    private static func isRTLScalar(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x0590...0x05FF: return true  // Hebrew
        case 0x0600...0x06FF: return true  // Arabic
        case 0x0750...0x077F: return true  // Arabic Supplement
        case 0x08A0...0x08FF: return true  // Arabic Extended-A
        case 0xFB1D...0xFB4F: return true  // Hebrew & Arabic presentation forms
        case 0xFB50...0xFDFF: return true  // Arabic presentation forms-A
        default: return false
        }
    }

    // MARK: - Helpers

    private static func medianSorted(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let n = sorted.count
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }
}
