#!/usr/bin/env python3
"""
Executable reference for the word-visibility algorithm specified in
specs/03-sanitization-spec.md section 3 (HiddenTextFilter). DEV-ONLY.

It mirrors the Swift design exactly: only character boxes are used (no PDF
render-mode or colour information, because PDFKit does not expose them), and
the page is rasterised WITHOUT annotations. The Swift implementation must give
the same verdicts on the fixtures; `--check` asserts that.

Uses PyMuPDF (AGPL) purely as a development-time renderer. Nothing here ships
in the app. Install: pip install pymupdf numpy

    python scripts/reference/visibility_reference.py --check
    python scripts/reference/visibility_reference.py path/to/file.pdf   # print verdicts
"""
from __future__ import annotations

import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pymupdf

# ---- constants: keep identical to VisibilityConstants in the Swift code -----
RENDER_SCALE = 2.0            # raster scale (pt -> px)
INK_DELTA = 40                # |luminance - background| (0-255) that counts as ink
MIN_INK_FRACTION = 0.01       # min share of measured pixels that must be ink
MIN_FONT_SIZE = 2.0           # glyphs smaller than this are "tiny"
MAX_BASELINE_ANGLE = 10.0     # degrees; steeper runs are "rotated"
NEIGHBOUR_PAD = 0.25          # vertical padding of other words' boxes, x box height
MIN_EXCLUSIVE_SHARE = 0.30    # below this, measure the full box instead
# -----------------------------------------------------------------------------

FIX = Path(__file__).resolve().parents[2] / "Packages/PDFCleanKit/Tests/PDFCleanKitTests/Fixtures"


@dataclass
class Word:
    text: str
    box: tuple[float, float, float, float]  # x0, y0, x1, y1 (top-left origin, points)
    size: float
    angle: float
    verdict: str = ""


def words_of(page) -> list[Word]:
    raw = page.get_text("rawdict", flags=pymupdf.TEXT_PRESERVE_WHITESPACE)
    out: list[Word] = []
    for b in raw["blocks"]:
        for line in b.get("lines", []):
            for span in line["spans"]:
                cur = []
                for ch in span["chars"] + [{"c": " ", "bbox": None}]:
                    if ch["c"].isspace():
                        if cur:
                            boxes = [c["bbox"] for c in cur]
                            box = (min(x[0] for x in boxes), min(x[1] for x in boxes),
                                   max(x[2] for x in boxes), max(x[3] for x in boxes))
                            angle = 0.0
                            if len(cur) >= 2:
                                (ax, ay), (bx, by) = [((c["bbox"][0] + c["bbox"][2]) / 2,
                                                       (c["bbox"][1] + c["bbox"][3]) / 2) for c in (cur[0], cur[-1])]
                                angle = abs(math.degrees(math.atan2(by - ay, bx - ax)))
                            out.append(Word("".join(c["c"] for c in cur), box, span["size"], angle))
                        cur = []
                    else:
                        cur.append(ch)
    return out


def classify_page(page) -> list[Word]:
    words = words_of(page)
    pr = page.rect
    pix = page.get_pixmap(matrix=pymupdf.Matrix(RENDER_SCALE, RENDER_SCALE),
                          colorspace=pymupdf.csGRAY, annots=False)
    img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width).astype(int)

    # Step 1: geometric verdicts (no raster needed)
    for w in words:
        x0, y0, x1, y1 = w.box
        if x1 <= pr.x0 or x0 >= pr.x1 or y1 <= pr.y0 or y0 >= pr.y1:
            w.verdict = "offPage"
        elif w.size < MIN_FONT_SIZE:
            w.verdict = "tiny"
        elif MAX_BASELINE_ANGLE < w.angle < 180 - MAX_BASELINE_ANGLE:
            w.verdict = "rotated"
    maskers = [w for w in words if not w.verdict]

    # Step 2: ink test on the exclusive area of each remaining word
    s = RENDER_SCALE
    for w in maskers:
        x0, y0, x1, y1 = w.box
        px0, px1 = int(max(x0, pr.x0) * s), int(min(x1, pr.x1) * s)
        py0, py1 = int(max(y0, pr.y0) * s), int(min(y1, pr.y1) * s)
        region = img[py0:max(py1, py0 + 1), px0:max(px1, px0 + 1)]
        mask = np.ones(region.shape, dtype=bool)
        for o in maskers:
            if o is w:
                continue
            ox0, oy0, ox1, oy1 = o.box
            pad = NEIGHBOUR_PAD * (oy1 - oy0)
            qx0, qx1 = int(ox0 * s) - px0, int(ox1 * s) - px0
            qy0, qy1 = int((oy0 - pad) * s) - py0, int((oy1 + pad) * s) - py0
            if qx1 <= 0 or qy1 <= 0 or qx0 >= region.shape[1] or qy0 >= region.shape[0]:
                continue
            mask[max(qy0, 0):max(qy1, 0), max(qx0, 0):max(qx1, 0)] = False
        measured = region[mask] if mask.mean() >= MIN_EXCLUSIVE_SHARE else region.ravel()
        border = np.concatenate([region[0], region[-1], region[:, 0], region[:, -1]])
        background = int(np.median(border))
        ink = float((np.abs(measured - background) > INK_DELTA).mean()) if measured.size else 0.0
        w.verdict = "visible" if ink >= MIN_INK_FRACTION else "hidden"
    return words


def check() -> int:
    manifest = json.loads((FIX / "manifest.json").read_text(encoding="utf-8"))
    failures = 0
    for fx in manifest["fixtures"]:
        if fx.get("expectError") or fx.get("expectNoCrash") or fx.get("ocrPages") or fx["id"].startswith("perf"):
            continue
        doc = pymupdf.open(str(FIX / fx["file"]))
        if doc.needs_pass:
            doc.authenticate(fx.get("password", ""))
        visible, removed = [], []
        for page in doc:
            for w in classify_page(page):
                (visible if w.verdict == "visible" else removed).append(w.text)
        for canary in fx.get("mustNotContain", []):
            if canary.startswith("CANARY-") and any(canary in v for v in visible):
                # watermark/footer canaries are visible on purpose; RepeatedContentFilter removes them
                if canary not in ("CANARY-WATERMARK", "CANARY-FOOTER-ID", "CANARY-ZWVARIANT"):
                    print(f"FAIL {fx['id']}: {canary} judged visible"); failures += 1
        removed_set, visible_set = set(removed), set(visible)
        for phrase in fx.get("mustContain", []) + fx.get("mustContainAfterFiltering", []):
            for token in phrase.split():
                if token in removed_set and token not in visible_set:
                    print(f"FAIL {fx['id']}: word {token!r} of a must-keep phrase was removed"); failures += 1
        print(f"ok  {fx['id']}: {len(visible)} visible words, {len(removed)} removed")
    print("REFERENCE CHECK", "FAILED" if failures else "PASSED")
    return 1 if failures else 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] != "--check":
        for path in sys.argv[1:]:
            doc = pymupdf.open(path)
            for i, page in enumerate(doc, 1):
                for w in classify_page(page):
                    if w.verdict != "visible":
                        print(f"p{i} {w.verdict:8s} {ascii(w.text)}")
        sys.exit(0)
    sys.exit(check())
