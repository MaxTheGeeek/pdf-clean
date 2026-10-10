import Foundation

/// A pipeline progress update, emitted while `ExtractionPipeline.run` is active (FR-23).
public struct PipelineProgress: Sendable, Equatable, Codable {
    /// Current major stage of the pipeline, in the order `specs/02-technical-spec.md` §7 describes.
    public enum Stage: String, Sendable, Equatable, Codable {
        case opening, readingPages, checkingVisibility, recognizingText, analyzingLayout, cleaning, done
    }

    /// Current major stage of the pipeline.
    public var stage: Stage
    /// 1-based page number this update refers to, 0 when the stage is not page-bound.
    public var page: Int
    /// Total number of pages in the document.
    public var pageCount: Int
    /// 0...1, monotonically non-decreasing across one `run` call.
    public var fractionCompleted: Double

    /// Creates a progress update.
    public init(stage: Stage, page: Int, pageCount: Int, fractionCompleted: Double) {
        self.stage = stage
        self.page = page
        self.pageCount = pageCount
        self.fractionCompleted = fractionCompleted
    }
}

/// One event in the stream returned by `ExtractionPipeline.run` (T-035).
public enum PipelineEvent: Sendable, Equatable, Codable {
    case progress(PipelineProgress)
    case finished(ExtractedDocument)
}
