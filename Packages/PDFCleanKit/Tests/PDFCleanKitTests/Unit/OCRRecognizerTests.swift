import CoreGraphics
import Foundation
@preconcurrency import PDFKit
import Testing

@testable import PDFCleanKit

/// TC-U28 (T-034).
@Suite("OCRRecognizer")
struct OCRRecognizerTests {
    @Test("converts a normalised bottom-left box to display space")
    func displayBoxConversion() {
        // Normalised box in the lower-left quarter of the page; pageSize 200x100.
        let normalized = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        let box = OCRRecognizer.displayBox(from: normalized, pageSize: CGSize(width: 200, height: 100))
        // x: 0.1*200=20, width: 0.2*200=40; y: (1-(0.1+0.2))*100=70, height: 0.2*100=20.
        #expect(box == CGRect(x: 20, y: 70, width: 40, height: 20))
    }

    @Test("converts observations to lines with estimated font size and split words")
    func convertObservations() {
        let observation = OCRRecognizer.Observation(
            boundingBox: CGRect(x: 0, y: 0.9, width: 0.5, height: 0.1),
            text: "hello world",
            confidence: 0.9
        )
        let (lines, lowConfidenceCount, total) = OCRRecognizer.convert(
            observations: [observation], page: 1, pageSize: CGSize(width: 100, height: 100)
        )
        #expect(lines.count == 1)
        #expect(lines[0].source == .ocr)
        #expect(lines[0].page == 1)
        #expect(lines[0].words.map(\.text) == ["hello", "world"])
        #expect(lines[0].fontSize == lines[0].box.height * 0.75)
        #expect(lowConfidenceCount == 0)
        #expect(total == 1)
    }

    @Test("counts low-confidence observations")
    func lowConfidenceCounting() {
        let observations = [
            OCRRecognizer.Observation(
                boundingBox: .init(x: 0, y: 0, width: 0.1, height: 0.1), text: "a", confidence: 0.9),
            OCRRecognizer.Observation(
                boundingBox: .init(x: 0, y: 0, width: 0.1, height: 0.1), text: "b", confidence: 0.3),
        ]
        let (_, lowConfidenceCount, total) = OCRRecognizer.convert(
            observations: observations, page: 1, pageSize: CGSize(width: 100, height: 100)
        )
        #expect(lowConfidenceCount == 1)
        #expect(total == 2)
        // 1 of 2 is 50%, above the 30% threshold.
        #expect(OCRRecognizer.isLowConfidence(lowConfidenceCount: lowConfidenceCount, total: total))
        #expect(!OCRRecognizer.isLowConfidence(lowConfidenceCount: 2, total: 10))
    }

    @Test("shouldRecognize triggers only when there are no visible words and ink is present")
    func shouldRecognizeTrigger() {
        let inkyRaster = GrayRaster(width: 2, height: 2, pixels: [0, 255, 255, 255])
        let blankRaster = GrayRaster(width: 2, height: 2, pixels: [255, 255, 255, 255])

        #expect(OCRRecognizer.shouldRecognize(visibleWordCount: 0, raster: inkyRaster))
        #expect(!OCRRecognizer.shouldRecognize(visibleWordCount: 0, raster: blankRaster))
        #expect(!OCRRecognizer.shouldRecognize(visibleWordCount: 3, raster: inkyRaster))
    }

    // MARK: - Fixture integration (real Vision OCR)

    @Test("scanned.pdf: offline OCR recovers the page text")
    func scannedFixtureRecognizesText() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "scanned", withExtension: "pdf", subdirectory: "Fixtures"))
        let document = try #require(PDFDocument(url: url))
        let page = try #require(document.page(at: 0))
        let image = try #require(OCRRecognizer.renderImage(page: page))
        let cropBox = page.bounds(for: .cropBox)
        let pageSize = PageGeometry.displaySize(cropBox: cropBox, rotation: page.rotation)

        let (lines, _, _) = try await OCRRecognizer.recognize(
            image: image, page: 1, pageSize: pageSize, languages: ["en-US"]
        )
        let text = lines.map(\.text).joined(separator: " ").lowercased()
        #expect(text.contains("recovered"))
        #expect(text.contains("offline"))
    }
}
