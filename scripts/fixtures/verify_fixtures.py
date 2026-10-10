#!/usr/bin/env python3
"""
Proves the fixtures are meaningful, using extractors independent of PDFKit:

1. every `mustNotContain` string really exists in the SOURCE (text layer, metadata,
   XMP, annotations, form fields or attachments) -> a naive extractor would leak it;
2. every `mustContain` phrase is recoverable from the text layer by a simple
   reference cleaner (so expectations are achievable), except OCR-only fixtures;
3. encryption / permission / error fixtures behave as declared;
4. `mustNotContainCodepoints` exist in the source text layer where declared.

Exit code 0 = all fixtures valid. Run: make fixtures-verify
"""
from __future__ import annotations

import json
import re
import sys
import unicodedata
from pathlib import Path

import logging

import pikepdf
from pdfminer.high_level import extract_text

logging.getLogger("pdfminer").setLevel(logging.ERROR)
FIX = Path(__file__).resolve().parents[2] / "Packages/PDFCleanKit/Tests/PDFCleanKitTests/Fixtures"
HOMOGLYPHS = {"а": "a", "о": "o", "е": "e", "р": "p", "с": "c", "х": "x"}


def all_source_strings(path: Path, password: str = "") -> str:
    """Text layer + every decoded object/stream in the file."""
    parts = []
    try:
        parts.append(extract_text(str(path), password=password))
    except Exception:
        pass
    with pikepdf.open(str(path), password=password) as pdf:
        for obj in pdf.objects:
            try:
                if isinstance(obj, pikepdf.Stream):
                    parts.append(obj.read_bytes().decode("latin-1", "ignore"))
                else:
                    parts.append(str(obj))
            except Exception:
                continue
        for name, spec in pdf.attachments.items():
            parts.append(spec.get_file().read_bytes().decode("latin-1", "ignore"))
    return "\n".join(parts)


def reference_clean(text: str) -> str:
    out = []
    for ch in text:
        cp = ord(ch)
        if 0xE0000 <= cp <= 0xE007F or unicodedata.category(ch) == "Cf":
            continue
        out.append(HOMOGLYPHS.get(ch, ch))
    t = unicodedata.normalize("NFKC", "".join(out))
    t = re.sub(r"(\w)-\n(\w)", r"\1\2", t)          # de-hyphenate
    return re.sub(r"\s+", " ", t)


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def main() -> int:
    manifest = json.loads((FIX / "manifest.json").read_text(encoding="utf-8"))
    failures = []
    for fx in manifest["fixtures"]:
        fid, path = fx["id"], FIX / fx["file"]
        pw = fx.get("password", "")
        err = fx.get("expectError")
        try:
            if err == "notAPDF":
                ok = not path.read_bytes().startswith(b"%PDF-")
                (failures.append(f"{fid}: file has a PDF header") if not ok else None)
                print(f"ok  {fid}: not a PDF"); continue
            if fx.get("expectNoCrash"):
                print(f"ok  {fid}: no-crash case ({path.stat().st_size} bytes)"); continue
            if err in ("passwordRequired", "wrongPassword"):
                try:
                    pikepdf.open(str(path), password=pw)
                    failures.append(f"{fid}: opened without the right password")
                except pikepdf.PasswordError:
                    print(f"ok  {fid}: {err}")
                continue
            if err == "copyingNotPermitted":
                with pikepdf.open(str(path)) as pdf:
                    if pdf.allow.extract:
                        failures.append(f"{fid}: extraction is allowed")
                    else:
                        print(f"ok  {fid}: extraction permission is off")
                continue

            if fx.get("ownerPasswordCase"):
                with pikepdf.open(str(path), password=pw) as pdf:
                    if not pdf.owner_password_matched:
                        failures.append(f"{fid}: password is not the owner password")
            source = all_source_strings(path, pw)
            for s in fx.get("mustNotContain", []):
                if s not in source:
                    failures.append(f"{fid}: canary {s!r} is NOT in the source - test would be meaningless")
            for cp in fx.get("mustNotContainCodepoints", []):
                if chr(int(cp, 16)) not in source:
                    failures.append(f"{fid}: code point U+{cp} not in source text layer")
            if fx.get("ocrPages"):
                txt = extract_text(str(path), password=pw)
                if txt.strip():
                    failures.append(f"{fid}: OCR fixture unexpectedly has a text layer")
            else:
                cleaned = reference_clean(extract_text(str(path), password=pw))
                for phrase in fx.get("mustContain", []):
                    if norm(phrase) not in cleaned:
                        failures.append(f"{fid}: phrase not recoverable by reference cleaner: {phrase!r}")
                for a in [fx.get("title")] + [h[1] for h in fx.get("headings", [])]:
                    if a and a not in cleaned:
                        failures.append(f"{fid}: heading/title not in text layer: {a!r}")
            inv = fx.get("sourceInventory")
            if inv:
                with pikepdf.open(str(path), password=pw) as pdf:
                    actual = {
                        "hasXMP": "/Metadata" in pdf.Root,
                        "hasOutline": "/Outlines" in pdf.Root and len(pdf.open_outline().root) > 0,
                        "hasFormFields": "/AcroForm" in pdf.Root,
                        "embeddedFileCount": len(pdf.attachments),
                        "annotationCount": sum(len(pg.get("/Annots", [])) for pg in pdf.pages),
                        "metadataKeys": {str(k)[1:] for k in pdf.docinfo.keys()},
                    }
                for key, want in inv.items():
                    if key == "minAnnotationCount":
                        ok = actual["annotationCount"] >= want
                    elif key == "metadataKeysInclude":
                        ok = set(want) <= actual["metadataKeys"]
                    else:
                        ok = actual[key] == want
                    if not ok:
                        failures.append(f"{fid}: sourceInventory.{key} expected {want}, source has {actual.get(key, actual)}")
            print(f"ok  {fid}")
        except Exception as e:  # noqa: BLE001
            failures.append(f"{fid}: {type(e).__name__}: {e}")
    if failures:
        print("\nFIXTURE PROBLEMS:")
        for f in failures:
            print("  -", f)
        return 1
    print(f"\nAll {len(manifest['fixtures'])} fixture cases verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
