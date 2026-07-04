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

1. 身為開發者，我希望有一個針對 Android 建置好的 Flutter 專案骨架，以便有一個可建置、可執行的起點。
2. 身為開發者，我希望把 Readium 的 Kotlin toolkit 整合為原生 Android 模組，以便 EPUB 解析/渲染依賴成熟、專門打造的函式庫，而非自行拼湊的解析邏輯。
3. 身為開發者，我希望 Readium 的原生閱讀視圖透過 `PlatformView` 嵌入 Flutter，以便 Flutter 能在自己的 widget 樹中承載 EPUB 內容。
4. 身為開發者，我希望把 Android 原生的 `PdfRenderer` 整合為 `PlatformView`，以便 PDF 頁面能原生渲染、不依賴第三方函式庫。
5. 身為開發者，我希望有一個單一的 `ReaderScreen` 抽象層，接受書籍檔案路徑並顯示第 1 頁，以便 App 其餘部分不需要知道是哪個原生引擎在渲染特定格式。
6. 身為開發者，我希望 `ReaderScreen` 能偵測檔案是 EPUB 還是 PDF，並分派到對應的原生視圖，以便格式專屬的邏輯能封裝在單一介面之後。
7. 身為終端使用者，我希望能從書架畫面開啟一個範例 EPUB 檔案並看到第一頁渲染出來，以便確認 App 真的能顯示 EPUB 書籍。
8. 身為終端使用者，我希望能從書架畫面開啟一個範例 PDF 檔案並看到第一頁渲染出來，以便確認 App 真的能顯示 PDF。
9. 身為開發者，我希望有一個最小可用的導航外殼（書架畫面與設定頁佔位），以便開啟一本書是從 App 正常入口就能觸及的真實使用者流程，而非寫死的測試殼。
10. 身為開發者，我希望 Flutter 外殼與各原生閱讀引擎之間有清楚的模組邊界，以便之後新增 iOS、TXT 或其他格式時不需要重構這個骨架。
11. 身為開發者，我希望這個骨架能透過標準的 Flutter build/run 指令在 Android 模擬器或裝置上執行，以便從第一天起就有可重現的本機開發循環。
12. 身為開發者，我希望有已提交版本控制的範例 EPUB 與 PDF 測試檔案，以便這個 seam 的測試在 CI 中可重複執行、不依賴外部下載。
13. 身為產品負責人，我希望最高風險的技術賭注（Readium 整合、PlatformView 橋接、原生 PDF 渲染）能及早被驗證，以便後續功能開發不會建立在未經驗證的地基上。

## Seam（已與使用者確認）

在 Flutter 這一側只開一個共同的最高層接縫：`ReaderScreen` — 對外的介面很單純，輸入「檔案路徑」，可觀察的外部行為是「畫面上顯示出該書第 1 頁的內容」。內部再依偵測到的格式（EPUB/PDF）分派到對應的原生 `PlatformView`。同一個 seam 用兩個測試案例驗證（EPUB fixture、PDF fixture），不需要為 EPUB 和 PDF 各自開一個接縫。細節見 `spec.md`。
