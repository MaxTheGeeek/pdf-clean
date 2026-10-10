import Foundation

/// Decoded form of `Fixtures/manifest.json` — one entry per PDF test fixture.
/// Field → assertion mapping lives in `specs/05-test-plan.md` §2; never hand-edit the
/// JSON file itself (`make fixtures` regenerates it).
struct FixtureManifest: Codable, Sendable, Equatable {
    let version: Int
    let fixtures: [Fixture]

    /// Loads and decodes `manifest.json` from the test bundle.
    static func load() throws -> FixtureManifest {
        guard
            let url = Bundle.module.url(
                forResource: "manifest",
                withExtension: "json",
                subdirectory: "Fixtures"
            )
        else {
            throw FixtureManifestError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FixtureManifest.self, from: data)
    }
}

/// Errors raised while loading the fixture manifest from the test bundle.
enum FixtureManifestError: Error {
    case resourceNotFound
}

/// One fixture case. Most fields are optional because each fixture only exercises a
/// subset of the assertions in the test plan's field → assertion table.
struct Fixture: Codable, Sendable, Equatable {
    let id: String
    let file: String
    let covers: [String]
    let title: String?
    let headings: [HeadingExpectation]?
    let headingCount: Int?
    let listItems: [ListItemExpectation]?
    let tocEntries: [TOCEntryExpectation]?
    let mustContain: [String]?
    let mustContainAfterFiltering: [String]?
    let mustNotContain: [String]?
    let mustNotContainDerived: [String]?
    let mustNotContainCodepoints: [String]?
    let occurrences: [String: Int]?
    let orderedPhrases: [String]?
    let separateParagraphs: [ParagraphPairExpectation]?
    let suspiciousIdentifiers: [String]?
    let sourceInventory: SourceInventoryExpectation?
    let ocrTolerant: Bool?
    let ocrPages: [Int]?
    let password: String?
    let ownerPasswordCase: Bool?
    let expectError: String?
    let expectNoCrash: Bool?
    let reportAtLeast: [String: Int]?
    let reportExactly: [String: Int]?
    let maxSeconds: Double?
    let comment: String?
}

/// `[level, text]` — one row of the `headings` field.
struct HeadingExpectation: Codable, Sendable, Equatable {
    let level: Int
    let text: String

    init(level: Int, text: String) {
        self.level = level
        self.text = text
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        level = try container.decode(Int.self)
        text = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(level)
        try container.encode(text)
    }
}

/// `[level, title, page]` — one row of the `tocEntries` field.
struct TOCEntryExpectation: Codable, Sendable, Equatable {
    let level: Int
    let title: String
    let page: Int

    init(level: Int, title: String, page: Int) {
        self.level = level
        self.title = title
        self.page = page
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        level = try container.decode(Int.self)
        title = try container.decode(String.self)
        page = try container.decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(level)
        try container.encode(title)
        try container.encode(page)
    }
}

/// `[a, b]` — one row of the `separateParagraphs` field: two phrases expected in
/// different `.paragraph` blocks.
struct ParagraphPairExpectation: Codable, Sendable, Equatable {
    let first: String
    let second: String

    init(first: String, second: String) {
        self.first = first
        self.second = second
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        first = try container.decode(String.self)
        second = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(first)
        try container.encode(second)
    }
}

/// One row of the `listItems` field.
struct ListItemExpectation: Codable, Sendable, Equatable {
    let ordered: Bool
    let text: String
}

/// The `sourceInventory` field: expectations about `SourceInventory` without ever
/// naming the actual metadata values (constitution P4).
struct SourceInventoryExpectation: Codable, Sendable, Equatable {
    let hasXMP: Bool?
    let hasOutline: Bool?
    let hasFormFields: Bool?
    let embeddedFileCount: Int?
    let minAnnotationCount: Int?
    let metadataKeysInclude: [String]?
}
