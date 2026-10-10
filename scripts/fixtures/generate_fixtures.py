#!/usr/bin/env python3
"""
Generate the PDF test fixtures used by PDFCleanKit tests.

Every fixture is built so that a *naive* extractor (one that just dumps the
text layer) produces the wrong result. The expectations each fixture must meet
live in fixtures/manifest.json; scripts/fixtures/verify_fixtures.py proves,
with an independent extractor, that each fixture really contains the hidden
content it claims to contain.

Usage (macOS or Linux):
    python3 -m venv .venv && .venv/bin/pip install -r scripts/fixtures/requirements.txt
    .venv/bin/python scripts/fixtures/generate_fixtures.py
Output goes to Packages/PDFCleanKit/Tests/PDFCleanKitTests/Fixtures/.
The output is deterministic (reportlab invariant mode, fixed trailer IDs), except the two
encrypted fixtures: AES encryption uses a random salt/IV, so their bytes differ per run.
"""
from __future__ import annotations

import io
import os
import sys
from pathlib import Path

import pikepdf
from PIL import Image, ImageDraw, ImageFont
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Packages/PDFCleanKit/Tests/PDFCleanKitTests/Fixtures"
FONTS = Path(__file__).resolve().parent / "fonts"
W, H = A4  # 595.27 x 841.89 pt

pdfmetrics.registerFont(TTFont("DejaVu", str(FONTS / "DejaVuSans.ttf")))
pdfmetrics.registerFont(TTFont("DejaVu-Bold", str(FONTS / "DejaVuSans-Bold.ttf")))

BODY = 11
LEADING = 15

# Some code points we must test (Unicode TAG characters, isolates, ideographic space)
# have no glyph in any normal font, so a PDF generator cannot emit them directly.
# Real-world "ASCII smuggling" PDFs do it by pointing the ToUnicode CMap of an
# existing glyph at the smuggled code point. We do the same: draw an otherwise
# unused Greek letter, then rewrite its ToUnicode entry to the target code point.
PLACEHOLDERS = {
    "\u03b1": 0xE0043, "\u03b2": 0xE0041, "\u03b3": 0xE004E,   # TAG C, A, N
    "\u03b4": 0xE0041, "\u03b5": 0xE0052, "\u03b6": 0xE0059,   # TAG A, R, Y
    "\u03b7": 0x2066, "\u03b8": 0x2069,                         # LRI, PDI
    "\u03b9": 0x3000,                                            # IDEOGRAPHIC SPACE
}


def utf16_hex(cp: int) -> str:
    if cp < 0x10000:
        return f"{cp:04X}"
    v = cp - 0x10000
    return f"{0xD800 + (v >> 10):04X}{0xDC00 + (v & 0x3FF):04X}"


def patch_tounicode(pdf: pikepdf.Pdf) -> int:
    """Rewrite ToUnicode entries of placeholder glyphs to the smuggled code points."""
    count = 0
    seen = set()
    for page in pdf.pages:
        fonts = page.Resources.get("/Font", {})
        for _, font in fonts.items():
            if "/ToUnicode" not in font or font.ToUnicode.objgen in seen:
                continue
            seen.add(font.ToUnicode.objgen)
            cmap = font.ToUnicode.read_bytes().decode("latin-1")
            new = cmap
            for ph, cp in PLACEHOLDERS.items():
                new = new.replace(f"<{ord(ph):04X}>", f"<{utf16_hex(cp)}>")
            if new != cmap:
                font.ToUnicode.write(new.encode("latin-1"))
                count += 1
    return count


def draw_segments(c, x, y, segments):
    """segments: list of (text, font, size, render_mode). Drawn in one text object."""
    t = c.beginText()
    t.setTextOrigin(x, y)
    for text, font, size, mode in segments:
        t.setFont(font, size)
        t.setTextRenderMode(mode)
        t.textOut(text)
    t.setTextRenderMode(0)
    c.drawText(t)


def new_canvas(name: str) -> canvas.Canvas:
    c = canvas.Canvas(str(OUT / name), pagesize=A4, invariant=1)
    c.setCreator("fixture-generator")
    c.setProducer("fixture-generator")
    return c


def lines(c, x, y, texts, font="Helvetica", size=BODY, leading=LEADING):
    """Draw each string as its own line; return the y below the last line."""
    c.setFont(font, size)
    for t in texts:
        c.drawString(x, y, t)
        y -= leading
    return y


def finalize(name: str, *, info: dict | None = None, xmp: dict | None = None,
             attachments: dict | None = None, encryption=None):
    """Re-save through pikepdf: fixed /ID, optional metadata, XMP, attachments, encryption."""
    path = OUT / name
    data = path.read_bytes()
    with pikepdf.open(io.BytesIO(data)) as pdf:
        patch_tounicode(pdf)
        if xmp:  # XMP first, without syncing, so it cannot overwrite the Info dictionary
            with pdf.open_metadata(set_pikepdf_as_editor=False, update_docinfo=False) as meta:
                for k, v in xmp.items():
                    meta[k] = v
        if info:
            for k, v in info.items():
                pdf.docinfo[k] = v
        if attachments:
            for fname, payload in attachments.items():
                pdf.attachments[fname] = pikepdf.AttachedFileSpec(pdf, payload, filename=fname)
        pdf.trailer.ID = pikepdf.Array([pikepdf.String(b"fixtureid000001"), pikepdf.String(b"fixtureid000001")])
        kwargs = dict(deterministic_id=False, static_id=True)
        if encryption is not None:
            kwargs["encryption"] = encryption
        pdf.save(str(path), **kwargs)


# ---------------------------------------------------------------------------
# 1. simple-structured.pdf : title, headings, paragraphs, hyphenation, lists,
#    running header/footer, paragraph continuing across a page break.
# ---------------------------------------------------------------------------
def simple_structured():
    name = "simple-structured.pdf"
    c = new_canvas(name)

    def header_footer(page, total):
        c.setFont("Helvetica", 8)
        c.drawString(50, H - 30, "ACME Corp \u00b7 Internal Use")
        c.drawRightString(W - 50, 30, f"Page {page} of {total}")

    header_footer(1, 2)
    c.setFont("Helvetica-Bold", 24)
    c.drawString(50, H - 90, "Quarterly Infrastructure Report")
    c.setFont("Helvetica-Bold", 18)
    c.drawString(50, H - 140, "1 Introduction")
    y = lines(c, 50, H - 165, [
        "This report summarises the infrastructure work completed during the quarter.",
        "The new platform improves resilience across our infra-",
        "structure and reduces operating costs significantly.",
    ])
    y -= 8
    lines(c, 50, y, [
        "A second paragraph begins after a visible vertical gap and must be kept",
        "separate from the first paragraph in the extracted output.",
    ])
    c.setFont("Helvetica-Bold", 14)
    c.drawString(50, H - 300, "1.1 Scope")
    lines(c, 50, H - 322, [
        "The scope covers compute, storage and networking for all internal services.",
    ])
    c.setFont("Helvetica-Bold", 14)
    c.drawString(50, H - 370, "1.2 Priorities")
    y = H - 392
    c.setFont("Helvetica", BODY)
    for text in ["Migrate legacy services to containers", "Consolidate monitoring dashboards into a single"]:
        c.setFont("DejaVu", BODY); c.drawString(50, y, "\u2022")  # bullet from a Unicode font
        c.setFont("Helvetica", BODY); c.drawString(64, y, text); y -= LEADING
    c.drawString(64, y, "view for the operations team"); y -= LEADING + 8
    c.drawString(50, y, "1."); c.drawString(64, y, "Alpha rollout in the staging region"); y -= LEADING
    c.drawString(50, y, "2."); c.drawString(64, y, "Beta rollout in the production region"); y -= LEADING + 12
    lines(c, 50, y, [
        "Throughout the third quarter the team tracked every change carefully and the migration",
    ])
    c.showPage()

    header_footer(2, 2)
    y = lines(c, 50, H - 70, [
        "continued without major incidents across all regions.",
    ])
    c.setFont("Helvetica-Bold", 18)
    c.drawString(50, H - 120, "2 Results")
    lines(c, 50, H - 145, [
        "Availability rose to ninety-nine point nine five percent for the quarter.",
    ])
    c.setFont("Helvetica-Bold", 14)
    c.drawString(50, H - 190, "2.1 Outcomes")
    lines(c, 50, H - 212, [
        "Costs fell by twelve percent while throughput doubled.",
    ])
    c.showPage()
    c.save()
    finalize(name)


# ---------------------------------------------------------------------------
# 2. toc.pdf : title page, table of contents with dot leaders, PDF outline.
# ---------------------------------------------------------------------------
def toc():
    name = "toc.pdf"
    c = new_canvas(name)
    c.setFont("Helvetica-Bold", 26)
    c.drawString(50, H - 200, "Handbook of Offline Tools")
    c.setFont("Helvetica", 12)
    c.drawString(50, H - 230, "Edition 2026")
    c.showPage()

    c.setFont("Helvetica-Bold", 18)
    c.drawString(50, H - 80, "Table of Contents")
    entries = [(0, "1 Getting Started", 3), (1, "1.1 Installation", 3), (1, "1.2 Configuration", 3),
               (0, "2 Advanced Usage", 4), (1, "2.1 Batch Mode", 4)]
    y = H - 120
    c.setFont("Helvetica", BODY)
    for level, title, page in entries:
        x = 50 + level * 20
        c.drawString(x, y, title)
        tw = c.stringWidth(title, "Helvetica", BODY)
        dots_start, dots_end = x + tw + 6, W - 80
        dots = "." * int((dots_end - dots_start) / c.stringWidth(".", "Helvetica", BODY))
        c.drawString(dots_start, y, dots)
        c.drawRightString(W - 50, y, str(page))
        y -= LEADING + 4
    c.showPage()

    def heading(key, text, size, y, level):
        c.bookmarkHorizontal(key, 0, y + size)  # unique key per outline entry
        c.addOutlineEntry(text, key, level=level)
        c.setFont("Helvetica-Bold", size); c.drawString(50, y, text)

    heading("h1", "1 Getting Started", 18, H - 80, 0)
    lines(c, 50, H - 105, ["Getting started requires no network connection at any point."])
    heading("h11", "1.1 Installation", 14, H - 150, 1)
    lines(c, 50, H - 172, ["Copy the application to the Applications folder."])
    heading("h12", "1.2 Configuration", 14, H - 220, 1)
    lines(c, 50, H - 242, ["All settings are stored only for the current session."])
    c.showPage()

    heading("h2", "2 Advanced Usage", 18, H - 80, 0)
    lines(c, 50, H - 105, ["Advanced usage covers automation through the command line tool."])
    heading("h21", "2.1 Batch Mode", 14, H - 150, 1)
    lines(c, 50, H - 172, ["Batch mode processes a folder of documents sequentially."])
    c.showPage()
    c.save()
    finalize(name)


# ---------------------------------------------------------------------------
# 3. hidden-content.pdf : every hiding technique we defend against.
# ---------------------------------------------------------------------------
WM_TEXT = "Licensed to max@example.com \u00b7 DOC-ID 7F3A-99X2 CANARY-WATERMARK"


def hidden_content():
    name = "hidden-content.pdf"
    c = new_canvas(name)

    def watermarks(page):
        # same visible line on every page, but each page hides a zero-width character at a
        # different place, so a naive exact-text comparison sees different lines per page
        variant = ["Distribution\u200b copy for Northwind Traders CANARY-ZWVARIANT",
                   "Distribution copy\u200b for Northwind Traders CANARY-ZWVARIANT"][page - 1]
        c.saveState()
        c.setFillColorRGB(0.6, 0.6, 0.6)
        c.setFont("DejaVu", 9)
        c.drawString(120, 400, variant)
        c.restoreState()
        # repeated per-recipient line at the same position on every page (visible, light grey)
        c.saveState()
        c.setFillColorRGB(0.75, 0.75, 0.75)
        c.setFont("DejaVu", 9)
        c.drawString(120, 420, WM_TEXT)
        # rotated diagonal watermark
        c.translate(150, 150)
        c.rotate(45)
        c.setFont("DejaVu-Bold", 40)
        c.drawString(0, 0, "CANARY-ROTATED")
        c.restoreState()
        # footer fingerprint
        c.setFont("DejaVu", 7)
        c.drawString(50, 25, "Copy #00417 CANARY-FOOTER-ID")

    # ---- page 1
    watermarks(1)
    # fake-bold heading: drawn twice with a 0.3pt offset
    c.setFont("DejaVu-Bold", 22)
    c.drawString(50, H - 80, "Confidential Briefing")
    c.setFont("DejaVu-Bold", 16)
    c.drawString(50, H - 125, "Summary")
    c.drawString(50.3, H - 125, "Summary")
    c.setFont("DejaVu", BODY)
    y = H - 150
    c.drawString(50, y, "This is the visible briefing text that must survive extraction."); y -= LEADING
    # zero-width / format characters inside words
    c.drawString(50, y, "Visi\u200bble para\u200cgraph text with\u2060 hidden\ufeff marks."); y -= LEADING
    # Unicode TAG characters spelling "CANARY" (classic ASCII smuggling)
    # The tag glyphs are drawn at 0.1pt in render mode 3 (zero width, no ink), then their
    # ToUnicode entries are rewritten to U+E0043.. by patch_tounicode().
    draw_segments(c, 50, y, [("Tag", "DejaVu", BODY, 0),
                             ("\u03b1\u03b2\u03b3\u03b4\u03b5\u03b6", "DejaVu", 0.1, 3),
                             (" smuggling test sentence.", "DejaVu", BODY, 0)]); y -= LEADING
    # bidi controls: the embedding pair has glyphs in DejaVu; the isolates go through placeholders
    draw_segments(c, 50, y, [("Bidi \u202acontrol\u202c characters ", "DejaVu", BODY, 0),
                             ("\u03b7", "DejaVu", 0.1, 3), ("are", "DejaVu", BODY, 0),
                             ("\u03b8", "DejaVu", 0.1, 3), (" removed.", "DejaVu", BODY, 0)]); y -= LEADING
    # homoglyphs: Cyrillic a (U+0430) and o (U+043E) inside Latin words
    c.drawString(50, y, "The p\u0430ssword p\u043elicy applies to all staff."); y -= LEADING
    # odd whitespace: NBSP, thin space, ideographic space, many spaces
    draw_segments(c, 50, y, [("Spacing\u00a0test\u2009with", "DejaVu", BODY, 0),
                             ("\u03b9", "DejaVu", BODY, 3),  # -> U+3000 ideographic space
                             ("odd     whitespace.", "DejaVu", BODY, 0)]); y -= LEADING
    # visible identifier the user may choose to redact
    c.drawString(50, y, "Reference: 3f2a9c1e-77b4-4c2e-9d1a-0b6e5f4a3c21"); y -= LEADING * 2

    # --- hidden text techniques ---
    # white text on white background
    c.setFillColorRGB(1, 1, 1)
    c.drawString(50, y, "CANARY-WHITE-TEXT"); y -= LEADING
    c.setFillColorRGB(0, 0, 0)
    # text render mode 3 (invisible)
    t = c.beginText(); t.setTextRenderMode(3); t.setFont("DejaVu", BODY); t.setTextOrigin(50, y)
    t.textLine("CANARY-INVISIBLE-RENDER")
    t.setTextRenderMode(0)  # render mode is graphics state: reset it or later text inherits it
    c.drawText(t); y -= LEADING
    # text covered by an opaque white rectangle
    c.drawString(50, y, "CANARY-COVERED-TEXT")
    c.setFillColorRGB(1, 1, 1); c.rect(45, y - 4, 250, LEADING, stroke=0, fill=1); c.setFillColorRGB(0, 0, 0)
    y -= LEADING
    # tiny text
    c.setFont("DejaVu", 0.5); c.drawString(50, y, "CANARY-TINY-TEXT"); c.setFont("DejaVu", BODY); y -= LEADING
    # text outside the page (beyond the right edge of the media box)
    c.drawString(W + 100, y, "CANARY-OFFPAGE")
    # clipped text
    c.saveState()
    p = c.beginPath(); p.rect(0, 0, 10, 10); c.clipPath(p, stroke=0, fill=0)
    c.drawString(50, y, "CANARY-CLIPPED")
    c.restoreState(); y -= LEADING

    c.drawString(50, y, "The final visible sentence on page one."); y -= LEADING
    # a white word inside an otherwise visible line
    draw_segments(c, 50, y, [("Inline check: alpha ", "DejaVu", BODY, 0)])
    x = 50 + c.stringWidth("Inline check: alpha ", "DejaVu", BODY)
    c.setFillColorRGB(1, 1, 1); c.setFont("DejaVu", BODY); c.drawString(x, y, "CANARY-INLINE-WHITE")
    c.setFillColorRGB(0, 0, 0)
    x += c.stringWidth("CANARY-INLINE-WHITE ", "DejaVu", BODY)
    c.drawString(x, y, "omega closes the line."); y -= LEADING
    # white text squeezed 8pt below a line full of descenders
    c.drawString(50, y, "Typography quickly gauges jumpy glyph descenders."); y -= 8
    c.setFillColorRGB(1, 1, 1); c.drawString(50, y, "CANARY-TIGHT-WHITE CANARY-TIGHT-WHITE"); c.setFillColorRGB(0, 0, 0)
    y -= LEADING
    # annotations and form field (never part of output)
    c.textAnnotation("CANARY-ANNOT-COMMENT", Rect=(400, H - 200, 420, H - 180))
    c.linkURL("https://tracker.example.com/CANARY-LINK", (50, H - 160, 300, H - 145), relative=0)
    c.acroForm.textfield(name="tracking", value="CANARY-FORM-VALUE", x=350, y=100, width=200, height=20)
    c.showPage()

    # ---- page 2
    watermarks(2)
    c.setFont("DejaVu-Bold", 16)
    c.drawString(50, H - 80, "Details")
    c.setFont("DejaVu", BODY)
    c.drawString(50, H - 105, "Second page visible content is preserved as well.")
    c.showPage()
    c.save()

    finalize(
        name,
        info={"/Title": "CANARY-META-TITLE", "/Author": "CANARY-META-AUTHOR",
              "/Keywords": "CANARY-META-KEYWORDS", "/TrackingID": "CANARY-META-CUSTOM"},
        xmp={"xmpMM:DocumentID": "uuid:CANARY-XMP-DOCID", "dc:description": "CANARY-XMP-DESCRIPTION"},
        attachments={"tracking.txt": b"CANARY-ATTACH-PAYLOAD"},
    )


# ---------------------------------------------------------------------------
# 4. two-column.pdf : right column is written FIRST in the content stream.
# ---------------------------------------------------------------------------
def two_column():
    name = "two-column.pdf"
    c = new_canvas(name)
    left = ["Left column begins with the opening argument of the article."] + \
           [f"Left filler line number {i} keeps the column realistic." for i in range(1, 19)] + \
           ["Left column ends here before the reader moves right."]
    right = ["Right column begins after the left column is finished."] + \
            [f"Right filler line number {i} continues the story." for i in range(1, 19)] + \
            ["Right column ends the article with a conclusion."]
    c.setFont("Helvetica", 9)
    y = H - 140
    for t in right:  # right column first in content order
        c.drawString(310, y, t); y -= 13
    y = H - 140
    for t in left:
        c.drawString(50, y, t); y -= 13
    c.setFont("Helvetica-Bold", 20)
    c.drawString(50, H - 90, "Two Column Article")
    c.showPage()
    c.save()
    finalize(name)


# ---------------------------------------------------------------------------
# 5. scanned.pdf (image only) and scanned-with-ocr-layer.pdf (image + invisible text)
# ---------------------------------------------------------------------------
DPI = 200
S = DPI / 72.0


def render_page_image(text_lines):
    img = Image.new("L", (int(W * S), int(H * S)), 255)
    d = ImageDraw.Draw(img)
    for (x, y, size, bold, text) in text_lines:
        font = ImageFont.truetype(str(FONTS / ("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf")), int(size * S))
        d.text((x * S, (H - y) * S), text, font=font, fill=0, anchor="ls")
    buf = io.BytesIO(); img.save(buf, format="PNG", optimize=True); buf.seek(0)
    return ImageReader(buf)


def scanned(name, title, with_layer):
    content = [
        (60, H - 100, 20, True, title),
        (60, H - 140, 12, False, "This page was produced as an image so that the text"),
        (60, H - 160, 12, False, "must be recovered with offline OCR on the device."),
        (60, H - 200, 12, False, "No network access is ever required for recognition."),
    ]
    c = new_canvas(name)
    c.drawImage(render_page_image(content), 0, 0, width=W, height=H)
    if with_layer:
        for (x, y, size, bold, text) in content:
            t = c.beginText(); t.setTextRenderMode(3)
            t.setFont("DejaVu-Bold" if bold else "DejaVu", size); t.setTextOrigin(x, y)
            t.textLine(text); c.drawText(t)
    c.showPage(); c.save()
    finalize(name)


# ---------------------------------------------------------------------------
# 6. encryption / permissions
# ---------------------------------------------------------------------------
def encrypted():
    name = "encrypted-user-password.pdf"
    c = new_canvas(name)
    c.setFont("Helvetica-Bold", 18); c.drawString(50, H - 80, "Encrypted Document")
    lines(c, 50, H - 110, ["Encrypted content unlocked with the correct password."])
    c.showPage(); c.save()
    finalize(name, encryption=pikepdf.Encryption(user="open-sesame", owner="owner-pass",
                                                 allow=pikepdf.Permissions(extract=True)))

    name = "copy-restricted.pdf"
    c = new_canvas(name)
    c.setFont("Helvetica-Bold", 18); c.drawString(50, H - 80, "Restricted Document")
    lines(c, 50, H - 110, ["The author disallowed text copying for this document."])
    c.showPage(); c.save()
    finalize(name, encryption=pikepdf.Encryption(user="", owner="owner-only",
                                                 allow=pikepdf.Permissions(extract=False, accessibility=False)))


# ---------------------------------------------------------------------------
# 7. unicode-normalization.pdf : ligatures, umlauts, soft hyphen.
# ---------------------------------------------------------------------------
def unicode_norm():
    name = "unicode-normalization.pdf"
    c = new_canvas(name)
    c.setFont("DejaVu-Bold", 18); c.drawString(50, H - 80, "Unicode Normalisation")
    c.setFont("DejaVu", BODY)
    y = H - 110
    for t in [
        "The \ufb01nancial \ufb02ow is reviewed monthly.",
        "Gr\u00f6\u00dfe und \u00dcbersicht der Stra\u00dfe bleiben erhalten.",
        "L\u2019\u00e9l\u00e8ve a r\u00e9ussi l\u2019examen.",
        "Infor\u00admation with a soft hyphen.",
        "Standalone marks survive : a \u2013 b . c _ d ( e ) f , g ; h \u00b7 i",
    ]:
        c.drawString(50, y, t); y -= LEADING
    c.showPage(); c.save()
    finalize(name)


# ---------------------------------------------------------------------------
# 8. invalid inputs and performance document
# ---------------------------------------------------------------------------
def invalid_inputs():
    (OUT / "not-a-pdf.pdf").write_bytes(b"This is plain text with a .pdf extension.\n")
    good = (OUT / "simple-structured.pdf").read_bytes()
    (OUT / "truncated.pdf").write_bytes(good[: len(good) // 3])


def perf():
    name = "perf-200-pages.pdf"
    c = new_canvas(name)
    filler = "Performance filler sentence used to measure extraction throughput on long documents."
    for p in range(1, 201):
        c.setFont("Helvetica-Bold", 16); c.drawString(50, H - 70, f"Chapter {p}")
        c.setFont("Helvetica", 10)
        y = H - 100
        for i in range(45):
            c.drawString(50, y, filler); y -= 15
        c.setFont("Helvetica", 8); c.drawRightString(W - 50, 30, str(p))
        c.showPage()
    c.save()
    finalize(name)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    simple_structured()
    toc()
    hidden_content()
    two_column()
    scanned("scanned.pdf", "Scanned page sample", with_layer=False)
    scanned("scanned-with-ocr-layer.pdf", "Searchable scan sample", with_layer=True)
    encrypted()
    unicode_norm()
    invalid_inputs()
    perf()
    for f in sorted(OUT.glob("*.pdf")):
        print(f"{f.name:34s} {f.stat().st_size:>9,d} bytes")


if __name__ == "__main__":
    sys.exit(main())
