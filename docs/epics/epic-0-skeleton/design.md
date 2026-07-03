# Epic 0 — 技術骨架：Flutter + Android + EPUB(Readium) + PDF 端到端

## Problem Statement

elinkBook 目前只有需求文件（`docs/prd.md`），完全沒有程式碼。過去曾嘗試以 WebView 為主的跨平台方案（Capacitor + epub.js）實作，但在直排中文文字的跳轉定位、劃線與備註一致性上反覆出現嚴重缺陷（見專案歷史 `elinkApp/docs/todo.md` 中大量相關修正紀錄）。在投入任何實際功能開發之前，需要先證明新選定的技術路線（Flutter 外殼 + 各格式專用原生渲染引擎）能夠真正整合起來、端到端運作，否則後續所有功能都建立在未經驗證的地基上。

## Solution

建立一個 Flutter 專案骨架，目標平台先鎖定 Android。整合 Readium 官方 Kotlin toolkit 作為 EPUB 的原生渲染引擎，整合 Android 系統內建的 `PdfRenderer` 作為 PDF 的原生渲染引擎，兩者都透過 Flutter 的 `PlatformView` 機制嵌入畫面。對外提供一個統一的 `ReaderScreen` 模組：給定一個書籍檔案路徑，它會自動判斷格式並顯示該書的第 1 頁。搭配一個最小可用的導覽外殼（書架畫面、設定頁佔位），讓「從書架點開一本書、看到內容渲染出來」成為一個真實、可觀察的使用者流程，而不是寫死的測試殼。

## 已探索並決定的架構方向（詳細理由見 ADR）

完整的技術選型過程與理由記錄在 [`docs/adr/0001-mobile-architecture.md`](../../adr/0001-mobile-architecture.md)。探索過程中考慮並排除了以下路線：

- **全 Web 技術跨平台殼**（Capacitor/Tauri，整個 UI 都是 WebView）— 已在先前實作中證實在直排文字互動細節上問題反覆，排除。
- **完全自寫原生排版引擎（不用任何 WebView/瀏覽器引擎）**— EPUB reflow 內容本質是 XHTML+CSS，從零重寫等於重新發明瀏覽器排版引擎，工程量對此團隊規模不可行，排除。
- **每平台各自寫原生 UI，不用 Flutter**— 會讓「圖書庫、設定、同步、書籤」這類與排版無關的一般畫面也要在每個平台重複實作，排除。

最終決定：Flutter 當共用殼；EPUB 用 Readium 官方原生 SDK（內部仍是 WebView，但成熟穩定，內建 Locator/Decorator 解決過去踩過的定位與劃線一致性問題）；PDF 用平台內建 API（Android `PdfRenderer`、iOS `PDFKit`）；TXT 留給後續獨立 Epic 處理（因為純文字沒有 HTML/CSS 複雜度，適合自寫輕量引擎）。第一波只做 Android。

## User Stories

1. As a developer, I want a Flutter project scaffolded targeting Android, so that there's a buildable, runnable starting point for the app.
2. As a developer, I want Readium's Kotlin toolkit integrated as a native Android module, so that EPUB parsing/rendering relies on a mature, purpose-built library instead of custom-built parsing.
3. As a developer, I want the Readium native reading view embedded into Flutter via a `PlatformView`, so that Flutter can host EPUB content inside its own widget tree.
4. As a developer, I want Android's native `PdfRenderer` integrated as a `PlatformView`, so that PDF pages render natively without a third-party library dependency.
5. As a developer, I want a single `ReaderScreen` abstraction that accepts a book file path and displays page 1, so that the rest of the app doesn't need to know which native engine is rendering a given format.
6. As a developer, I want `ReaderScreen` to detect whether a file is EPUB or PDF and dispatch to the matching native view, so that format-specific logic stays encapsulated behind one interface.
7. As an end user, I want to open a sample EPUB file from the library screen and see its first page rendered, so that I can confirm the app can actually display an EPUB book.
8. As an end user, I want to open a sample PDF file from the library screen and see its first page rendered, so that I can confirm the app can actually display a PDF.
9. As a developer, I want a minimal navigation shell (a library/bookshelf screen and a settings-screen placeholder), so that opening a book is a real user flow reachable from the app's normal entry point, not a hardcoded harness.
10. As a developer, I want clear module boundaries between the Flutter shell and each native reading engine, so that adding iOS, TXT, or further formats later doesn't require restructuring this skeleton.
11. As a developer, I want this skeleton runnable via the standard Flutter build/run commands on an Android emulator or device, so that there's a reproducible local development loop from day one.
12. As a developer, I want committed sample EPUB and PDF fixture files, so that the seam's tests are repeatable in CI without depending on external downloads.
13. As a product owner, I want the riskiest technical bets (Readium integration, PlatformView bridging, native PDF rendering) proven out early, so that subsequent feature work isn't blocked by an unproven foundation.

## Seam（已與使用者確認）

在 Flutter 這一側只開一個共同的最高層接縫：`ReaderScreen` — 對外的介面很單純，輸入「檔案路徑」，可觀察的外部行為是「畫面上顯示出該書第 1 頁的內容」。內部再依偵測到的格式（EPUB/PDF）分派到對應的原生 `PlatformView`。同一個 seam 用兩個測試案例驗證（EPUB fixture、PDF fixture），不需要為 EPUB 和 PDF 各自開一個接縫。細節見 `spec.md`。
