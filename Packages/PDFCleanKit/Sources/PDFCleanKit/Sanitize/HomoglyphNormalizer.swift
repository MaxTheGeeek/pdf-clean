import Foundation

/// Homoglyph / lookalike normalisation (sanitisation spec §7), gated by
/// `ExtractionOptions.normalizeLookalikes`.
enum HomoglyphNormalizer {
    /// Counters bumped while normalising one piece of text.
    struct Counts: Sendable, Equatable {
        var normalizedHomoglyphs = 0
    }

    /// Normalises `text` and returns the result with a counter for what changed.
    static func normalize(_ text: String) -> (text: String, counts: Counts) {
        var counts = Counts()
        let widened = normalizeFullwidthAndMathAlphanumeric(text)
        let normalized = normalizeMixedScriptTokens(widened, counts: &counts)
        return (normalized, counts)
    }

    /// Fullwidth ASCII and Mathematical Alphanumeric Symbols, always applied regardless
    /// of script mixing.
    private static func normalizeFullwidthAndMathAlphanumeric(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFF01...0xFF5E:
                if let ascii = Unicode.Scalar(scalar.value - 0xFEE0) {
                    result.append(ascii)
                } else {
                    result.append(scalar)
                }
            case 0x1D400...0x1D7FF:
                // Mathematical Alphanumeric Symbols decompose to plain letters/digits
                // under NFKC compatibility mapping — no need for a 1000-entry table.
                let mapped = String(scalar).precomposedStringWithCompatibilityMapping
                result.append(contentsOf: mapped.unicodeScalars)
            default:
                result.append(scalar)
            }
        }
        return String(result)
    }

    /// Replaces Cyrillic/Greek lookalikes inside tokens (`\p{L}[\p{L}\p{M}]*`) that mix
    /// Latin letters with Cyrillic/Greek ones every one of which has a known mapping.
    /// Pure-Cyrillic or pure-Greek tokens are never touched.
    private static func normalizeMixedScriptTokens(_ text: String, counts: inout Counts) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\p{L}[\\p{L}\\p{M}]*") else {
            return text
        }
        let nsText = text as NSString
        var result = ""
        var lastEnd = 0
        let fullRange = NSRange(location: 0, length: nsText.length)
        for match in regex.matches(in: text, range: fullRange) {
            let range = match.range
            result += nsText.substring(with: NSRange(location: lastEnd, length: range.location - lastEnd))
            result += normalizeToken(nsText.substring(with: range), counts: &counts)
            lastEnd = range.location + range.length
        }
        result += nsText.substring(from: lastEnd)
        return result
    }

    private static func normalizeToken(_ token: String, counts: inout Counts) -> String {
        let scalars = Array(token.unicodeScalars)
        var hasLatinLetter = false
        var foreignLetters: [Unicode.Scalar] = []
        for scalar in scalars {
            if isLatinLetter(scalar) {
                hasLatinLetter = true
            } else if isCyrillicOrGreekLetter(scalar) {
                foreignLetters.append(scalar)
            }
        }
        guard hasLatinLetter, !foreignLetters.isEmpty else { return token }
        guard foreignLetters.allSatisfy({ lookalikes[$0] != nil }) else { return token }

        var result = String.UnicodeScalarView()
        for scalar in scalars {
            if let replacement = lookalikes[scalar] {
                result.append(replacement)
                counts.normalizedHomoglyphs += 1
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }

    private static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
    }

    private static func isCyrillicOrGreekLetter(_ scalar: Unicode.Scalar) -> Bool {
        ((0x0400...0x052F).contains(scalar.value) || (0x0370...0x03FF).contains(scalar.value))
            && scalar.properties.isAlphabetic
    }

    /// Cyrillic/Greek look-alike → Latin, sanitisation spec §7 table.
    private static let lookalikes: [Unicode.Scalar: Unicode.Scalar] = [
        // Cyrillic lower.
        "\u{0430}": "a", "\u{0435}": "e", "\u{043E}": "o", "\u{0440}": "p", "\u{0441}": "c",
        "\u{0443}": "y", "\u{0445}": "x", "\u{0456}": "i", "\u{0458}": "j", "\u{0455}": "s",
        "\u{0501}": "d", "\u{051B}": "q", "\u{051D}": "w", "\u{04BB}": "h", "\u{04CF}": "l",
        // Cyrillic upper.
        "\u{0410}": "A", "\u{0412}": "B", "\u{0415}": "E", "\u{041A}": "K", "\u{041C}": "M",
        "\u{041D}": "H", "\u{041E}": "O", "\u{0420}": "P", "\u{0421}": "C", "\u{0422}": "T",
        "\u{0425}": "X", "\u{0423}": "Y", "\u{0406}": "I", "\u{0408}": "J", "\u{0405}": "S",
        // Greek lower.
        "\u{03BF}": "o", "\u{03BD}": "v", "\u{03B9}": "i", "\u{03BA}": "k",
        // Greek upper.
        "\u{0391}": "A", "\u{0392}": "B", "\u{0395}": "E", "\u{0396}": "Z", "\u{0397}": "H",
        "\u{0399}": "I", "\u{039A}": "K", "\u{039C}": "M", "\u{039D}": "N", "\u{039F}": "O",
        "\u{03A1}": "P", "\u{03A4}": "T", "\u{03A5}": "Y", "\u{03A7}": "X",
    ]
}
