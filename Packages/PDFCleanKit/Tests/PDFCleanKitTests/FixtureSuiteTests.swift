import Foundation
import Testing

@testable import PDFCleanKit

/// Fixture integration suite (TC-F01 skeleton, T-003). Parameterised over every id in
/// `manifest.json`. Cases are recorded as a known issue ("pipeline pending") until
/// `ExtractionPipeline` exists (T-035) — `withKnownIssue` (not `.disabled`) is used
/// deliberately so every argument still expands into its own listed test case instead of
/// collapsing into one skipped test; `not-a-pdf` is the exception because its expectation
/// — the file does not start with the PDF header — needs no pipeline at all.
@Suite("FixtureSuite")
struct FixtureSuiteTests {
    static func loadedManifest() -> FixtureManifest {
        do {
            return try FixtureManifest.load()
        } catch {
            fatalError("failed to load fixture manifest: \(error)")
        }
    }

    static var pendingFixtureIDs: [String] {
        loadedManifest().fixtures.map(\.id).filter { $0 != "not-a-pdf" }
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

    @Test("fixture case — pipeline pending", arguments: pendingFixtureIDs)
    func fixtureCase(_ id: String) {
        withKnownIssue("pipeline pending: enable once ExtractionPipeline exists (T-035)") {
            Issue.record("no pipeline yet to run fixture \(id) through")
        }
    }

    @Test("not-a-pdf: file does not start with the %PDF header")
    func notAPDFHasNoPDFHeader() throws {
        let manifest = try FixtureManifest.load()
        let fixture = try #require(manifest.fixtures.first { $0.id == "not-a-pdf" })
        let name = (fixture.file as NSString).deletingPathExtension
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "pdf", subdirectory: "Fixtures")
        )
        let data = try Data(contentsOf: url)
        #expect(data.prefix(5) != Data("%PDF-".utf8))
    }
}
