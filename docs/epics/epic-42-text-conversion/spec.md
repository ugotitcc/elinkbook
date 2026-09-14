# Epic 42 — 簡繁轉換：規格 (Spec)

這是實作 `epic-42-text-conversion` 的唯一事實來源。決策的完整討論過程與理由請見 `design.md`（`/grill-with-docs` 2026-09-14／2026-09-15，15 項 Discovery 決策）與審查修訂（`reviews/review-epic-and-design.md`，2026-09-15，本檔案依專案慣例不進版控）、[ADR 0030](../../adr/0030-text-conversion-character-level-for-cfi-safety.md)（轉換精細度定案為 1:1 字元轉換）、[ADR 0031](../../adr/0031-text-conversion-dual-runtime-dictionary-not-opencc-js.md)（函式庫選型：雙端共用原始字元表，不 vendor `opencc-js`）。本文件延續 `design.md` 的所有範圍界定與審查修訂結果，不重複列出理由，僅在此定案核心介面/型別，供 Scrum Master 階段拆解工單使用。

## Problem Statement

見 `design.md`「緣起與範圍界定」。

## Solution

三態顯示切換（原文／轉換為繁體／轉換為簡體），涵蓋：

1. **資料模型**：`GlobalReaderPrefs.reading`（`ReadingDefaults`）與 `BookReaderPrefs` 各新增一個欄位，比照既有「排版方向覆寫」雙層解析模式。
2. **雙端字元轉換模組**：JS 端（WebView 顯示層，1:1 字元 DOM Walker，見 ADR 0030）與 Dart 端（純 Dart 查找表，見 ADR 0031），皆由同一份 OpenCC 原始字元表資料生成，結果一致。
3. **UI 入口**：`ReadingDefaultsScreen`（全域預設）＋ `ReaderSettingsSheet`／`FxlSettingsSheet`（單書覆寫，依格式分流）。
4. **全文檢索整合**：`SearchRepository` 查詢端 Query Expansion。
5. **TTS 整合**：朗讀段文字轉換與 CFI 錨點解耦。

## Implementation Decisions

### 資料模型

- 新增 `enum TextConversionMode { original, toTraditional, toSimplified }`（`app/lib/reader/text_conversion_mode.dart`，比照 `dual_page_mode.dart` 既有單檔單 enum 慣例）。
- `BookReaderPrefs` 新增欄位 `final TextConversionMode? textConversionOverride;`（`null` = 未覆寫，比照 `writingModeOverride`/`pageTurnModeOverride` 既有慣例）：
  - `toMap()` 新增 `'text_conversion_override': textConversionOverride?.name`。
  - `fromMap()` 新增 `textConversionOverride: enumByNameOrNull(TextConversionMode.values, map['text_conversion_override'] as String?)`。
  - `copyWith()`／`==`／`hashCode` 依既有模式一併補上此欄位。
  - `reflowableEpubFields()`：本欄位屬於流式 EPUB 版面設定實際呈現的欄位，**保留**（不強制清 null）。
- `ReadingDefaults` 新增欄位 `final TextConversionMode textConversion;`（non-nullable，預設 `TextConversionMode.original`，比照 `pageTurnMode`/`screenOrientation` 既有慣例）：
  - `copyWith()`／`==`／`hashCode` 依既有模式一併補上。
- `ReaderPrefsManagerImpl`（`app/lib/reader/reader_prefs_manager_impl.dart`）：
  - 新增 SharedPreferences key（暫名 `_textConversionKey`，比照既有 key 命名慣例）。
  - `loadGlobalPrefs()` 的 `ReadingDefaults(...)` 建構新增一行：`textConversion: _readEnum(sp, _textConversionKey, TextConversionMode.values) ?? TextConversionMode.original,`（沿用既有 `_readEnum` helper，第 102-114 行）。
  - 寫入路徑新增對應 `sp.setString(_textConversionKey, prefs.reading.textConversion.name)`。
- **生效值解析**：新增純函式（暫名 `resolveTextConversion(BookReaderPrefs book, ReadingDefaults global)`，比照專案既有「純函式優先」慣例）回傳 `book.textConversionOverride ?? global.textConversion`（審查修正 M-2：第二個參數型別為 `ReadingDefaults`，故直接取其 `textConversion` 欄位，不經過 `.reading`——`.reading` 是 `GlobalReaderPrefs` 才有的巢狀欄位，先前版本此處筆誤），供 `ReaderScreen`／各 Flutter 端渲染呼叫點統一使用，不在多處重複 `??` 邏輯。

### JS 端字元轉換模組（見 ADR 0030／ADR 0031）

- 新增 vendor 檔案（暫名 `app/android/app/src/main/assets/foliate/text_conversion_dict.js`，精確檔名/路徑留待實作階段），內容為由 `STCharacters.txt`／`TSCharacters.txt` 生成的兩個純物件字面量（`s2t`／`t2s` 查找表），比照 `foliate-js` 釘定版本、不經 npm 建置的 vendoring 慣例。
- **字典生成腳本的正規化約束（審查修正 I-3）**：OpenCC 原始字元表為 TSV 格式，右側目標欄位可能包含多個以半形空格分隔的候選字（例如 `后\t後 后`、`干\t乾 幹 干`）——生成腳本**必須**先以空白分割右側欄位、只取第一個候選字（`candidates.split(' ')[0]`），並內建 assertion 嚴格檢驗產生的每一組鍵值皆為 `key.runes.length === 1 && value.runes.length === 1`，任何一筆不滿足即中止生成，防止多字元候選字被誤植入字典而打破 ADR 0030 的 ΔL=0 前提。JS 與 Dart 兩份查找表須用同一份生成邏輯／同一次執行輸出，避免各自實作規則漂移。
- 新增 DOM Walker 函式（暫名 `applyTextConversion(root, mode)`，於 `main.js` 或獨立模組），比照 `extractSegmentsForSection`（`main.js:683-738`）既有的 `createTreeWalker`／`NodeFilter.SHOW_TEXT` 寫法：
  - 走訪範圍：目前渲染中 section 的可見文字節點，排除 `<rt>`／`<script>`／`<style>` 標籤（沿用 `extractSegmentsForSection` 既有排除清單並視需要擴充）。
  - **原始文字快取（審查修正 I-1，取代「單向反向查表還原」的錯誤假設）**：簡化字存在真實的多對一併字（例如「後」「后」皆簡化為「后」；「幹」「乾」「干」皆簡化為「干」），`s2t`/`t2s` 字典**不是雙射**，不存在無損的反向轉換——若走訪節點時原地覆寫 `node.nodeValue` 且不備份原文，切回「原文」模式時無法正確還原（例如「后」不知道該還原成「後」還是「后」）。走訪每個文字節點時，若尚未快取過，先用動態屬性存一份原文：`if (node._elinkOrigText === undefined) node._elinkOrigText = node.nodeValue;`；**任何模式切換皆以 `node._elinkOrigText` 為轉換輸入基準，絕不對已轉換的 `node.nodeValue` 做二次轉換或反向推導**：`original` 模式直接 `node.nodeValue = node._elinkOrigText`；`toTraditional`／`toSimplified` 模式對 `node._elinkOrigText` 逐字元查表後寫入 `node.nodeValue`。
  - 轉換邏輯：**逐字元查表替換**，**不得**做任何多字元 lookahead 或長度改變的替換（ADR 0030 決策 4 的硬性限制）。**注意**：ΔL=0（長度不變，保護 CFI）與「是否雙射／可逆」是兩個獨立性質——上一段的原始文字快取解決的是後者，不影響、也不依賴 ADR 0030 對前者的結論。
  - **開書當下與逐 section 觸發**：比照第 3 點「逐 section Lazy 轉換」，在 `beforeRender`／section 渲染完成的既有掛鉤點呼叫（精確整合點留待實作階段對照 `paginator.js` 現行渲染生命週期 API 查證）。
  - **閱讀中即時切換的更新路徑（審查修正 I-2）**：`buildFoliatePreferencesMap`（`foliate_reader_view.dart:98`）需新增注入 `textConversion: resolveTextConversion(...).name`。`main.js` 的 `window.applyPreferences`（194 行起）需比照既有 `writingMode` 變動偵測手法（`main.js:345-356`：僅在真的變動、而非「有帶欄位就觸發」時才動作，避免裝置旋轉等既有 `applyPreferences(lastAppliedPrefs)` 重呼叫造成多餘副作用）——偵測 `prefs.textConversion !== lastAppliedPrefs?.textConversion` 時，呼叫 `view.goTo(view.lastLocation?.cfi)` 觸發目前章節以新的轉換模式重新載入（與 `writingMode` 完全同一套既有機制，不需要另外設計對目前可見 DOM 直接重新走訪的替代路徑）。
  - **前置條件**：`app/tool/check_foliate_es_compat.js` 的 `extractPolyfillSource()` 目前寫死抓取 `foliate_reader_view.dart` 裡的 `_esCompatPolyfillJs`，但該常數已搬到 `foliate_native_bridge.dart:219` 且改名為 `esCompatPolyfillJs`（無底線前綴），腳本執行必定拋例外。**本 Epic 開始改動 `main.js`／`foliate_native_bridge.dart` 前，須先修復這支守門腳本的引用路徑**（獨立於本 Epic 的既有 bug，但會擋住本 Epic 新增 vendor 檔案的 ES 相容性檢查）。

### Dart 端字元轉換模組（見 ADR 0031）

- 新增 Dart 檔案（暫名 `app/lib/reader/text_conversion_dict.dart`），內容為由**同一份**原始字元表資料生成的 `Map<String, String>`（`kS2tDict`／`kT2sDict`，命名留待實作階段）。
- 新增純函式 `String convertText(String input, TextConversionMode mode)`（`original` 時原樣回傳，其餘依對應字典逐字元查表替換，查不到的字元維持原樣）。
- **呼叫點清單**（依 `design.md` 第 8 點「情境分流」）：
  - **單書情境**（傳入 `resolveTextConversion()` 解析後的該書生效值）：`BookTocItem.title` 渲染前（目錄面板 widget）、書籤清單章節名稱、劃線清單摘要文字（僅摘要片段，**不含**備註文字本身，見 `design.md` 第 9 點）。
  - **跨書情境**（傳入呼叫端持有的 `GlobalReaderPrefs.reading.textConversion`，不做單書覆寫；與上方 `resolveTextConversion(book, global)` 參數型別為 `ReadingDefaults` 不同層級，此處呼叫端直接持有完整 `GlobalReaderPrefs`）：書架書名/作者渲染（`LibraryScreen`）、全庫搜尋結果片段（書名/作者匹配區＋內容匹配區，見下方「全文檢索整合」）。

### UI 入口

- **全域預設**：`ReadingDefaultsScreen` 新增一列三態選擇器（沿用該畫面既有欄位樣式）。
- **單書覆寫 UI 需為含 `null` 的四態選擇器（審查修正 M-2）**：`BookReaderPrefs.textConversionOverride` 為 nullable，`null` 代表「跟隨全域預設」。比照 `reader_settings_sheet.dart:959-963` `_buildScreenOrientationOverrideRow()` 既有模式——選項清單第一項固定為 `(null, '使用全域預設', ...)`，其後才是 3 個具體列舉值——不可只做 3 個具體選項的選擇器（那樣使用者覆寫後將無法選回「跟隨全域」）。
- **依格式分流至既有版面設定 Bottom Sheet**——
  - 流式 EPUB／KF8／TXT／MD：`ReaderSettingsSheet`。
  - FXL EPUB／KF8：`FxlSettingsSheet`。
  - **CBZ 明確排除，且需要新的建構子參數（審查修正 M-1）**：`FxlSettingsSheet` 同時服務 FXL EPUB/KF8 與 CBZ（見 `CONTEXT.md`「固定版面」詞條），本控制項僅在**非 CBZ** 的 FXL 書籍開啟時顯示。核對現行建構子（`fxl_settings_sheet.dart:17-27`）只有 `prefs`／`onChanged`／`isEinkMode` 三個參數，**沒有任何格式相關資訊、也沒有既有的條件隱藏欄位邏輯可比照**——需新增建構子參數（暫名 `final bool showTextConversion;`），由呼叫端 `reader_screen.dart`（現行呼叫點約 935-943 行）依開啟中書籍格式判斷（非 CBZ）傳入，Sheet 內部依此參數決定是否渲染此欄位。這是本 Sheet 第一個格式感知的條件渲染欄位，非既有模式的延伸。
  - PDF：不顯示（`PdfSettingsSheet` 不新增此欄位）。

### 全文檢索整合（`SearchRepository`，審查修正 C-1，推翻 design.md 第 11 點 I-1 原修正方案）

**先前版本的錯誤**：原規劃「查詢字串先套用『目前顯示模式的反向字典』轉回原文」，此方案建立在「1:1 字元轉換雙向確定（bijective）」這個錯誤假設上——簡化字存在真實的多對一併字（「後」「后」皆簡化為「后」；「幹」「乾」「干」皆簡化為「干」），**不存在無損的反向字典**。若系統不記錄書籍原文語系（`design.md` 第 7 點已定案匯入時不偵測），單向反向轉換會導致：使用者設定「轉換為繁體」、正在閱讀一本**繁體原文書**，照畫面顯示的繁體字搜尋，系統卻誤套用 `toSimplified` 反向字典把查詢字串轉成簡體送查，在繁體原文書中得到 0 筆命中；全庫搜尋更會讓簡體/繁體原文書其中一類全數漏檢。

**改採多變體查詢擴充（Multi-variant Query Expansion）**，不假設任何反向關係：

- 對使用者輸入的原始查詢字串 `q0`，透過 Dart 端字典（第 4 點 `convertText`）產生 `qt = convertText(q0, toTraditional)`、`qs = convertText(q0, toSimplified)`，去重後得到變體清單 `variants = distinct([q0, qt, qs])`。
- **內容匹配查詢**（`searchContent`／`searchContentInBook`，`search_repository.dart:117/210`）：對 `variants` 中每個變體分別呼叫既有 `tokenizeForQuery()`（`cjk_tokenizer.dart:56`，本函式簽章與行為不變），以 FTS5 標準 `OR` 運算子組合後送入既有 `MATCH ?` 參數位置（例如輸入「電腦」產生 `'"電 腦" OR "电 脑"'`）——`search_repository.dart:159/257` 既有的 `WHERE book_content_fts MATCH ?` 寫法不需改動查詢結構本身，只需組出這個組合字串。
- **書名/作者查詢**（`searchTitleAuthor`，`search_repository.dart:97-114`）：對 `variants` 中每個變體分別跳脫既有 LIKE 萬用字元（沿用既有 `\\`／`%`／`_` 跳脫邏輯，`search_repository.dart:103-106`），以 SQL `OR` 串接對應的 `whereArgs`（例如 2 個變體時 `WHERE (title LIKE ? OR author LIKE ?) OR (title LIKE ? OR author LIKE ?)`，`variants` 只有 1 項時等同現行行為不變）。
- 搜尋結果的內容匹配摘要片段（`ContentMatchSnippet`，`search_repository.dart:12-22`）在回傳給 UI 前，依上方「Dart 端字元轉換模組」的「跨書情境」規則呼叫 `convertText()` 轉換後呈現，此點不受本次修正影響。
- 索引寫入端（`SqliteSearchRepository`／`foliate_content_indexer.dart` 等既有索引建置路徑）**不變**，`book_content_fts` 永遠索引原文，不受本 Epic 影響。

### TTS 整合（見 `design.md` 第 11 點 I-2 修正）

- `main.js` 的 `extractSegmentsForSection()`（683-738 行）本身**不修改**——`createDocument()` 建立的 DOM、算出的 `cfi` 欄位維持對應原文，不受轉換影響。
- 回傳的 `segments[].text` 在傳給語音合成器前，需經過一次 `convertText(text, mode)` 轉換（`mode` 為該書「單書情境」生效值）——具體轉換發生在 JS 端回傳前一併處理，還是 Dart 端接收 `segments` 後、餵給 TTS 引擎前處理，留待實作階段依現有 `buildTtsSegments()`／`buildSegmentsForSection()` 呼叫鏈的既有分工決定（見 `main.js:678-682` 共用邏輯註解）。
- `showTtsHighlight` 等同步高亮方法傳入的定位錨點維持使用 `cfi` 欄位（原文），不受本 Epic 影響。

### Markdown 匯出

不需新增程式碼——`highlights`/`notes`/`bookmarks` 資料表儲存的摘要片段欄位本來就恆為原文（顯示層轉換只發生在畫面渲染當下，從不寫回資料庫），匯出服務直接讀 DB 欄位即自然保證原文（見 `design.md` 第 10 點 M-2 澄清）。

## Migration

- SQLite 版本自 25 升級至 26：`book_reader_prefs` 新增欄位 `text_conversion_override TEXT`（可空，既有裝置升級後自動為 `NULL`，語意等同「未覆寫」，不需要額外回填邏輯——比照既有欄位新增的一貫模式，非本 Epic 特有）。
- **遷移程式碼放置位置（審查修正 M-3）**：核對 `sqlite_library_repository.dart:144-239`，`onUpgrade` 對 `book_reader_prefs` 表的每一次欄位新增皆嚴格放在 `else`（`oldVersion >= 2`）分支內、以 `if (oldVersion < N)` 包住（例如既有 `_addPdfReaderPrefsColumns`／`_addDualPageColumns`／`_addLetterSpacingColumn` 等皆同一模式）——因為 `oldVersion < 2` 時 `_createBookReaderPrefsTable` 已一步到位建表含全部既有欄位，若在 `else` 分支外無條件執行 `ALTER TABLE`，會讓 `oldVersion == 1` 的裝置對剛建好、已含新欄位的表重複 `ALTER TABLE` 拋出 `duplicate column name` 例外。本次新增的 `text_conversion_override` 須比照同一慣例，寫成 `else` 分支內的 `if (oldVersion < 26) { await _addTextConversionColumn(db); }`，不得放在 `if/else` 區塊外。
- `ReadingDefaults.textConversion` 全域預設值：既有裝置升級後，對應 SharedPreferences key 讀不到值，`_readEnum()` 回傳 `null`，`??` 退回 `TextConversionMode.original`，無需遷移程式碼。

## Testing Decisions

- **`app/test/`**（純 Dart／widget test）：
  - `convertText()`／JS 端查找表（若可透過既有 `main.js` 單元測試基礎設施，如 `@xmldom/xmldom` 對照測試模式，比照 `check_foliate_es_compat.js` 既有驗證手法）：已知字元對正確轉換、查不到的字元原樣保留、`original` 模式恆等於輸入。
  - `resolveTextConversion()` 純函式：`book.textConversionOverride` 非 null 時優先於 `global.textConversion`；為 null 時回退全域值。
  - `BookReaderPrefs`／`ReadingDefaults` 的 `toMap`/`fromMap`/`copyWith`/`==`/`hashCode` 新欄位往返正確（比照既有欄位測試模式）。
  - `SqliteSearchRepository` 查詢端多變體擴充（審查修正 M-4）：驗證任一查詢詞會同時擴充為原文/繁體/簡體變體，送入 FTS5 的 `MATCH` 字串包含 `OR` 組合；驗證閱讀繁體原文書時以繁體字搜尋、閱讀簡體原文書時以簡體字搜尋，皆能精確命中（不因目前顯示模式而漏檢）。
  - DOM Walker 原始文字還原（審查修正 M-4）：模擬文本含併字字元（如「幹」「后」），走過 `original` → `toSimplified` → `original` 循環後，文字節點內容須與初始原文 100% 一致（驗證 `_elinkOrigText` 快取機制無損）。
  - `FxlSettingsSheet` widget 測試（審查修正 M-4）：傳入 `showTextConversion: true`（FXL EPUB/KF8）時顯示簡繁轉換選項；傳入 `showTextConversion: false`（CBZ）時該控制項不存在。
  - `check_foliate_es_compat.js` 修復後應可正常執行不拋例外（回歸驗證前置條件已修復）。
- **CFI 穩定性回歸測試（ADR 0030 核心不變量的直接驗證，優先度最高）**：以既有劃線/書籤整合測試 fixture 為基礎，驗證「在『轉換為繁體』模式下建立一筆劃線 → 切回『原文』模式 → 該劃線仍精確框住同一段原文文字（CFI 解析結果與轉換前一致）」；反向（原文模式建立、切到轉換模式驗證）亦須覆蓋。
- **`app/integration_test/`**（真機）：DOM Walker 實際套用於已渲染 WebView 內容後，既有劃線/書籤渲染位置不偏移；TTS 朗讀文字确实依目前顯示模式呈現、朗讀同步高亮定位不受影響。

## Out of Scope

見 `design.md`「明確排除於本 Epic 之外」，本文件不重複列出。額外補充（Architecting 階段確認）：詞彙/片語＋兩岸慣用詞感知轉換（ADR 0030 已正式排除，非本 Epic 範圍，亦非「留待未來」的既定計畫，需要另立 Epic／ADR 重新評估才能重啟）。

## Further Notes

- 本規格未列出所有欄位/方法的最終精確簽章（例如 JS/Dart 查找表的確切變數命名、DOM Walker 與 `paginator.js` 渲染生命週期的精確掛鉤點、原始字元表轉換腳本的產生方式），實作前請參閱 `design.md`「本次落地範圍」與本文件「Implementation Decisions」，實際簽章留待實作計畫階段（`plans/plan-issue-N.md`）決定（比照本專案一貫的 `spec.md` 慣例，見 `epic-8-sync/spec.md`「Further Notes」先例）。
- `FxlSettingsSheet` 內「依格式條件式隱藏單一欄位」而非「整張 Sheet 依格式切換」是本文件相對於 `design.md` 字面「CBZ／PDF 版面設定畫面完全不顯示」措辭的精確化，原因是 `FxlSettingsSheet` 本身就是 CBZ 與 FXL EPUB/KF8 共用的同一張 Sheet（見 `CONTEXT.md`「固定版面」詞條），並非各自獨立的畫面；核對現行建構子（`fxl_settings_sheet.dart:17-27`）並無既有的格式感知條件渲染邏輯可供比照，`showTextConversion` 是這張 Sheet 第一個此類參數（審查修正 M-1，見「UI 入口」）。
- **本文件於 2026-09-15 依審查報告（`reviews/review-spec.md`，本檔案依專案慣例不進版控）修訂**：推翻了原規劃的「查詢端反向字典轉換」（C-1，改採多變體查詢擴充）與「DOM Walker 無備份直接反向推導」（I-1，改採 `_elinkOrigText` 原始文字快取）兩個建立在錯誤雙射假設上的方案；兩者的錯誤根源相同——1:1 字元轉換保證「長度不變（ΔL=0，ADR 0030 的結論，未受影響）」，但**不保證「雙向可逆」**，這是兩個獨立性質，未來修訂本文件時應避免重蹈同一種混淆。
