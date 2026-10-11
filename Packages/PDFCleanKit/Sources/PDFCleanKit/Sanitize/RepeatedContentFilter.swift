import CoreGraphics

/// Removes running headers/footers, page numbers and repeated watermark lines across the whole
/// document (sanitisation spec §5, FR-12, FR-16). Runs after all pages are assembled into
/// `Line`s. Rules run in the order A → C → B; a line removed by one rule is not counted again.
/// Pure, side-effect free.
enum RepeatedContentFilter {

    struct Result: Equatable, Sendable {
        var lines: [Line]
        var removedHeaderFooterLines: Int = 0
        var removedRepeatedLines: Int = 0
    }

    /// `pageSizes` maps page index to its display-space size, needed for the margin band and
    /// relative-position tests. `pageCount` is the document's total page count (the filter is a
    /// no-op below `repeatRatioMinPages`, even if `lines` only covers fewer pages with content).
    static func filter(
        lines: [Line],
        pageCount: Int,
        pageSizes: [Int: CGSize],
        bodySize: CGFloat,
        removeHeadersFooters: Bool = true,
        removeRepeatedLines: Bool = true
    ) -> Result {
        guard pageCount >= Constants.repeatRatioMinPages else {
            return Result(lines: lines)
        }
        let threshold = max(
            Constants.repeatRatioMinPages,
            Int((Double(pageCount) * Constants.repeatRatio).rounded(.up)))

        var removed = Set<Int>()
        var removedHF = 0
        var removedRep = 0

        if removeHeadersFooters {
            removedHF += applyRuleA(
                lines: lines, pageSizes: pageSizes, bodySize: bodySize, threshold: threshold, removed: &removed)
            removedHF += applyRuleC(lines: lines, pageSizes: pageSizes, removed: &removed)
        }
        if removeRepeatedLines {
            removedRep += applyRuleB(
                lines: lines, pageSizes: pageSizes, bodySize: bodySize, threshold: threshold, removed: &removed)
        }

        let remaining = lines.indices.filter { !removed.contains($0) }.map { lines[$0] }
        return Result(lines: remaining, removedHeaderFooterLines: removedHF, removedRepeatedLines: removedRep)
    }

    // MARK: - Rule A: headers/footers

    /// A margin-band line, at most `headerFooterMaxSizeFactor × body` in size, whose `digitKey`
    /// recurs in the band on at least `threshold` pages is removed everywhere it occurs.
    private static func applyRuleA(
        lines: [Line], pageSizes: [Int: CGSize], bodySize: CGFloat, threshold: Int, removed: inout Set<Int>
    ) -> Int {
        var groups: [String: [Int]] = [:]
        for i in lines.indices where !removed.contains(i) {
            let line = lines[i]
            guard let size = pageSizes[line.page], isInMarginBand(line, pageHeight: size.height) else { continue }
            guard line.fontSize <= CGFloat(Constants.headerFooterMaxSizeFactor) * bodySize else { continue }
            groups[digitKey(line.text), default: []].append(i)
        }
        return removeGroupsMeetingThreshold(groups, lines: lines, threshold: threshold, removed: &removed)
    }

    // MARK: - Rule C: page numbers

    /// A margin-band line matching a page-number pattern is removed even when it does not
    /// repeat.
    private static func applyRuleC(lines: [Line], pageSizes: [Int: CGSize], removed: inout Set<Int>) -> Int {
        let numberPattern =
            #/^(page|seite|p\.|s\.)?\s*(\d{1,4}|[ivxlcdm]{1,6})(\s*(of|von|\/|de|di)\s*\d{1,4})?$/#.ignoresCase()
        let dashPattern = #/^[-–—]\s*\d{1,4}\s*[-–—]$/#

        var count = 0
        for i in lines.indices where !removed.contains(i) {
            let line = lines[i]
            guard let size = pageSizes[line.page], isInMarginBand(line, pageHeight: size.height) else { continue }
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            if trimmed.wholeMatch(of: numberPattern) != nil || trimmed.wholeMatch(of: dashPattern) != nil {
                removed.insert(i)
                count += 1
            }
        }
        return count
    }

    // MARK: - Rule B: repeated lines / watermarks

    /// A line, at most `repeatedLineMaxSizeFactor × body` in size, whose exact text and relative
    /// position (± `positionTolerance`) recur on at least `threshold` pages is removed
    /// everywhere it occurs. The size cap keeps real headings (which exceed it) safe.
    private static func applyRuleB(
        lines: [Line], pageSizes: [Int: CGSize], bodySize: CGFloat, threshold: Int, removed: inout Set<Int>
    ) -> Int {
        var byExactKey: [String: [Int]] = [:]
        for i in lines.indices where !removed.contains(i) {
            let line = lines[i]
            guard line.fontSize <= CGFloat(Constants.repeatedLineMaxSizeFactor) * bodySize else { continue }
            guard pageSizes[line.page] != nil else { continue }
            byExactKey[exactKey(line.text), default: []].append(i)
        }

        var count = 0
        for (_, indices) in byExactKey {
            var pool = indices
            while let seed = pool.first {
                pool.removeFirst()
                guard let seedSize = pageSizes[lines[seed].page] else { continue }
                let seedPosition = relativePosition(lines[seed], size: seedSize)

                var cluster = [seed]
                var rest: [Int] = []
                for idx in pool {
                    guard let size = pageSizes[lines[idx].page] else { rest.append(idx); continue }
                    let position = relativePosition(lines[idx], size: size)
                    if abs(position.x - seedPosition.x) <= Constants.positionTolerance,
                        abs(position.y - seedPosition.y) <= Constants.positionTolerance
                    {
                        cluster.append(idx)
                    } else {
                        rest.append(idx)
                    }
                }
                pool = rest

                let pages = Set(cluster.map { lines[$0].page })
                if pages.count >= threshold {
                    for idx in cluster { removed.insert(idx) }
                    count += cluster.count
                }
            }
        }
        return count
    }

    // MARK: - Shared helpers

    private static func removeGroupsMeetingThreshold(
        _ groups: [String: [Int]], lines: [Line], threshold: Int, removed: inout Set<Int>
    ) -> Int {
        var count = 0
        for (_, indices) in groups {
            let pages = Set(indices.map { lines[$0].page })
            guard pages.count >= threshold else { continue }
            for i in indices { removed.insert(i) }
            count += indices.count
        }
        return count
    }

    private static func isInMarginBand(_ line: Line, pageHeight: CGFloat) -> Bool {
        guard pageHeight > 0 else { return false }
        let band = CGFloat(Constants.marginBand) * pageHeight
        return line.box.minY < band || line.box.maxY > pageHeight - band
    }

    private static func relativePosition(_ line: Line, size: CGSize) -> (x: Double, y: Double) {
        guard size.width > 0, size.height > 0 else { return (0, 0) }
        return (Double(line.box.minX / size.width), Double(line.box.minY / size.height))
    }

    /// NFC text with collapsed whitespace runs.
    private static func exactKey(_ text: String) -> String {
        let nfc = text.precomposedStringWithCanonicalMapping
        return nfc.replacing(#/\s+/#, with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// `exactKey`, lower-cased, with every digit run and every word-bounded roman numeral
    /// replaced by `#` (sanitisation spec §5).
    private static func digitKey(_ text: String) -> String {
        var s = exactKey(text).lowercased()
        s = s.replacing(#/\d+/#, with: "#")
        s = s.replacing(#/\b[ivxlcdm]+\b/#, with: "#")
        return s
    }
}
