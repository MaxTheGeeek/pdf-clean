import Foundation

/// Every way the pipeline can fail to produce a document. Mapped to localized,
/// user-facing text in `specs/02-technical-spec.md` §8.
public enum PipelineError: Error, Sendable, Equatable, Codable {
    case notAPDF
    case unreadablePDF
    case passwordRequired
    case wrongPassword
    case copyingNotPermitted
    case tooLarge(pages: Int, bytes: Int64)
    case emptyDocument
    case ocrFailed(page: Int)
    case outputVerificationFailed([OutputViolation])
    case cancelled
    case io(String)
}

/// One way `OutputVerifier` can reject a render (constitution P2). Carries only enough
/// to classify and log the violation — never the offending text or metadata value
/// itself (constitution P4).
///
/// Minimal definition to let `PipelineError` compile ahead of `OutputVerifier` itself
/// (T-014); revisit the case list there once the verifier's checks are implemented
/// (`specs/02-technical-spec.md` §6.11 names the checks: forbidden code points,
/// non-ASCII spaces, C0 controls, leaked metadata values).
public enum OutputViolation: Sendable, Equatable, Codable {
    case forbiddenCodepoint(scalar: UInt32)
    case nonASCIISpace(scalar: UInt32)
    case c0Control(scalar: UInt32)
    case metadataValueLeak
}
