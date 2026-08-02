# Epic 14 — 系統設定：設計 (Design)

> 本文件由 `/grill-with-docs` 2026-08-02 逐項確認產生，並於 2026-08-02 經 `/superpowers:requesting-code-review` 審查（`tmp/epic-14/review-design.md`）與 `/superpowers:receiving-code-review` 逐項核對原始碼後修訂：Critical 項目（Readium `EpubReaderView.kt`/`addFontFamilyDeclaration` 已隨 Epic 20 汰換的過時描述）確認成立並修正；核對過程中另發現審查已套用的修訂本身仍有兩處與原始碼不符（`AppFont`→family name 對照表為編造值、SharedPreferences key 命名少了既有 `global_reader_` 前綴），以及字型服務機制應比照現有 5 款內建字型的「Dart `shouldInterceptRequest` 攔截＋原生一次性讀取位元組、不落地快取」模式（`WebViewAssetLoader.InternalStoragePathHandler` 為書籍本體大檔案專用，非字型檔案適用機制），皆已一併核實修正。依「單機閱讀優先波次」排序，本 Epic 是目前唯一尚未啟動、且優先於 `epic-8-sync` 動工的 Epic（見 `docs/epics.md` 「預訂開發順序與目前進度」表）。

## 問題陳述

FR-35/36/37/38/42 要求一個集中的「系統設定」畫面，涵蓋跨書籍的全域行為：自訂字型管理、音量鍵翻頁總開關、螢幕方向/翻頁模式/全螢幕顯示的全域預設值（個別書籍可覆寫）。`SettingsScreen`（`epic-18` Issue 24 建立）目前只有「佈景」「導航熱區」「關於」三個項目，完全沒有本 Epic 相關入口。另外一項 2026-08-02 追加需求：`NavZoneSettingsScreen` 的熱區模板選擇（左翻頁/右翻頁/單手/自訂）要從純文字 `RadioListTile` 改為圖示化呈現（參考截圖 `tmp/images/導航熱區建議.jpg`）。FR-39（同步設定入口）已於 `epic-8-sync` Discovery 階段確認由該 Epic 自行處理（`SettingsScreen` 已存在，可直接加子頁面），本 Epic 不需碰。

## 範圍界定

### 包含範圍

- **字型管理**（FR-35）：`SettingsScreen` 新增獨立「字型管理」子畫面，支援上傳（`.ttf`/`.otf`，可批次多選）、清單顯示（含內建 5 款＋使用者自訂）、刪除；刪除使用中字型時比照 FR-09 規則自動退回預設字型（`fontFamily` 重置為 `null` 並觸發 SQLite 串聯更新）。
- **閱讀預設值**（FR-36/37/38/42）：`SettingsScreen` 新增獨立「閱讀預設值」子畫面，集中呈現音量鍵翻頁開關、螢幕方向 5 選一、翻頁模式 2 選一、全螢幕顯示開關（皆為全域預設值，個別書籍延用既有 `book_reader_prefs` 覆寫機制）。
- **導航熱區模板圖示化**（追加需求）：`NavZoneSettingsScreen` 的模板選擇 UI 改為「簡單／自訂」二選一 tab＋圖示卡片，底層資料模型（`NavZoneMode` 4 選一）與 9 格自訂編輯器不變。

### 明確排除

- **FR-39（同步設定入口）**——確認由 `epic-8-sync` 自行處理，本 Epic 不建立任何相關 UI 或假入口。
- **音量鍵翻頁的原生攔截邏輯本身**——`epic-7-interaction` 已完成，本 Epic 只加一顆全域開關控制既有機制的啟用/停用。
- **螢幕方向/翻頁模式的全域-單書雙層解析邏輯**——`reader_prefs_manager_impl.dart` 的 `resolve()` 已經支援（`pageTurnMode`/`screenOrientation` 皆已是雙層解析），本 Epic 只需新增 UI，不需要新增解析邏輯本身。
- **PDF 自訂字型套用**——PDF 為原生點陣圖渲染，不套用使用者選擇的字型，FR-35 只對 EPUB 生效（見決策 2）。

## 決策紀錄（Discovery 逐項確認與審查修訂）

| # | 決策點 | 採用結果 |
|---|---|---|
| 1 | `SettingsScreen` 新項目分組 | 新增 2 個獨立子畫面：**「字型管理」**（FR-35，內容複雜需要自己的畫面）與**「閱讀預設值」**（集中 FR-36/37/38/42 四項全域開關，理由是四者性質相近——皆為「跨書籍生效、個別書籍可覆寫」的全域預設值）。`SettingsScreen` 主列表最終為：佈景／字型管理／閱讀預設值／導航熱區／關於 |
| 2 | 自訂字型資料模型 | 新增 `custom_fonts` 表（`id`／`displayName`／`familyName`／`fontUri`）；`book_reader_prefs.fontFamily` 型別從 `AppFont?`（封閉列舉）改為 `String?`（family name，內建 5 款與自訂字型統一用 family name 字串表示，`AppFont` enum 僅保留供字型清單 UI 呈現用途）。刪除自訂字型時，SQLite 自動執行 `UPDATE book_reader_prefs SET font_family = NULL WHERE font_family = ?` 將使用中書籍重置為預設。**PDF 不受影響**——PDF 為原生點陣圖渲染，不套用字型設定，FR-35 只對 EPUB 生效 |
| 3 | 自訂字型檔案儲存方式 | **不複製進 App 私有目錄**，比照 ADR 0002 對書籍檔案的既有決策精神與 ADR 0021 決策：上傳時僅 `takePersistableUriPermission()` 取得永久讀取權限，`custom_fonts.fontUri` 存 `content://` URI。**服務機制比照現有 5 款內建字型的既有模式**（`foliate_native_bridge.dart` 的 `loadFlutterFontAsset()`／`foliate_epub_reader_view.dart` 的 `_shouldInterceptRequest`），而非書籍本體專用的 `WebViewAssetLoader.InternalStoragePathHandler`（後者僅用於 217MB 級大檔案的原生串流，字型檔小很多不需要）：`buildFontFaceCss()` 新增自訂字型的 `@font-face` 規則（指向新的虛擬路徑前綴，例如 `/assets/custom-fonts/<familyName>`）；`_shouldInterceptRequest` 新增對應分支，呼叫 `ReaderResourceChannel` 新增的方法（例如 `readCustomFontBytes(uri)`），原生端 `context.contentResolver.openInputStream(uri).use { it.readBytes() }` 一次性讀取後直接回傳 `WebResourceResponse`，不寫入任何快取檔案——與內建字型「每次請求即時讀取、不落地」的既有行為一致 |
| 4 | 字型上傳格式與驗證 | 限定 `.ttf`／`.otf`（`file_picker` `FileType.custom` + `allowedExtensions`）；解析字型檔 `name` table 取得實際 family name 供 Foliate-JS 註冊 `@font-face`；顯示名稱預設用檔名（去副檔名）、使用者可重新命名，不影響實際 family name。**重複上傳阻擋**：以 family name 比對 `custom_fonts` 既有記錄，重複時中止上傳並提示「此字型已存在」，不建立新記錄 |
| 5 | 批次上傳 | `file_picker` 開啟時 `allowMultiple: true`，一次可選多個字型檔；比照 `epic-21` Issue 2 的 `ImportResult` 合併訊息模式，逐一驗證後用單一合併提示呈現結果（例如「已新增 3 款字型，2 款已存在已跳過」） |
| 6 | FR-42 全域層涵蓋格式範圍 | **涵蓋全部三種格式**（EPUB 流式／FXL／PDF），不限縮在 PRD 原文字面「固定版面 EPUB／PDF」——現有單書 `fullscreen` 欄位（`epic-19`）三種格式皆已支援，若全域預設層只覆蓋 2/3 格式會比 PRD 原文更不一致。新增 `GlobalReaderPrefs.fullscreen` 欄位，`resolve()` 改為 `book.fullscreen ?? global.fullscreen`（比照 `pageTurnMode`/`screenOrientation` 既有雙層解析模式）。**PRD FR-42 文字需同步修正**（見「PRD 修正」） |
| 7 | 導航熱區模板圖示化 | 資料模型不變（`NavZoneMode` 4 選一維持），純視覺改版：畫面改為「簡單／自訂」二選一 tab，選「簡單」時橫排 3 張圖示卡片（左翻頁／右翻頁／單手，各自畫縮小版三欄示意圖＋←/≡/→圖示，取代原本 3 個 `RadioListTile`），切換模板時 `navZoneCustomActions`（自訂 9 格資料）仍完整保留於 `GlobalReaderPrefs`；選「自訂」導向現有 9 格編輯器（`nav_zone_settings_screen.dart`），並維持 Epic 7 防死鎖驗證（至少 1 格須為選單 `ZoneAction.menu`） |

## PRD 修正

- **FR-42** 原文「固定版面全螢幕顯示開關：系統設定提供全域『固定版面（如漫畫類）EPUB／PDF 是否全螢幕顯示』開關」需修正為涵蓋全部格式（含流式 EPUB），反映決策 6 與既有 `epic-19` 單書層的實際範圍；比照 `epic-7-interaction` FR-24 措辭修正的既有先例處理。

## 新增的資料模型與 SQLite Migration

- **新表 `custom_fonts`**：`id` (INTEGER PRIMARY KEY)／`displayName` (TEXT)／`familyName` (TEXT UNIQUE)／`fontUri` (TEXT, `content://`，決策 3)。
- **`book_reader_prefs.fontFamily` Migration**：型別由列舉 `AppFont?` 改為 `String?`（family name，決策 2）。SQLite 升級時（目前 `sqlite_library_repository.dart:30` 版本為 15，本 Epic 為下一個要實作的 Epic，預期升級至 v16）：
  - `AppFont` 列舉值對應轉換（取自 `app_font.dart:19-32` 現行 `AppFontFamilyName.familyName` 實際回傳值，非猜測值）：
    - `'sourceHanSans'` 轉換為 `'SourceHanSansTC'`
    - `'sourceHanSerif'` 轉換為 `'SourceHanSerifTC'`
    - `'guanKiapTsingKhai'` 轉換為 `'GuanKiapTsingKhai'`
    - `'taiwanPearl'` 轉換為 `'TaiwanPearl'`
    - `'genRyuMinTW'` 轉換為 `'GenRyuMinTW'`
  - 原為 `NULL` 者維持 `NULL`（代表延伸退回預設/書籍內建樣式）。
- **`GlobalReaderPrefs` 新增欄位與 SharedPreferences Key**（沿用 `reader_prefs_manager_impl.dart:37-39` 既有的 `global_reader_<欄位名>` 命名慣例，非另立新前綴）：
  - `volumeKeyEnabled` (`bool`，預設 `true`，SharedPreferences key: `global_reader_volume_key_enabled`)
  - `fullscreen` (`bool`，預設 `false`，SharedPreferences key: `global_reader_fullscreen`)
- 預期為一次累加式 SQLite Schema Migration（`if (oldVersion < N)`）。

## 架構影響摘要

| 模組 | 異動類型 | 說明 |
|------|---------|------|
| `SettingsScreen` | 擴充 | 新增「字型管理」「閱讀預設值」兩個入口（決策 1） |
| 新建 `FontManagementScreen` | 新建 | 字型清單（內建+自訂）、批次上傳（決策 5）、重新命名、刪除（含使用中字型退回預設 `null` 並觸發 SQLite 串聯更新，FR-09 規則） |
| 新建 `ReadingDefaultsScreen` | 新建 | 音量鍵開關、螢幕方向 5 選一、翻頁模式 2 選一、全螢幕開關，讀寫 `GlobalReaderPrefs` |
| `foliate_native_bridge.dart` | 擴充 | `buildFontFaceCss()` 新增自訂字型 `@font-face` 規則（新虛擬路徑前綴 `/assets/custom-fonts/<familyName>`），與既有內建 5 款字型規則並列產出（決策 2/3） |
| `foliate_epub_reader_view.dart` | 擴充 | `_shouldInterceptRequest` 新增自訂字型路徑分支，呼叫新增的 Dart 橋接函式取得位元組（決策 3） |
| `ReaderResourceChannel.kt` | 擴充 | 新增 `readCustomFontBytes(uri)` method（`ContentResolver.openInputStream` 一次性讀取，不落地快取，比照既有 `readAndroidAsset` 的無快取模式，而非 `cacheBookForServing` 的落地快取模式，決策 3） |
| `book_reader_prefs.dart` | 擴充 | `fontFamily` 型別改為 `String?`（決策 2），同步更新 `toMap`/`fromMap` |
| `global_reader_prefs.dart` | 擴充 | 新增 `volumeKeyEnabled`（key: `global_reader_volume_key_enabled`）與 `fullscreen`（key: `global_reader_fullscreen`）兩欄位 |
| `reader_prefs_manager_impl.dart` | 擴充 | `resolve()` 新增 `fullscreen` 雙層解析（`book.fullscreen ?? global.fullscreen`，決策 6）；`loadGlobalPrefs`/`saveGlobalPrefs` 新增對應 SharedPreferences 鍵 |
| `nav_zone_settings_screen.dart` | 擴充 | 模板選擇區塊改版為「簡單／自訂」Tab 與圖示卡片（決策 7），保留 9 格編輯器與防死鎖驗證 |
| `sqlite_library_repository.dart` | 擴充 | 新 migration：新建 `custom_fonts` 表＋`book_reader_prefs.fontFamily` 列舉轉 family name 字串遷移 |

## 已知風險 / 待 Architecting 階段確認的技術細節

- **字型檔 family name 解析**：需要在 Dart 或 Kotlin 端解析字型檔的 `name` table（TrueType/OpenType 格式），確認是否有現成套件可用（如 Dart `ttf_parser` 或 Kotlin 二進位解析），或需自行寫最小化的二進位解析器，留待 `spec.md` 確認。
- **`fontFamily` 既有資料遷移**：既有書籍的 `AppFont` 列舉值需要正確對應轉換成 Family Name 字串，需在單元測試中驗證 SQLite Migration Script 的正確性。
- **`readCustomFontBytes` 重複請求效能**：決策 3 採用「不落地、每次請求即時讀取」與內建字型一致的模式；若換頁/重新整理頻繁觸發同一字型的重複請求造成明顯延遲，是否需要加一層記憶體快取，留待 Architecting 階段依實測結果評估，非預先假設需要。

## 範圍外 (Out of Scope)

- **FR-39（同步設定入口）**——`epic-8-sync` 職責。
- **PDF 自訂字型**——PDF 不套用字型設定，見決策 2。
- **音量鍵原生攔截邏輯本身**——`epic-7-interaction` 已完成。
