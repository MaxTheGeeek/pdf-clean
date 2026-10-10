# 04 · UI specification

One window (macOS) / one navigation stack (iOS). Four screens following the single
flow **Open → Wait → Review → Save**. Native SwiftUI controls only, light/dark mode,
no custom web views.

## 1. Import (state `idle`)

```
┌──────────────────────────────────────────────────────────┐
│                         PDFClean                          │
│                                                           │
│   ┌───────────────────────────────────────────────────┐   │
│   │                 [doc.text icon]                    │   │
│   │        Drop a PDF here  ·  or  [ Open PDF… ]       │   │
│   │   Works offline. Nothing leaves this device.       │   │
│   └───────────────────────────────────────────────────┘   │
│                                         Options…  (gear)  │
└──────────────────────────────────────────────────────────┘
```
- macOS: the dashed drop zone highlights on drag-over (`.dropDestination`); ⌘O opens
  the file importer. iOS: big "Choose PDF" button; iPad also accepts drops.
- A non-PDF drop shows an inline error banner under the drop zone for 4 s.
- "Options…" opens `OptionsView` (macOS: Settings window, ⌘,; iOS: sheet).

## 2. Password sheet (state `awaitingPassword`)
- Title: "Password needed" (user password) or "Owner password needed" (copy
  restricted, with one-line explanation of the restriction).
- `SecureField`, buttons Cancel / Unlock (default). Wrong password: field shakes, red
  caption "That password didn't work." The password is kept only in memory for the job.

## 3. Processing (state `processing`)
```
  report-q3.pdf
  Checking visibility · page 37 of 120
  [■■■■■■■■■■■■■■□□□□□□□□□□□□]  31 %
                         [ Cancel ]
```
- Determinate `ProgressView(value:)` from `fractionCompleted`; stage label localised.
- Cancel (Esc on macOS) → back to Import within 1 s.
- VoiceOver announces stage changes (not every page).

## 4. Result (state `result`)

macOS (`NavigationSplitView`, three columns on wide windows):
```
┌ Outline ─────────┬ Preview ──────────────────────────────┬ Cleaned ─────────────┐
│ Title            │  Quarterly Infrastructure Report       │ ✓ Verified clean     │
│ 1 Introduction   │  1 Introduction                        │ Hidden words      7  │
│   1.1 Scope      │  This report summarises …              │ Invisible chars  14  │
│   1.2 Priorities │  • Migrate legacy services …           │ Repeated lines    4  │
│ 2 Results        │                                         │ …                    │
│   2.1 Outcomes   │                                         │ Source contained:    │
│                  │                                         │  metadata (6 keys),  │
│                  │                                         │  XMP, 3 annotations, │
│                  │                                         │  1 attachment        │
│                  │                                         │ Identifiers (1)      │
│                  │                                         │  ☐ 3f2a9c1e-… ×1     │
├──────────────────┴─────────────────────────────────────────┴──────────────────────┤
│ Format: [Markdown ▾]   [ Show source ]                      [ New ]  [ Save… ⌘S ]  │
└───────────────────────────────────────────────────────────────────────────────────┘
```
- **Outline**: title + headings (indented by level) + "Contents" entry when a TOC
  exists; selecting scrolls the preview (`ScrollViewReader`, block ids).
- **Preview**: native rendering — title `.largeTitle`, H1 `.title`, H2 `.title2`, H3+
  `.title3`, paragraphs `.body`, lists with markers, TOC as an indented list with
  trailing page numbers, preformatted in monospaced. Text is selectable.
  "Show source" swaps to the exact export string of the chosen format (monospaced).
- **Cleaned panel** (`ReportPanel`): badge "Verified clean" when `OutputVerifier`
  passed for the current format; non-zero counters only, each with a help tooltip
  explaining the technique in one sentence; OCR pages ("Text recognised on pages 1, 4");
  warnings; source inventory (keys/counts only); identifier list with a checkbox per
  finding and "Redact all". Redaction updates preview and export immediately.
- **Toolbar**: format picker (Markdown · HTML · Plain text), Save… (⌘S) presenting the
  system exporter with the suggested name, New (⌘N) returns to Import (asks to confirm
  if not saved).
- iOS/iPadOS: iPhone shows Preview full-screen with a toolbar menu for Outline (sheet),
  Report (sheet), Format, Save; iPad uses the split view like macOS.

## 5. Options (`OptionsView`) — all persisted in `@AppStorage` (settings only, no content)
| Option | Default |
|--------|---------|
| Text recognition (OCR): Automatic / Off / Always | Automatic |
| Recognition languages (multi-select: English, German, French, Spanish, Italian, Portuguese, Dutch, + system languages Vision supports) | English, German |
| Remove running headers, footers and page numbers | On |
| Remove repeated lines (watermarks) | On |
| Remove rotated text (diagonal watermarks) | On |
| Normalise look-alike characters | On |
| Include table-of-contents page numbers | On |
| Mark page breaks | Off |
| Neutral file name (`document-clean`) | Off |
| Default export format | Markdown |

## 6. Errors (state `failed`)
Centered icon, title and message from tech spec §8; buttons "Choose Another File" and,
where applicable, "Try Again". Never show stack traces, paths or document text.

## 7. Accessibility and keyboard
- All buttons have labels and hints; progress has an accessibility value ("31 percent").
- macOS shortcuts: ⌘O open, ⌘S save, ⌘N new, ⌘, options, Esc cancel processing.
- Dynamic Type on iOS up to accessibility sizes (layout switches to vertical stacks).
- Colour is never the only signal (icons + text for status).

## 8. Copy (English source strings; German in the String Catalog)
- "Drop a PDF here" / "PDF hier ablegen"
- "Works offline. Nothing leaves this device." / "Funktioniert offline. Nichts verlässt dieses Gerät."
- "Verified clean" / "Geprüft sauber"
- "Hidden words removed" / "Versteckte Wörter entfernt"
