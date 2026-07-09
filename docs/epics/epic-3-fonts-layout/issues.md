# Epic 3 — 字型與版面設定：工單清單 (Issues)

依 `spec.md`（搭配 `design.md`、`docs/adr/0005-epub-page-margins-single-value.md`、`docs/adr/0006-epub-reader-batch-preferences-contract.md`）拆解出的細粒度垂直切片工單。Issue 1 為起始工單；Issue 2 依賴 Issue 1；Issue 3、Issue 4 依賴 Issue 2；Issue 5 只依賴 Issue 1，可與 Issue 2/3/4 平行進行；Issue 6 為收尾工單，依賴 Issue 2-5 全部完成。

---

## Issue 1：資料層基礎建設——BookReaderPrefs 與全域偏好設定儲存（已完成，合併於 PR #25）

**依賴：** 無（起始工單）

**描述：**
建立 Epic 3 全部後續 issue 共用的資料模型與持久化機制，純 Dart、不涉及原生程式碼、不需要真實裝置：

- 新增列舉型別：`AppFont`（`app/lib/reader/app_font.dart`，5 個內建字型）、`EpubTextAlign`（`app/lib/reader/epub_text_align.dart`，對應 Readium `TextAlign` 反編譯確認的 6 個值：`center`/`justify`/`start`/`end`/`left`/`right`）、`ScreenOrientationSetting`（`app/lib/reader/screen_orientation_setting.dart`，`auto`/`lock0`/`lock90`/`lock180`/`lock270`）
- 新增 `BookReaderPrefs`（`app/lib/reader/book_reader_prefs.dart`）：不可變資料類別，欄位見 `spec.md`「資料模型」章節，含 `BookReaderPrefs.empty` 靜態常數
- 新增 SQLite 表 `book_reader_prefs`（`book_id` 為主鍵，`REFERENCES books(id) ON DELETE CASCADE`，所有欄位皆為 nullable，見 `spec.md` 的 `CREATE TABLE` 定義）
- 新增 `BookReaderPrefsRepository`（`app/lib/reader/book_reader_prefs_repository.dart`）：`load(bookId)`（無對應列時回傳 `BookReaderPrefs.empty`）、`save(bookId, prefs)`（upsert）
- 新增 `GlobalReaderDefaults`（`app/lib/reader/global_reader_defaults.dart`）：`shared_preferences`，`loadPageTurnMode()`/`savePageTurnMode()`（預設 `PageTurnMode.paginated`）、`loadScreenOrientation()`/`saveScreenOrientation()`（預設 `ScreenOrientationSetting.auto`），比照 `LibraryPreferences` 慣例（含 `byName` 失敗時 catch 回退預設值）
- 新增 `AppThemePreferences`（`app/lib/theme/app_theme_preferences.dart`）與 `AppTheme` 列舉（`light`/`dark`/`sepia`）：`shared_preferences`，`loadTheme()`/`saveTheme()`（預設 `AppTheme.light`）、`loadEinkMode()`/`saveEinkMode()`（預設 `false`），比照 `LibraryPreferences` 慣例

**單元測試要求：**
- 純 Dart unit test：`BookReaderPrefs`／各列舉型別的建構與相等性；`byName` 對無效字串的回退行為
- `BookReaderPrefsRepository`：無對應列時回傳 `BookReaderPrefs.empty`；`save()`/`load()` round-trip 涵蓋所有欄位；刪除 `books` 表對應列後，`book_reader_prefs` 對應列因 `ON DELETE CASCADE` 一併消失
- `GlobalReaderDefaults`／`AppThemePreferences`：比照 `LibraryPreferences` 既有測試（`SharedPreferences.setMockInitialValues` 驅動），驗證預設值與 round-trip

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- 本 issue 完全不需要真實裝置即可驗收（純 Dart + SQLite + shared_preferences 皆可在 `flutter test` 環境驗證）

---

## Issue 2：原生契約擴充——批次偏好設定與字型素材註冊（已完成，合併於 PR #26）

**依賴：** Issue 1（需要 `AppFont`/`EpubTextAlign` 等列舉型別供 map key 對應使用）

**描述：**
依 ADR 0006 擴充 `EpubReaderView`/`EpubReaderView.kt` 契約：

- **Dart 端（`app/lib/reader/epub_reader_view.dart`）**：新增 8 個建構參數（`fontFamily`/`fontSize`/`fontWeight`/`lineHeight`/`paragraphSpacing`/`pageMargins`/`textAlign`/`publisherStyles`，型別與既有 `writingMode`/`pageTurnMode` 皆為 nullable）；`_onPlatformViewCreated` 把所有非 null 偏好參數（含既有 `writingMode`/`pageTurnMode`）組成 `initialPreferences` map，隨 `openBook` 呼叫送出；`didUpdateWidget` 改為偵測全部 10 個欄位是否有任一變動，變動時把目前所有非 null 欄位組成 map，透過單一 `setPreferences` 呼叫送出
- **原生端（`EpubReaderView.kt`）**：`openBook` 新增 `initialPreferences: Map<String, Any?>?` 參數，`attachNavigator()` 成功後套用（組出 `EpubPreferences`、`plus()` 合併進 `currentPreferences`、`submitPreferences()`）；新增 `setPreferences` 處理，**移除**既有 `setWritingMode`／`setPageTurnMode` 兩個方法（兩者邏輯併入 `setPreferences`）；`fontWeight` 換算公式（`400 × fontWeight`）由原生端的 Readium 內部處理，Dart 端不需要在這一層做換算（`fontWeight` 建構參數本身就是已經是倍率語意，UI 層的 300-900 → 倍率換算屬於 Issue 3 的責任）
- **字型素材登記**（見 `spec.md`「自訂字型如何讓原生 WebView 實際載入」，修正先前「`pubspec.yaml` `fonts:` 區塊即可生效」的錯誤假設）：`app/pubspec.yaml` 新增 `assets:` 宣告（5 款字型檔案，供原生端 `AssetManager` 存取，非 `fonts:` 區塊——後者只影響 Flutter 自己的 Skia 渲染）；`attachNavigator()` 建構 `createFragmentFactory` 時額外組出 `EpubNavigatorFragment.Configuration`，透過 `addFontFamilyDeclaration(...)` 為 5 款字型逐一登記（`servedAssets` 需列入對應路徑；字型檔案 URL 透過 `FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(...)` 換算）；`AppFont` enum 新增 family 名稱 getter（`app/lib/reader/app_font.dart`），對應原生端登記時使用的名稱字串（供 `fontFamily` map key 轉換使用）

**單元測試要求：**
- `EpubReaderView` widget test（假 `MethodChannel` handler）：驗證 `_onPlatformViewCreated` 呼叫 `openBook` 時，`initialPreferences` 正確包含所有非 null 建構參數（含 `writingMode`/`pageTurnMode`）；驗證任一偏好欄位變動時觸發 `setPreferences`，內含所有目前非 null 欄位
- `flutter pub get` 成功、字型檔案可被正確載入（`flutter analyze` 不因新增 `assets:` 區塊產生警告）
- **已知測試限制（沿用既有慣例）**：原生端 `openBook`/`setPreferences` 的實際 Kotlin 邏輯無法透過 `flutter test`（無裝置）驗證，原生行為驗證留給 Issue 6

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- 既有的 writingMode/pageTurnMode 相關測試（Issue 1/2/4 建立）需同步調整為透過新的 `setPreferences`/`initialPreferences` 機制驗證，不得因本次契約異動而遺留呼叫已移除方法的測試程式碼

---

## Issue 3：版面設定 Bottom Sheet——字型與數值型控制項（已完成，合併於 PR #27）

**依賴：** Issue 2

**描述：**
新增 `ReaderSettingsSheet`（`app/lib/screens/reader_settings_sheet.dart`），比照 `prototype/index.html` 第 1379-1520 行設計的單一「版面設定」頁籤：

- 字型選擇（5 款內建字型下拉選單或列表）、字型大小滑桿＋微調按鈕、字型粗細滑桿＋微調按鈕（UI 顯示 300-900 慣用數值，送給 `EpubReaderView.fontWeight` 前需除以 400 換算成倍率——**滑桿行為對所有字型一致，不因單一字重字型而限制範圍或加提示**，見 `design.md`「已知限制」）、行高滑桿＋微調按鈕、段落間距滑桿＋微調按鈕、邊距滑桿＋微調按鈕（單一數值，見 ADR 0005）、文字對齊選項、停用書本 CSS 開關（對應 `publisherStyles` 的反向語意）
- 每個控制項互動後，即時呼叫 `BookReaderPrefsRepository.save()` 持久化，並更新傳給 `EpubReaderView` 的對應建構參數（觸發 Issue 2 的 `setPreferences` 機制即時套用，邊看邊調）
- `ReaderScreen` 新增「⚙️ 版面」按鈕（`Key('reader_layout_settings_button')`）開啟此 Bottom Sheet；`_isFixedLayout == true` 時按鈕不顯示

**單元測試要求：**
- Widget test：Bottom Sheet 開啟後各控制項初始值正確反映傳入的 `BookReaderPrefs`；拖動/點擊各控制項後，`BookReaderPrefsRepository.save()` 被正確呼叫且參數正確；字重滑桿 UI 顯示值與送給 `EpubReaderView` 的倍率值換算正確（例如 UI 700 → 送出 1.75）
- Widget test：`_isFixedLayout == true` 時「⚙️ 版面」按鈕不顯示
- `integration_test`（真實裝置）：開啟 Bottom Sheet 後調整任一控制項，確認畫面持續渲染成功、無 `onError`（沿用既有斷言模式）；關閉重開該書後確認設定被正確記住（驗證 Issue 2 的 `initialPreferences` 機制真正生效，不只是 UI 顯示）

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- 手動驗證：調整字型大小/行距/邊距等任一數值型設定，畫面即時反映變化；關閉重開書本後設定依然生效

---

## Issue 4：版面設定 Bottom Sheet——三個覆寫選擇器與螢幕方向鎖定（已完成，合併於 PR #28）

**依賴：** Issue 2（`setPreferences` 機制）、可與 Issue 3 平行開發（共用同一個 `ReaderSettingsSheet`，但控制項區塊獨立）

**描述：**
在 Issue 3 建立的 `ReaderSettingsSheet` 內新增三個覆寫選擇器，皆採圖示直接點選：

- **排版方向覆寫**（三態）：📖採用書籍排版／⬇強制直排／➔強制橫排三顆圖示按鈕，對應 `writingModeOverride`（`null`/`vertical`/`horizontal`）；`ReaderScreen` 內部資料模型拆分為 `_autoDetectedWritingMode`（唯讀，來自 `onLayoutResolved`）與 `_writingModeOverride`（持久化），實際送給 `EpubReaderView.writingMode` 的值＝`_writingModeOverride ?? _autoDetectedWritingMode`
- **翻頁模式覆寫**：圖示選擇（使用全域預設／點擊翻頁／滾動翻頁），對應 `pageTurnModeOverride`；解析值＝`pageTurnModeOverride ?? GlobalReaderDefaults.pageTurnMode`
- **螢幕方向覆寫**：圖示選擇（使用全域預設／自動旋轉／鎖定 0°／90°／180°／270°，6 個選項，UI 排列方式可能需要多排呈現），對應 `screenOrientationOverride`；解析值＝`screenOrientationOverride ?? GlobalReaderDefaults.screenOrientation`；解析出的最終值透過 `SystemChrome.setPreferredOrientations(...)` 套用真實 OS 層級鎖定
- `ReaderScreen.dispose()` 新增 `SystemChrome.setPreferredOrientations([])`，還原系統預設允許自由旋轉，比照音量鍵離開閱讀器還原系統音量的既有處理原則
- **移除現有兩顆過渡性按鈕**：`reader_writing_mode_toggle`（Issue 2 建立）、`reader_page_turn_mode_toggle`（Issue 4 建立）連同對應的 widget test／`integration_test` 一併移除，功能已整併進本 issue 的圖示選擇器

**單元測試要求：**
- Widget test：三個圖示選擇器的初始顯示狀態正確反映解析後的值（含雙層解析：覆寫值優先，`null` 時顯示全域預設值對應的圖示）；點擊後正確更新 `BookReaderPrefs` 並觸發 `setPreferences`
- Widget test：確認 `reader_writing_mode_toggle`／`reader_page_turn_mode_toggle` 這兩個 Key 已不存在於 `ReaderScreen`
- `integration_test`（真實裝置）：驗證 `ReaderScreen` 進入時螢幕方向鎖定生效（若測試環境可控制裝置方向）；驗證離開閱讀器後 `SystemChrome.setPreferredOrientations([])` 已被呼叫（可透過方法呼叫記錄斷言，不需要真的觀察裝置實際轉動）

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨、`flutter test` 全數通過無回歸
- 手動驗證：三個覆寫選擇器皆能正確覆寫全域/自動偵測預設值；鎖定螢幕方向後手動旋轉裝置畫面不跟著轉；離開閱讀器後裝置可自由旋轉

---

## Issue 5：全域主題與 E-Ink 高對比模式

**依賴：** Issue 1（`AppThemePreferences`），可與 Issue 2/3/4 平行開發

**描述：**
`app/lib/main.dart`（`ElinkBookApp`）啟動時載入 `AppThemePreferences`，依 `isEinkMode` 決定實際套用的 `ThemeData`：

- `isEinkMode == true`：一律套用固定的高對比黑白 `ThemeData`，不論 `theme` 目前選了什麼（`theme` 值持續儲存，供關閉 E-Ink 後還原顯示）
- `isEinkMode == false`：依 `theme`（`light`/`dark`/`sepia`）套用對應的 `ThemeData`
- 主題切換 UI：比照 `prototype/index.html` 第 3372-3375 行，於 `LibraryScreen` 頂部工具列新增主題切換點（三選一）與 E-Ink 開關（獨立疊加，不是第 4 個主題選項——見 `design.md`「FR-31」與 `CONTEXT.md`「E-Ink 高對比模式」詞條）

**單元測試要求：**
- Widget test：`ElinkBookApp` 依 `AppThemePreferences` 載入結果套用正確的 `ThemeData`（`isEinkMode == true` 時套用高對比主題，不論 `theme` 為何）
- Widget test：`LibraryScreen` 主題切換點擊後，`AppThemePreferences.saveTheme()`/`saveEinkMode()` 被正確呼叫，且畫面即時反映新主題

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- 手動驗證：切換深色/羊皮紙/預設主題，畫面即時反映；開啟 E-Ink 高對比後不論選哪個主題皆呈現高對比黑白；關閉 E-Ink 後恢復原本選擇的主題色調

---

## Issue 6：真機驗證與收尾

**依賴：** Issue 2、Issue 3、Issue 4、Issue 5 全部完成

**描述：**
本 issue 為裝置端整合驗證與 Epic 收尾，比照 Epic 2 Issue 3/4/5 的既有模式，部分項目屬人工視覺 QA 性質：

- **關鍵驗證項（自動化 `integration_test`）**：自動旋轉模式下實際旋轉真實裝置，確認 Readium／`R2WebView` 是否如反編譯推測般自動重新分頁，不需要額外手動觸發（見 `spec.md`「已驗證的技術基礎」）。若實測發現不會自動重新分頁，需記錄具體現象並另立後續 issue 補上監聽方向變化事件並手動觸發的邏輯，不阻塞本 epic 其餘部分收尾。
- **端到端持久化驗證（人工視覺 QA）**：對同一本書依序調整多個版面設定（字型、行距、邊距、排版方向覆寫、翻頁模式覆寫、螢幕方向覆寫），關閉 App、重新開啟，確認所有設定皆被正確記住並套用（驗證 Issue 2 的 `initialPreferences` 機制在多欄位組合情境下依然正確，不只是單一欄位）
- **字重換算與模擬粗體視覺確認**：實機觀察 5 款字型在字重滑桿調整後的實際渲染效果，確認思源黑體/宋體（Variable Font）呈現真實字重變化、其餘 3 款呈現模擬粗體效果符合預期（非渲染錯誤或崩潰）
- **自訂字型實際載入驗證**：確認 Issue 2 登記的 `addFontFamilyDeclaration`／`servedAssets` 機制在真實裝置上確實生效——切換 5 款內建字型後畫面文字確實改變外觀（而非靜默 fallback 回瀏覽器預設字型）；若發現 `servedAssets` 的 `PatternMatcher` 比對或 `getLookupKeyForAsset` 路徑格式有誤導致字型未生效，需記錄具體現象並修正（見 `spec.md`「自訂字型如何讓原生 WebView 實際載入」的殘餘風險）
- 彙整驗證紀錄，更新 `docs/epics/epic-3-fonts-layout/issues.md` 各 issue 最終驗收狀態

**單元測試要求：**
- 無新增自動化單元測試（本 issue 以整合/裝置驗證為主）；自動旋轉重新分頁為本 issue 明確要求的 `integration_test` 項目

**驗收標準：**
- 自動旋轉重新分頁驗證產出明確結論（自動生效／需額外開發，兩者皆可，但不得懸而未決）
- 端到端持久化驗證產出書面紀錄（比照 `qa-issue-N-*.md` 既有慣例）
- `flutter analyze` 乾淨、`flutter test` 全數通過
- 若有發現需要後續處理的落差，已建立對應的後續 issue 追蹤，不阻塞本 epic 合併
