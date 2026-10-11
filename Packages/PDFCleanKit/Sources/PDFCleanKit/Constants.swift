import CoreGraphics

/// Every tunable threshold in the pipeline, in one place (constitution P5). Keep in sync
/// with `specs/02-technical-spec.md` §10 and `scripts/reference/visibility_reference.py`;
/// change all three together, with fixture evidence.
public enum Constants {
    // MARK: Visibility (VisibilityFilter raster, sanitisation spec §3)

    /// Points → pixels scale factor for the visibility raster.
    public static let renderScale: CGFloat = 2.0
    /// Minimum per-channel byte difference from the background to count as ink, out of 255.
    public static let inkDelta: Int = 40
    /// Minimum fraction of a word's exclusive area that must be ink for it to count as visible.
    public static let minInkFraction: Double = 0.01
    /// Padding, as a fraction of box height, excluded around a word to avoid neighbour descenders.
    public static let neighbourPad: Double = 0.25
    /// Below this fraction of exclusive area remaining, fall back to testing the full box.
    public static let minExclusiveShare: Double = 0.30

    // MARK: Glyph-level filters (sanitisation spec §2)

    /// Glyphs smaller than this (points) are removed as tiny/invisible text.
    public static let minFontSize: CGFloat = 2.0
    /// Maximum angle (degrees) from horizontal/vertical still considered axis-aligned.
    public static let maxBaselineAngle: Double = 10
    /// Minimum glyphs in a diagonal run to call it a rotated watermark run.
    public static let minRotatedRun: Int = 3
    /// Maximum distance (× font size) between consecutive glyphs of a rotated run.
    public static let diagonalMaxStep: Double = 2.0
    /// Minimum fraction of a glyph's area inside the page to not be considered off-page.
    public static let offPageMinInside: Double = 0.5
    /// A candidate rotated run is kept (not dropped) when at least this fraction of its glyphs
    /// are CJK/Hangul/Kana — genuine vertical writing, not a diagonal watermark.
    public static let cjkVerticalExceptionRatio: Double = 0.8

    // MARK: Overlap dedupe (sanitisation spec §4)

    /// Minimum IoU for two same-text words to be treated as duplicates.
    public static let duplicateIoU: Double = 0.7

    // MARK: Repeated content filter (sanitisation spec §5)

    /// Header/footer band height as a fraction of page height.
    public static let marginBand: Double = 0.07
    /// Header/footer lines may be at most this × the body font size.
    public static let headerFooterMaxSizeFactor: Double = 1.05
    /// Repeated (non-header/footer) lines may be at most this × the body font size —
    /// headings are never removed by this rule.
    public static let repeatedLineMaxSizeFactor: Double = 1.15
    /// Fraction of pages a line must repeat on to be filtered.
    public static let repeatRatio: Double = 0.5
    /// Minimum page count for the repeated-content filter to apply at all.
    public static let repeatRatioMinPages: Int = 2
    /// Position tolerance, as a fraction of page size, for the "same position" test.
    public static let positionTolerance: Double = 0.02

    // MARK: Layout (tech spec §6.7)

    /// Gap between words, as a fraction of font size, that starts a new word.
    public static let wordGapFactor: Double = 0.25
    /// Horizontal gap between lines, as a fraction of font size, that implies a column gutter.
    public static let columnGapFactor: Double = 2.0
    /// Minimum gutter width (points) for the XY-cut reading-order algorithm.
    public static let minGutter: CGFloat = 12.0
    /// Title font size must be at least this × the body font size.
    public static let titleSizeFactor: Double = 1.4
    /// Heading font size must be at least this × the body font size.
    public static let headingSizeFactor: Double = 1.15
    /// Minimum gap above a bold candidate line, as a fraction of body line spacing, for it to
    /// qualify as a heading by the bold-candidate rule (tech spec §6.7.4(b)).
    public static let headingGapFactor: Double = 1.2
    /// Maximum gap between two same-style heading candidate lines, as a fraction of body line
    /// spacing, for them to merge into one heading (tech spec §6.7.4).
    public static let headingMergeGapFactor: Double = 1.3
    /// Paragraph break threshold, as a fraction of normal line spacing.
    public static let paragraphGapFactor: Double = 1.4
    /// A line shorter than this × column width may end a paragraph.
    public static let shortLineFactor: Double = 0.7
    /// Fraction of a page's lines that must look like TOC entries to call it a TOC page.
    public static let tocLineRatio: Double = 0.4
    /// Minimum number of lines for a page to be considered for TOC detection.
    public static let tocMinLines: Int = 4
    /// Horizontal positions within this many points are treated as one indentation cluster
    /// (TOC entry levels, list nesting levels).
    public static let indentationClusterTolerance: CGFloat = 5.0
    /// Maximum left-edge deviation (points) for a line to count as a list item's continuation.
    public static let listContinuationAlignmentTolerance: CGFloat = 3.0
    /// A line gap wider than this × font size is a "table-like" internal gap (preformatted
    /// detection).
    public static let preformattedGapFactor: Double = 2.0

    // MARK: OCR (tech spec §6.5)

    /// Render resolution (dots per inch) for OCR.
    public static let ocrDPI: Int = 300
    /// Minimum fraction of ink coverage on a page that triggers OCR in `.auto` mode.
    public static let ocrMinInkCoverage: Double = 0.005

    // MARK: Robustness limits (NFR-06)

    /// Documents with more pages than this are refused with `PipelineError.tooLarge`.
    public static let maxPages: Int = 2000
    /// Documents larger than this (bytes) are refused with `PipelineError.tooLarge`.
    public static let maxBytes: Int64 = 500 * 1024 * 1024
    /// Documents with more pages than this surface `ReportWarning.manyPages`.
    public static let warnPages: Int = 300
}
