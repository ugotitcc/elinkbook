# Epic 66 Issue 13：Windows integration_test 冒煙測試執行報告

- **執行日期**：2026-11-09
- **測試環境**：Windows 11，Flutter 3.47.9，Dart 3.13.7，WebView2 (本機版本)，Debug 建置
- **限制說明**：本報告結果僅代表本機開發環境、debug 版與本機 WebView2，未外推至乾淨機器或 release 版。

---

## 基準線與失敗分類總覽

### 基準線盤點 (2026-11-09)
- 通過檔案 (19 支):
  - `smoke_test.dart`
  - `foliate_epub_reader_view_test.dart`
  - `pdf_highlights_notes_test.dart`
  - `foliate_txt_test.dart`
  - `foliate_md_test.dart`
  - `foliate_cbz_test.dart`
  - `foliate_kf8_test.dart`
  - `epub_pagination_test.dart`
  - `epub_dual_page_test.dart`
  - `fxl_bookmarks_test.dart`
  - `notes_bookmark_test.dart`
  - `pdf_nav_zone_test.dart`
  - `reader_footer_test.dart`
  - `reading_position_test.dart`
  - `foliate_navigation_degrade_test.dart`
  - `foliate_single_column_test.dart`
  - `foliate_stream_nav_zone_test.dart`
  - `foliate_margin_test.dart`
  - `markdown_export_test.dart`
- 失敗檔案 (8 支):
  - Task 2: `epub_fxl_tap_zone_test.dart`、`foliate_toc_footer_test.dart`、`pdf_reader_view_test.dart`
  - Task 3: `epub_toc_test.dart`、`epub_highlights_notes_test.dart`、`foliate_highlights_notes_test.dart`、`reader_screen_test.dart`
  - Task 4: `library_screen_test.dart`

---

## Task 2 診斷紀錄（「無法載入書籍」）

### 1. `epub_fxl_tap_zone_test.dart` & `foliate_toc_footer_test.dart`
- **失敗現象**：開書渲染完成後，`onError` 回呼被觸發，收到錯誤訊息「無法載入書籍」（`readerFailedToLoadBookMessage`）。在 `foliate_toc_footer_test.dart` 中 4 個測試有 3 個以此錯誤失敗。
- **根因分析**：
  - 在 `app/lib/reader/foliate_reader_view.dart:887` 中：
    ```dart
    controller.addJavaScriptHandler(
      handlerName: FoliateBridgeHandlers.onLocatorChanged,
      callback: (args) =>
          widget.onLocatorChanged?.call(parseLocatorChanged(args)),
    );
    ```
  - 當呼叫端（測試中）以單行賦值語法提供回呼時：`onLocatorChanged: (info) => lastPosition = info`，Dart 的賦值運算式 `lastPosition = info` 會將賦值結果（即 `EpubPositionInfo` 實例）作為 closure 的回傳值。
  - 因為 `callback` 採用箭頭語法 `=>`，該 `EpubPositionInfo` 物件被直接當作 JavaScript Handler 的回傳值交給 `flutter_inappwebview` 橋接層。
  - `flutter_inappwebview`（Windows WebView2）在將回傳值序列化回傳給 JS 端 `window.flutter_inappwebview.callHandler()` 時呼叫 `jsonEncode`，因 `EpubPositionInfo` 非 JSON 原生結構而拋出例外：
    `Unhandled Promise Rejection: error, Exception: Converting object to an encodable object failed: Instance of 'EpubPositionInfo'`。
  - JS 端捕獲 unhandledrejection 後調用 `onError`，導致 Dart 端接收到「無法載入書籍」假性開書錯誤。
- **修復方案**：在 `foliate_reader_view.dart` 中將 `onLocatorChanged` 的 callback 改為區塊語法 `{ widget.onLocatorChanged?.call(...); return null; }`，明確回傳 `null`，避免洩漏非 encodable 物件給 JS 橋接層。
- **修復分類**：類別 B（Windows / WebView2 橋接序列化相容問題，產品程式修復）。
- **驗證結果**：`epub_fxl_tap_zone_test.dart` 通過（1/1），`foliate_toc_footer_test.dart` 全數通過（4/4）。

### 2. `pdf_reader_view_test.dart`
- **失敗現象**：第 3 個測試「開啟以 file:// URI 表示的有效 PDF 檔案觸發 onPageRendered」失敗，`onError` 出現「無法載入書籍」。其餘 3 個案例通過。
- **根因分析**：
  - 在 `app/lib/reader/pdf_reader_view.dart:862` 中：
    ```dart
    final document = widget.filePath.contains('://')
        ? await _openContentUriDocument()
        : await PdfDocument.openFile(widget.filePath);
    ```
  - 測試傳入 `file:///C:/...`，因 `contains('://')` 為 true 被誤導流至 `_openContentUriDocument()`。
  - `_openContentUriDocument()` 呼叫原生 MethodChannel `elinkbook/reader_resources` 之 `copyToTemp`（僅存在於 Android 原生端），在 Windows 上拋出 `MissingPluginException` 並落入 catch 觸發 `onError`。
- **修復方案**：在 `pdf_reader_view.dart` 檢查路徑若以 `file://` 開頭，先以 `Uri.parse(widget.filePath).toFilePath()` 轉換為本機檔案系統絕對路徑，直接以 `PdfDocument.openFile` 開啟；僅非 `file://` 之 URI（如 `content://`）才導向 `_openContentUriDocument()`。
- **修復分類**：類別 B（Windows 跨平台路徑解析問題，產品程式修復）。
- **驗證結果**：`pdf_reader_view_test.dart` 全數通過（4/4）。


