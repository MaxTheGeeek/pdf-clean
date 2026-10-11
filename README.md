# PDFClean

Offline macOS and iOS/iPadOS app that extracts the **visible** text of a PDF as a clean,
structured document — title, headings, table of contents, paragraphs, lists — and
removes everything hidden: invisible or white text, covered/clipped/off-page/tiny text,
diagonal and per-recipient watermarks, zero-width and Unicode-tag characters, bidi
controls, look-alike characters, metadata, XMP, annotations, form values and
attachments.

**Open PDF → wait → review what was removed → save as Markdown, HTML or plain text.**
Nothing leaves the device: the macOS app is sandboxed without network access, and the
code contains no networking at all.

> Status: specification and scaffold complete; implementation proceeds task by task
> (`specs/06-tasks.md`), driven by Claude Code.

## Requirements
- macOS 14+ with **Xcode 16+** (Swift 6 toolchain) — needed for every build
- Homebrew (for XcodeGen) and Python 3.10+ (fixtures only)
- VS Code with the recommended extensions (Swift, Claude Code) — optional but configured

## Quick start
```bash
make bootstrap      # installs XcodeGen, creates .venv for fixture tools
make verify         # spec traceability + offline gate + lint + package tests
make build-mac      # generates PDFClean.xcodeproj and builds the macOS app
make build-ios      # builds the iOS app for the simulator
```
Open in Xcode: `make generate && open PDFClean.xcodeproj` (schemes `PDFClean-macOS`,
`PDFClean-iOS`). For device builds set `DEVELOPMENT_TEAM` in `project.yml` (or in Xcode
› Signing & Capabilities) and regenerate.

## Working with Claude Code (spec-driven)
Open the folder in VS Code (Claude Code extension) or run `claude` in it. `CLAUDE.md`
loads automatically and points to the specs.

| Command | What it does |
|---------|--------------|
| `/status` | progress per phase and the next unblocked task |
| `/next-task` | picks and implements the next task end to end |
| `/implement-task T-031` | implements one specific task |
| `/verify` | runs every gate and explains failures |
| `/spec-change "<change>"` | updates requirements → tests → tasks before any code |

Review agents: `spec-reviewer` (conformance to the specs) and `sanitization-auditor`
(adversarial hunt for hidden-content leaks). Suggested loop per task:
`/next-task` → review → "use the spec-reviewer agent" → commit.

## Repository map
| Path | Content |
|------|---------|
| `specs/00-constitution.md` | non-negotiable principles |
| `specs/01-requirements.md` | 24 functional + 9 non-functional requirements with acceptance criteria |
| `specs/02-technical-spec.md` | architecture, public API, algorithms, constants |
| `specs/03-sanitization-spec.md` | threat catalogue (T1–T22) and exact removal rules |
| `specs/04-ui-spec.md` | screens, states, options, accessibility |
| `specs/05-test-plan.md` | 45 test cases, fixture harness rules, manual QA |
| `specs/06-tasks.md` | 43 tasks in 7 phases with dependencies and done criteria |
| `specs/adr/` | architecture decisions (native Swift, raster visibility, formats, permissions, SDD) |
| `Packages/PDFCleanKit/` | Swift package: core library, `pdfclean` CLI, tests, fixtures |
| `App/` | SwiftUI app shared by macOS and iOS |
| `scripts/` | gates, fixture generator/verifier, executable reference of the visibility algorithm |

## GitHub Actions
Pushes and pull requests to `main` run `make verify` and build downloadable macOS DMG and
iPhone Simulator ZIP artifacts. These are unsigned CI builds; the simulator ZIP cannot be
installed on a physical iPhone.

To build a signed iPhone IPA for TestFlight/App Store Connect, configure the `ios-signing`
GitHub environment with `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64`,
`IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_APP_STORE_PROFILE_BASE64`, and `IOS_TEAM_ID`,
then run **iOS device IPA** manually with `build_ipa` enabled. Use an Apple Distribution
certificate and an App Store provisioning profile matching the app bundle ID. The workflows
create build artifacts only; macOS notarization and App Store upload are not configured.

## Test fixtures
`Packages/PDFCleanKit/Tests/PDFCleanKitTests/Fixtures/` holds 12 generated PDFs and
`manifest.json` (15 cases) describing exactly what each output must and must not
contain. `hidden-content.pdf` plants 22 canary strings using every hiding technique;
none may appear in any export. `make fixtures-verify` proves — with extractors
independent of PDFKit — that every canary really exists in the source and that the
visibility algorithm removes hidden words without touching visible ones.

## Limitations (v1)
Tables are kept as preformatted text, images are dropped, DOCX/PDF export is in the
backlog, and hidden text deliberately placed on top of other visible ink can survive
(see `specs/03-sanitization-spec.md` §3.3, §8). PDFs that forbid copying are processed
only with the owner password.

Fixture fonts: DejaVu Sans (see `scripts/fixtures/fonts/LICENSE-DejaVu.txt`).
