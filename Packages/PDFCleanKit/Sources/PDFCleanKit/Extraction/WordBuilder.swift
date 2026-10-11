import CoreGraphics

/// Groups a page's glyph sequence into words (tech spec §6.4). Splits at whitespace/newline
/// separators and at geometry jumps (gap > `wordGapFactor × size`, or a vertical centre jump >
/// 0.5 × glyph height — a new line in content order). A zero-width/format glyph (empty box,
/// not whitespace) never splits a word — "Visi⟨U+200B⟩ble" stays one word, the invisible
/// character kept so `UnicodeSanitizer` can remove it later. A word built from only such
/// glyphs has no geometry and attaches to the preceding word instead of standing alone. Pure,
/// side-effect free.
enum WordBuilder {

    static func build(glyphs: [Glyph]) -> [Word] {
        var words: [Word] = []
        var current: [Glyph] = []

        func flush() {
            guard !current.isEmpty else { return }
            let word = makeWord(from: current)
            if word.box.isNull, let lastIndex = words.indices.last {
                words[lastIndex].glyphs += word.glyphs
                words[lastIndex].text += word.text
            } else {
                words.append(word)
            }
            current = []
        }

        for glyph in glyphs {
            // Whitespace is always a separator, regardless of whether PDFKit happened to
            // report a non-empty advance-width box for it — only a *non*-whitespace empty box
            // (a genuine zero-width/format character) stays inside the current word.
            if isWhitespaceOrNewline(glyph.text) {
                flush()
                continue
            }
            if shouldSplit(current: current, next: glyph) {
                flush()
            }
            current.append(glyph)
        }
        flush()
        return words
    }

    // MARK: - Splitting

    /// Compares `next` against the last *geometrically meaningful* (non-empty-box) glyph so
    /// far — a run of zero-width glyphs carries no position to measure a gap from.
    private static func shouldSplit(current: [Glyph], next: Glyph) -> Bool {
        guard isZeroWidth(next.box) == false else { return false }
        guard let previous = current.last(where: { !isZeroWidth($0.box) }) else { return false }
        let size = max(previous.fontSize, next.fontSize)
        let horizontalGap = next.box.minX - previous.box.maxX
        if horizontalGap > CGFloat(Constants.wordGapFactor) * size { return true }
        // Font size, not the glyph's own ink-box height: PDFKit's `characterBounds` ink boxes
        // vary a lot letter to letter (ascenders/descenders, even occasional degenerate
        // zero-height boxes for ordinary visible glyphs) — far too noisy to threshold against
        // directly. Font size is the stable per-character metric this same rule already uses
        // for the horizontal gap just above.
        let verticalJump = abs(next.box.midY - previous.box.midY)
        return verticalJump > 0.5 * size
    }

    // MARK: - Assembly

    private static func makeWord(from glyphs: [Glyph]) -> Word {
        let text = glyphs.map(\.text).joined()
        var box = CGRect.null
        var pageBox = CGRect.null
        var fontSize: CGFloat = 0
        var boldCount = 0
        var geometricCount = 0
        for glyph in glyphs where !isZeroWidth(glyph.box) {
            box = box.union(glyph.box)
            pageBox = pageBox.union(glyph.pageBox)
            fontSize = max(fontSize, glyph.fontSize)
            if glyph.isBold { boldCount += 1 }
            geometricCount += 1
        }
        return Word(
            text: text, box: box, pageBox: pageBox, glyphs: glyphs, fontSize: fontSize,
            isBold: geometricCount > 0 && boldCount * 2 > geometricCount)
    }

    private static func isWhitespaceOrNewline(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isWhitespace)
    }

    /// A glyph with zero *advance* — a genuine zero-width/format character. Deliberately not
    /// `CGRect.isEmpty`: PDFKit occasionally reports a zero-*height* box for an ordinary,
    /// normally-advancing visible glyph (observed on real fixture text), which `isEmpty` would
    /// also catch and wrongly exclude from gap measurements, folding its width into the
    /// neighbouring gap.
    private static func isZeroWidth(_ box: CGRect) -> Bool {
        box.width <= 0
    }
}
