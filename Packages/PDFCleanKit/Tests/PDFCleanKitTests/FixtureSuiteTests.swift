import Foundation
import Testing

@testable import PDFCleanKit

/// TC-F01 (T-035): runs every fixture through the real `ExtractionPipeline` and checks it
/// against the field → assertion table in `specs/05-test-plan.md` §2.
@Suite("FixtureSuite")
struct FixtureSuiteTests {
    static func loadedManifest() -> FixtureManifest {
        do {
            return try FixtureManifest.load()
        } catch {
            fatalError("failed to load fixture manifest: \(error)")
        }
    }

    static var fixtureIDs: [String] {
        loadedManifest().fixtures.map(\.id)
    }

    @Test("manifest decodes without loss (round-trip)")
    func manifestRoundTrips() throws {
        let manifest = try FixtureManifest.load()
        #expect(manifest.fixtures.count == 15)

        let reencoded = try JSONEncoder().encode(manifest)
        let decodedAgain = try JSONDecoder().decode(FixtureManifest.self, from: reencoded)
        #expect(decodedAgain == manifest)

        let hiddenContent = try #require(manifest.fixtures.first { $0.id == "hidden-content" })
        #expect(hiddenContent.mustNotContain?.count == 26)
        #expect(hiddenContent.mustNotContainCodepoints?.count == 18)
        #expect(hiddenContent.reportAtLeast?["removedHiddenWords"] == 7)
        #expect(hiddenContent.sourceInventory?.minAnnotationCount == 3)

        let toc = try #require(manifest.fixtures.first { $0.id == "toc" })
        #expect(toc.tocEntries?.count == 5)
        #expect(toc.tocEntries?.first == TOCEntryExpectation(level: 1, title: "1 Getting Started", page: 3))

        let simpleStructured = try #require(manifest.fixtures.first { $0.id == "simple-structured" })
        #expect(simpleStructured.listItems?.count == 4)
        #expect(
            simpleStructured.separateParagraphs?.first
                == ParagraphPairExpectation(
                    first: "This report summarises",
                    second: "A second paragraph begins"
                )
        )
    }

    @Test("simple-structured fixture extracts the expected title")
    func simpleStructuredTitle() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "simple-structured", withExtension: "pdf", subdirectory: "Fixtures")
        )

        let pipeline = ExtractionPipeline()
        let document = try await Self.runToCompletion(pipeline: pipeline, url: url, password: nil)
        let title = document.blocks.compactMap { block -> String? in
            if case .title(let text) = block { return text }
            return nil
        }.first

        #expect(title == "Quarterly Infrastructure Report")
    }

    @Test("fixture case", arguments: fixtureIDs)
    func fixtureCase(_ id: String) async throws {
        let manifest = try FixtureManifest.load()
        let fixture = try #require(manifest.fixtures.first { $0.id == id })
        let stem = (fixture.file as NSString).deletingPathExtension
        let url = try #require(
            Bundle.module.url(forResource: stem, withExtension: "pdf", subdirectory: "Fixtures"))

        if let expectedErrorName = fixture.expectError {
            await expectError(expectedErrorName, url: url, password: fixture.password)
            return
        }
        if fixture.expectNoCrash == true {
            await expectNoCrash(url: url, password: fixture.password)
            return
        }

        let pipeline = ExtractionPipeline()
        let start = Date()
        let document = try await Self.runToCompletion(pipeline: pipeline, url: url, password: fixture.password)
        let elapsed = Date().timeIntervalSince(start)

        let exporter = DocumentExporter()
        let markdown = try exporter.render(document, as: .markdown)
        let html = try exporter.render(document, as: .html)
        let plainText = try exporter.render(document, as: .plainText)
        let collapsedPlainText = Self.collapsedWhitespace(plainText)

        checkTitle(fixture, document: document)
        checkHeadings(fixture, document: document)
        checkTOC(fixture, document: document)
        checkListItems(fixture, document: document)
        checkMustContain(fixture, collapsedPlainText: collapsedPlainText)
        checkMustNotContain(fixture, markdown: markdown, html: html, plainText: plainText)
        checkMustNotContainCodepoints(fixture, markdown: markdown, html: html, plainText: plainText)
        checkOccurrences(fixture, plainText: plainText)
        checkOrderedPhrases(fixture, plainText: plainText)
        checkSeparateParagraphs(fixture, document: document)
        checkOCRPages(fixture, document: document)
        checkReportCounters(fixture, document: document)
        checkSourceInventory(fixture, document: document)
        checkSuspiciousIdentifiers(fixture, document: document)
        checkMaxSeconds(fixture, elapsed: elapsed)
    }

    // MARK: - Error / no-crash cases

    private func expectError(_ expectedName: String, url: URL, password: String?) async {
        let pipeline = ExtractionPipeline()
        do {
            _ = try await Self.runToCompletion(pipeline: pipeline, url: url, password: password)
            Issue.record("expected PipelineError.\(expectedName) but the pipeline succeeded")
        } catch let error as PipelineError {
            #expect(Self.caseName(of: error) == expectedName)
        } catch {
            Issue.record("expected PipelineError.\(expectedName) but got \(error)")
        }
    }

    private func expectNoCrash(url: URL, password: String?) async {
        let pipeline = ExtractionPipeline()
        do {
            _ = try await Self.runToCompletion(pipeline: pipeline, url: url, password: password)
        } catch is PipelineError {
            // Completing or throwing a PipelineError are both acceptable.
        } catch {
            Issue.record("expected completion or a PipelineError, got \(error)")
        }
    }

    // MARK: - Per-field checks

    private func checkTitle(_ fixture: Fixture, document: ExtractedDocument) {
        guard let expected = fixture.title else { return }
        let actual = document.blocks.compactMap { block -> String? in
            if case .title(let text) = block { return text }
            return nil
        }.first
        if fixture.ocrTolerant == true {
            #expect(actual.map(Self.alphanumericLower) == Self.alphanumericLower(expected))
        } else {
            #expect(actual == expected)
        }
    }

    private func checkHeadings(_ fixture: Fixture, document: ExtractedDocument) {
        let headings = document.blocks.compactMap { block -> (level: Int, text: String)? in
            if case .heading(let level, let text) = block { return (level, text) }
            return nil
        }
        if let expected = fixture.headings {
            #expect(headings.count == expected.count)
            for (actual, exp) in zip(headings, expected) {
                #expect(actual.level == exp.level)
                #expect(actual.text == exp.text)
            }
        }
        if let expectedCount = fixture.headingCount {
            #expect(headings.count == expectedCount)
        }
    }

    private func checkTOC(_ fixture: Fixture, document: ExtractedDocument) {
        guard let expected = fixture.tocEntries else { return }
        let tocBlock = document.blocks.first {
            if case .tableOfContents = $0 { return true }
            return false
        }
        guard case .tableOfContents(_, let entries) = tocBlock else {
            Issue.record("expected a tableOfContents block")
            return
        }
        #expect(entries.count == expected.count)
        for (actual, exp) in zip(entries, expected) {
            #expect(actual.level == exp.level)
            #expect(actual.title == exp.title)
            #expect(actual.page == String(exp.page))
        }
    }

    private func checkListItems(_ fixture: Fixture, document: ExtractedDocument) {
        guard let expected = fixture.listItems else { return }
        let items = document.blocks.compactMap { block -> ListItem? in
            if case .listItem(let item) = block { return item }
            return nil
        }
        #expect(items.count == expected.count)
        for (actual, exp) in zip(items, expected) {
            #expect(actual.ordered == exp.ordered)
            #expect(actual.text == exp.text)
        }
    }

    private func checkMustContain(_ fixture: Fixture, collapsedPlainText: String) {
        let phrases = (fixture.mustContain ?? []) + (fixture.mustContainAfterFiltering ?? [])
        for phrase in phrases {
            if fixture.ocrTolerant == true {
                #expect(
                    Self.alphanumericLower(collapsedPlainText).contains(Self.alphanumericLower(phrase)),
                    "missing (ocr-tolerant): \(phrase)")
            } else {
                #expect(
                    collapsedPlainText.contains(Self.collapsedWhitespace(phrase)), "missing: \(phrase)")
            }
        }
    }

    private func checkMustNotContain(_ fixture: Fixture, markdown: String, html: String, plainText: String) {
        let phrases = (fixture.mustNotContain ?? []) + (fixture.mustNotContainDerived ?? [])
        for phrase in phrases {
            #expect(!markdown.contains(phrase), "markdown contains: \(phrase)")
            #expect(!html.contains(phrase), "html contains: \(phrase)")
            #expect(!plainText.contains(phrase), "plainText contains: \(phrase)")
        }
    }

    private func checkMustNotContainCodepoints(_ fixture: Fixture, markdown: String, html: String, plainText: String) {
        for hex in fixture.mustNotContainCodepoints ?? [] {
            guard let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) else { continue }
            #expect(!markdown.unicodeScalars.contains(scalar), "markdown contains U+\(hex)")
            #expect(!html.unicodeScalars.contains(scalar), "html contains U+\(hex)")
            #expect(!plainText.unicodeScalars.contains(scalar), "plainText contains U+\(hex)")
        }
    }

    private func checkOccurrences(_ fixture: Fixture, plainText: String) {
        for (phrase, expectedCount) in fixture.occurrences ?? [:] {
            let actualCount = plainText.components(separatedBy: phrase).count - 1
            #expect(actualCount == expectedCount, "\(phrase)")
        }
    }

    private func checkOrderedPhrases(_ fixture: Fixture, plainText: String) {
        guard let phrases = fixture.orderedPhrases else { return }
        var searchStart = plainText.startIndex
        for phrase in phrases {
            guard let range = plainText.range(of: phrase, range: searchStart..<plainText.endIndex) else {
                Issue.record("phrase out of order or missing: \(phrase)")
                continue
            }
            searchStart = range.upperBound
        }
    }

    private func checkSeparateParagraphs(_ fixture: Fixture, document: ExtractedDocument) {
        guard let pairs = fixture.separateParagraphs else { return }
        let paragraphs = document.blocks.compactMap { block -> String? in
            if case .paragraph(let text) = block { return text }
            return nil
        }
        for pair in pairs {
            let firstIndex = paragraphs.firstIndex { $0.contains(pair.first) }
            let secondIndex = paragraphs.firstIndex { $0.contains(pair.second) }
            #expect(firstIndex != nil, "paragraph containing \(pair.first) not found")
            #expect(secondIndex != nil, "paragraph containing \(pair.second) not found")
            if let firstIndex, let secondIndex {
                #expect(firstIndex != secondIndex, "\(pair.first) / \(pair.second) in the same paragraph")
            }
        }
    }

    private func checkOCRPages(_ fixture: Fixture, document: ExtractedDocument) {
        guard let expected = fixture.ocrPages else { return }
        #expect(document.report.ocrPages == expected)
    }

    private func checkReportCounters(_ fixture: Fixture, document: ExtractedDocument) {
        for (name, minValue) in fixture.reportAtLeast ?? [:] {
            guard let keyPath = SanitizationReport.counterKeyPath(named: name) else {
                Issue.record("unknown counter: \(name)")
                continue
            }
            #expect(document.report[keyPath: keyPath] >= minValue, "\(name)")
        }
        for (name, exactValue) in fixture.reportExactly ?? [:] {
            guard let keyPath = SanitizationReport.counterKeyPath(named: name) else {
                Issue.record("unknown counter: \(name)")
                continue
            }
            #expect(document.report[keyPath: keyPath] == exactValue, "\(name)")
        }
    }

    private func checkSourceInventory(_ fixture: Fixture, document: ExtractedDocument) {
        guard let expected = fixture.sourceInventory else { return }
        let inventory = document.report.sourceInventory
        if let hasXMP = expected.hasXMP { #expect(inventory.hasXMP == hasXMP) }
        if let hasOutline = expected.hasOutline { #expect(inventory.hasOutline == hasOutline) }
        if let hasFormFields = expected.hasFormFields { #expect(inventory.hasFormFields == hasFormFields) }
        if let embeddedFileCount = expected.embeddedFileCount {
            #expect(inventory.embeddedFileCount == embeddedFileCount)
        }
        if let minAnnotationCount = expected.minAnnotationCount {
            #expect(inventory.annotationCount >= minAnnotationCount)
        }
        if let include = expected.metadataKeysInclude {
            #expect(Set(include).isSubset(of: Set(inventory.metadataKeys)))
        }
    }

    private func checkSuspiciousIdentifiers(_ fixture: Fixture, document: ExtractedDocument) {
        for text in fixture.suspiciousIdentifiers ?? [] {
            #expect(document.report.suspiciousIdentifiers.contains { $0.text == text }, "missing finding: \(text)")
        }
    }

    private func checkMaxSeconds(_ fixture: Fixture, elapsed: TimeInterval) {
        guard let maxSeconds = fixture.maxSeconds else { return }
        // Debug builds run unoptimized; the budget is relaxed accordingly (spec §2).
        #expect(elapsed <= maxSeconds * 3, "took \(elapsed)s, budget \(maxSeconds * 3)s")
    }

    // MARK: - Helpers

    private static func runToCompletion(
        pipeline: ExtractionPipeline, url: URL, password: String?
    ) async throws -> ExtractedDocument {
        for try await event in await pipeline.run(fileURL: url, password: password) {
            if case .finished(let document) = event {
                return document
            }
        }
        throw PipelineError.io("stream ended without finishing")
    }

    private static func caseName(of error: PipelineError) -> String {
        switch error {
        case .notAPDF: return "notAPDF"
        case .unreadablePDF: return "unreadablePDF"
        case .passwordRequired: return "passwordRequired"
        case .wrongPassword: return "wrongPassword"
        case .copyingNotPermitted: return "copyingNotPermitted"
        case .tooLarge: return "tooLarge"
        case .emptyDocument: return "emptyDocument"
        case .ocrFailed: return "ocrFailed"
        case .outputVerificationFailed: return "outputVerificationFailed"
        case .cancelled: return "cancelled"
        case .io: return "io"
        }
    }

    private static func collapsedWhitespace(_ text: String) -> String {
        text.split { $0.isWhitespace }.joined(separator: " ")
    }

    private static func alphanumericLower(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
