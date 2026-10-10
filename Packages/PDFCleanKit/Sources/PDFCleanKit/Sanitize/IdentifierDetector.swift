import Foundation

/// Detects redactable identifier-like strings in final block text (tech spec §6.9).
/// Regexes run independently; where matches from different kinds overlap, the longest
/// match wins. Findings are deduplicated by exact text and ordered by first occurrence.
enum IdentifierDetector {
    /// Finds every redactable identifier in `text`, deduplicated by exact text and
    /// ordered by first occurrence.
    static func detect(in text: String) -> [IdentifierFinding] {
        let resolved = resolveOverlaps(allMatches(in: text), in: text)
            .sorted { $0.range.lowerBound < $1.range.lowerBound }

        var findings: [IdentifierFinding] = []
        var indexByText: [String: Int] = [:]
        for match in resolved {
            let matchedText = String(text[match.range])
            if let index = indexByText[matchedText] {
                findings[index].occurrences += 1
            } else {
                indexByText[matchedText] = findings.count
                findings.append(IdentifierFinding(text: matchedText, kind: match.kind, occurrences: 1))
            }
        }
        return findings
    }

    /// Regex literals are compiled at build time; declaring them as locals (rather than
    /// static properties) sidesteps Swift 6's strict-concurrency check, since `Regex` is
    /// not `Sendable` and can't be stored as shared global state.
    private static func allMatches(
        in text: String
    ) -> [(range: Range<String.Index>, kind: IdentifierFinding.Kind)] {
        let uuidRegex = #/\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b/#
        let jwtRegex = #/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/#
        let hexRegex = #/\b(?=[0-9a-fA-F]*[a-fA-F])(?=[0-9a-fA-F]*\d)[0-9a-fA-F]{16,}\b/#
        let base64Regex =
            #/\b(?=[A-Za-z0-9+\/_-]*[A-Z])(?=[A-Za-z0-9+\/_-]*[a-z])(?=[A-Za-z0-9+\/_-]*\d)[A-Za-z0-9+\/_-]{24,}={0,2}/#
        let emailRegex = #/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/#
        let keyPatternRegex = #/\b(?=[A-Z0-9-]*\d)[A-Z0-9]{4,}(?:-[A-Z0-9]{4,}){2,}\b/#

        var results: [(range: Range<String.Index>, kind: IdentifierFinding.Kind)] = []
        results += text.matches(of: uuidRegex).map { ($0.range, .uuid) }
        results += text.matches(of: jwtRegex).map { ($0.range, .jwt) }
        results += text.matches(of: hexRegex).map { ($0.range, .hex) }
        results += text.matches(of: base64Regex).map { ($0.range, .base64Token) }
        results += text.matches(of: emailRegex).map { ($0.range, .email) }
        results += text.matches(of: keyPatternRegex).map { ($0.range, .keyPattern) }
        return results
    }

    /// Among overlapping matches, keeps only the longest; ties break toward the earlier
    /// start for determinism.
    private static func resolveOverlaps(
        _ matches: [(range: Range<String.Index>, kind: IdentifierFinding.Kind)],
        in text: String
    ) -> [(range: Range<String.Index>, kind: IdentifierFinding.Kind)] {
        let sorted = matches.sorted { lhs, rhs in
            let lhsLength = text.distance(from: lhs.range.lowerBound, to: lhs.range.upperBound)
            let rhsLength = text.distance(from: rhs.range.lowerBound, to: rhs.range.upperBound)
            if lhsLength != rhsLength { return lhsLength > rhsLength }
            return lhs.range.lowerBound < rhs.range.lowerBound
        }
        var accepted: [(range: Range<String.Index>, kind: IdentifierFinding.Kind)] = []
        for candidate in sorted where !accepted.contains(where: { $0.range.overlaps(candidate.range) }) {
            accepted.append(candidate)
        }
        return accepted
    }
}
