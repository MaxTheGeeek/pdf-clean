import CoreGraphics
@preconcurrency import PDFKit
@preconcurrency import Vision

/// Recognises text on pages with no usable text layer (tech spec §6.5), via Vision.
enum OCRRecognizer {
    /// One recognised line, decoupled from `VNRecognizedTextObservation` so the geometry
    /// conversion (`convert`) is unit-testable without running Vision.
    struct Observation: Sendable, Equatable {
        /// Normalised (0...1), origin bottom-left — Vision's own convention.
        var boundingBox: CGRect
        var text: String
        var confidence: Float
    }

    /// `.auto` mode triggers OCR only when the page has no visible text and its raster
    /// has more ink than `Constants.ocrMinInkCoverage` — blank pages are skipped.
    static func shouldRecognize(visibleWordCount: Int, raster: GrayRaster) -> Bool {
        guard visibleWordCount == 0 else { return false }
        return inkCoverage(of: raster) > Constants.ocrMinInkCoverage
    }

    /// Fraction of `raster`'s pixels darker than white by more than `Constants.inkDelta`.
    static func inkCoverage(of raster: GrayRaster) -> Double {
        guard !raster.pixels.isEmpty else { return 0 }
        let inkCount = raster.pixels.reduce(into: 0) { count, pixel in
            if 255 - Int(pixel) > Constants.inkDelta { count += 1 }
        }
        return Double(inkCount) / Double(raster.pixels.count)
    }

    /// `true` once more than 30 % of a page's observations had confidence < 0.5 — the
    /// caller adds `ReportWarning.ocrLowConfidence` when this holds.
    static func isLowConfidence(lowConfidenceCount: Int, total: Int) -> Bool {
        guard total > 0 else { return false }
        return Double(lowConfidenceCount) / Double(total) > 0.3
    }

    /// Converts recognised observations into `Line`s (one per observation, `source:
    /// .ocr`): bounding box from Vision's normalised bottom-left origin to display
    /// space, font size estimated as box height × 0.75, text split into words on
    /// whitespace (Vision doesn't give per-word boxes within one observation, so every
    /// word of a line shares that line's box).
    static func convert(
        observations: [Observation], page: Int, pageSize: CGSize
    ) -> (lines: [Line], lowConfidenceCount: Int, total: Int) {
        var lines: [Line] = []
        var lowConfidenceCount = 0
        for observation in observations {
            let box = displayBox(from: observation.boundingBox, pageSize: pageSize)
            let fontSize = box.height * 0.75
            let words = observation.text.split(separator: " ").map { token in
                Word(text: String(token), box: box, pageBox: box, glyphs: [], fontSize: fontSize, isBold: false)
            }
            if !words.isEmpty {
                lines.append(Line(page: page, words: words, box: box, fontSize: fontSize, isBold: false, source: .ocr))
            }
            if observation.confidence < 0.5 {
                lowConfidenceCount += 1
            }
        }
        return (lines, lowConfidenceCount, observations.count)
    }

    /// Vision's `boundingBox` is normalised with origin bottom-left; converts to display
    /// space (origin top-left) at `pageSize`.
    static func displayBox(from normalized: CGRect, pageSize: CGSize) -> CGRect {
        CGRect(
            x: normalized.minX * pageSize.width,
            y: (1 - normalized.maxY) * pageSize.height,
            width: normalized.width * pageSize.width,
            height: normalized.height * pageSize.height
        )
    }

    /// Renders `page`'s content (no annotations) to a grayscale `CGImage` at
    /// `Constants.ocrDPI`, for Vision.
    static func renderImage(page: PDFPage) -> CGImage? {
        let cropBox = page.bounds(for: .cropBox)
        let scale = CGFloat(Constants.ocrDPI) / 72.0
        let width = Int((cropBox.width * scale).rounded(.up))
        let height = Int((cropBox.height * scale).rounded(.up))
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -cropBox.minX, y: -cropBox.minY)
        if let pageRef = page.pageRef {
            context.drawPDFPage(pageRef)
        }
        return context.makeImage()
    }

    /// Runs Vision text recognition on `image` and converts the results into `Line`s.
    /// Checks for cancellation before and after the (synchronous) Vision call.
    static func recognize(
        image: CGImage, page: Int, pageSize: CGSize, languages: [String]
    ) async throws -> (lines: [Line], lowConfidenceCount: Int, total: Int) {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        try Task.checkCancellation()

        let observations = (request.results ?? []).compactMap { result -> Observation? in
            guard let candidate = result.topCandidates(1).first else { return nil }
            return Observation(
                boundingBox: result.boundingBox, text: candidate.string, confidence: candidate.confidence)
        }
        return convert(observations: observations, page: page, pageSize: pageSize)
    }
}
