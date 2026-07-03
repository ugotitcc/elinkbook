# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

This repository currently contains only a product requirements document (`docs/prd.md`). There is no source code, build system, package manifest, or test suite yet — implementation has not started. There are no commands to build, lint, or test.

When code is added, this file should be updated with the actual commands (build/lint/test/single-test invocation) and the real project structure.

## What this product is

elinkBook (全能跨平台電子書閱讀器) is a cross-platform ebook reader whose core differentiator is correct, high-quality support for **vertical writing (直排) Traditional Chinese typography** — including proper punctuation placement (dashes, quotes) and 避頭尾 (line-breaking rules) — plus deep layout customization and seamless cross-device sync.

Full requirements live in `docs/prd.md`. Key points to know before implementing:

### Supported formats & rendering
- **ePub3** (reflowable and fixed-layout), **PDF**, **TXT** are the three core formats (P0).
- ePub: auto-detect writing direction (see FR-06). Detection method not yet decided — to be discussed separately. Rendering stack also not yet decided.
- PDF: target <2s open time for 100MB+ files; supports image filters (contrast/brightness/bold), smart/manual crop, and page-fit as default. (Rendering stack not yet decided — to be discussed separately.)
- TXT: auto-detect encoding and chapter headings to synthesize a hierarchical TOC with estimated page numbers (fixed-character-count pagination heuristic).
- File import: local file picker plus Google Drive and OneDrive cloud access. Google Drive login/auth/download must keep working on devices without Google Play Services (e.g. some E-Ink readers).

### Layout & typography
- One-tap switch between horizontal and vertical-RL layout for ePub3/TXT.
- Bundled default fonts, all rendering fully offline via local `@font-face`: 思源黑體 and 思源宋體 (open-source SIL OFL baseline) plus three commercial-licensed fonts — 原俠正楷, 台灣圓體, 源流明體. Deleting the currently-active custom font must auto-fall-back to the default font.
- Layout controls: line spacing, paragraph spacing, independent top/bottom/left/right margin sliders, page-turn mode (scroll vs. none), text alignment, 預設/直排/橫排 mode switch, screen-orientation lock (0/90/180/270°), and a "disable book CSS" toggle. Every numeric control (font size, weight, line/paragraph spacing, margins) needs +/- fine-adjustment buttons alongside its slider. When orientation is not locked, rotating the device must recompute pagination for the new viewport.
- Vertical-RL layout must not let images or headings get split across a page break.
- Theme switching: Dark, Sepia, and default Light themes, coexisting with the separate E-Ink high-contrast mode.

### Navigation, annotations, bookmarks
- Universal TOC component across all three formats, showing title + page number, must jump to the target location within 200ms.
- Bookmarks store a position (EPUB: CFI; PDF: page number; TXT: character offset) + chapter name; support rename, single delete, and "delete all bookmarks for this book." Bookmark management is in MVP scope, not a later-phase item.
- Highlights and notes are independent object types (a note does not overwrite a highlight); both must remain visually consistent when switching between vertical/horizontal layout. Support single-item edit/delete, plus bulk-delete-all for highlights and for notes separately (bulk delete gated behind a confirmation dialog).
- Highlights support multiple colors plus a distinct "highlighter" sub-type. Highlight/note positions need finer precision than bookmarks: EPUB uses CFI, PDF uses page number + in-page coordinates (not just page number), TXT uses character offset.
- A unified sidebar lists all highlights and notes (not bookmarks, which have their own separate list/view) with jump-to-location on tap.
- Markdown export covers highlights, personal notes, and the bookmark list.

### Search
- Full-text search across the whole library (title, author, in-book content), results within 500ms even at ~1,000-book library scale. Recommended approach: SQLite FTS5 (or equivalent) index. Search results must support jump-to-chapter, and must separate title/author matches from in-book content matches.

### Sync
- Sync backend decision: **PocketBase** (Firebase/Supabase were considered alternatives).
- Reading position (EPUB: CFI; PDF: page number; TXT: character offset) auto-syncs on app close / book switch, converting correctly between vertical and horizontal reading modes; target latency <2s, conflict-resolution success rate 99.9%. If the synced cloud position disagrees with the local position when a book opens, prompt the user to confirm before jumping — never overwrite silently.
- Reading-time statistics are stored locally per day and aggregated into a ~365-day heatmap/contribution-graph view (pattern reference: Readest); tapping a cell shows that day's detail. Timing must be based on detected reading activity (page turn/scroll/long-press), excluding idle or backgrounded time.

### Library management
- Bookshelf view: 6 covers per row; also a list view with metadata + progress %. The app must remember the user's last-chosen view mode.
- Cover generation strategy: ePub → embedded cover image; PDF → first-page render; TXT → dynamically generated cover from the title text.
- Sort by last-read (default), creation time, author, or title.

### Explicit non-goals (out of scope)
- No DRM circumvention (e.g., Adobe DRM).
- No ebook store / purchase or rental flows.
- No PDF content editing (text/image mutation).
- No full social platform (feed, friends) — only one-way sharing of highlights/stats as images.

### Interaction model
- Minimal, low-chrome UI; core navigation, TOC, and basic adjustments must be reachable one-handed via configurable hot zones.
- Navigation Zones: customizable 3×3 tap-grid with selectable mapping presets (traditional / one-handed / Kindle-like); in vertical-RL (RTL) mode, the tap-grid mapping must mirror left/right to match right-to-left page-turn logic.
- Volume-key page turning is required; volume keys must revert to normal system volume control once the reader screen is left.
- E-Ink-friendly high-contrast mode with reduced transition animations (avoid ghosting).
- Mobile and desktop should share equivalent button/menu layout logic to minimize cross-device relearning.

## Working in this repo right now

Since there is no code yet, treat tasks here as either (a) refining `docs/prd.md` itself, or (b) scaffolding a new implementation from scratch. If scaffolding, check with the user on platform/framework choice (the PRD implies a cross-platform app with a WebView-based ePub renderer and native PDF rendering, but does not mandate a specific framework) before committing to a stack.
