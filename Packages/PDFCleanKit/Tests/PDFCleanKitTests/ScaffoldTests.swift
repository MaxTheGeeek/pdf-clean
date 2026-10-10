import Foundation
import Testing

@testable import PDFCleanKit

/// Smoke tests that keep the scaffold honest until the real suites exist (T-001, T-003).
@Suite("Scaffold")
struct ScaffoldTests {
    @Test func versionIsSet() {
        #expect(!PDFCleanKit.version.isEmpty)
    }

    @Test func fixtureManifestIsBundled() throws {
        let url = try #require(
            Bundle.module.url(forResource: "manifest", withExtension: "json", subdirectory: "Fixtures")
        )
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let root = try #require(object as? [String: Any])
        let fixtures = try #require(root["fixtures"] as? [[String: Any]])
        #expect(fixtures.count == 15)
        for fixture in fixtures {
            let file = try #require(fixture["file"] as? String)
            let name = (file as NSString).deletingPathExtension
            #expect(
                Bundle.module.url(forResource: name, withExtension: "pdf", subdirectory: "Fixtures") != nil,
                "missing fixture \(file)"
            )
        }
    }
}
