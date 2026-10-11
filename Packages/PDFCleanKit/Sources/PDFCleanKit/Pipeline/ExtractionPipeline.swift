import Foundation
import NaturalLanguage
@preconcurrency import PDFKit

/// Runs the whole extraction pipeline end to end (tech spec §1, §6, §7): opens the document,
/// extracts and sanitises each page's words, assembles layout, and produces the final
/// `ExtractedDocument` with its `SanitizationReport`. An actor so PDFKit/CoreGraphics/Vision
/// objects never cross its isolation boundary; public results are value types.
public actor ExtractionPipeline {
    private let options: ExtractionOptions

    /// Creates a pipeline with the given options.
    public init(options: ExtractionOptions = ExtractionOptions()) {
        self.options = options
    }

    /// Emits progress events and finally `.finished`. Throws `PipelineError`. Honors
    /// cooperative cancellation between pages (and inside OCR).
    public func run(fileURL: URL, password: String?) -> AsyncThrowingStream<PipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let document = try await self.execute(fileURL: fileURL, password: password) { progress in
                        continuation.yield(.progress(progress))
                    }
                    continuation.yield(.finished(document))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Per-page counters

    private struct PageCounts {
        var removedOffPageWords = 0
        var removedTinyGlyphs = 0
        var removedRotatedRuns = 0
        var removedHiddenWords = 0
        var removedOverlappingDuplicates = 0
        var removedInvisibleCodepoints = 0
        var removedPrivateUseCodepoints = 0
        var normalizedWhitespace = 0
        var normalizedLigatures = 0
        var normalizedHomoglyphs = 0
        var sawReplacementCharacter = false
        var ocrPage = false
        var ocrLowConfidence = false
    }

    private func execute(
        fileURL: URL, password: String?, onProgress: @Sendable (PipelineProgress) -> Void
    ) async throws -> ExtractedDocument {
        onProgress(PipelineProgress(stage: .opening, page: 0, pageCount: 0, fractionCompleted: 0))
        let opened = try DocumentOpener.open(fileURL: fileURL, password: password)
        try Task.checkCancellation()

        let pageCount = opened.document.pageCount
        var report = SanitizationReport()
        report.sourceInventory = opened.inventory
        report.warnings = opened.warnings

        onProgress(
            PipelineProgress(
                stage: .opening, page: 0, pageCount: pageCount, fractionCompleted: ProgressReporter.afterOpening))

        var allLines: [Line] = []
        var pageSizes: [Int: CGSize] = [:]
        var pageHeights: [Int: CGFloat] = [:]
        var ocrPages: [Int] = []
        var ocrLowConfidencePages = 0

        for pageIndex in 0..<pageCount {
            try Task.checkCancellation()
            guard let page = opened.document.page(at: pageIndex) else { continue }
            let cropBox = page.bounds(for: .cropBox)
            let pageSize = PageGeometry.displaySize(cropBox: cropBox, rotation: page.rotation)
            pageSizes[pageIndex] = pageSize
            pageHeights[pageIndex] = pageSize.height

            onProgress(
                PipelineProgress(
                    stage: .readingPages, page: pageIndex + 1, pageCount: pageCount,
                    fractionCompleted: ProgressReporter.pagesProgress(pageIndex: pageIndex, pageCount: pageCount)))

            let (lines, counts) = try await processPage(
                page: page, pageIndex: pageIndex, pageSize: pageSize, cropBox: cropBox)
            allLines += lines

            report.removedOffPageWords += counts.removedOffPageWords
            report.removedTinyGlyphs += counts.removedTinyGlyphs
            report.removedRotatedRuns += counts.removedRotatedRuns
            report.removedHiddenWords += counts.removedHiddenWords
            report.removedOverlappingDuplicates += counts.removedOverlappingDuplicates
            report.removedInvisibleCodepoints += counts.removedInvisibleCodepoints
            report.removedPrivateUseCodepoints += counts.removedPrivateUseCodepoints
            report.normalizedWhitespace += counts.normalizedWhitespace
            report.normalizedLigatures += counts.normalizedLigatures
            report.normalizedHomoglyphs += counts.normalizedHomoglyphs
            if counts.sawReplacementCharacter, !report.warnings.contains(.unreadableCharacters) {
                report.warnings.append(.unreadableCharacters)
            }
            if counts.ocrPage {
                ocrPages.append(pageIndex + 1)
                if counts.ocrLowConfidence { ocrLowConfidencePages += 1 }
            }
        }
        report.ocrPages = ocrPages
        if !ocrPages.isEmpty, Double(ocrLowConfidencePages) / Double(ocrPages.count) > 0.3 {
            report.warnings.append(.ocrLowConfidence)
        }

        onProgress(
            PipelineProgress(
                stage: .analyzingLayout, page: 0, pageCount: pageCount, fractionCompleted: ProgressReporter.afterPages)
        )

        let stats = FontStatistics.compute(lines: allLines)
        let repeated = RepeatedContentFilter.filter(
            lines: allLines, pageCount: pageCount, pageSizes: pageSizes, bodySize: stats.bodySize,
            removeHeadersFooters: options.removeHeadersFooters, removeRepeatedLines: options.removeRepeatedLines)
        report.removedHeaderFooterLines += repeated.removedHeaderFooterLines
        report.removedRepeatedLines += repeated.removedRepeatedLines

        let blocks = StructureAnalyzer.analyze(
            lines: repeated.lines, pageHeights: pageHeights, outlineHints: outlineHints(of: opened.document),
            includePageBreaks: options.includePageBreaks)

        onProgress(
            PipelineProgress(
                stage: .cleaning, page: 0, pageCount: pageCount, fractionCompleted: ProgressReporter.afterLayout))

        let (sanitizedBlocks, lateCounts) = sanitizeFinalBlocks(blocks)
        if lateCounts.removedInvisibleCodepoints > 0 || lateCounts.removedPrivateUseCodepoints > 0
            || lateCounts.normalizedWhitespace > 0 || lateCounts.normalizedLigatures > 0
        {
            Log.event(
                "sanitize.late", ("removedInvisibleCodepoints", lateCounts.removedInvisibleCodepoints),
                ("normalizedWhitespace", lateCounts.normalizedWhitespace))
        }

        let identifierText = sanitizedBlocks.map(Self.blockText).joined(separator: "\n")
        report.suspiciousIdentifiers = IdentifierDetector.detect(in: identifierText)

        guard !sanitizedBlocks.isEmpty else { throw PipelineError.emptyDocument }

        onProgress(
            PipelineProgress(
                stage: .done, page: 0, pageCount: pageCount, fractionCompleted: ProgressReporter.afterCleaning))

        return ExtractedDocument(
            blocks: sanitizedBlocks, report: report, pageCount: pageCount,
            dominantLanguage: Self.detectLanguage(blocks: sanitizedBlocks))
    }

    // MARK: - Per-page extraction (tech spec §6.2–6.5)

    private func processPage(
        page: PDFPage, pageIndex: Int, pageSize: CGSize, cropBox: CGRect
    ) async throws -> (lines: [Line], counts: PageCounts) {
        var counts = PageCounts()
        let words: [Word]
        if let glyphs = GlyphExtractor.extract(page: page) {
            let filtered = GlyphFilter.filter(
                glyphs: glyphs, pageSize: pageSize, removeRotatedText: options.removeRotatedText)
            counts.removedOffPageWords = filtered.removedOffPageWords
            counts.removedTinyGlyphs = filtered.removedTinyGlyphs
            counts.removedRotatedRuns = filtered.removedRotatedRuns
            words = WordBuilder.build(glyphs: filtered.glyphs)
        } else {
            words = GlyphExtractor.extractFallbackWords(page: page)
        }

        let raster = autoreleasepool { PageRasterizer.render(page: page) }
        let visibility = VisibilityFilter.classify(words: words, raster: raster, cropBox: cropBox)
        let visibleWords = zip(words, visibility).filter(\.1).map(\.0)
        counts.removedHiddenWords = words.count - visibleWords.count

        let deduped = OverlapDeduper.dedupe(words: visibleWords)
        counts.removedOverlappingDuplicates = deduped.removedOverlappingDuplicates

        var sanitizedWords: [Word] = []
        for var word in deduped.words {
            let (unicodeText, unicodeCounts) = UnicodeSanitizer.sanitize(word.text)
            counts.removedInvisibleCodepoints += unicodeCounts.removedInvisibleCodepoints
            counts.removedPrivateUseCodepoints += unicodeCounts.removedPrivateUseCodepoints
            counts.normalizedWhitespace += unicodeCounts.normalizedWhitespace
            counts.normalizedLigatures += unicodeCounts.normalizedLigatures
            counts.sawReplacementCharacter = counts.sawReplacementCharacter || unicodeCounts.sawReplacementCharacter

            var text = unicodeText
            if options.normalizeLookalikes {
                let (homoglyphText, homoglyphCounts) = HomoglyphNormalizer.normalize(unicodeText)
                text = homoglyphText
                counts.normalizedHomoglyphs += homoglyphCounts.normalizedHomoglyphs
            }
            guard !text.isEmpty else { continue }
            word.text = text
            sanitizedWords.append(word)
        }

        let shouldAutoOCR =
            options.ocrMode == .auto
            && OCRRecognizer.shouldRecognize(visibleWordCount: sanitizedWords.count, raster: raster)
        if options.ocrMode == .always || shouldAutoOCR {
            if let image = autoreleasepool(invoking: { OCRRecognizer.renderImage(page: page) }) {
                let (ocrLines, lowConfidenceCount, total) = try await OCRRecognizer.recognize(
                    image: image, page: pageIndex + 1, pageSize: pageSize, languages: options.ocrLanguages)
                counts.ocrPage = true
                counts.ocrLowConfidence = OCRRecognizer.isLowConfidence(
                    lowConfidenceCount: lowConfidenceCount, total: total)
                return (ocrLines, counts)
            }
        }

        let assembly = LineAssembler.assemble(page: pageIndex + 1, words: sanitizedWords, source: .textLayer)
        return (ReadingOrder.order(lines: assembly.lines, rtl: assembly.hasRTL), counts)
    }

    // MARK: - Outline hints (tech spec §6.7.4)

    private func outlineHints(of document: PDFDocument) -> [HeadingClassifier.Hint] {
        guard let root = document.outlineRoot else { return [] }
        var hints: [HeadingClassifier.Hint] = []
        func walk(_ outline: PDFOutline, level: Int) {
            for i in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: i) else { continue }
                if let label = child.label, let destinationPage = child.destination?.page {
                    let pageIndex = document.index(for: destinationPage)
                    hints.append(
                        HeadingClassifier.Hint(
                            page: pageIndex + 1, normalizedText: HeadingClassifier.normalize(label), level: level))
                }
                walk(child, level: level + 1)
            }
        }
        walk(root, level: 1)
        return hints
    }

    // MARK: - Final-block sanitising (tech spec §6.8, defense in depth)

    private func sanitizeFinalBlocks(_ blocks: [Block]) -> (blocks: [Block], counts: UnicodeSanitizer.Counts) {
        var total = UnicodeSanitizer.Counts()

        func clean(_ text: String, isPreformatted: Bool = false) -> String {
            let (cleaned, counts) = UnicodeSanitizer.sanitize(text, isPreformatted: isPreformatted)
            total.removedInvisibleCodepoints += counts.removedInvisibleCodepoints
            total.removedPrivateUseCodepoints += counts.removedPrivateUseCodepoints
            total.normalizedWhitespace += counts.normalizedWhitespace
            total.normalizedLigatures += counts.normalizedLigatures
            return cleaned
        }

        var sanitized: [Block] = []
        sanitized.reserveCapacity(blocks.count)
        for block in blocks {
            switch block {
            case .title(let text):
                sanitized.append(.title(clean(text)))
            case .heading(let level, let text):
                sanitized.append(.heading(level: level, text: clean(text)))
            case .paragraph(let text):
                sanitized.append(.paragraph(clean(text)))
            case .listItem(var item):
                item.text = clean(item.text)
                sanitized.append(.listItem(item))
            case .tableOfContents(let heading, let entries):
                var cleanedHeading: String?
                if let heading {
                    cleanedHeading = clean(heading)
                }
                var cleanedEntries: [TOCEntry] = []
                cleanedEntries.reserveCapacity(entries.count)
                for entry in entries {
                    var e = entry
                    e.title = clean(e.title)
                    cleanedEntries.append(e)
                }
                sanitized.append(.tableOfContents(heading: cleanedHeading, entries: cleanedEntries))
            case .preformatted(let text):
                sanitized.append(.preformatted(clean(text, isPreformatted: true)))
            case .math(let math):
                sanitized.append(.math(MathBlock(text: clean(math.text), kind: math.kind)))
            case .pageBreak:
                sanitized.append(block)
            }
        }
        return (sanitized, total)
    }

    // MARK: - Language detection and identifier text

    private static func blockText(_ block: Block) -> String {
        switch block {
        case .title(let text): return text
        case .heading(_, let text): return text
        case .paragraph(let text): return text
        case .listItem(let item): return item.text
        case .tableOfContents(let heading, let entries):
            return ([heading].compactMap { $0 } + entries.map(\.title)).joined(separator: " ")
        case .preformatted(let text): return text
        case .math(let math): return math.text
        case .pageBreak: return ""
        }
    }

    private static func detectLanguage(blocks: [Block]) -> String? {
        let text = blocks.map(blockText).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
}
