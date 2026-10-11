import CoreGraphics
import Foundation

/// Detects a table-of-contents run and its entries (tech spec §6.7.4 TOC rule, FR-08). A page is
/// a TOC page when it has a line matching the "Contents"-style keyword regex, or when at least
/// `tocLineRatio` of its lines (minimum `tocMinLines`) look like `title … page-number` entries.
/// Starting from the first such page, consecutive following pages that still qualify are folded
/// into the same run. Pure, side-effect free.
enum TOCDetector {

    /// One detected table-of-contents run: its heading line (if any), its entries, and the
    /// indices into the input `lines` array it consumed — the caller excludes these from later
    /// heading/paragraph processing.
    struct Result: Equatable, Sendable {
        var heading: String?
        var entries: [TOCEntry]
        var consumedIndices: Set<Int>
    }

    /// `lines` must already be assembled and in per-page reading order.
    static func detect(lines: [Line]) -> Result? {
        let pagesInOrder = orderedPages(of: lines)
        guard let startPage = pagesInOrder.first(where: { isTOCPage(page: $0, lines: lines) }) else {
            return nil
        }

        var runPages: Set<Int> = [startPage]
        var cursor = startPage
        for page in pagesInOrder where page > startPage {
            guard page == cursor + 1, isTOCPage(page: page, lines: lines) else { break }
            runPages.insert(page)
            cursor = page
        }

        var heading: String?
        var headingIndex: Int?
        var rawEntries: [(index: Int, title: String, page: String?, box: CGRect, mergedIndices: [Int])] = []
        var pendingTitle: String?
        var pendingIndices: [Int] = []

        for i in lines.indices where runPages.contains(lines[i].page) {
            let trimmed = lines[i].text.trimmingCharacters(in: .whitespaces)
            if isKeywordLine(trimmed) {
                if heading == nil {
                    heading = trimmed
                    headingIndex = i
                }
                // Anything pending before the heading (e.g. a title sharing this page) is not
                // part of a wrapped TOC entry; drop it rather than merging it into the next one.
                pendingTitle = nil
                pendingIndices = []
                continue
            }
            if let parsed = parseEntry(trimmed) {
                let title = [pendingTitle, parsed.title].compactMap { $0 }.joined(separator: " ")
                rawEntries.append((i, title, parsed.page, lines[i].box, pendingIndices))
                pendingTitle = nil
                pendingIndices = []
            } else if !trimmed.isEmpty {
                pendingTitle = [pendingTitle, trimmed].compactMap { $0 }.joined(separator: " ")
                pendingIndices.append(i)
            }
        }
        guard !rawEntries.isEmpty else { return nil }

        let clusters = indentationClusters(of: rawEntries.map { $0.box.minX })
        var consumed = Set<Int>()
        if let headingIndex { consumed.insert(headingIndex) }
        let entries = rawEntries.map { raw -> TOCEntry in
            consumed.insert(raw.index)
            consumed.formUnion(raw.mergedIndices)
            let level = numberingDepth(of: raw.title) ?? clusterRank(of: raw.box.minX, in: clusters)
            return TOCEntry(level: min(max(level, 1), 4), title: raw.title, page: raw.page)
        }
        return Result(heading: heading, entries: entries, consumedIndices: consumed)
    }

    // MARK: - Page qualification

    private static func orderedPages(of lines: [Line]) -> [Int] {
        var seen = Set<Int>()
        var result: [Int] = []
        for line in lines where !seen.contains(line.page) {
            seen.insert(line.page)
            result.append(line.page)
        }
        return result.sorted()
    }

    private static func isTOCPage(page: Int, lines: [Line]) -> Bool {
        let pageLines = lines.filter { $0.page == page }
        if pageLines.contains(where: { isKeywordLine($0.text.trimmingCharacters(in: .whitespaces)) }) {
            return true
        }
        guard pageLines.count >= Constants.tocMinLines else { return false }
        let matching = pageLines.filter { parseEntry($0.text.trimmingCharacters(in: .whitespaces)) != nil }.count
        return Double(matching) / Double(pageLines.count) >= Constants.tocLineRatio
    }

    private static func isKeywordLine(_ text: String) -> Bool {
        let regex =
            #/^(table of contents|contents|inhaltsverzeichnis|inhalt|sommaire|table des matières|índice|indice|فهرست( مطالب)?)$/#
            .ignoresCase()
        return text.wholeMatch(of: regex) != nil
    }

    // MARK: - Entry parsing

    /// Matches `title … page` (dot/space/other leaders, ≥ 2 repeats, then a decimal or lowercase
    /// roman page number). Leaders never appear in the returned title or page.
    private static func parseEntry(_ text: String) -> (title: String, page: String?)? {
        let regex = #/^(.+?)[\s.·…_]{2,}(\d{1,4}|[ivxlcdm]{1,6})$/#
        guard let match = text.wholeMatch(of: regex) else { return nil }
        let title = String(match.1).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (title, String(match.2))
    }

    private static func numberingDepth(of text: String) -> Int? {
        let regex = #/^(\d+(?:\.\d+)*)\.?\s+\p{Lu}/#
        guard let match = text.firstMatch(of: regex) else { return nil }
        return match.1.split(separator: ".").count
    }

    // MARK: - Indentation clustering

    /// Distinct left-edge positions, rounded to `indentationClusterTolerance`, sorted ascending
    /// (less indented first).
    private static func indentationClusters(of xPositions: [CGFloat]) -> [CGFloat] {
        let tolerance = Constants.indentationClusterTolerance
        let rounded = xPositions.map { (($0 / tolerance).rounded()) * tolerance }
        return Array(Set(rounded)).sorted()
    }

    /// 1-based rank of `x`'s cluster among `clusters` (least indented = level 1).
    private static func clusterRank(of x: CGFloat, in clusters: [CGFloat]) -> Int {
        let tolerance = Constants.indentationClusterTolerance
        let rounded = ((x / tolerance).rounded()) * tolerance
        return (clusters.firstIndex(of: rounded) ?? 0) + 1
    }
}
