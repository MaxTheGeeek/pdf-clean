import Foundation
@preconcurrency import PDFKit
import Testing

@testable import PDFCleanKit

/// TC-U14 (T-031): `GlyphExtractor` against real fixture PDFs — the UTF-16/surrogate-pair
/// path, and the `simple-structured` word check named in the task's own test line: page 1's
/// words include "infra-" and "structure" (the hyphenated line break).
@Suite("GlyphExtractor")
struct GlyphExtractorTests {

    @Test("simple-structured page 1 words include the hyphenated \"infra-\" / \"structure\" pair")
    func hyphenatedWordsPresent() throws {
        let document = try openFixture("simple-structured")
        let page = try #require(document.page(at: 0))
        let glyphs = try #require(GlyphExtractor.extract(page: page))
        let words = WordBuilder.build(glyphs: glyphs)
        let texts = words.map(\.text)
        #expect(texts.contains("infra-"))
        #expect(texts.contains("structure"))
    }

    @Test("extraction never crashes on any page, including supplementary-plane (surrogate pair) text")
    func noCrashAcrossAllPages() throws {
        // hidden-content.pdf carries Unicode TAG characters (U+E0041 etc.) — supplementary
        // plane, i.e. UTF-16 surrogate pairs — among its canaries.
        let document = try openFixture("hidden-content")
        var totalGlyphs = 0
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i), let glyphs = GlyphExtractor.extract(page: page) else { continue }
            totalGlyphs += glyphs.count
            // Every glyph is exactly one Unicode scalar's worth of text (or a decomposed
            // surrogate pair reassembled into one Swift Character) — never empty.
            for glyph in glyphs {
                #expect(!glyph.text.isEmpty)
            }
        }
        #expect(totalGlyphs > 0)
    }

    @Test("words reconstruct recognisable text somewhere in the document")
    func wordsReconstructKnownPhrase() throws {
        let document = try openFixture("hidden-content")
        var fullText = ""
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i), let glyphs = GlyphExtractor.extract(page: page) else { continue }
            fullText += WordBuilder.build(glyphs: glyphs).map(\.text).joined(separator: " ")
        }
        #expect(fullText.contains("visible"))
    }

    // MARK: - Fixtures

    func openFixture(_ name: String) throws -> PDFDocument {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "pdf", subdirectory: "Fixtures"))
        return try #require(PDFDocument(url: url))
    }
}
