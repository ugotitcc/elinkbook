# 字典功能 Phase 1：現況稽核

稽核日期：2026-10-19。範圍：唯讀。本次未修改任何程式碼。

所有路徑相對於 repo 根目錄 `U:\MyDeveloper\AI\elinkBook`。

## 1. 結論摘要

- 專案內沒有任何字典功能。`app/lib/reader/text_conversion_dict.dart` 是 OpenCC 簡繁轉換表，不是字典。
- 選字流程已經把「選取的文字」傳到 Dart 端，不需要改 JavaScript。
- 查字典按鈕可以掛在 `AnnotationToolbar`。
- 專案只有 Android（`app/android/`）。沒有 `windows/`、`ios/`。
- 主資料庫已到 `version: 28`。字典資料另開資料庫，避免動到它。
- `AndroidManifest.xml` 設了 `usesCleartextTraffic="true"`。線上查詞必須在程式碼內強制 `https`。

## 2. 架構與慣例

| 項目 | 現況 | 路徑 |
|---|---|---|
| 模組切分 | 依功能分資料夾，不是 feature-first | `app/lib/{reader,library,screens,search,sync,remote,cloud_import,downloads,stats,storage,wifi_transfer,l10n,theme}` |
| 狀態管理 | 沒有狀態管理套件。`StatefulWidget` + 建構子傳依賴 | ADR 0037 |
| 依賴注入 | 依賴依「誰在用」分組，`main()` 建一次，經建構子傳遞。不用 DI 套件、不用 `InheritedWidget` | `app/lib/screens/app_dependencies.dart`、`reader_feature_dependencies.dart`、`docs/adr/0037-*.md` |
| 依賴規則 | 組內依賴一律 non-null required | ADR 0037 §3 |
| 測試替身 | `test/support/` 的工廠建預設全 fake 的依賴組 | `app/test/support/` |
| 註解與命名 | 註解用正體中文，識別字用英文 | 全專案 |
| 多語系 | `app/lib/l10n/` 的 `.arb`，有 `en`、`zh`、`zh_CN`、`zh_TW` | `app/l10n.yaml` |

## 3. 選字與 JavaScript 橋接

資料流：

```
foliate-js (WebView iframe)
  selectionchange
    -> main.js reportSelection()                         [app/android/app/src/main/assets/foliate/main.js:1270-1317]
    -> callHandler('onSelectionChanged', cfiJson, fraction, left, top, right, bottom, text, existingAnnotationId)
    -> foliate_bridge_handlers.dart  (常數 onSelectionChanged / onSelectionCleared，行 13、18)
    -> EpubSelectionInfo.text                            [app/lib/reader/epub_selection_info.dart]
    -> ReaderScreen._handleSelectionChanged()            [app/lib/screens/reader_screen.dart:1879]
    -> _currentSelection 非 null -> 顯示 AnnotationToolbar [reader_screen.dart:2928]
```

- `EpubSelectionInfo.text` 已經是 `selection.toString()`。查字典**不需要改 `main.js`**。
- 固定版面（FXL）在 `_handleSelectionChanged` 第一行就 `return`（`reader_screen.dart:1882`）。FXL 與 CBZ 沒有選字，查字典不適用。
- TXT、MD 匯入時合成為 EPUB，和一般 EPUB 走同一條選字路徑。查字典自然涵蓋。
- PDF 有自己的選字：`PdfSelectionInfo`（`app/lib/reader/pdf_selection_info.dart`），同樣餵給 `AnnotationToolbar`（`reader_screen.dart:2950`）。
- 關閉選取：`_handleCloseAnnotationToolbar()`（`reader_screen.dart:1905`）會清 Dart 狀態並呼叫 JS 的 `window.clearSelection()`。
- 複製按鈕：`_handleCopySelection(String text)`（`reader_screen.dart:1934`）。查字典按鈕可比照這個寫法。

## 4. 閱讀器 UI 元件

- `AnnotationToolbar`（`app/lib/screens/annotation_toolbar.dart`，150 行）：兩列。第一列三色螢光筆、底線、關閉；第二列複製、備註、刪除。E-Ink 模式以邊框取代陰影（`isEinkMode`）。
- 底部面板範本：`notes_bottom_sheet.dart`、`toc_bottom_sheet.dart`、`widgets/eb_sheet_shell.dart`。
- 主題：`app/lib/theme/elink_tokens.dart`（`ElinkTokens` 為 `ThemeExtension`）。
- 設定畫面：`app/lib/screens/settings_scaffold.dart`，四分區（外觀、閱讀、同步與帳號、關於）。「閱讀」分區已有字型管理、閱讀預設值、導航熱區、朗讀語音。字典設定可放這裡。

## 5. 資料庫與儲存

- 主庫：`SqliteLibraryRepository`（`app/lib/library/sqlite_library_repository.dart`），`version: 28`，已有 FTS5。
- 全域 `databaseFactory = databaseFactoryFfi`（`app/lib/main.dart:95`），Android 也走 `sqlite3` 的 native assets（ADR 0028）。另開一個資料庫檔用同一個 `openDatabase` 即可。
- 同步表規格：`app/lib/sync/sync_table_specs.dart`。字典資料不應進同步（體積大、可能有版權）。
- 偏好設定：`shared_preferences`（例：`FullTextSearchSettingsRepository`）。
- 憑證：`flutter_secure_storage`。字典功能目前用不到。
- 字型檔案：`downloadable_font_store.dart`、`custom_fonts_repository.dart`。是「使用者匯入檔案到 App 私有目錄」的既有先例。

## 6. 依賴與平台

已有、可直接用：

- `file_picker ^11.0.2`：選檔。
- `http ^1.6.0`：網路。
- `archive ^4.0.9`：壓縮檔（StarDict 的 `.dz`、gzip 之後用得到）。
- `sqflite_common_ffi`、`sqflite`：資料庫。
- `flutter_inappwebview ^6.1.5`：顯示 MDX 的 HTML。
- `connectivity_plus`：判斷網路。

限制：

- `pubspec.yaml` 有 `win32` 相依鏈警告（`share_plus`、`package_info_plus`、`file_picker` 互相卡版本）。新增任何套件前先跑 `flutter pub get` 確認不破壞解析。
- `flutter_inappwebview_android` 用本地 patch（`app/patches/`）。
- `minSdk = 24`（`app/android/app/build.gradle.kts`）。
- 平台：只有 `android/`。CLAUDE.md 寫明初期不含桌面版。

## 7. 網路與隱私現況

- `AndroidManifest.xml` 有 `INTERNET` 權限。
- `android:usesCleartextTraffic="true"`（第 8 行）。線上查詞若只靠系統政策，`http` 也會通。必須在 Dart 端拒絕非 `https`。
- 隱私頁：`site/privacy.html`。加入線上查詞後要更新。Google Play 的資料安全表單也要對照。
- 既有線上功能（同步、OPDS、雲端匯入）都是使用者明確設定帳號或伺服器後才連線。

## 8. 測試與慣例

- `app/test/`：純 Dart 與 widget 測試，`flutter test` 執行。
- `app/integration_test/`：必須在真機或模擬器執行，WebView 渲染只能在這裡驗。
- 提交前：
  - `flutter analyze`，必須是 `No issues found!`。
  - `node tool/check_l10n_hardcoded_strings.js`：抓畫面中沒走 `AppLocalizations` 的硬編碼中文。
  - `node tool/check_integration_keys.js`：改了 `lib/` 的 Key 或 `integration_test/` 時執行。
- 測試範圍規則（CLAUDE.md）：單一任務只跑觸及的測試檔。完整 `flutter test` 只在計畫最後一個 Task 與合併前各跑一次。
- 測試固定檔：`app/test/fixtures/`。字典測試檔放同一處。

## 9. 整合點清單

| 整合點 | 路徑 | 改動 |
|---|---|---|
| 查字典按鈕 | `app/lib/screens/annotation_toolbar.dart` | 新增一個 callback `onLookupPressed` 與一顆按鈕 |
| 開啟查詢面板 | `app/lib/screens/reader_screen.dart`（約 2928、2950 行） | 傳入 callback，開底部面板 |
| 依賴組 | `app/lib/screens/reader_feature_dependencies.dart`、`app/lib/main.dart:317` | 新增 `dictionaryService` 欄位，non-null required |
| 設定入口 | `app/lib/screens/settings_scaffold.dart` | 「閱讀」分區新增「字典」項目 |
| 授權頁 | `app/lib/licenses/third_party_licenses.dart`、`app/assets/licenses/` | 新增所用套件的授權全文 |
| 隱私說明 | `site/privacy.html` | 加入線上查詞說明 |
| 多語系 | `app/lib/l10n/app_*.arb` | 新增字串 |

不需要改動：

- `main.js`、`foliate_bridge_handlers.dart`、`foliate_native_bridge.dart`（選字資料已齊全）。
- CFI、閱讀進度、劃線、TTS 相關程式碼。
- 主資料庫 schema。

## 10. 已知缺口與風險

1. **字典資料來源**：英→繁中的自由授權字典很少。見 `DICTIONARY_FORMATS_AND_LICENSES.md`。
2. **選字內容不是單字**：中文長按常選到一整句。需要長度上限與處理規則。
3. **PDF**：PDF 選字走另一條路徑。Phase 1 建議先只做 EPUB 系（含 TXT、MD），PDF 列為後續。
4. **WebView 內再開 WebView**：MDX 詞條要在第二個 `InAppWebView` 顯示。需在真機確認 E-Ink 裝置的記憶體與啟動時間。
5. **本稽核沒有實測**：`mdict_flutter`、`dict_reader` 都還沒用真實字典測過。
