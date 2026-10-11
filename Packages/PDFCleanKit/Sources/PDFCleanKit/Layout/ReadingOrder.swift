import CoreGraphics

/// Orders a page's assembled lines into reading order via a recursive XY-cut (tech spec
/// §6.7.2): split the current region at the widest horizontal whitespace band spanning it, or —
/// when no such band exists — at a vertical whitespace gutter at least `Constants.minGutter`
/// wide that stays clear for at least 60 % of the region's height. Horizontal cuts are preferred
/// over vertical ones whenever both are available. A leaf (no further cut possible) is read
/// top-to-bottom, left-to-right (right-to-left on RTL-dominant pages). Pure, side-effect free.
enum ReadingOrder {

    /// Minimum fraction of a candidate gutter's region height that must stay clear of lines for
    /// it to count as a column separator (tech spec §6.7.2).
    private static let minGutterHeightCoverage: Double = 0.6

    /// Reorders `lines` (in arbitrary/content order, as produced by `LineAssembler`) into visual
    /// reading order. `rtl` flips left/right group order and leaf tie-breaking for RTL pages.
    static func order(lines: [Line], rtl: Bool = false) -> [Line] {
        guard lines.count > 1 else { return lines }

        if let cut = horizontalCut(of: lines) {
            return order(lines: cut.top, rtl: rtl) + order(lines: cut.bottom, rtl: rtl)
        }
        if let cut = verticalCut(of: lines) {
            let left = order(lines: cut.left, rtl: rtl)
            let right = order(lines: cut.right, rtl: rtl)
            return rtl ? right + left : left + right
        }
        return leafOrder(lines: lines, rtl: rtl)
    }

    // MARK: - Horizontal cut

    private struct HorizontalCut {
        var top: [Line]
        var bottom: [Line]
    }

    /// Finds the widest horizontal whitespace band across the full region (a y-range no line's
    /// box intersects) and splits the lines above it from the lines below it. `nil` when every
    /// line's vertical extent transitively overlaps the next — a single merged band, so no
    /// horizontal cut is available.
    private static func horizontalCut(of lines: [Line]) -> HorizontalCut? {
        let sorted = lines.sorted { $0.box.minY < $1.box.minY }
        var bandEnd = sorted[0].box.maxY
        var bestGap: CGFloat = 0
        var bestSplitIndex: Int?
        for i in 1..<sorted.count {
            let line = sorted[i]
            if line.box.minY > bandEnd {
                let gap = line.box.minY - bandEnd
                if gap > bestGap {
                    bestGap = gap
                    bestSplitIndex = i
                }
            }
            bandEnd = max(bandEnd, line.box.maxY)
        }
        guard let split = bestSplitIndex else { return nil }
        return HorizontalCut(top: Array(sorted[0..<split]), bottom: Array(sorted[split...]))
    }

    // MARK: - Vertical cut

    private struct VerticalCut {
        var left: [Line]
        var right: [Line]
    }

    /// Finds the widest vertical whitespace gutter (≥ `Constants.minGutter`, clear for ≥ 60 % of
    /// the region's height) and splits the lines left of it from the lines right of it.
    private static func verticalCut(of lines: [Line]) -> VerticalCut? {
        let regionMinY = lines.map(\.box.minY).min() ?? 0
        let regionMaxY = lines.map(\.box.maxY).max() ?? 0
        let regionHeight = regionMaxY - regionMinY
        guard regionHeight > 0 else { return nil }

        let sorted = lines.sorted { $0.box.minX < $1.box.minX }
        var candidates: [(start: CGFloat, end: CGFloat)] = []
        var bandEnd = sorted[0].box.maxX
        for i in 1..<sorted.count {
            let line = sorted[i]
            if line.box.minX > bandEnd {
                candidates.append((bandEnd, line.box.minX))
            }
            bandEnd = max(bandEnd, line.box.maxX)
        }

        var best: (start: CGFloat, end: CGFloat)?
        var bestWidth: CGFloat = 0
        for candidate in candidates {
            let width = candidate.end - candidate.start
            guard width >= Constants.minGutter, width > bestWidth else { continue }
            let blocked = blockedHeight(of: lines, inXRange: candidate, regionMinY: regionMinY, regionMaxY: regionMaxY)
            let freeFraction = 1 - Double(blocked / regionHeight)
            guard freeFraction >= minGutterHeightCoverage else { continue }
            bestWidth = width
            best = candidate
        }
        guard let gutter = best else { return nil }

        let mid = (gutter.start + gutter.end) / 2
        let left = lines.filter { $0.box.midX < mid }
        let right = lines.filter { $0.box.midX >= mid }
        guard !left.isEmpty, !right.isEmpty else { return nil }
        return VerticalCut(left: left, right: right)
    }

    /// Total height (clamped to the region) covered by at least one line whose box intersects
    /// the candidate x-range, merging overlapping y-intervals.
    private static func blockedHeight(
        of lines: [Line], inXRange xRange: (start: CGFloat, end: CGFloat), regionMinY: CGFloat, regionMaxY: CGFloat
    ) -> CGFloat {
        let intervals =
            lines
            .filter { $0.box.minX < xRange.end && $0.box.maxX > xRange.start }
            .map { (max($0.box.minY, regionMinY), min($0.box.maxY, regionMaxY)) }
            .sorted { $0.0 < $1.0 }

        var total: CGFloat = 0
        var currentStart: CGFloat?
        var currentEnd: CGFloat = 0
        for (start, end) in intervals {
            guard start < end else { continue }
            if currentStart != nil, start <= currentEnd {
                currentEnd = max(currentEnd, end)
            } else {
                if let cs = currentStart { total += currentEnd - cs }
                currentStart = start
                currentEnd = end
            }
        }
        if let cs = currentStart { total += currentEnd - cs }
        return total
    }

    // MARK: - Leaf ordering

    /// Orders a leaf's lines top-to-bottom, then left-to-right (right-to-left for RTL pages).
    private static func leafOrder(lines: [Line], rtl: Bool) -> [Line] {
        lines.sorted {
            if $0.box.minY != $1.box.minY { return $0.box.minY < $1.box.minY }
            return rtl ? $0.box.minX > $1.box.minX : $0.box.minX < $1.box.minX
        }
    }
}
