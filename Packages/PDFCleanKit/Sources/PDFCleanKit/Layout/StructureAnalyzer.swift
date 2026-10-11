import CoreGraphics

/// Orchestrates the whole layout pipeline from assembled, reading-order lines to the final
/// document structure (tech spec §6.7.4): outline hints → TOC → title → headings → lists →
/// preformatted → paragraphs. Pure, side-effect free.
///
/// *Interpretation* (spec gap): the detected table of contents is placed immediately after the
/// title block (or at the very start, if there is no title) rather than interleaved at its
/// exact original position in the line sequence — the realistic case of a contents page near
/// the front of the document, and it avoids a much more complex interleaving scheme for a case
/// that essentially never arises (a TOC run occupies its own page(s)).
enum StructureAnalyzer {

    /// `lines` must already be assembled (`LineAssembler`) and in per-page reading order
    /// (`ReadingOrder`), concatenated for the whole document. `pageHeights` maps page index to
    /// display-space page height, for the title's "upper 50 %" rule. `outlineHints` come from
    /// the PDF outline (`DocumentOpener`); TOC-derived hints are added automatically.
    static func analyze(
        lines: [Line],
        pageHeights: [Int: CGFloat] = [:],
        outlineHints: [HeadingClassifier.Hint] = [],
        includePageBreaks: Bool = false
    ) -> [Block] {
        guard !lines.isEmpty else { return [] }
        let stats = FontStatistics.compute(lines: lines)
        let toc = TOCDetector.detect(lines: lines)

        let afterTOC: [Line]
        var hints = outlineHints
        if let toc {
            afterTOC = lines.enumerated().filter { !toc.consumedIndices.contains($0.offset) }.map(\.element)
            let lastTOCPage = toc.consumedIndices.map { lines[$0].page }.max() ?? -1
            hints += tocHeadingHints(for: toc.entries, in: afterTOC, afterPage: lastTOCPage)
        } else {
            afterTOC = lines
        }

        let headingClassified = HeadingClassifier.classify(
            lines: afterTOC, pageHeights: pageHeights, bodySize: stats.bodySize, bodySpacing: stats.bodyLineSpacing,
            hints: hints)

        var blocks: [Block] = []
        var bodyRun: [Line] = []
        func flushBodyRun() {
            guard !bodyRun.isEmpty else { return }
            blocks += processBodyRun(bodyRun, bodySpacing: stats.bodyLineSpacing, includePageBreaks: includePageBreaks)
            bodyRun = []
        }
        for classification in headingClassified {
            switch classification {
            case .title(let text):
                flushBodyRun()
                blocks.append(.title(text))
            case .heading(let level, let text):
                flushBodyRun()
                blocks.append(.heading(level: level, text: text))
            case .body(let line):
                bodyRun.append(line)
            }
        }
        flushBodyRun()

        if let toc {
            let tocBlock = Block.tableOfContents(heading: toc.heading, entries: toc.entries)
            if let titleIndex = blocks.firstIndex(where: {
                if case .title = $0 { return true }; return false
            }) {
                blocks.insert(tocBlock, at: titleIndex + 1)
            } else {
                blocks.insert(tocBlock, at: 0)
            }
        }
        return blocks
    }

    // MARK: - Body run (lists, preformatted, paragraphs)

    private static func processBodyRun(
        _ lines: [Line], bodySpacing: CGFloat, includePageBreaks: Bool
    ) -> [Block] {
        var blocks: [Block] = []
        var otherRun: [Line] = []
        func flushOther() {
            guard !otherRun.isEmpty else { return }
            blocks += ParagraphBuilder.build(
                lines: otherRun, bodySpacing: bodySpacing, includePageBreaks: includePageBreaks)
            otherRun = []
        }
        for item in ListDetector.classify(lines: lines) {
            switch item {
            case .listItem(let listItem):
                flushOther()
                blocks.append(.listItem(listItem))
            case .other(let line):
                otherRun.append(line)
            }
        }
        flushOther()
        return blocks
    }

    // MARK: - TOC entries as heading hints for later pages

    /// Each TOC entry's title acts as a heading hint for the first later line whose normalised
    /// text matches it (tech spec §6.7.4: "TOC entries also act as heading hints").
    private static func tocHeadingHints(
        for entries: [TOCEntry], in lines: [Line], afterPage: Int
    ) -> [HeadingClassifier.Hint] {
        entries.compactMap { entry in
            let normalized = HeadingClassifier.normalize(entry.title)
            guard
                let match = lines.first(where: {
                    $0.page > afterPage && HeadingClassifier.normalize($0.text) == normalized
                })
            else { return nil }
            return HeadingClassifier.Hint(page: match.page, normalizedText: normalized, level: entry.level)
        }
    }
}
