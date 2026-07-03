# ADR 0001: Mobile Architecture — Flutter Shell, Readium for EPUB, Platform-Native PDF

## Status

Accepted

## Context

elinkBook has no code yet. A prior implementation attempt (documented in the project's history, `elinkApp/docs/todo.md`) used a WebView-based cross-platform stack (Capacitor + epub.js) and repeatedly hit defects specifically in the areas that matter most for this product: vertical (直排) CJK text jump-navigation, and highlight/note consistency across vertical/horizontal layout switches. The core product differentiator is high-quality vertical Traditional Chinese typography (FR-32: punctuation rotation, 避頭尾 line-breaking), so the rendering approach for reading content is the highest-risk architectural decision in the project.

Two extremes were considered and rejected:

- **Fully custom native rendering with no browser engine at all** (writing an EPUB reflow — i.e. XHTML/CSS — layout engine from scratch in Rust/C++ or per-platform native code): rejected as infeasible for this team size. EPUB reflowable content is XHTML+CSS; a from-scratch renderer means reimplementing HTML parsing, CSS cascade, box-model layout, and text shaping — effectively cloning a browser's layout engine. No mainstream EPUB reader (Apple Books, Kobo, Kindle) does this.
- **Fully native, per-platform UI with no shared shell** (separate Swift/iOS and Kotlin/Android apps, each reimplementing the entire app — library, settings, sync, bookmarks, stats — independently): rejected because it multiplies every future feature's implementation cost by the number of platforms, indefinitely, not just the reading engine.

## Decision

- **App shell**: Flutter, shared across platforms, hosting all non-reading UI (library, settings, sync status, bookmark/highlight/note lists, reading stats, about page).
- **EPUB rendering**: Readium's official native SDKs — `readium-kotlin-toolkit` (Android) and `readium-swift-toolkit` (iOS, later). These are WebView-based internally (WKWebView/Android WebView) but are mature, purpose-built, and used in production readers (Thorium Reader, Palace/SimplyE). They provide `Locator` (CFI-equivalent positioning) and `Decorator` (highlight/note overlay) APIs — the exact subsystems that caused defects in the prior DIY (epub.js) attempt. Embedded into Flutter via `PlatformView`.
- **PDF rendering**: each platform's built-in API — Android `PdfRenderer`, iOS `PDFKit` — not a third-party library like PDFium. Simpler integration; platform APIs are sufficient for the fixed-layout, non-reflow nature of PDF. Embedded into Flutter via `PlatformView`.
- **TXT rendering**: a custom lightweight vertical-CJK text layout engine (separate future epic, `epic-11-txt-engine`). Unlike EPUB, plain text has no HTML/CSS layer to reimplement, so a from-scratch engine is tractable here — this is the one format where custom native rendering (potentially a shared Rust/C++ core) is actually justified.
- **Platform priority**: Android first, iOS second (`epic-13-ios`, deliberately last in the epic order). No desktop target in the initial waves — Readium's tooling and community support are strongest on mobile.

## Consequences

- EPUB and PDF integration code is inherently per-platform native (Kotlin for Readium/PdfRenderer on Android, later Swift for Readium/PDFKit on iOS) regardless of the Flutter shell — the shell's value is in not having to rewrite the other ~70% of the app (library, settings, sync, bookmarks, stats) per platform.
- Because Readium still uses a WebView internally, this does not eliminate WebView-related risk entirely — it trades a DIY WebView integration for a mature, purpose-built one. If Readium's vertical-writing or Decorator support proves insufficient during `epic-0-skeleton` or `epic-2-vertical-core`, this ADR should be revisited.
- No shared Rust/C++ core is introduced for EPUB or PDF. A shared core remains an option worth reconsidering specifically for the TXT engine (`epic-11-txt-engine`), where the "write once, no HTML/CSS complexity" argument actually holds.
- Local database (SQLite), sync (PocketBase) integration, and state management choices are not covered by this ADR — they are separate decisions for later epics.

## Alternatives considered

- Capacitor/Tauri + web-tech UI (whole app, not just EPUB, in a WebView): rejected based on prior implementation history in this exact area.
- Flutter + Flutter's own text engine for everything (no PlatformView, no Readium): rejected — Flutter's Skia-based text engine lacks mature vertical-writing-mode support, which is the product's core differentiator.
- PDFium (bridged via FFI or a native plugin) instead of platform-native PDF APIs: rejected for this first pass in favor of the simpler platform-native integration; can be revisited if platform APIs prove insufficient for FR-11's image-filter/crop requirements.
