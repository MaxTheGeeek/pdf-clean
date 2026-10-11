import CoreGraphics
import Foundation

/// Classifies a page's assembled, reading-order lines into the document title, leveled
/// headings and body lines (tech spec §6.7.4 title + heading rules). Headings pre-identified by
/// the PDF outline or `TOCDetector` (via `Hint`) take priority over typographic detection. Pure,
/// side-effect free; unmatched lines pass through as `.body` for later stages (`ListDetector`,
/// `ParagraphBuilder`).
enum HeadingClassifier {

    /// A heading pre-identified by the PDF outline or the detected table of contents, matched
    /// by normalised text on the same page.
    struct Hint: Equatable, Sendable {
        var page: Int
        var normalizedText: String
        var level: Int
    }

    enum Classification: Equatable, Sendable {
        case title(String)
        case heading(level: Int, text: String)
        case body(Line)
    }

    /// Normalises text for outline/TOC matching: casefold, collapse whitespace, strip trailing
    /// dots and digits (tech spec §6.7.4).
    static func normalize(_ text: String) -> String {
        var s = text.folding(options: .caseInsensitive, locale: nil)
        s = s.replacing(#/\s+/#, with: " ")
        s = s.trimmingCharacters(in: .whitespaces)
        s = s.replacing(#/[\s.\d]+$/#, with: "")
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Classifies `lines` (already in per-page reading order) into title, leveled headings and
    /// body lines, in that priority order. `pageHeights` maps page index to display-space page
    /// height (needed for the title's "upper 50 %" rule).
    static func classify(
        lines: [Line],
        pageHeights: [Int: CGFloat],
        bodySize: CGFloat,
        bodySpacing: CGFloat,
        hints: [Hint] = []
    ) -> [Classification] {
        guard !lines.isEmpty else { return [] }

        var consumed = Set<Int>()
        var results: [Int: Classification] = [:]

        for (i, line) in lines.enumerated() {
            let normalized = normalize(line.text)
            if let hint = hints.first(where: { $0.page == line.page && $0.normalizedText == normalized }) {
                results[i] = .heading(level: hint.level, text: line.text)
                consumed.insert(i)
            }
        }

        if let titleRun = findTitle(lines: lines, consumed: consumed, pageHeights: pageHeights, bodySize: bodySize) {
            results[titleRun.startIndex] = .title(titleRun.text)
            consumed.formUnion(titleRun.indices)
        }

        for run in findHeadings(lines: lines, consumed: consumed, bodySize: bodySize, bodySpacing: bodySpacing) {
            results[run.startIndex] = .heading(level: run.level, text: run.text)
            consumed.formUnion(run.indices)
        }

        var output: [Classification] = []
        for i in lines.indices {
            if let classification = results[i] {
                output.append(classification)
            } else if !consumed.contains(i) {
                output.append(.body(lines[i]))
            }
        }
        return output
    }

    // MARK: - Shared run type

    private struct Run {
        var startIndex: Int
        var indices: [Int]
        var text: String
        var level: Int = 0
    }

    // MARK: - Title

    /// First page with an unconsumed line, line(s) in its upper half whose size is at least
    /// `titleSizeFactor × body` and whose style does not recur on more than one other page
    /// (otherwise it is a recurring heading style, e.g. "Chapter 1…200", not a title). Adjacent
    /// lines (by array position) with the same rounded size and weight merge into one title.
    private static func findTitle(
        lines: [Line], consumed: Set<Int>, pageHeights: [Int: CGFloat], bodySize: CGFloat
    ) -> Run? {
        let unconsumedPages = lines.indices.filter { !consumed.contains($0) }.map { lines[$0].page }
        guard let firstPage = unconsumedPages.min() else { return nil }
        let pageHeight = pageHeights[firstPage] ?? (lines.filter { $0.page == firstPage }.map(\.box.maxY).max() ?? 0)

        let candidates = lines.indices.filter { i in
            !consumed.contains(i) && lines[i].page == firstPage && lines[i].box.minY < pageHeight / 2
        }
        let minTitleSize = CGFloat(Constants.titleSizeFactor) * bodySize
        let sized = candidates.filter { lines[$0].fontSize >= minTitleSize }
        guard let winnerSize = sized.map({ roundedSize(lines[$0].fontSize) }).max() else { return nil }
        guard let firstWinner = sized.first(where: { roundedSize(lines[$0].fontSize) == winnerSize }) else {
            return nil
        }
        let winnerBold = lines[firstWinner].isBold

        // Recurring-style guard: the same style elsewhere, on more than one other page, means
        // this is a repeating heading style (e.g. chapter titles), not a one-off document title.
        let otherPages = Set(
            lines.indices
                .filter { $0 != firstWinner && lines[$0].page != firstPage }
                .filter { roundedSize(lines[$0].fontSize) == winnerSize && lines[$0].isBold == winnerBold }
                .map { lines[$0].page }
        )
        guard otherPages.count <= 1 else { return nil }

        var indices = [firstWinner]
        var cursor = firstWinner
        while cursor + 1 < lines.count, !consumed.contains(cursor + 1), lines[cursor + 1].page == firstPage,
            roundedSize(lines[cursor + 1].fontSize) == winnerSize, lines[cursor + 1].isBold == winnerBold
        {
            indices.append(cursor + 1)
            cursor += 1
        }
        let text = indices.map { lines[$0].text }.joined(separator: " ")
        return Run(startIndex: firstWinner, indices: indices, text: text)
    }

    // MARK: - Headings

    private struct HeadingCandidate {
        var roundedSize: CGFloat
        var isBold: Bool
        var isBoldAtBody: Bool
        var numberingDepth: Int?
    }

    /// A line qualifies as a heading candidate when its size is at least `headingSizeFactor ×
    /// body` (a), or it is bold, at most 12 words, has no terminal period and the gap above it
    /// is at least `headingGapFactor × bodySpacing` (b). A numbered line (`^1.2. Title`) that
    /// already qualifies via (a) or (b) additionally carries its numbering depth, which —
    /// *interpretation*, filling a spec ambiguity — overrides the size-rank level below
    /// ("numbering depth breaks ties", tech spec §6.7.4): when a heading's own numbering
    /// disagrees with the level its font size alone would imply, the explicit numbering wins.
    private static func candidate(
        at i: Int, lines: [Line], bodySize: CGFloat, bodySpacing: CGFloat
    ) -> HeadingCandidate? {
        let line = lines[i]
        let trimmed = line.text.trimmingCharacters(in: .whitespaces)
        let wordCount = trimmed.split(separator: " ", omittingEmptySubsequences: true).count
        let endsWithPeriod = trimmed.hasSuffix(".")
        let sizeOK = line.fontSize >= CGFloat(Constants.headingSizeFactor) * bodySize
        let gap = gapAbove(i, lines: lines)
        let gapOK = gap >= CGFloat(Constants.headingGapFactor) * bodySpacing
        let boldOK = line.isBold && wordCount <= 12 && !endsWithPeriod && gapOK
        guard sizeOK || boldOK else { return nil }

        let rounded = roundedSize(line.fontSize)
        let isBoldAtBody = boldOK && !sizeOK && rounded == roundedSize(bodySize)
        return HeadingCandidate(
            roundedSize: rounded, isBold: line.isBold, isBoldAtBody: isBoldAtBody,
            numberingDepth: numberingDepth(of: trimmed))
    }

    private static func numberingDepth(of text: String) -> Int? {
        let regex = #/^(\d+(?:\.\d+)*)\.?\s+\p{Lu}/#
        guard let match = text.firstMatch(of: regex) else { return nil }
        return match.1.split(separator: ".").count
    }

    private static func findHeadings(
        lines: [Line], consumed: Set<Int>, bodySize: CGFloat, bodySpacing: CGFloat
    ) -> [Run] {
        var candidates: [Int: HeadingCandidate] = [:]
        for i in lines.indices where !consumed.contains(i) {
            if let c = candidate(at: i, lines: lines, bodySize: bodySize, bodySpacing: bodySpacing) {
                candidates[i] = c
            }
        }
        guard !candidates.isEmpty else { return [] }

        var runs: [[Int]] = []
        var current: [Int] = []
        for i in lines.indices {
            guard let c = candidates[i] else {
                if !current.isEmpty { runs.append(current) }
                current = []
                continue
            }
            if let lastIndex = current.last, let lastC = candidates[lastIndex],
                lastIndex == i - 1, lastC.roundedSize == c.roundedSize, lastC.isBold == c.isBold,
                gapAbove(i, lines: lines) <= CGFloat(Constants.headingMergeGapFactor) * bodySpacing
            {
                current.append(i)
            } else {
                if !current.isEmpty { runs.append(current) }
                current = [i]
            }
        }
        if !current.isEmpty { runs.append(current) }

        // Level by distinct size, descending (1, 2, 3, 4…, capped at 4); bold-at-body-size runs
        // sit one level below the smallest real size level (or level 1 if there is none).
        let realSizes = Set(
            runs.compactMap { run -> CGFloat? in
                guard let c = candidates[run[0]], !c.isBoldAtBody else { return nil }
                return c.roundedSize
            }
        ).sorted(by: >)
        func rank(of size: CGFloat) -> Int {
            min((realSizes.firstIndex(of: size) ?? realSizes.count - 1) + 1, 4)
        }
        let smallestRealLevel = realSizes.isEmpty ? 0 : rank(of: realSizes[realSizes.count - 1])

        var results: [Run] = []
        for run in runs {
            guard let c = candidates[run[0]] else { continue }
            let text = run.map { lines[$0].text }.joined(separator: " ")
            let level: Int
            if let depth = c.numberingDepth {
                level = min(max(depth, 1), 4)
            } else if c.isBoldAtBody {
                level = smallestRealLevel == 0 ? 1 : min(smallestRealLevel + 1, 4)
            } else {
                level = rank(of: c.roundedSize)
            }
            results.append(Run(startIndex: run[0], indices: run, text: text, level: level))
        }
        return results
    }

    // MARK: - Geometry helpers

    /// Vertical gap between `lines[i]` and the preceding line, when they are on the same page
    /// and their horizontal extents overlap (same column). `.greatestFiniteMagnitude` (i.e. an
    /// unbounded gap) at the top of a page or column, or when there is no preceding line.
    private static func gapAbove(_ i: Int, lines: [Line]) -> CGFloat {
        guard i > 0 else { return .greatestFiniteMagnitude }
        let previous = lines[i - 1]
        let line = lines[i]
        guard previous.page == line.page else { return .greatestFiniteMagnitude }
        guard previous.box.minX < line.box.maxX, line.box.minX < previous.box.maxX else {
            return .greatestFiniteMagnitude
        }
        return line.box.minY - previous.box.maxY
    }

    private static func roundedSize(_ size: CGFloat) -> CGFloat {
        (size * 2).rounded() / 2
    }
}
