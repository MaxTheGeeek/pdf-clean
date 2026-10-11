import CoreGraphics
import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U24 (T-020): `PageGeometry` converts between unrotated PDF page space (origin bottom-left,
/// y upward, often offset crop box) and display space (origin top-left of the crop box, y downward,
/// `/Rotate` applied) for rotations 0/90/180/270.
@Suite("PageGeometry")
struct PageGeometryTests {

    let cropBox = CGRect(x: 100, y: 200, width: 600, height: 800)
    let offsetCropBox = CGRect(x: 50, y: 80, width: 612, height: 792)

    @Test("normalizes invalid, negative and full-turn rotations")
    func normalizedRotation() {
        #expect(PageGeometry.normalizedRotation(0) == 0)
        #expect(PageGeometry.normalizedRotation(90) == 90)
        #expect(PageGeometry.normalizedRotation(180) == 180)
        #expect(PageGeometry.normalizedRotation(270) == 270)
        #expect(PageGeometry.normalizedRotation(360) == 0)
        #expect(PageGeometry.normalizedRotation(720) == 0)
        #expect(PageGeometry.normalizedRotation(45) == 0)
        #expect(PageGeometry.normalizedRotation(-90) == 270)
        #expect(PageGeometry.normalizedRotation(-450) == 270)
        #expect(PageGeometry.normalizedRotation(540) == 180)
    }

    @Test("display size swaps width and height only for 90/270")
    func displaySizeSwapsAxes() {
        #expect(PageGeometry.displaySize(cropBox: cropBox, rotation: 0) == CGSize(width: 600, height: 800))
        #expect(PageGeometry.displaySize(cropBox: cropBox, rotation: 90) == CGSize(width: 800, height: 600))
        #expect(PageGeometry.displaySize(cropBox: cropBox, rotation: 180) == CGSize(width: 600, height: 800))
        #expect(PageGeometry.displaySize(cropBox: cropBox, rotation: 270) == CGSize(width: 800, height: 600))
    }

    @Test("rotation 0 maps an offset crop-box point into display space (y-flip)")
    func rotationZeroExactMapping() {
        // page rect, crop box (x:100,y:200,w:600,h:800)
        let pageRect = CGRect(x: 250, y: 400, width: 200, height: 100)
        let display = PageGeometry.pageToDisplay(pageRect, cropBox: cropBox, rotation: 0)
        // u = (250-100)/600 = 0.25 -> x=150, width = (350-150)/600*600 = 200
        // v_min = (400-200)/800 = 0.25, v_max = (500-200)/800 = 0.375
        // displayY_min = (1-0.375)*800 = 500, displayY_max = (1-0.25)*800 = 600
        #expect(display == CGRect(x: 150, y: 500, width: 200, height: 100))
    }

    @Test("rotation 90 swaps axes for a known point")
    func rotationNinetyExactMapping() {
        // page point (x:400,y:400): u=0.5, v=0.25 -> display = (v*h, u*w) = (200, 300)
        let pageRect = CGRect(x: 400, y: 400, width: 10, height: 10)
        let display = PageGeometry.pageToDisplay(pageRect, cropBox: cropBox, rotation: 90)
        assertCGRectEqual(display, CGRect(x: 200, y: 300, width: 10, height: 10), tolerance: 0.001)
    }

    @Test("page <-> display round-trips for every rotation with an offset crop box")
    func roundTripAllRotations() {
        let rects = [
            CGRect(x: 80, y: 90, width: 200, height: 60),
            CGRect(x: 300, y: 400, width: 40, height: 120),
            CGRect(x: 60, y: 800, width: 500, height: 30),
        ]
        for rotation in [0, 90, 180, 270] {
            for rect in rects {
                let display = PageGeometry.pageToDisplay(rect, cropBox: offsetCropBox, rotation: rotation)
                let back = PageGeometry.displayToPage(display, cropBox: offsetCropBox, rotation: rotation)
                assertCGRectEqual(back, rect, tolerance: 0.001)
            }
        }
    }

    @Test("display <-> page round-trips for every rotation with an offset crop box")
    func roundTripAllRotationsInverse() {
        let rects = [
            CGRect(x: 10, y: 20, width: 200, height: 60),
            CGRect(x: 300, y: 120, width: 40, height: 120),
            CGRect(x: 500, y: 30, width: 90, height: 20),
        ]
        for rotation in [0, 90, 180, 270] {
            for rect in rects {
                let page = PageGeometry.displayToPage(rect, cropBox: offsetCropBox, rotation: rotation)
                let display = PageGeometry.pageToDisplay(page, cropBox: offsetCropBox, rotation: rotation)
                assertCGRectEqual(display, rect, tolerance: 0.001)
            }
        }
    }

    @Test("degenerate inputs return a null rect")
    func degenerateInputs() {
        #expect(PageGeometry.pageToDisplay(.null, cropBox: cropBox, rotation: 0).isNull)
        #expect(PageGeometry.displayToPage(.zero, cropBox: CGRect.zero, rotation: 0).isNull)
    }

    private func assertCGRectEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) {
        #expect(abs(a.minX - b.minX) <= tolerance)
        #expect(abs(a.minY - b.minY) <= tolerance)
        #expect(abs(a.width - b.width) <= tolerance)
        #expect(abs(a.height - b.height) <= tolerance)
    }
}
