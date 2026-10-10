import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U06 (T-012).
@Suite("IdentifierDetector")
struct IdentifierDetectorTests {
    // MARK: Positives

    @Test("detects a UUID")
    func detectsUUID() {
        let findings = IdentifierDetector.detect(in: "Reference: 3f2a9c1e-77b4-4c2e-9d1a-0b6e5f4a3c21 end.")
        #expect(findings.count == 1)
        #expect(findings[0].kind == .uuid)
        #expect(findings[0].text == "3f2a9c1e-77b4-4c2e-9d1a-0b6e5f4a3c21")
    }

    @Test("detects a JWT, not its base64-looking payload segment")
    func detectsJWT() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dGhpc2lzYXNpZ25hdHVyZXZhbHVl"
        let findings = IdentifierDetector.detect(in: "Token: \(jwt) end.")
        #expect(findings.count == 1)
        #expect(findings[0].kind == .jwt)
        #expect(findings[0].text == jwt)
    }

    @Test("detects a hex string containing both letters and digits")
    func detectsHex() {
        let findings = IdentifierDetector.detect(in: "Checksum a1b2c3d4e5f60718 done.")
        #expect(findings.count == 1)
        #expect(findings[0].kind == .hex)
        #expect(findings[0].text == "a1b2c3d4e5f60718")
    }

    @Test("detects a base64-like token with mixed case and digits")
    func detectsBase64Token() {
        let token = "AbCdEfGhIjKlMnOpQrStUvWx12"
        let findings = IdentifierDetector.detect(in: "Secret \(token) stored.")
        #expect(findings.count == 1)
        #expect(findings[0].kind == .base64Token)
        #expect(findings[0].text == token)
    }

    @Test("detects an email address")
    func detectsEmail() {
        let findings = IdentifierDetector.detect(in: "Contact max@example.com for access.")
        #expect(findings.count == 1)
        #expect(findings[0].kind == .email)
        #expect(findings[0].text == "max@example.com")
    }

    @Test("detects a dash-separated key pattern with a digit")
    func detectsKeyPattern() {
        let findings = IdentifierDetector.detect(in: "License ABCD-1234-EFGH activated.")
        #expect(findings.count == 1)
        #expect(findings[0].kind == .keyPattern)
        #expect(findings[0].text == "ABCD-1234-EFGH")
    }

    // MARK: Negatives

    @Test(
        "plain dates, ISBNs, words and COVID-19 are not flagged",
        arguments: [
            "Meeting on 2026-10-10 at noon.",
            "ISBN 978-3-16-148410-0.",
            "The quick brown fox jumps over the lazy dog.",
            "The COVID-19 pandemic changed remote work.",
        ]
    )
    func negativesAreNotFlagged(_ text: String) {
        #expect(IdentifierDetector.detect(in: text).isEmpty)
    }

    // MARK: Dedup and ordering

    @Test("findings are deduplicated by exact text, counted, and ordered by first occurrence")
    func dedupAndOrder() {
        let text = """
            Contact max@example.com or max@example.com again.
            Reference: 3f2a9c1e-77b4-4c2e-9d1a-0b6e5f4a3c21.
            """
        let findings = IdentifierDetector.detect(in: text)
        #expect(findings.count == 2)
        #expect(findings[0].kind == .email)
        #expect(findings[0].occurrences == 2)
        #expect(findings[1].kind == .uuid)
        #expect(findings[1].occurrences == 1)
    }
}
