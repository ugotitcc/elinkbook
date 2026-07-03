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
- ePub: auto-detect writing direction (see FR-06); detection method itself not yet decided. Rendering stack decided — see "Tech stack (decided)" below (Readium).
- PDF: target <2s open time for 100MB+ files; supports image filters (contrast/brightness/bold), smart/manual crop, and page-fit as default. Rendering stack decided — see "Tech stack (decided)" below (platform-native APIs).
- TXT: auto-detect encoding and chapter headings to synthesize a hierarchical TOC with estimated page numbers (fixed-character-count pagination heuristic).
- File import: local file picker plus Google Drive and OneDrive cloud access. Google Drive login/auth/download must keep working on devices without Google Play Services (e.g. some E-Ink readers).

### Layout & typography
- One-tap switch between horizontal and vertical-RL layout for ePub3/TXT.
- Bundled default fonts, all rendering fully offline via local `@font-face`: 思源黑體 and 思源宋體 (open-source SIL OFL baseline) plus three commercial-licensed fonts — 原俠正楷, 台灣圓體, 源流明體. Deleting the currently-active custom font must auto-fall-back to the default font.
- Layout controls: line spacing, paragraph spacing, independent top/bottom/left/right margin sliders, page-turn mode (scroll vs. none), text alignment, 預設/直排/橫排 mode switch, screen-orientation lock (0/90/180/270°), and a "disable book CSS" toggle. Every numeric control (font size, weight, line/paragraph spacing, margins) needs +/- fine-adjustment buttons alongside its slider. When orientation is not locked, rotating the device must recompute pagination for the new viewport.
- Vertical-RL layout must not let images or headings get split across a page break.
- Punctuation must rotate/center correctly for vertical CJK typesetting, and line-breaking must follow 避頭尾 rules (forbidden line-start/line-end characters), conforming to CNS 11643 or an equivalent standard (FR-32).
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

There is no code yet. Treat tasks here as either (a) refining `docs/prd.md` itself, or (b) starting implementation via the SDD workflow below (see `docs/epics.md` for what's next).

### Tech stack (decided)

- **App shell**: Flutter, shared across platforms.
- **Mobile-first, Android before iOS.** No desktop target in the first waves (see `docs/epics.md` epic-13).
- **EPUB**: Readium's official native toolkits (`readium-kotlin-toolkit` on Android, `readium-swift-toolkit` on iOS) — not a custom parser, not a WebView library like epub.js. Rendered via Flutter `PlatformView`, using Readium's Locator (CFI-equivalent) and Decorator (highlight/note overlay) APIs.
- **PDF**: each platform's built-in API (Android `PdfRenderer`, iOS `PDFKit`), not PDFium, rendered via `PlatformView`.
- **TXT**: a custom lightweight vertical-CJK layout engine (separate epic — `epic-11-txt-engine`), not Readium/WebView-based, since plain text has no HTML/CSS layer to reimplement.
- Rationale: a prior WebView-based attempt (Capacitor + epub.js) produced recurring defects in vertical-text jump-navigation and highlight/note consistency (see project history). Rebuilding EPUB's full XHTML/CSS reflow engine from scratch (to avoid WebView entirely) was rejected as infeasible for this team size — that's effectively reimplementing a browser layout engine. Readium is the middle path: WebView-based internally, but a mature, purpose-built SDK instead of DIY glue code.

## Spec-Driven Development (SDD) 工作流程

This repo follows a Spec-Driven Development workflow combining BMad Method's role separation, Matt Pocock's spec-first rigor, and Superpowers' review skills. Two implementers can execute work: **Claude Code** and **Antigravity CLI**. Switching to Antigravity CLI is always manual and human-initiated — never assume or trigger it. When a "developer" subagent is dispatched without the human explicitly invoking Antigravity CLI, use a Claude Code subagent (the same LLM/tool currently active), not a simulated Antigravity call.

### Directory structure

```
docs/
├── adr/                    # Global: architecture decision records
├── epics/                  # Active epic sandboxes (design.md, spec.md, issues.md, plans/, reviews/)
├── archive/                # Completed epics, moved here as <YYYY-MM-DD>-<short-name>/
├── prd.md                  # Global: product requirements
├── CONTEXT.md              # Global: ubiquitous language + code constraints (not created yet)
└── epics.md                # Global: epic status board — see below
```

### `docs/epics.md` — the global status board

Every epic gets one row: code/name, status, current storage path, linked PRD section, notes.

- ⚪ **Backlog** — planned, not started, no directory yet
- 🟡 **Active** — design/spec/coding in progress, lives under `docs/epics/<epic-name>/`
- 🟢 **Archived** — merged and stable, moved to `docs/archive/<YYYY-MM-DD>-<short-name>/`

Register a new epic here (status `Active`, path filled in) *before* starting its Discovery phase. Update status/path to `Archived` when archiving. This file is the single place to find "what epic am I looking for and where does it currently live" — see current epic list and priority order in `docs/epics.md` itself.

### Lifecycle

1. **Task classification** (human): new feature/refactor → new epic; bugfix → find the affected epic, work under its `reviews/`.
2. **Discovery** (Claude Code, as PM/Analyst) — `/brainstorming` + `/grill-with-docs` → `docs/epics/<epic-name>/design.md`. Bugfixes skip to `/diagnose` → `docs/epics/<epic-name>/reviews/bugfix-repro.md` instead.
3. **Architecting** (Claude Code, as Architect) — write an ADR if the architecture changes, and define core interfaces/types in `docs/epics/<epic-name>/spec.md` (single source of truth for the epic from here on).
4. **Scrum Master phase** (Claude Code) — decompose the epic into thin vertical-slice issues in `docs/epics/<epic-name>/issues.md`, each with its required unit-test coverage.
5. **Planning & review** (implementer as author, Claude Code as reviewer) — implementer claims an issue, writes `docs/epics/<epic-name>/plans/plan-issue-<N>.md`, requests review (`requesting-code-review`/`receiving-code-review`) before coding starts.
6. **TDD coding & QA** (implementer as author, Claude Code as reviewer) — red-green-refactor, then code review; results archived to `docs/epics/<epic-name>/reviews/review-issue-<N>.md`; hand off to the human for merge.
7. **Archiving** (human-directed) — move the whole epic directory to `docs/archive/<YYYY-MM-DD>-<short-name>/`, update its `docs/epics.md` row to `Archived` with the new path.

## Agent skills

### Issue tracker

Local markdown under `docs/epics/<epic-name>/` (SDD epic sandbox), not Gitea. Gitea (`git.jigong.org/huthief/elinkBook`, via `tea` CLI logged in as `jigong`) remains the git remote for code only. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`) — not yet created on the repo. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` + `docs/adr/` at repo root (neither exists yet). See `docs/agents/domain.md`.
