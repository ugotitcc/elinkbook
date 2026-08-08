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

`app/lib/screens/reader_screen.dart` 是唯一的閱讀器入口，依副檔名分派到：
- `FoliateEpubReaderView` → `readest/foliate-js` 跑在 `flutter_inappwebview` 的 `InAppWebView` 內（所有 EPUB，含 FXL 與流式，見 ADR 0017）
- `PdfReaderView` → `pdfrx`（PDFium 透過 `dart:ffi` 直接呼叫，非 `PlatformView`，見 ADR 0022）

`PdfReaderView` 為純 Dart widget，底層 `pdfrx` 透過 FFI 直接呼叫 PDFium，不再使用原生 `PlatformView`。`content://` URI 存取走原生端 `ReaderResourceChannel.kt` 串流複製到本機暫存檔後回傳路徑。`FoliateEpubReaderView` 不是傳統 `PlatformView`，透過 `foliate_native_bridge.dart` 與原生端溝通。

### Native 層

Kotlin 原始碼位於 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/`：
- `MainActivity.kt`（`FlutterFragmentActivity`，因 `registerForActivityResult` 需要）
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

### 偏好設定系統

- `BookReaderPrefs`：單書版面偏好（`app/lib/reader/book_reader_prefs.dart`）
- `BookReaderPrefsRepository`：SQLite 持久化（`app/lib/reader/book_reader_prefs_repository.dart`）
- `GlobalReaderDefaults`：全域預設值，`shared_preferences`（`app/lib/reader/global_reader_defaults.dart`）
- `AppThemePreferences`：主題/E-Ink 模式（`app/lib/theme/app_theme_preferences.dart`）

## Testing

### 兩層架構

| 層級 | 位置 | 執行方式 | 用途 |
|------|------|----------|------|
| Unit/Widget | `app/test/` | `flutter test` | 純 Dart，不需裝置 |
| Integration | `app/integration_test/` | `flutter test -d <device-id>` | 需真機，驗證原生 PlatformView 渲染 |

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
flutter test integration_test/reader_screen_test.dart -d <device-id>  # 整合測試
flutter build apk --debug                       # 建置 debug APK
```

## Key Files

| 檔案 | 用途 |
|------|------|
| `docs/prd.md` | 完整產品需求 |
| `docs/epics.md` | Epic 狀態看板（唯一查 epic 位置的地方） |
| `CONTEXT.md` | 領域詞彙表 |
| `docs/adr/` | 架構決定紀錄（22 則） |
| `prototype/index.html` | UI/UX 原型（手機外殼模擬器） |
| `docs/agents/issue-tracker.md` | 工單追蹤系統慣例 |

## Conventions

- **語言**：程式碼註解與文件使用繁體中文
- **SDD 工作流程**：Discovery → Architecting → Issues → Plans → Implementation
- **Epic 目錄結構**：`docs/epics/<epic-name>/`（含 design.md、spec.md、issues.md、plans/、reviews/）
- **歸檔**：`docs/archive/<YYYY-MM-DD>-<簡稱>/`
- **ADR**：`docs/adr/NNNN-<title>.md`
- **Method Channel 契約**：對稱三段式（openBook → onPageRendered/onError）
- **偏好設定**：null = 不覆寫，使用預設值；非 null = 覆寫
- **`plans/plan-issue-<N>.md` 進度追蹤**：Task 底下的 Step 一旦完成，須把該 Step 前面的 `- [ ]` 改為 `- [x]`，讓計劃檔案即時反映開發進度

## Gotchas

- `flutter analyze` 必須乾淨才能提交
- Integration tests 必須指定 `-d <device-id>`，否則會找不到裝置
- 原生渲染引擎需要真實裝置檔案路徑，不能直接讀 Flutter asset（見 `stageSampleBookFile()`）
- `BookReaderPrefs.fontWeight` 使用 Readium 倍率語意（1.0 = normal），非 CSS 300-900 原始值
- `pdfrx` 透過 FFI 直接呼叫 PDFium，不走 PlatformView——勿與舊版 `PdfReaderView.kt`/`PdfReaderViewFactory.kt` 混淆（已清退）
- `foliate-js` 釘定版本會使用較新 ES 內建方法（`Object.groupBy`、`Array.prototype.at`），較舊 Android System WebView 不支援時需在 `_esCompatPolyfillJs` 補 polyfill
- `content://` URI 存取必須走原生端 `ReaderResourceChannel.kt` 串流複製到本機暫存檔，不可直接讀取
