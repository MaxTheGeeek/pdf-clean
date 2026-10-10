import os

/// The only logging entry point (constitution P4, technical spec section 11).
///
/// Event names and keys are `StaticString`, values are integers, so document text,
/// file names, paths and metadata values cannot be logged by construction.
/// `scripts/check_offline.sh` rejects any other logging API in the sources.
public enum Log {
    /// Logs `name key=value ...` at info level, e.g. `Log.event("page.done", ("page", 3), ("ms", 41))`.
    public static func event(_ name: StaticString, _ values: (StaticString, Int)...) {
        // Created per call: cheap, and avoids global mutable/non-Sendable state in Swift 6 mode.
        let logger = Logger(subsystem: "com.maxbehzadi.pdfclean", category: "core")
        var line = "\(name)"
        for (key, value) in values {
            line += " \(key)=\(value)"
        }
        logger.info("\(line, privacy: .public)")
    }
}
