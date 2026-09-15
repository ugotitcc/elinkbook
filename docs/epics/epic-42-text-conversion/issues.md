# Epic 42 — 簡繁轉換：工單清單 (Issues)

依 `spec.md`（唯一事實來源，含 ADR 0030／ADR 0031 與 spec 審查修訂）拆解為 Issue 0-5。**Issue 0 優先開始；Issue 1 依賴 Issue 0（`TextConversionMode` enum 定義，見 `reviews/review-issues.md` I-1 修正，推翻先前「Issue 0/1 彼此獨立」的誤判）；Issue 2-5 皆阻塞於 Issue 0＋Issue 1，但彼此互相獨立、可平行進行**（2026-09-15 `/to-tickets` 確認拆分方式；2026-09-15 依審查報告修正依賴關係與多項技術細節）。

---

## Issue 0：前置修復＋雙端字典生成

**Status:** completed（`plans/plan-issue-0.md` 5 個 Task 全數完成，`check_foliate_es_compat.js` 常數引用漂移已修復，`TextConversionMode` enum／`convertText()`／`parseCharTable()`／JS-Dart 雙端同源查找表皆已落地，`flutter analyze`/`flutter test`／`node` 腳本測試全數通過。獨立程式審查 `reviews/review-issue-0.md`：0 Critical／0 Important／2 Minor，皆已修訂〔移除 `epubcfi.js:266` 行號耦合、vendor OpenCC LICENSE 全文〕，結論 Ready to merge: Yes）

**依賴：** 無（可立即開始）

**範圍：**
- 修復 `app/tool/check_foliate_es_compat.js` 的 `extractPolyfillSource()`：目前寫死抓取 `foliate_reader_view.dart` 裡的 `_esCompatPolyfillJs`，但該常數已搬到 `foliate_native_bridge.dart:219` 且改名為 `esCompatPolyfillJs`（無底線前綴），腳本執行必定拋例外。修正引用路徑（檔案＋常數名稱），確認腳本可正常執行不拋例外。此為既有、與本 Epic 決策無關的 bug，但會擋住本 Epic 後續新增 vendor 檔案的 ES 相容性檢查，須最優先處理。
- 新增字典生成腳本（一次性執行或未來可重跑），輸入為 OpenCC 原始字元表（`STCharacters.txt`／`TSCharacters.txt`）。**來源與存放規範（審查修正 I-3）**：專案目前未內含這兩個檔案，須從 BYVoid/OpenCC 官方倉庫取得（例如 `https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/`，實作時查證當下的正確路徑/發行版標籤是否仍有效，不假設此處網址永久不變）；原始 TSV 檔存放於專案內固定目錄（暫名 `app/tool/opencc_data/`），比照既有 vendoring 慣例納入版控；生成腳本本身放在 `app/tool/`（暫名 `generate_conversion_dicts.js` 或等效）。輸出兩份查找表：
  - JS 端 vendor 檔案（`app/android/app/src/main/assets/foliate/` 下，暫名 `text_conversion_dict.js`，純物件字面量，比照 `foliate-js` 釘定版本、不經 npm 建置的 vendoring 慣例）。
  - Dart 端檔案（暫名 `app/lib/reader/text_conversion_dict.dart`，`Map<String, String>` 常數）。
  - **正規化約束（spec.md 審查修正 I-3）**：右側目標欄位若含多個以半形空格分隔的候選字（例如 `后\t後 后`），只取第一個候選字；生成腳本須內建 assertion 嚴格檢驗每組鍵值皆為 `key.runes.length === 1 && value.runes.length === 1`，任何一筆不滿足即中止生成。JS 與 Dart 兩份查找表須用同一份生成邏輯／同一次執行輸出。
- 新增 `enum TextConversionMode { original, toTraditional, toSimplified }`（`app/lib/reader/text_conversion_mode.dart`，比照 `dual_page_mode.dart` 既有單檔單 enum 慣例）。
- 新增 Dart 純函式 `String convertText(String input, TextConversionMode mode)`：`original` 時原樣回傳，其餘依對應字典逐字元查表替換，查不到的字元維持原樣。

**單元測試要求：**
- `convertText()`：已知字元對正確轉換（含至少一組多對一併字案例，如「後」「后」皆應轉換為「后」）；查不到的字元原樣保留；`original` 模式恆等於輸入。
- 字典生成腳本：對含多候選字的測試輸入行，驗證只取第一個候選字；對刻意植入的多字元候選字輸入，驗證 assertion 會中止生成（不會產生 ΔL≠0 的字典項）。
- `check_foliate_es_compat.js` 修復後可正常執行完畢、不拋例外（回歸驗證）。

**驗收標準：** 上述測試通過；JS 字典檔案已 vendor 進版控且可被 WebView 載入（至少手動驗證一次 `node --check text_conversion_dict.js` 語法正確）；`flutter analyze` 乾淨。

---

## Issue 1：資料模型＋全域/單書 UI 入口

**Status:** ready-for-agent

**依賴：** Issue 0（審查修正 I-1：本工單引用 Issue 0 定義的 `TextConversionMode` enum，非真正獨立，先前「與 Issue 0 平行」的標註有誤，已修正）

**範圍：**
- `BookReaderPrefs` 新增欄位 `final TextConversionMode? textConversionOverride;`（`null` = 未覆寫）：`toMap()`／`fromMap()`／`copyWith()`／`==`／`hashCode` 依既有欄位模式一併補上；`reflowableEpubFields()` 保留此欄位（不強制清 null）。
- `ReadingDefaults` 新增欄位 `final TextConversionMode textConversion;`（non-nullable，預設 `TextConversionMode.original`）：`copyWith()`／`==`／`hashCode` 依既有模式一併補上。
- `ReaderPrefsManagerImpl`：新增 SharedPreferences key、`loadGlobalPrefs()` 讀取（沿用既有 `_readEnum` helper）、寫入路徑補上對應 `sp.setString(...)`。
- 新增純函式 `resolveTextConversion(BookReaderPrefs book, ReadingDefaults global)`，回傳 `book.textConversionOverride ?? global.textConversion`。
- SQLite 版本 25→26：`book_reader_prefs` 新增欄位 `text_conversion_override TEXT`（可空）。**遷移程式碼須放在 `sqlite_library_repository.dart` 既有 `else`（`oldVersion >= 2`）分支內的 `if (oldVersion < 26)`**，比照該檔案既有欄位新增慣例，不得放在 `if/else` 區塊外（否則 `oldVersion == 1` 裝置升級會拋出 `duplicate column name` 例外）。
- **全域預設 UI**：`ReadingDefaultsScreen` 新增一列三態選擇器（沿用該畫面既有欄位樣式）。
- **單書覆寫 UI**：`ReaderSettingsSheet`（流式 EPUB／KF8／TXT／MD）與 `FxlSettingsSheet`（FXL EPUB／KF8）皆新增含 `null` 的四態選擇器（`null` 標示「使用全域預設」，比照 `reader_settings_sheet.dart:959-963` `_buildScreenOrientationOverrideRow()` 既有模式，選項清單第一項固定為全域預設）。`FxlSettingsSheet` 需新增建構子參數（暫名 `final bool showTextConversion;`），由呼叫端 `reader_screen.dart` 依開啟中書籍格式判斷（非 CBZ）傳入；CBZ 開啟該 Sheet 時此欄位不顯示。PDF（`PdfSettingsSheet`）不新增此欄位。

**單元測試要求：**
- `BookReaderPrefs`／`ReadingDefaults` 的 `toMap`/`fromMap`/`copyWith`/`==`/`hashCode` 新欄位往返正確。
- `resolveTextConversion()`：`book.textConversionOverride` 非 null 時優先於 `global.textConversion`；為 null 時回退全域值。
- SQLite migration（v25→v26）：既有裝置升級後 `text_conversion_override` 存在且為 `NULL`；模擬 `oldVersion == 1` 升級不拋 `duplicate column name` 例外。
- Widget test：`ReadingDefaultsScreen` 三態選擇器可正確切換並持久化（重新載入後值不變）。
- Widget test：`ReaderSettingsSheet`／`FxlSettingsSheet` 四態選擇器（含「使用全域預設」）正確寫回 `textConversionOverride`。
- Widget test：`FxlSettingsSheet` 傳入 `showTextConversion: true`（FXL EPUB/KF8）時顯示該選項；傳入 `showTextConversion: false`（CBZ）時該控制項不存在。

**驗收標準：** 上述測試通過、`flutter analyze` 乾淨；真機或模擬器上可在系統設定與單書版面設定切換此偏好並正確持久化（此時切換尚不會改變畫面文字，轉換效果由 Issue 2／3 接上）。

---

## Issue 2：JS 端 DOM Walker 與 CFI 安全轉換

**Status:** ready-for-agent

**依賴：** Issue 0（字典檔案／`convertText`）、Issue 1（`resolveTextConversion`／偏好設定管線）

**範圍：**
- 新增 DOM Walker 函式（暫名 `applyTextConversion(root, mode)`，於 `main.js` 或獨立模組），比照 `extractSegmentsForSection`（`main.js:683-738`）既有的 `createTreeWalker`／`NodeFilter.SHOW_TEXT` 寫法，走訪目前渲染中 section 的可見文字節點，排除 `<rt>`／`<script>`／`<style>` 標籤。
- **原始文字快取**：每個文字節點首次走訪時，以動態屬性快取原文（`if (node._elinkOrigText === undefined) node._elinkOrigText = node.nodeValue;`）。任何模式切換皆以 `node._elinkOrigText` 為轉換輸入基準，絕不對已轉換的 `node.nodeValue` 做二次轉換或反向推導：`original` 模式直接還原 `node._elinkOrigText`；`toTraditional`／`toSimplified` 對 `node._elinkOrigText` 逐字元查表後寫入。
- 轉換邏輯逐字元查表替換，不得做任何多字元 lookahead 或長度改變的替換。
- **新章節載入時的觸發點（審查修正 M-2，取代原「`beforeRender`」錯誤措辭）**：`main.js` 並沒有公開的 `beforeRender` 事件可掛鉤——比照既有 `view.addEventListener('load', ...)`（`main.js:1020`，新章節載入時觸發，`e.detail.doc` 即該 section 渲染後的 DOM），在此既有監聽器內對新載入章節呼叫 `applyTextConversion(e.detail.doc, currentTextConversion)`。
- **閱讀中即時切換（審查修正 C-1，推翻原「呼叫 `view.goTo()`」方案）**：原規劃比照 `writingMode` 變動時呼叫 `view.goTo(view.lastLocation?.cfi)`，但核對 `paginator.js:3651-3673` 的 `#goTo()` 確認：`directionChanged`（是否變更排版方向）為 `false` 時，會直接命中「View already loaded — reuse it without clearing/reloading」分支，完全不重建 DOM、不觸發任何渲染事件——簡繁切換不改變排版方向，`directionChanged` 恆為 `false`，呼叫 `view.goTo()` 對畫面文字沒有任何刷新效果，這是與 `writingMode`（改變 `directionChanged`）本質不同的情境，不能類比套用。**改採**：`buildFoliatePreferencesMap`（`foliate_reader_view.dart:98`）新增注入 `textConversion: resolveTextConversion(...).name`；`main.js` 的 `window.applyPreferences` 偵測 `prefs.textConversion !== lastAppliedPrefs?.textConversion` 時，直接走訪目前所有可見文件（既有 API `view.renderer.getContents()`，已用於 `main.js:571/1067`，回傳目前可見的 `{ doc, index, overlayer }` 物件）並對每個 `doc` 呼叫 `applyTextConversion(doc, prefs.textConversion)`，不經過 `view.goTo()`——得益於 `_elinkOrigText` 快取與 ΔL=0，原地置換不會造成版面尺寸跳動。

**單元測試要求：**
- **CFI 穩定性回歸測試（優先度最高）**：以既有劃線/書籤整合測試 fixture 為基礎，驗證「在『轉換為繁體』模式下建立一筆劃線 → 切回『原文』模式 → 該劃線仍精確框住同一段原文文字」；反向（原文模式建立、切到轉換模式驗證）亦須覆蓋。
- DOM Walker 原始文字還原：模擬文本含併字字元（如「幹」「后」），走過 `original` → `toSimplified` → `original` 循環後，文字節點內容須與初始原文 100% 一致。
- `app/integration_test/`（真機）：DOM Walker 實際套用於已渲染 WebView 內容後，既有劃線/書籤渲染位置不偏移；閱讀中透過 Bottom Sheet 切換模式，畫面文字立即刷新（不需翻頁）。

**驗收標準：** 上述測試通過；真機開啟 EPUB/KF8/TXT/MD 書籍，切換三態顯示模式時畫面文字正確轉換，既有劃線/書籤定位不受影響，閱讀中即時切換立即生效。

---

## Issue 3：Dart 端跨畫面顯示轉換

**Status:** ready-for-agent

**依賴：** Issue 0（`convertText`）、Issue 1（`resolveTextConversion`／`GlobalReaderPrefs.reading.textConversion`）

**範圍：**
- **單書情境**（傳入 `resolveTextConversion()` 解析後的該書生效值）：`BookTocItem.title` 渲染前（目錄面板 widget）、書籤清單章節名稱、劃線清單摘要片段（僅摘要片段，**不含**備註文字本身）。**（審查修正 M-1，範圍擴大）**：`ReaderScreen` 內顯示書名/章節名稱的 Flutter Text 渲染點——`_buildFoliateHeaderText()`（`reader_screen.dart:2913-2958`，流式/FXL 頁首章節名稱或 `widget.bookTitle`）、傳入 `ReaderChromeTopBar`／`ReaderChromeBottomBar`（`reader_screen.dart:1467/2374/2755`）與 PDF 標題列（`reader_screen.dart:1691`）的 `bookTitle`——皆須依同一規則轉換。建議統一收斂成一個 getter（例如 `_displayBookTitle`），內部呼叫 `convertText(widget.bookTitle, resolveTextConversion(...))`，供上述所有渲染點取用，避免逐點各自轉換造成遺漏。
- **跨書情境**（傳入呼叫端持有的 `GlobalReaderPrefs.reading.textConversion`，不做單書覆寫）：書架書名/作者渲染（`LibraryScreen`）。

**單元測試要求：**
- Widget test：目錄面板／書籤清單／劃線清單在不同 `textConversionOverride`／全域預設組合下，顯示的文字正確轉換。
- Widget test（審查修正 M-1）：`_buildFoliateHeaderText()` 與傳入 `ReaderChromeTopBar`／`ReaderChromeBottomBar`／PDF 標題列的書名/章節名稱依該書生效模式正確轉換。
- Widget test：備註文字在任何顯示模式下皆維持使用者輸入原樣，不受轉換影響。
- Widget test：書架書名/作者依全域預設值轉換，且不受個別書籍的 `textConversionOverride` 影響（跨書情境不做單書覆寫）。

**驗收標準：** 上述測試通過、`flutter analyze` 乾淨；真機驗證目錄/書籤/劃線清單與書架書名顯示符合對應情境規則。

---

## Issue 4：全文檢索多變體查詢擴充

**Status:** ready-for-agent

**依賴：** Issue 0（`convertText`）、Issue 1（`GlobalReaderPrefs.reading.textConversion`，供結果摘要片段顯示轉換用）

**範圍：**
- 對使用者輸入的原始查詢字串 `q0`，產生 `qt = convertText(q0, toTraditional)`、`qs = convertText(q0, toSimplified)`，去重後得到變體清單 `variants = distinct([q0, qt, qs])`。
- **內容匹配查詢**（`searchContent`／`searchContentInBook`，`search_repository.dart:117/210`）：對 `variants` 中每個變體分別呼叫既有 `tokenizeForQuery()`，以 FTS5 `OR` 運算子組合後送入既有 `MATCH ?` 參數位置。
- **書名/作者查詢**（`searchTitleAuthor`，`search_repository.dart:97-114`）：對 `variants` 中每個變體分別跳脫既有 LIKE 萬用字元，以 SQL `OR` 串接對應的 `whereArgs`。
- 搜尋結果的內容匹配摘要片段（`ContentMatchSnippet`）在回傳給 UI 前，依「跨書情境」規則呼叫 `convertText()` 轉換後呈現。
- 索引寫入端（`book_content_fts`）**不變**，永遠索引原文。
- **跨字形截斷定位與高亮連動（審查修正 I-2）**：`SearchRepository._truncate(text, query)`（`search_repository.dart:301-309`）與 `splitHighlightSegments(text, query)`（`highlight_segments.dart:35`，經 `book_search_screen.dart:354` 呼叫）目前皆用單一 `query` 字串對 `text` 做 `indexOf`。多變體擴充上線後，若命中內容與使用者輸入字形不同（例如使用者輸入簡體「电脑」命中繁體原文「電腦」的章節），這兩處會找不到位置，`_truncate` 退化成從頭截斷（片段不置中在關鍵字上）、`splitHighlightSegments` 完全不產生高亮片段（非崩潰，是顯示品質退化）。修正方向：兩處呼叫端在比對前，改用 `variants`（第一點產生的原文/繁體/簡體三個變體）依序嘗試 `indexOf`，取第一個能在 `text` 中找到的變體做比對基準，而非只用原始 `q0`。

**單元測試要求：**
- 驗證任一查詢詞會同時擴充為原文/繁體/簡體變體，送入 FTS5 的 `MATCH` 字串包含 `OR` 組合。
- 驗證閱讀繁體原文書時以繁體字搜尋、閱讀簡體原文書時以簡體字搜尋，皆能精確命中（不因目前顯示模式而漏檢）——此為 spec 審查 C-1 修正的核心回歸案例，須明確覆蓋。
- 驗證 `searchTitleAuthor` 對多變體的 `OR` 串接查詢正確組出 SQL 與 `whereArgs`。
- 驗證內容匹配摘要片段依全域顯示模式正確轉換後呈現。
- 驗證 `_truncate` 在原文字形與查詢詞字形不同（繁簡互跨命中）時，仍能以正確變體定位、將截斷窗口置中於關鍵字，而非退回從頭截斷（審查修正 I-2）。
- 驗證 `splitHighlightSegments` 在原文字形與查詢詞字形不同時，改用能匹配上的變體後可正確產出 `isMatch: true` 的高亮片段（審查修正 I-2）。

**驗收標準：** 上述測試通過、`flutter analyze` 乾淨；真機驗證繁體/簡體原文書皆可用任一字形搜尋命中，且搜尋結果片段的截斷定位與關鍵字高亮在跨字形命中時仍正確呈現。

---

## Issue 5：TTS 朗讀文字轉換整合

**Status:** ready-for-agent

**依賴：** Issue 0（`convertText`）、Issue 1（`resolveTextConversion`）

**範圍：**
- `main.js` 的 `extractSegmentsForSection()`（683-738 行）本身不修改——`createDocument()` 建立的 DOM、算出的 `cfi` 欄位維持對應原文。
- 回傳的 `segments[].text` 在傳給語音合成器前，經過一次 `convertText(text, mode)` 轉換（`mode` 為該書「單書情境」生效值）；具體轉換發生在 JS 端回傳前或 Dart 端接收後，依現有 `buildTtsSegments()`／`buildSegmentsForSection()` 呼叫鏈的既有分工決定。
- `showTtsHighlight` 等同步高亮方法傳入的定位錨點維持使用 `cfi` 欄位（原文），不受本 Epic 影響。

**單元測試要求：**
- 驗證朗讀段文字依目前顯示模式正確轉換，`cfi` 欄位不受影響。
- `app/integration_test/`（真機）：朗讀時語音內容符合目前顯示模式；朗讀同步高亮定位不受轉換影響。

**驗收標準：** 上述測試通過；真機驗證朗讀語音文字與畫面顯示模式一致，Read-along 同步高亮定位精確度不受影響。
