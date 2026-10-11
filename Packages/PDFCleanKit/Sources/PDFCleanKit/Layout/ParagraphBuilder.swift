import CoreGraphics

/// Carves preformatted (table-like) runs out of a body-line run and groups the rest into
/// paragraphs (tech spec §6.7.4 preformatted + paragraphs rules, FR-09). Pure, side-effect free.
///
/// *Interpretation* (spec gap): "the column's left edge" / "column width" are read as the
/// minimum left edge and maximum line width observed across the whole run passed to one
/// `build` call — a run already corresponds to one body segment between headings/lists, which
/// in practice means one column. A genuine multi-column body run (lines from two columns
/// concatenated without an intervening heading) is out of scope for this reading.
enum ParagraphBuilder {

    private static let sentenceEnders: Set<Character> = [".", "!", "?", ":", ";", "\"", "”", "»", ")"]

    /// `lines` must already be assembled and in reading order, with lists already removed.
    /// `includePageBreaks` inserts `.pageBreak(page:)` at a page transition the text does not
    /// continue across (cross-page paragraph continuation, tech spec §6.7.4).
    static func build(lines: [Line], bodySpacing: CGFloat, includePageBreaks: Bool = false) -> [Block] {
        guard !lines.isEmpty else { return [] }

        var blocks: [Block] = []
        var pending: [Line] = []
        var i = 0
        while i < lines.count {
            if isTableLike(lines[i]) {
                var j = i
                while j < lines.count, isTableLike(lines[j]) { j += 1 }
                if j - i >= 3 {
                    blocks += paragraphs(for: pending, bodySpacing: bodySpacing, includePageBreaks: includePageBreaks)
                    pending = []
                    blocks.append(.preformatted(preformattedText(for: Array(lines[i..<j]))))
                    i = j
                    continue
                }
            }
            pending.append(lines[i])
            i += 1
        }
        blocks += paragraphs(for: pending, bodySpacing: bodySpacing, includePageBreaks: includePageBreaks)
        return blocks
    }

    // MARK: - Preformatted (table-like) runs

    /// A line has at least 2 internal gaps wider than `preformattedGapFactor × size` between
    /// consecutive words (table-like columns).
    private static func isTableLike(_ line: Line) -> Bool {
        guard line.words.count >= 3 else { return false }
        var gaps = 0
        for i in 1..<line.words.count {
            let previous = line.words[i - 1]
            let word = line.words[i]
            let threshold = CGFloat(Constants.preformattedGapFactor) * max(previous.fontSize, word.fontSize)
            if word.box.minX - previous.box.maxX > threshold { gaps += 1 }
        }
        return gaps >= 2
    }

    /// Renders a table-like run as text: words joined by one space, except at a qualifying
    /// internal gap, which becomes two spaces; lines joined by newline.
    private static func preformattedText(for lines: [Line]) -> String {
        lines.map { line in
            var parts: [String] = []
            for (i, word) in line.words.enumerated() {
                if i > 0 {
                    let previous = line.words[i - 1]
                    let threshold = CGFloat(Constants.preformattedGapFactor) * max(previous.fontSize, word.fontSize)
                    parts.append(word.box.minX - previous.box.maxX > threshold ? "  " : " ")
                }
                parts.append(word.text)
            }
            return parts.joined()
        }.joined(separator: "\n")
    }

    // MARK: - Paragraphs

    private static func paragraphs(for lines: [Line], bodySpacing: CGFloat, includePageBreaks: Bool) -> [Block] {
        guard !lines.isEmpty else { return [] }
        let columnLeftEdge = lines.map(\.box.minX).min() ?? 0
        let columnWidth = lines.map(\.box.width).max() ?? 0

        var blocks: [Block] = []
        var current: [Line] = [lines[0]]
        for i in 1..<lines.count {
            let previous = lines[i - 1]
            let line = lines[i]
            let decision = paragraphBreak(
                current: line, previous: previous, columnLeftEdge: columnLeftEdge, columnWidth: columnWidth,
                bodySpacing: bodySpacing)
            if decision.newParagraph {
                blocks.append(.paragraph(joinedText(of: current)))
                if includePageBreaks, decision.pageChanged {
                    blocks.append(.pageBreak(page: line.page))
                }
                current = [line]
            } else {
                current.append(line)
            }
        }
        blocks.append(.paragraph(joinedText(of: current)))
        return blocks
    }

    /// Starts a new paragraph on: a page change (unless the text visibly continues — no
    /// terminal punctuation on the previous line and a lowercase start on the next, since line
    /// geometry is not comparable across pages); a large gap above; a font size or weight
    /// change; a first-line indent beyond 1 em from the column's left edge; or a short line
    /// ending in terminal punctuation.
    private static func paragraphBreak(
        current: Line, previous: Line, columnLeftEdge: CGFloat, columnWidth: CGFloat, bodySpacing: CGFloat
    ) -> (newParagraph: Bool, pageChanged: Bool) {
        if previous.page != current.page {
            let endsWithTerminal = sentenceEnders.contains(
                previous.text.trimmingCharacters(in: .whitespaces).last ?? " ")
            let startsLowercase = current.text.trimmingCharacters(in: .whitespaces).first?.isLowercase ?? false
            let continues = !endsWithTerminal && startsLowercase
            return (!continues, true)
        }
        if current.box.minY - previous.box.maxY > CGFloat(Constants.paragraphGapFactor) * bodySpacing {
            return (true, false)
        }
        if abs(current.fontSize - previous.fontSize) > 0.5 { return (true, false) }
        if current.isBold != previous.isBold { return (true, false) }
        if current.box.minX - columnLeftEdge > current.fontSize { return (true, false) }
        if let lastChar = previous.text.trimmingCharacters(in: .whitespaces).last, sentenceEnders.contains(lastChar),
            columnWidth > 0, previous.box.width < CGFloat(Constants.shortLineFactor) * columnWidth
        {
            return (true, false)
        }
        return (false, false)
    }

    // MARK: - Joining

    private static func joinedText(of lines: [Line]) -> String {
        guard var result = lines.first?.text else { return "" }
        for line in lines.dropFirst() {
            result = join(previous: result, next: line.text)
        }
        return result
    }

    /// A trailing hyphen or soft hyphen preceded by a letter either disappears (next line
    /// starts lowercase: it was a line-break hyphenation) or is kept visible with no space
    /// (next line starts uppercase/digit); otherwise lines join with one space.
    private static func join(previous: String, next: String) -> String {
        let hyphenCharacters: Set<Character> = ["-", "\u{00AD}"]
        guard let lastChar = previous.last, hyphenCharacters.contains(lastChar) else {
            return previous + " " + next
        }
        let stem = String(previous.dropLast())
        guard let beforeHyphen = stem.last, beforeHyphen.isLetter, let firstChar = next.first else {
            return previous + " " + next
        }
        if firstChar.isLowercase {
            return stem + next
        } else if firstChar.isUppercase || firstChar.isNumber {
            return stem + "-" + next
        } else {
            return previous + " " + next
        }
    }
}
