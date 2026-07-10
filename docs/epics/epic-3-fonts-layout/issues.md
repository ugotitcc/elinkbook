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

## Issue 5：全域主題與 E-Ink 高對比模式（已完成，合併於 PR #29）

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

## Issue 6：真機驗證與收尾（已完成，發現 3 個後續問題）

**依賴：** Issue 2、Issue 3、Issue 4、Issue 5 全部完成

**驗證結果（2026-07-09）：**
- ✅ 自動旋轉重新分頁 `integration_test` 已通過
- ✅ 自訂字型載入驗證通過（Check 1）
- ✅ 端到端偏好設定持久化驗證通過（Check 3）
- ❌ 字重（fontWeight）設定無視覺效果 → 已建立 Issue 7 追蹤
- ❌ 閱讀器底部被狀態列遮蔽 → 已建立 Issue 8 追蹤
- ❌ PDF 書籍無法換頁 → 已建立 Issue 9 追蹤

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

---

## Issue 7：字型粗細（fontWeight）設定無視覺效果（已修復，真機確認）

**依賴：** Issue 2（`EpubReaderView` 的 `fontWeight` 參數傳遞）

**描述：**
真機驗證（Issue 6）發現：拖動字重滑桿從 300 到 900，畫面文字粗細無任何視覺變化。所有 5 款內建字型皆受影響。`a2e1cc3` commit 曾一度修正（Dart 端維持 Readium 倍率語意，換算公式正確），但緊接著的 `197a013` commit（「啟用 textNormalization for font weight」）引入新的迴歸，導致問題再次出現；第一輪 `/diagnose`（移除 `textNormalization=true`）後真機再次回報仍無效，經第二輪 `/diagnose` 找到更深一層的根因。

**根因一（`textNormalization=true` 的迴歸，已修）：** 反編譯 `readium-navigator:3.3.0` 的 `classes.jar`（`EpubSettingsKt`）確認：`fontOverride`（CSS 旗標 `readium-font-on`）判斷式為 `(fontFamily != null) || textNormalization`，`a11yNormalize`（CSS 旗標 `readium-a11y-on`）則直接等於 `textNormalization`——導致這兩個旗標永遠為真。內建的 `ReadiumCSS-after.css` 有規則 `:root[style*=readium-font-on][style*=readium-a11y-on]{font-weight:400!important}`，永遠命中並蓋掉字重滑桿送出的值。已移除 `EpubReaderView.kt` 中寫死的 `textNormalization = true`。

**根因二（Readium `fontWeight` preference 本身缺少往下蓋規則，已修）：** 移除 `textNormalization` 後，真機用 WebView 遠端除錯（Chrome DevTools Protocol）確認 `<html>`／`<body>` 的 `font-weight` 確實正確算出使用者設定值，但仍回報「無效」——因為 ReadiumCSS 對 `fontSize`/`lineHeight`/`paraSpacing` 都有把值強制往下蓋到 `p`/`div`/`li` 等內文元素的規則（例如 `dd,div,li,p,pre{font-size:1rem!important}`），唯獨 `font-weight` 沒有對應規則，只設在 `<html>`、靠繼承往下傳——書本自己 CSS 對段落/標題只要有任何 `font-weight` 宣告（很常見），繼承就不會發生，使用者看不到效果。已在 `EpubReaderView.kt` 新增 `applyFontWeightCascade()`，比照 Readium 自己對 `fontSize` 的作法，額外注入一個 `<style>` 強制把值蓋到 `body, p, div, li, span, td, th, blockquote, dd, dt, a, h1~h6`，並在換頁與滑桿即時調整時都重新套用。詳細分析見 `plans/plan-issue-7.md`。

**驗收結果（真機，Chrome DevTools Protocol 直接量測）：**
- `htmlComputedFontWeight`／`bodyComputedFontWeight` 正確算出滑桿值（含 `!important`）
- 注入的 `<style id="elinkbook-font-weight-cascade">` 內容正確反映滑桿值，強制套用到內文元素選擇器清單
- `flutter test` 通過、`flutter analyze` 乾淨

**根因三（原俠正楷／台灣圓體／源流明體 3 款單一靜態字重字型完全無反應，已修）：** 這 3 款字型檔案本身只有一種靜態字重，唯一能有效果的方式是靠瀏覽器內建的模擬粗體（synthetic bold）。但 `buildFontFamiliesConfiguration()` 原本對全部 5 款字型無差別註冊了 `FontWeight.NORMAL`＋`FontWeight.BOLD` 兩個 `@font-face`，對這 3 款字型而言兩個宣告指向同一份檔案——瀏覽器誤以為「已經有對應這個字重的正確字面」而抑制了原本會自動套用的模擬粗體。已改成只有思源黑體/宋體（真 Variable Font，`variableWeightFamilies` 集合）才註冊雙 face，其餘 3 款只註冊一個 face，讓瀏覽器預設的 `font-synthesis` 接手。真機用 CDP 查詢 `document.fonts` 確認：3 款靜態字重字型現在只各自註冊單一 400 字重 face、2 款變數字型維持 400+700 雙 face。詳細分析見 `plans/plan-issue-7.md`。

---

## Issue 8：閱讀器底部被狀態列/導航列遮蔽（已修復，真機確認）

**依賴：** 無

**描述：**
真機驗證（Issue 6）發現：閱讀書籍（尤其是漫畫類內容）時，畫面最下方內容被 Android 狀態列（status bar）或導航行動列（navigation bar）遮蔽，導致底部內容不可讀。`197a013` commit 的 `SafeArea` 對流動式 EPUB／PDF 已解決此問題，但固定版面（漫畫）後續真機驗證仍回報「上下仍會被切到一些，橫放時更嚴重、不會自動縮放」；第一輪 `/diagnose`（移除 `applyFixedLayoutCssInjection()`）後真機再次回報仍會裁切，經第二輪 `/diagnose` 找到 Readium 官方原始碼層級的根因。

**根因一（`applyFixedLayoutCssInjection()` 與原生 `Fit.CONTAIN` 打架，已修）：** `9a1f0c8` commit 針對固定版面額外注入的 CSS 強制 `html, body { width:100vw; height:100vh }`，是跟 `SafeArea` 給的原生容器真實尺寸完全獨立的 WebView 內部視口單位，與原生 `Fit.CONTAIN`（`a2e1cc3`）互相打架。已移除 `applyFixedLayoutCssInjection()`／`findWebView()` 兩個函式與其呼叫點。

**根因二（Readium 固定版面 XML 版面本身只做 fit-by-width，不做 fit-by-height，已修）：** 移除注入的 CSS 後，真機用 WebView 遠端除錯確認固定版面頁面的 WebView 實際 Android View 高度仍是全螢幕高度（2401px，對照同裝置流動式 EPUB 正確地是 2116px），證明問題不在我們自己的 Kotlin 邏輯。直接讀取 `readium/kotlin-toolkit` 3.3.0 官方原始碼（`readium_navigator_fragment_fxllayout_single.xml`）確認：內層 `R2BasicWebView` 用 `layout_height="wrap_content"`，配合 `useWideViewPort`/`loadWithOverviewMode` 只做「縮放至符合可用寬度」，完全沒有同時考慮可用高度的邏輯——超出外層 `ScrollView` 可視範圍的部分變成預設不可見的可捲動區域，而非被縮小。這是 Readium 3.3.0 內建資源本身的行為，不在我們的原始碼樹裡。已在 `EpubReaderView.kt` 新增 `applyFxlFitScale()`：換頁時找到內層 WebView，比較 `container.height`（Flutter 給定、已扣除系統列的真實可用高度）與 WebView 實際測量高度，透過 `View.scaleX`/`scaleY`/`pivotX`/`pivotY`（純視覺變形，不觸碰 Readium 內部狀態）等比縮小到剛好塞進可用高度。詳細分析見 `plans/plan-issue-8.md`。

**驗收結果（真機，第一版）：**
- 修正前：漫畫封面頁滿版貼齊螢幕邊緣，最下面一列內容被裝置常駐 Taskbar 遮住一截
- 修正後：同一頁完整置中顯示、四邊有正確留白，不再被 Taskbar 遮蔽；旋轉至橫向後同樣完整置中顯示，符合 `Fit.CONTAIN` 等比縮放語意
- **但**使用者後續真機測試翻到書中其他頁，回報「仍有部份切到」

**根因三（殘留裁切＋旋轉不重算，已修）：** 不是四捨五入誤差，是兩個時機問題：(1) `onPageLoaded()` 觸發當下 WebView `wrap_content` 高度可能還沒完全撐開（圖片解碼/reflow 未完成），讀到偏小的高度導致縮放比例偏大（縮得不夠）；(2) `MainActivity` 宣告 `configChanges="orientation|screenSize|..."`，旋轉不會重建 Activity/Fragment，`onPageLoaded()` 不會再次觸發，縮放比例停留在舊方向的數值。已把 `applyFxlFitScale()` 改成在 `container`（穩定存在、不隨翻頁重建）上掛 `ViewTreeObserver.OnGlobalLayoutListener`，只要 View 樹版面發生變化（旋轉、內容延遲撐高、換頁換新 WebView 實例）就重新計算縮放比，`dispose()` 時移除監聽器。詳細分析見 `plans/plan-issue-8.md`。

**驗收結果（此輪，僅用封面頁測試）：**
- 漫畫封面頁直向完整置中顯示，四邊留白正確；旋轉至橫向後立即重新等比縮放，四邊留白正確
- **但**使用者提供實際 `葬送的芙莉蓮 11.epub`，指出「封面算第一頁的話，第 7, 8, 9 頁會出現切到的情況」且「旋轉螢幕時不會重新縮放」，經第四、五輪 `/diagnose` 找到兩個更深的根因。

**根因四（View 樹中同時存在多個 WebView，只處理到第一個，已修）：** 直接用使用者提供的檔案 `adb push` 到裝置、用 Chrome DevTools Protocol 監看 URL 搭配 `adb shell input swipe` 精準定位到第 7 頁截圖，重現裁切。`adb shell dumpsys activity --view-hierarchy` 檢查發現 Readium 的 `R2ViewPager` 為了讓翻頁動畫流暢，同時保留了目前頁前後相鄰的頁面——**同時存在 3 個獨立的 `R2BasicWebView` 實例**。先前 `findViewByType`（單數）只回傳 View 樹中第一個符合型別的節點，不保證是使用者實際翻到、正在顯示的那一頁；封面頁剛好在樹裡排序靠前所以第一輪測試看起來修好了，翻到第 7-9 頁後「目前顯示的那一頁」不再是第一個，就完全沒被套用縮放。已新增 `findViewsByType`（複數），`applyFxlFitScale()`／`applyFontWeightCascade()` 都改成對「找到的每一個 WebView」個別套用邏輯。

**根因五（pivot 縮放沒有校正 Readium 內部的置中位移，已修）：** 改成處理全部 WebView 後，部分頁面變成**頂端**裁切、底部多出不成比例的空白。原因是 Readium 內建 XML（`RelativeLayout` 包 `LinearLayout[layout_centerInParent]` 包 WebView）本身就會依內容高度把 WebView 在 `RelativeLayout` 內垂直置中，WebView 進入函式時量測到的 `top` 可能早就不是 0；先前 `pivotY=0` 是以 WebView *自己*（已經帶著這個位移的）左上角為錨點縮放，位移會原封不動保留在畫面上。已改用 `View.getLocationOnScreen()` 直接量出 WebView 與容器的實際螢幕座標差，反推出讓縮放後內容置中所需的 `translationX`／`translationY` 補償值；縮放比例也改成 `min(可用寬度/內容寬度, 可用高度/內容高度)`（真正雙軸 `Fit.CONTAIN`）。詳細分析見 `plans/plan-issue-8.md`。

**驗收結果（真機，最終版，使用者提供的實際檔案）：**
- 第 7 頁（使用者原始回報的裁切頁面）：完整可見，四邊留白正確
- 隨機再抽測的另一頁：同樣完整可見、四邊留白正確
- 同一頁旋轉至橫向：立即重新置中，四邊留白正確
- `flutter test integration_test/epub_reader_view_test.dart` 真機 9/9 全過、`flutter analyze` 乾淨

---

## Issue 9：PDF 書籍無法換頁（已修復，且已優化實機解析度低之缺陷）

**依賴：** 無

**描述：**
真機驗證（Issue 6）發現：開啟 PDF 書籍後，無法進行翻頁操作（手勢或按鈕皆無效），PDF 閱讀功能完全不可用。

**可能原因：**
- `PdfReaderView.kt` 的手勢偵測（GestureDetector）未正確綁定
- 或頁面導航邏輯（goToNextPage/goToPreviousPage）有誤

**驗收標準：**
- PDF 書籍可正常左右滑動翻頁
- 頁碼指示正確更新
- `flutter test` 通過、`flutter analyze` 乾淨
