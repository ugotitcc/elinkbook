# Epic 0 — 技術骨架：規格 (Spec)

This is the single source of truth for implementing `epic-0-skeleton`. See `design.md` for the problem/solution narrative and `docs/adr/0001-mobile-architecture.md` for the full architecture rationale.

## Modules

- **Flutter app shell** (Dart) — minimal navigation: a library/bookshelf screen (placeholder — real library management is `epic-1-library`) and a settings-screen placeholder.
- **`ReaderScreen`** (Dart, Flutter widget) — the single public seam of this epic. Accepts a file path, detects format, dispatches to the matching native view.
- **Native Android module wrapping Readium's Kotlin toolkit** — exposes an `EpubReaderView` `PlatformView` to Flutter.
- **Native Android module wrapping `android.graphics.pdf.PdfRenderer`** — exposes a `PdfReaderView` `PlatformView` to Flutter.

## Interfaces

- `ReaderScreen(filePath: String)` — public contract: given a real file path, renders page 1 of that book. Internally:
  - Detects format by file extension / magic bytes.
  - `.epub` → instantiates `EpubReaderView`
  - `.pdf` → instantiates `PdfReaderView`
- Platform channel contract (both `EpubReaderView` and `PdfReaderView` implement the same minimal shape):
  - `openBook(path: String) -> void` — Flutter → native, tells the native view to load and render page 1.
  - `onPageRendered() -> void` — native → Flutter, signals successful render (used by tests to assert non-blank content without a screenshot diff).
  - `onError(message: String) -> void` — native → Flutter, signals a load/render failure.

## Architectural decisions (from ADR 0001, restated for this epic's scope)

- Flutter is the shared app shell; EPUB uses Readium's official native SDK (not epub.js, not a custom parser); PDF uses the platform's built-in API (not PDFium). Android is built and verified before iOS.
- No desktop target in this task.
- TXT rendering is explicitly out of scope for this epic (separate future engine, `epic-11-txt-engine`).
- No schema or persistence layer is introduced in this task — no SQLite, no PocketBase wiring. Those are separate future epics (`epic-8-sync` and library/annotation epics).

## Testing Decisions

- A good test here verifies **external, observable behavior**: does `ReaderScreen`, given a real file, visibly render non-blank page content — not internal details of Readium's or `PdfRenderer`'s internal state.
- The single seam (`ReaderScreen`) is exercised twice: once with a committed sample EPUB fixture, once with a committed sample PDF fixture.
- **No prior art exists in this codebase** — this is the first test ever written here. Because the content lives inside a `PlatformView`, plain Flutter widget tests likely cannot observe the rendered native content (widget tests run without real platform views). Use Flutter's `integration_test` package running on a real Android emulator/device, asserting `onPageRendered` fired (rather than `onError`) as the pass condition, rather than a plain unit test or a screenshot diff.

## Out of Scope

- iOS integration (Readium Swift toolkit, iOS PDFKit) — `epic-13-ios`, after Android is proven
- TXT custom rendering engine — `epic-11-txt-engine`
- Desktop platforms (Windows/macOS/Linux)
- Local database/persistence (SQLite), PocketBase sync wiring, full-text search indexing
- Any layout customization (fonts, margins, themes, vertical/horizontal toggle, orientation lock) — this task only proves page-1 rendering, not the full reading experience (`epic-2` / `epic-3`)
- Annotations (highlights, notes, bookmarks) — `epic-6-annotations`
- Navigation zones, volume-key page turning — `epic-7-interaction`
- Any UI polish beyond the minimal placeholder screens needed to make the seam reachable

## Further Notes

Follow-up epics that build on this skeleton (not covered here): `epic-13-ios` (iOS integration), `epic-11-txt-engine` (TXT custom engine, possible shared Rust/C++ core), `epic-8-sync` (local database schema + PocketBase wiring), and the feature epics (`epic-1` through `epic-10`, `epic-12`) layered on top of this foundation. Next step after this spec is approved: Scrum Master phase — decompose into thin vertical-slice issues in `issues.md`.
