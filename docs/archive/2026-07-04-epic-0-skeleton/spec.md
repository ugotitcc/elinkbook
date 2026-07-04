# Epic 0 — 技術骨架：規格 (Spec)

這是實作 `epic-0-skeleton` 的唯一事實來源。問題/解法的完整敘述請見 `design.md`，完整的架構理由請見 `docs/adr/0001-mobile-architecture.md`。

## 模組 (Modules)

- **Flutter app 外殼**（Dart）—— 最小化導航：書架/圖書庫畫面（佔位——真正的圖書庫管理是 `epic-1-library`）與設定頁佔位。
- **`ReaderScreen`**（Dart，Flutter widget）—— 本 Epic 唯一的公開 seam。接受檔案路徑、偵測格式、分派到對應的原生視圖。
- **包裝 Readium Kotlin toolkit 的原生 Android 模組** —— 向 Flutter 暴露一個 `EpubReaderView` `PlatformView`。
- **包裝 `android.graphics.pdf.PdfRenderer` 的原生 Android 模組** —— 向 Flutter 暴露一個 `PdfReaderView` `PlatformView`。

## 介面 (Interfaces)

- `ReaderScreen(filePath: String)` —— 對外契約：給定一個真實檔案路徑，渲染該書第 1 頁。內部運作：
  - 依副檔名/魔數 (magic bytes) 偵測格式。
  - `.epub` → 建立 `EpubReaderView`
  - `.pdf` → 建立 `PdfReaderView`
- Platform channel 契約（`EpubReaderView` 與 `PdfReaderView` 皆實作同一組最小介面）：
  - `openBook(path: String) -> void` —— Flutter → 原生，通知原生視圖載入並渲染第 1 頁。
  - `onPageRendered() -> void` —— 原生 → Flutter，表示渲染成功（供測試斷言畫面有內容，不需比對截圖）。
  - `onError(message: String) -> void` —— 原生 → Flutter，表示載入/渲染失敗。

## 架構決策（源自 ADR 0001，於此 Epic 範圍內重述）

- Flutter 為共用 App 外殼；EPUB 使用 Readium 官方原生 SDK（非 epub.js、非自訂解析器）；PDF 使用平台內建 API（非 PDFium）。先建置並驗證 Android，之後才做 iOS。
- 本任務不含桌面版目標。
- TXT 渲染明確排除於本 Epic 之外（獨立的未來引擎，`epic-11-txt-engine`）。
- 本任務不引入任何資料結構或持久化層——沒有 SQLite、沒有 PocketBase 串接。這些屬於後續獨立的 Epic（`epic-8-sync` 及圖書庫/註記相關 Epic）。

## 測試決策 (Testing Decisions)

- 一個好的測試在這裡驗證的是**外部、可觀察的行為**：給定一個真實檔案，`ReaderScreen` 是否確實渲染出非空白的頁面內容——而非 Readium 或 `PdfRenderer` 內部狀態的細節。
- 唯一的 seam（`ReaderScreen`）用兩個案例驗證：一次用已提交版本控制的範例 EPUB 測試檔，一次用已提交版本控制的範例 PDF 測試檔。
- **此程式碼庫中沒有既有前例可循**——這是這裡第一次寫測試。因為內容存在於 `PlatformView` 之中，一般的 Flutter widget test 很可能無法觀察到渲染出來的原生內容（widget test 執行時沒有真實的 platform view）。應使用 Flutter 的 `integration_test` 套件，在真實的 Android 模擬器/裝置上執行，並以 `onPageRendered` 是否觸發（而非 `onError`）作為通過條件，而非單純的單元測試或截圖比對。

## 範圍外 (Out of Scope)

- iOS 整合（Readium Swift toolkit、iOS PDFKit）—— `epic-13-ios`，待 Android 驗證後才進行
- TXT 自訂渲染引擎 —— `epic-11-txt-engine`
- 桌面平台（Windows/macOS/Linux）
- 本地資料庫/持久化（SQLite）、PocketBase 同步串接、全文檢索索引
- 任何版面客製化（字型、邊距、主題、直排/橫排切換、方向鎖定）—— 本任務只驗證第 1 頁能渲染，不涉及完整閱讀體驗（`epic-2`/`epic-3`）
- 註記（劃線、備註、書籤）—— `epic-6-annotations`
- 導航區域、音量鍵翻頁 —— `epic-7-interaction`
- 除了讓 seam 可被觸及所需的最小佔位畫面之外，任何 UI 潤飾

## 補充說明 (Further Notes)

延續此骨架的後續 Epic（不在本規格涵蓋範圍內）：`epic-13-ios`（iOS 整合）、`epic-11-txt-engine`（TXT 自訂引擎，可能搭配共用 Rust/C++ 核心）、`epic-8-sync`（本地資料庫 schema + PocketBase 串接），以及建立在這個地基之上的各功能 Epic（`epic-1` 至 `epic-10`、`epic-12`）。本規格核准後的下一步：Scrum Master 階段——拆解為細粒度的垂直切片工單，寫入 `issues.md`。
