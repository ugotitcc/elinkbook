# AGENTS.md

elinkBook — Flutter Android 電子書閱讀器。直排繁體中文排版為核心差異化。

## Quick Start

```bash
cd app
flutter pub get
flutter analyze          # 必須乾淨才能提交
flutter test             # 純 Dart unit/widget tests
flutter devices          # 列出可用裝置
```

## Architecture

### 唯一 Seam：ReaderScreen

`app/lib/screens/reader_screen.dart` 是格式無關的統一入口，依 `detectBookFormat()`（`app/lib/reader/book_format.dart`，依副檔名判斷 `epub`/`pdf`/`azw3`/`cbz`/`txt`/`md`/`unknown`）與 `Book.isFixedLayout` 分派到兩條完全獨立的渲染路徑：

- **`PdfReaderView`**（`app/lib/reader/pdf_reader_view.dart`）→ `pdfrx`（PDFium 透過 `dart:ffi` 直接呼叫，非 `PlatformView`，見 ADR 0022）。功能：單頁/雙頁並列、頁碼與跳頁、`content://` URI 存取、E-Ink 影像濾鏡、智慧/手動裁切、劃線/備註/書籤、目錄、內文搜尋、縮圖快取。
  - **不可逆決策**：`Isolate.run()` 的 closure 須為獨立於 State 之外的頂層函式，參數列僅含可跨 isolate 傳遞型別——否則 Dart VM 會打包 closure 詞法作用域，牽連 `PdfPage`/`PdfDocument` 內部不可傳遞的 rxdart `BehaviorSubject` 導致執行期例外。
  - **`content://` URI 存取**：走原生端 `ReaderResourceChannel.kt` 串流複製到本機暫存檔後再開啟——`pdfrx.openCustom()` 隨機存取分段讀取已證實有 FFI 非同步限制，此為已文件記錄的回退路徑，不要嘗試改回 `openCustom()`。
  - **內文搜尋**：刻意避開 `PdfTextSearcher`/`PdfViewerController.useDocument`（`testWidgets`/fake-async 環境下有死鎖風險）。

- **`FoliateReaderView`**（`app/lib/reader/foliate_reader_view.dart`）→ **所有 Foliate 格式使用**（EPUB 流式與 FXL、KF8/AZW3、CBZ、TXT、MD），`readest/foliate-js`（釘定 commit、直接複製進版控，見 `app/android/app/src/main/assets/foliate/`）跑在 `flutter_inappwebview` 的 `InAppWebView` 內，**不是**傳統 `PlatformView`，透過 `foliate_native_bridge.dart` 與原生端溝通。TXT/MD 匯入時落地合成為 EPUB3 結構，之後與一般 EPUB 走完全相同的渲染/分頁/CFI 路徑（見 ADR 0023）。
  - **ES 兼容**：釘定版本會無條件使用較新 ES 內建方法（`Object.groupBy`、`Array.prototype.at`），較舊 Android System WebView 不支援時需在 `_esCompatPolyfillJs` 補 polyfill。**每次升級後**都要跑 `node app/tool/check_foliate_es_compat.js` 靜態掃描。

### Native 層

Kotlin 原始碼位於 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/`：
- `MainActivity.kt`（`FlutterFragmentActivity`，**不要嘗試改回 `FlutterActivity`**——資料夾匯入的 `registerForActivityResult` 依賴 `FragmentActivity`）
- `BookMetadataChannel.kt`（EPUB metadata 讀取，仍依賴 `readium-shared`/`readium-streamer`）
- `ReaderResourceChannel.kt`（`content://` URI 串流讀取）
- `ReaderViewAttachmentTracker.kt`（共用元件，音量鍵攔截狀態追蹤）

### Method Channel 契約

| 頻道 | 方向 | 用途 |
|------|------|------|
| `elinkbook/volume_key` | Dart↔Kotlin | 音量鍵翻頁、ReaderView 附加/分離通知 |
| `elinkbook/folder_picker` | Dart→Kotlin | 資料夾選擇器（SAF） |
| `elinkbook/app_info` | Dart→Kotlin | 取得 WebView 版本、Build 時間 |
| `elinkbook/fullscreen` | Dart→Kotlin | 全螢幕模式（WindowInsetsController） |
| `elinkbook/reader_resources` | Dart→Kotlin | `content://` URI 串流讀取 |

### LibraryScreen 與圖書庫管理

`app/lib/screens/library_screen.dart` 是書架畫面，資料經 `LibraryRepository`（抽象介面，`app/lib/library/library_repository.dart`；實作 `SqliteLibraryRepository`，`sqflite`）存取。核心概念：
- **`Book`**（`app/lib/library/models/book.dart`）：`filePath` 是 `content://`/`file://` URI 或本機路徑；`coverPath` 一律是本機複本。`groupName` 為單選分類，系統保留值 `BookGroup.uncategorized` 不可刪除/改名。
- **匯入**：`BookImportService`（檔案/資料夾選取，可選依資料夾名稱自動建立分類）。
- **批次操作**：長按進入選取模式，支援「移動到分類」。
- **檢視模式**：格狀/列表，由 `LibraryPreferences`（`SharedPreferences`）記住上次選擇。

### 偏好設定系統

- `BookReaderPrefs`：單書版面偏好（`app/lib/reader/book_reader_prefs.dart`）
- `BookReaderPrefsRepository`：SQLite 持久化（`app/lib/reader/book_reader_prefs_repository.dart`）
- `GlobalReaderDefaults`：全域預設值，`shared_preferences`（`app/lib/reader/global_reader_defaults.dart`）
- `AppThemePreferences`：主題/E-Ink 模式（`app/lib/theme/app_theme_preferences.dart`）

## Tech Stack（已決策）

- **App 外殼**：Flutter，跨平台共用，手機優先，Android 先於 iOS。
- **EPUB/KF8/CBZ/TXT/MD**：單引擎 `readest/foliate-js`（見 ADR 0011、ADR 0017、ADR 0023），跑在 `flutter_inappwebview` 的 `InAppWebView` 內。
- **PDF**：`pdfrx`（PDFium 透過 `dart:ffi` 直接呼叫，見 ADR 0022）。
- **Android minSdk**：24（由 Readium + integration_test 外掛下限決定）。
- **同步後端**：PocketBase。

## Testing

### 兩層架構

| 層級 | 位置 | 執行方式 | 用途 |
|------|------|----------|------|
| Unit/Widget | `app/test/` | `flutter test` | 純 Dart，不需裝置 |
| Integration | `app/integration_test/` | `flutter test -d <device-id>` | 需真機，驗證原生渲染 |

### 重要測試鍵值

- `Key('reader_loading_indicator')` — 載入中
- `Key('reader_error_text')` — 錯誤訊息

Integration test 斷言模式：等待 loading indicator 消失且無 error text。

### 範例測試檔

`app/test/fixtures/sample.epub` 與 `sample.pdf` 已在 `pubspec.yaml` 宣告為 asset。

## Commands

```bash
# 在 app/ 目錄下執行
flutter test                                    # 所有 unit tests
flutter test test/screens/reader_screen_test.dart  # 單一測試檔
flutter analyze                                 # 靜態分析，提交前必須乾淨
node tool/check_l10n_hardcoded_strings.js       # 新增/修改畫面字串或測試後、提交前：偵測未經 AppLocalizations 包裝的硬編碼中文字串、test/ 內缺 locale 的 MaterialApp
flutter test integration_test/reader_screen_test.dart -d <device-id>  # 整合測試
flutter build apk --debug                       # 建置 debug APK

# 需要測試 Google Drive/OneDrive 真實 OAuth 登入流程時
flutter run --dart-define-from-file=config/cloud_oauth.json
flutter build apk --release --dart-define-from-file=config/cloud_oauth.json
```

## Key Files

| 檔案 | 用途 |
|------|------|
| `docs/prd.md` | 完整產品需求 |
| `docs/epics.md` | Epic 狀態看板（唯一查 epic 位置的地方） |
| `CONTEXT.md` | 領域詞彙表 |
| `docs/adr/` | 架構決定紀錄（22 則） |
| `prototype/index.html` | UI/UX 原型（手機外殼模擬器），所有功能性 Epic 設計畫面須先參考 |
| `docs/agents/issue-tracker.md` | 工單追蹤系統慣例 |

## Conventions

- **語言**：程式碼註解與文件使用繁體中文
- **SDD 工作流程**：Discovery → Architecting → Issues → Plans → Implementation
- **Epic 目錄結構**：`docs/epics/<epic-name>/`（含 design.md、spec.md、issues.md、plans/、reviews/）
- **歸檔**：`docs/archive/<YYYY-MM-DD>-<簡稱>/`
- **ADR**：`docs/adr/NNNN-<title>.md`
- **Method Channel 契約**：對稱三段式（openBook → onPageRendered/onError）
- **偏好設定**：null = 不覆寫，使用預設值；非 null = 覆寫
- **`plans/plan-issue-<N>.md` 進度追蹤**：Task 底下的 Step 一旦完成，須把該 Step 前面的 `- [ ]` 改為 `- [x]`
- **審查**：先產出報告，嚴禁直接修改被審查的文件或程式碼；TUI 彙整與審查報告摘要均須明確列出 Critical / Important / Minor 數量以利判斷決策

## Gotchas

- `flutter analyze` 必須乾淨才能提交
- Integration tests 必須指定 `-d <device-id>`，否則會找不到裝置
- 原生渲染引擎需要真實裝置檔案路徑，不能直接讀 Flutter asset
- `BookReaderPrefs.fontWeight` 使用 Readium 倍率語意（1.0 = normal），非 CSS 300-900 原始值
- `pdfrx` 透過 FFI 直接呼叫 PDFium，不走 PlatformView——勿與舊版 `PdfReaderView.kt`/`PdfReaderViewFactory.kt` 混淆（已清退）
- `foliate-js` 釘定版本會使用較新 ES 內建方法，較舊 Android System WebView 不支援時需補 polyfill
- `content://` URI 存取必須走原生端 `ReaderResourceChannel.kt` 串流複製到本機暫存檔，不可直接讀取
- `MainActivity` 必須是 `FlutterFragmentActivity`（非 `FlutterActivity`）
- Android `minSdk` 是 24（非 30），由 Readium + integration_test 外掛下限決定
- `tapMaxDurationMs` PDF 端與 EPUB 端數值目前剛好相同（700ms）但校準狀態不同，PDF 端用 `clock.now()` 而非裸 `DateTime.now()`