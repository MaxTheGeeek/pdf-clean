import CoreGraphics

/// Detects bulleted and ordered list items among a run of body lines (tech spec §6.7.4 lists
/// rule, FR-10). A line starts an item when its first word is a bullet glyph or an ordered
/// marker (`1.`, `(a)`, `iv)` …); following lines whose left edge aligns with the item's text
/// (± `listContinuationAlignmentTolerance`) and that are not themselves a new marker are
/// continuation lines, merged into the item. Nesting level is the indentation-cluster rank of
/// the marker's x position. Pure, side-effect free; non-list lines pass through unchanged.
///
/// Known limitation (documented, not fixed — the ordered-marker regex is deliberately simple
/// per spec): a line starting with a single-letter initial and a period, e.g. "A. Smith, Esq.",
/// is indistinguishable from an ordered marker "A." and is detected as one.
enum ListDetector {

    enum Classification: Equatable, Sendable {
        case listItem(ListItem)
        case other(Line)
    }

    static func classify(lines: [Line]) -> [Classification] {
        guard !lines.isEmpty else { return [] }

        struct RawItem {
            var index: Int
            var ordered: Bool
            var marker: String
            var text: String
            var markerX: CGFloat
            var mergedIndices: [Int]
        }

        var rawItems: [RawItem] = []
        var consumed = Set<Int>()
        var i = 0
        while i < lines.count {
            guard let parsed = parseMarker(lines[i]) else {
                i += 1
                continue
            }
            var itemIndices = [i]
            var itemWords = Array(lines[i].words.dropFirst())
            let textStartX = lines[i].words.count > 1 ? lines[i].words[1].box.minX : lines[i].box.maxX

            var j = i + 1
            while j < lines.count, parseMarker(lines[j]) == nil,
                abs(lines[j].box.minX - textStartX) <= Constants.listContinuationAlignmentTolerance
            {
                itemWords += lines[j].words
                itemIndices.append(j)
                j += 1
            }

            let text = itemWords.map(\.text).joined(separator: " ")
            rawItems.append(
                RawItem(
                    index: i, ordered: parsed.ordered, marker: parsed.marker, text: text,
                    markerX: lines[i].box.minX, mergedIndices: Array(itemIndices.dropFirst())))
            consumed.formUnion(itemIndices)
            i = j
        }

        guard !rawItems.isEmpty else { return lines.map { .other($0) } }

        let clusters = indentationClusters(of: rawItems.map(\.markerX))
        var itemsByIndex: [Int: ListItem] = [:]
        for raw in rawItems {
            let level = clusterRank(of: raw.markerX, in: clusters) - 1  // ListItem is 0-based
            itemsByIndex[raw.index] = ListItem(ordered: raw.ordered, marker: raw.marker, level: level, text: raw.text)
        }

        var result: [Classification] = []
        for idx in lines.indices {
            if let item = itemsByIndex[idx] {
                result.append(.listItem(item))
            } else if !consumed.contains(idx) {
                result.append(.other(lines[idx]))
            }
        }
        return result
    }

    // MARK: - Marker parsing

    private static let bulletGlyphs: Set<Character> = [
        "•", "◦", "▪", "▫", "‣", "⁃", "●", "○", "■", "□", "–", "—", "-", "*", "·",
    ]

    private static func parseMarker(_ line: Line) -> (ordered: Bool, marker: String)? {
        guard let first = line.words.first else { return nil }
        let text = first.text
        if text.count == 1, let c = text.first, bulletGlyphs.contains(c) {
            return (false, text)
        }
        let orderedRegex = #/^\(?(\d{1,3}|[a-zA-Z]|[ivxlcdm]{1,6})[.)]$/#
        if text.wholeMatch(of: orderedRegex) != nil {
            return (true, text)
        }
        return nil
    }

    // MARK: - Indentation clustering

    private static func indentationClusters(of xPositions: [CGFloat]) -> [CGFloat] {
        let tolerance = Constants.indentationClusterTolerance
        let rounded = xPositions.map { (($0 / tolerance).rounded()) * tolerance }
        return Array(Set(rounded)).sorted()
    }

    private static func clusterRank(of x: CGFloat, in clusters: [CGFloat]) -> Int {
        let tolerance = Constants.indentationClusterTolerance
        let rounded = ((x / tolerance).rounded()) * tolerance
        return (clusters.firstIndex(of: rounded) ?? 0) + 1
    }
}
