import Foundation

/// Pure Unicode sanitisation (sanitisation spec §6): PUA bullets, ligatures, invisible /
/// format character removal (with the ZWNJ/ZWJ context exceptions of §6.1), whitespace
/// normalisation, and NFC. Applied to every word right after the visibility filters and
/// again, idempotently, to every final block's text.
enum UnicodeSanitizer {
    /// Counters bumped while sanitising one piece of text. Combine across words/blocks by
    /// adding fields (all `Int`, except the warning flag which is OR-combined).
    struct Counts: Sendable, Equatable {
        var removedInvisibleCodepoints = 0
        var removedPrivateUseCodepoints = 0
        var normalizedWhitespace = 0
        var normalizedLigatures = 0
        /// `true` if a U+FFFD replacement character was removed — the caller should add
        /// `ReportWarning.unreadableCharacters` once per document when this is set.
        var sawReplacementCharacter = false
    }

    /// Sanitises `text` and returns the result with counters for what changed.
    /// - Parameter isPreformatted: keeps literal TAB characters instead of turning them
    ///   into spaces (preformatted blocks render TABs as-is).
    static func sanitize(_ text: String, isPreformatted: Bool = false) -> (text: String, counts: Counts) {
        var counts = Counts()
        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()

        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            let previous: Unicode.Scalar? = index > 0 ? scalars[index - 1] : nil
            let next: Unicode.Scalar? = index + 1 < scalars.count ? scalars[index + 1] : nil

            if let bullet = UnicodeTables.puaBullets[scalar] {
                output.append(bullet)
            } else if let decomposition = UnicodeTables.ligatures[scalar] {
                output.append(contentsOf: decomposition.unicodeScalars)
                counts.normalizedLigatures += 1
            } else if scalar.value == 0x00AD {
                if isEndOfWord(next) {
                    output.append("-")
                } else {
                    counts.removedInvisibleCodepoints += 1
                }
            } else if scalar.value == 0x200C || scalar.value == 0x200D {
                if UnicodeTables.shouldKeepJoiner(scalar, previous: previous, next: next) {
                    output.append(scalar)
                } else {
                    counts.removedInvisibleCodepoints += 1
                }
            } else if scalar.value == 0xFE0E || scalar.value == 0xFE0F {
                if let previous, previous.properties.isEmoji {
                    output.append(scalar)
                } else {
                    counts.removedInvisibleCodepoints += 1
                }
            } else if scalar.value == 0xFFFD {
                counts.removedInvisibleCodepoints += 1
                counts.sawReplacementCharacter = true
            } else if UnicodeTables.isPrivateUse(scalar) {
                counts.removedPrivateUseCodepoints += 1
            } else if UnicodeTables.isUnconditionallyRemoved(scalar) {
                counts.removedInvisibleCodepoints += 1
            } else if UnicodeTables.isUnassignedOrLeftoverFormat(scalar) {
                counts.removedInvisibleCodepoints += 1
            } else {
                output.append(scalar)
            }
            index += 1
        }

        let (whitespaceNormalized, whitespaceCount) = normalizeWhitespace(
            String(output),
            isPreformatted: isPreformatted
        )
        counts.normalizedWhitespace = whitespaceCount

        return (whitespaceNormalized.precomposedStringWithCanonicalMapping, counts)
    }

    /// A soft hyphen at the very end of a word becomes `-` instead of being removed, so
    /// the paragraph builder can repair line-break hyphenation.
    private static func isEndOfWord(_ next: Unicode.Scalar?) -> Bool {
        guard let next else { return true }
        return next.properties.generalCategory == .spaceSeparator || next.value == 0x0A || next.value == 0x09
    }

    /// Collapses every Zs character, TAB (outside preformatted) and LF to a single space,
    /// collapses runs of spaces, and trims. Returns the count of characters converted
    /// (not counting pre-existing plain spaces that were only collapsed).
    private static func normalizeWhitespace(_ text: String, isPreformatted: Bool) -> (String, Int) {
        var count = 0
        var converted = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x20:
                converted.append(scalar)
            case 0x09:
                if isPreformatted {
                    converted.append(scalar)
                } else {
                    converted.append(" ")
                    count += 1
                }
            case 0x0A:
                converted.append(" ")
                count += 1
            default:
                if scalar.properties.generalCategory == .spaceSeparator {
                    converted.append(" ")
                    count += 1
                } else {
                    converted.append(scalar)
                }
            }
        }

        var collapsed = String.UnicodeScalarView()
        var lastWasSpace = false
        for scalar in converted {
            let isSpace = scalar.value == 0x20
            if isSpace && lastWasSpace { continue }
            lastWasSpace = isSpace
            collapsed.append(scalar)
        }

        let trimmed = String(collapsed).trimmingCharacters(in: CharacterSet(charactersIn: " "))
        return (trimmed, count)
    }
}
