# Epic 42 — 簡繁轉換：工單清單 (Issues)

依 `spec.md`（唯一事實來源，含 ADR 0032／ADR 0031、offset-mapping-spec.md 與 spec 審查修訂）拆解為 Issue 0-5。**Issue 0 優先開始；Issue 1 依賴 Issue 0（`TextConversionMode` enum 定義）；Issue 2-5 皆阻塞於 Issue 0＋Issue 1，但彼此互相獨立、可平行進行**（2026-09-15 決策確認方案 A：簡轉繁 `s2twp`＋雙向分段偏移映射，繁轉簡 `tw2s` 保留原著文風）。

> **2026-09-15 文件現況更正**：本檔案的 Issue 0 段落已依上述方案 A 改寫「範圍」／「單元測試要求」為目標終態（`s2twp`＋`TWPhrases`＋`TextOffsetMap`），但 PR [#245](https://git.jigong.org/huthief/elinkBook/pulls/245) 實際合併進 `main` 的程式碼，是**改寫之前**、依已被 ADR 0032 取代的 ADR 0030（純字元 1:1、無詞彙、無偏移映射）完成的——`app/tool/opencc_data/` 只有 `STCharacters.txt`／`TSCharacters.txt`，尚無 `TWPhrases.txt`／`TWVariants.txt`；`app/lib/reader/text_conversion.dart`／`text_conversion_dict.dart` 與 JS 端字典皆仍是舊版純字元查找表；全專案（JS＋Dart）尚無 `TextOffsetMap` 類別。**Issue 0 的「Status: completed」僅涵蓋舊方案（ADR 0030）**，方案 A（ADR 0032）新增的台灣常用詞字典與雙向偏移映射範圍另立 **Issue 0b**（見下）補齊，**Issue 2 除依賴 Issue 0／Issue 1 外，另新增依賴 Issue 0b**（`TextOffsetMap`／`s2twp`／`tw2s` 字典為 Issue 2 DOM Walker 的直接前提）。Issue 1（資料模型＋UI）不受此落差影響，僅依賴穩定不變的 `TextConversionMode` enum，可依現有範圍直接開工。

---

## Issue 0：前置修復＋雙端字典生成（支援台灣常用詞）

**Status:** completed（僅涵蓋舊方案 ADR 0030 範圍，見上方「2026-09-15 文件現況更正」；`plans/plan-issue-0.md` 5 個 Task 全數完成，`check_foliate_es_compat.js` 常數引用漂移已修復，`TextConversionMode` enum／`convertText()`／`parseCharTable()`／JS-Dart 雙端同源查找表〔純字元 1:1，`STCharacters.txt`／`TSCharacters.txt`〕皆已落地，`flutter analyze`/`flutter test`／`node` 腳本測試全數通過。獨立程式審查 `reviews/review-issue-0.md`：0 Critical／0 Important／2 Minor，皆已修訂〔移除 `epubcfi.js:266` 行號耦合、vendor OpenCC LICENSE 全文〕，結論 Ready to merge: Yes。**方案 A（ADR 0032）新增的 `TWPhrases`／`s2twp`／`tw2s` 字典與 `TextOffsetMap` 演算法尚未實作，見 Issue 0b**）

**依賴：** 無（可立即開始）

**範圍：**
- 修復 `app/tool/check_foliate_es_compat.js` 的 `extractPolyfillSource()`：目前寫死抓取 `foliate_reader_view.dart` 裡的 `_esCompatPolyfillJs`，修正引用路徑至 `foliate_native_bridge.dart:219` 的 `esCompatPolyfillJs`，確認腳本可正常執行不拋例外。
- 新增字典生成腳本（`app/tool/generate_conversion_dicts.js`），輸入為 OpenCC 原始字元與常用詞表（`STCharacters.txt`、`TSCharacters.txt`、`TWPhrases.txt`、`TWVariants.txt` 等，存放於 `app/tool/opencc_data/`）。依據 **方案 A（ADR 0032）** 輸出兩端查找表：
  - **簡轉繁（`toTraditional`）**：`s2twp` 字典組合（單字＋`TWPhrases` 817 條台灣在地化慣用語，如「記憶體」、「軟體」、「程式碼」、「伺服器」）。
  - **繁轉簡（`toSimplified`）**：`tw2s` 字典組合（標準台繁到簡體字形，不套用大陸用語，忠實保留原著風格）。
  - JS 端 vendor 檔案（`app/android/app/src/main/assets/foliate/text_conversion_dict.js`）。
  - Dart 端檔案（`app/lib/reader/text_conversion_dict.dart`）。
- 新增 `enum TextConversionMode { original, toTraditional, toSimplified }`（`app/lib/reader/text_conversion_mode.dart`）。
- 新增 Dart 純函式 `String convertText(String input, TextConversionMode mode)` 與 `TextOffsetMap` 演算法類別（支援片語匹配與字元替換）。

**單元測試要求：**
- `convertText()`：
  - 簡轉繁（`s2twp`）：驗證一般字形轉換（如「后」→「後」）與台灣慣用詞轉換（如「内存」→「記憶體」、「软件」→「軟體」）。
  - 繁轉簡（`tw2s`）：驗證字形轉換（如「記憶體」→「记忆体」、「妥瑞氏症」→「妥瑞氏症」，不被替換為大陸詞彙）。
  - 查不到之字詞原樣保留；`original` 模式恆等於輸入。
- 字典生成腳本：驗證產出的 JS 與 Dart 檔案結構正確，語法可通過 `node --check`。
- `check_foliate_es_compat.js` 修復後可正常執行完畢、不拋例外。

**驗收標準：** 上述測試通過；雙端字典檔案已 vendor 進版控；`flutter analyze` 乾淨。

---

## Issue 0b：台灣常用詞字典擴充＋`TextOffsetMap` 演算法（補齊 Issue 0 的 ADR 0032 落差）

**Status:** completed（2026-09-15 新增——`0d2a1e90`「簡轉繁的部份，改為轉換為台灣常用語」把方案由 ADR 0030 升級為 ADR 0032，但僅改寫本檔案 Issue 0 段落文字與 `spec.md`，未同步更新 Issue 0「Status」、未實際落地程式碼；本 Issue 補齊該落差，見上方「2026-09-15 文件現況更正」。**2026-09-15 已完成並合併回 `main`（PR [#246](https://git.jigong.org/huthief/elinkBook/pulls/246)，分支 `feat/epic-42-issue-0b`）**：`plans/plan-issue-0b.md` 7 個 Task 全數完成——vendor `TWPhrases.txt`（818 條）／`TSPhrases.txt`（480 條）、`parsePhraseTable()`／`assertMaxPhraseKeyLength()`、`s2twpPhraseDict`／`tw2sPhraseDict` 雙端字典、`TextOffsetMap`（Dart＋JS）、`convertText()` 片語優先轉換（`toTraditional` 兩階段／`toSimplified` 單一階段不對稱設計）、新增 `convertTextDetailed()`／`applyTextConversionToString()`。獨立程式審查（`reviews/review-issue-0b.md`）：0 Critical／0 Important／1 Minor（README.md 詞條數量誤差，已修訂），結論 Ready to merge: Yes。`node`／`flutter test`／`flutter analyze` 全數通過零回歸。Issue 2 現已可開工。）

**依賴：** Issue 0（既有 `TextConversionMode` enum／`convertText()` 介面／`parseCharTable()` 生成腳本框架，本 Issue 在其上擴充，不變更既有函式簽章）

**範圍：**
- **補齊字典來源檔案**：從 BYVoid/OpenCC 官方倉庫取得 `TWPhrases.txt`（簡轉繁台灣慣用語，817 條）與 `TWVariants.txt`（若 `tw2s` 標準台繁轉簡體字形需要），存放於既有 `app/tool/opencc_data/`，比照既有 `STCharacters.txt`／`TSCharacters.txt` 的 vendoring 慣例（含 LICENSE 來源標註）。
- **改寫 `generate_conversion_dicts.js`，依方案 A（ADR 0032）輸出非對稱字典組合**：
  - `toTraditional`（簡轉繁）：`s2twp` = 單字對照（既有 `STCharacters.txt`）＋`TWPhrases` 詞彙前綴樹（Trie，支援最長匹配優先，避免詞彙內部字元被單字表提前置換）。
  - `toSimplified`（繁轉簡）：`tw2s` = 標準台繁轉簡體字形（既有 `TSCharacters.txt`），**不**套用 `tw2sp` 大陸用語，維持原著文風。
  - 既有「多候選字取第一個」「單字元 assertion」正規化約束（Issue 0 已落地）延伸適用於詞彙表：詞彙表的鍵/值兩側各自允許多字元（非 Issue 0 單字元限制），但同一鍵不得重複、值不得為空字串。
- **新增 `TextOffsetMap` 演算法類別**（依 `offset-mapping-spec.md` 第 2 節 `origToDisplay`／`displayToOrig` 演算法規格逐一實作）：
  - **Dart 端**：`app/lib/reader/text_conversion.dart`（或獨立新檔）新增 `TextOffsetMap` 類別＋`OffsetEntry` 資料結構，供 Issue 2 JS 端邏輯移植對照與 Dart 端未來潛在需求（例如 TTS 單字級高亮，見 `offset-mapping-spec.md` 4.1 節）共用同一份演算法定義／測試向量。
  - **JS 端**：於 `text_conversion_dict.js` 或獨立新模組實作對應的 `TextOffsetMap`／`origToDisplay`／`displayToOrig` 函式（供 Issue 2 DOM Walker 直接引用，Issue 2 本身不重新實作演算法）。
  - `convertText()`／JS 端轉換函式擴充為**片語優先、單字元其次**的比對邏輯（Trie 或等效最長匹配），並在替換過程中同步收集 `[origOffset, origLen, dispOffset, dispLen]` 區段，供建構 `TextOffsetMap`。

**單元測試要求：**
- 字典生成腳本：驗證 `s2twp` 輸出含 `TWPhrases` 詞彙（如「内存」→「記憶體」、「软件」→「軟體」）且長度可不同於原字元數；驗證 `tw2s` 輸出不含大陸用語替換（如「妥瑞氏症」原樣保留）。
- `convertText()`／JS 端轉換：片語最長匹配優先於單字元替換（例如同時存在「记忆」單字對照與「记忆体」詞彙時，優先套用詞彙）。
- `TextOffsetMap`（Dart／JS 各自）：依 `offset-mapping-spec.md` 2.2 節演算法逐一覆蓋——`origToDisplay`／`displayToOrig` 於區段內／區段外／區段邊界（Floor/Ceil snap policy）之正確性；長度不變節點（97.6%）`offsetMap` 為 `null` 時直接回傳原 offset（零開銷路徑）。
- 邊界案例：連續多個非等長替換區段（`accumDelta` 累計正確性）；Unicode 代理對（Astral Plane，UTF-16 佔 2 code units）替換造成的偏移。

**驗收標準：** 上述測試通過；`node --check` 語法驗證雙端字典檔案；`flutter analyze` 乾淨；產出的 `TextOffsetMap` 演算法與 `offset-mapping-spec.md` 逐條數學定義一致（供 Issue 2 直接消費，Issue 2 開工前必須先完成本 Issue）。

---

## Issue 1：資料模型＋全域/單書 UI 入口

**Status:** completed（**2026-09-15 已完成並合併回 `main`（PR [#247](https://git.jigong.org/huthief/elinkBook/pulls/247)，分支 `feat/epic-42-issue-1`）**：`plans/plan-issue-1.md` 8 個 Task 全數完成——`BookReaderPrefs.textConversionOverride`／`ReadingDefaults.textConversion`／`resolveTextConversion()`＋SQLite v25→v26 遷移＋`ReadingDefaultsScreen`／`ReaderSettingsSheet`／`FxlSettingsSheet` UI。獨立程式審查（`reviews/review-issue-1.md`）：0 Critical／0 Important／2 Minor，結論 Ready to merge: Yes。`flutter test`（9 個目標測試檔合計 525 項）／`flutter analyze` 全數通過零回歸。Issue 2 現已可開工。）

**依賴：** Issue 0

**範圍：**
- `BookReaderPrefs` 新增欄位 `final TextConversionMode? textConversionOverride;`（`null` = 未覆寫）：`toMap()`／`fromMap()`／`copyWith()`／`==`／`hashCode` 依既有欄位模式一併補上；`reflowableEpubFields()` 保留此欄位（不強制清 null）。
- `ReadingDefaults` 新增欄位 `final TextConversionMode textConversion;`（non-nullable，預設 `TextConversionMode.original`）：`copyWith()`／`==`／`hashCode` 依既有模式一併補上。
- `ReaderPrefsManagerImpl`：新增 SharedPreferences key、`loadGlobalPrefs()` 讀取（沿用既有 `_readEnum` helper）、寫入路徑補上對應 `sp.setString(...)`。
- 新增純函式 `resolveTextConversion(BookReaderPrefs book, ReadingDefaults global)`，回傳 `book.textConversionOverride ?? global.textConversion`。
- SQLite 版本 25→26：`book_reader_prefs` 新增欄位 `text_conversion_override TEXT`（可空）。遷移程式碼須放在 `sqlite_library_repository.dart` 既有 `else`（`oldVersion >= 2`）分支內的 `if (oldVersion < 26)`。
- **全域預設 UI**：`ReadingDefaultsScreen` 新增一列三態選擇器。
- **單書覆寫 UI**：`ReaderSettingsSheet`（流式 EPUB／KF8／TXT／MD）與 `FxlSettingsSheet`（FXL EPUB／KF8）皆新增含 `null` 的四態選擇器。`FxlSettingsSheet` 需新增建構子參數 `final bool showTextConversion;`，非 CBZ 時顯示。PDF 不新增此欄位。

**單元測試要求：**
- `BookReaderPrefs`／`ReadingDefaults` 的 `toMap`/`fromMap`/`copyWith`/`==`/`hashCode` 新欄位往返正確。
- `resolveTextConversion()`：`book.textConversionOverride` 非 null 時優先於 `global.textConversion`；為 null 時回退全域值。
- SQLite migration（v25→v26）：既有裝置升級後 `text_conversion_override` 存在且為 `NULL`；模擬 `oldVersion == 1` 升級不拋 `duplicate column name` 例外。
- Widget test：`ReadingDefaultsScreen` 三態選擇器可正確切換並持久化。
- Widget test：`ReaderSettingsSheet`／`FxlSettingsSheet` 四態選擇器正確寫回 `textConversionOverride`。
- Widget test：`FxlSettingsSheet` 依 `showTextConversion` 決定是否渲染。

**驗收標準：** 上述測試通過、`flutter analyze` 乾淨；系統設定與單書設定切換此偏好正確持久化。

---

## Issue 2：JS 端 DOM Walker 與雙向分段偏移映射（CFI 保護）

**Status:** completed（**2026-09-16 已完成並合併回 `main`（PR [#248](https://git.jigong.org/huthief/elinkBook/pulls/248)，分支 `feat/epic-42-issue-2`）**：`plans/plan-issue-2.md`（經 `review-plan-issue-2.md` 審查修正 2 項 Critical──C-1 `toOriginalRange()` 須回傳純資料物件、不得建構真實 DOM Range；C-2 `resolveDisplayRange()` 須在呼叫 `anchor(doc)` 前暫時復原已轉換節點原文，不得事後調整其回傳值──與 2 項 Important／2 項 Minor 後定案）6 個 Task 全數完成：新增 `text-conversion-walker.js`（`applyTextConversion`／`adjustOffsetForCfi`／`toOriginalRange`／`resolveDisplayRange`）、`main.js` 對 `view.getCFI`／`view.resolveCFI` 做實例層級方法遮蔽（全專案唯一 Range↔CFI 轉換入口，涵蓋 `view.js` 內部 `#onRelocate()`／`#toSearchMatch()`／`resolveNavigation()`）、DOM Walker 接線至 `'load'` 事件與 `window.applyPreferences()` 即時切換（並重新呼叫 `window.setDecorations()` 修正既有標記錯位）、`FoliateReaderView.textConversion` 建構參數、`reader_screen.dart` 傳入 `resolveTextConversion()` 解析結果、CFI 穩定性回歸整合測試。獨立程式審查（`reviews/review-issue-2.md`）：實際執行全部驗證指令（含另開 worktree 跑 `.mjs` 測試／`flutter analyze`／327 項目標 `flutter test`／獨立查證 `view.js`／`epub.js` 原始碼確認方法遮蔽涵蓋所有呼叫點），確認 0 Critical／0 Important（僅真機 `integration_test` 待執行，非實作缺口）／2 Minor（`resolveDisplayRange()` try/finally 無 catch 之隱含假設、`applyPreferences()` truthy 判斷之未來限制，皆已於合併前補上說明註解），結論 Ready to merge: Yes。至此 CFI（劃線／書籤／閱讀位置／TTS）在簡繁顯示轉換下的座標保護已完整落地，Issue 3-5（皆依賴 Issue 0／Issue 1，彼此獨立）已可開工。）

**依賴：** Issue 0（字典檔案／`convertText`）、Issue 0b（`TWPhrases`／`s2twp`／`tw2s` 字典與 `TextOffsetMap` 演算法，本 Issue 的 DOM Walker 直接消費、不重新實作）、Issue 1（`resolveTextConversion`／偏好設定管線）

**範圍：**
- 新增 DOM Walker 函式 `applyTextConversion(root, mode)`（於 `main.js` 或獨立模組），走訪目前渲染中 section 的可見文字節點，排除 `<rt>`／`<script>`／`<style>` 標籤。
- **原始文字快取**：文字節點首次走訪時，動態快取原文（`if (node._elinkOrigText === undefined) node._elinkOrigText = node.nodeValue;`），任何模式轉換皆以 `node._elinkOrigText` 為基準輸入。
- **雙向分段偏移映射（`TextOffsetMap`，見 ADR 0032 與 `offset-mapping-spec.md`）**：
  - 在進行 `s2twp` 詞彙替換時，若 `dispText.length !== origText.length`（全量約 2.4%，含「記憶體」等 237 條長度改變詞彙與擴展區代理對），建立 `TextOffsetMap` 綁定於 `node._elinkOffsetMap`；其餘 97.6% 節點保持 `null`（零開銷）。
  - **`fromRange` 攔截**：使用者在畫面選取文字建立劃線時，透過 `displayToOrig(map, offset, snapPolicy)` 將選取座標轉為原始未轉換文字的 offset，再傳給 `epubcfi.fromRange`，保證存入資料庫的 CFI 100% 依據原文。
  - **`toRange` 攔截**：讀取 CFI 還原劃線時，透過 `origToDisplay(map, offset)` 將原文 offset 映射回 live DOM 當下位置，精確包裹台灣常用詞，且杜絕 `IndexSizeError`。
- **觸發與即時切換**：
  - 新章節載入：在 `view.addEventListener('load', ...)` 監聽器內對 `e.detail.doc` 執行轉換。
  - 閱讀中即時切換：`window.applyPreferences` 偵測 `prefs.textConversion` 變動時，走訪 `view.renderer.getContents()` 所有可見 `doc` 原地執行 `applyTextConversion` 刷新。

**單元測試要求：**
- **CFI 穩定性回歸測試（核心）**：
  - 包含非等長詞彙（例如原文「内存」，轉換為「記憶體」；或「方便面」→「泡麵」）的段落，驗證在繁體模式下建立劃線，產生的 CFI 反查原文位置 100% 正確；切回原文模式劃線精確落在「内存」上；切回繁體模式再度精確落在「記憶體」上，無任何字元偏斜。
  - 邊界貼齊測試：驗證光標落在置換詞中間時，Floor/Ceil 貼齊策略可完整框選整個詞彙。
- DOM Walker 原始文字還原：走過 `original` → `toTraditional` → `original` 循環後，文字節點內容與初始原文 100% 一致。
- `app/integration_test/`（真機）：在 WebView 內切換模式時畫面即時刷新，台灣常用詞正確呈現且既有劃線不偏移。

**驗收標準：** 上述測試通過；真機開啟 EPUB 驗證簡轉繁具備台灣在地化詞彙（「記憶體」、「軟體」等），繁轉簡忠實保留原著文風，劃線與書籤在三態切換下定位 100% 精確穩定。

---

## Issue 3：Dart 端跨畫面顯示轉換

**Status:** completed（**2026-09-16 已完成並合併回 `main`（PR [#249](https://git.jigong.org/huthief/elinkBook/pulls/249)，分支 `feat/epic-42-issue-3`）**：`plans/plan-issue-3.md`（經 `reviews/review-plan-issue-3.md` 審查修正 1 項 Critical──C-1 `BookCover`／`CoverPlaceholder` 遺漏轉換導致 Task 4 測試斷言邏輯矛盾──與 2 項 Important（I-1 `_openBookActionSheet` 動作選單標題漏轉、I-2 `_initialize()` 的 `unawaited` 造成啟動畫面閃爍競態）／1 項 Minor（M-1 `_currentChapterTitle()` 待活化方法字形遺漏）後定案；1 項 Minor M-2〔全套 `flutter test` 改限定測試清單〕經技術理由駁回未採納）4 個 Task 全數完成：`TocBottomSheet`／`NotesBottomSheet` 新增 `textConversion` 建構參數（預設 `TextConversionMode.original`，比照 `FxlSettingsSheet.showTextConversion` 既有先例向後相容）、`ReaderScreen` 新增 `_textConversionMode`／`_displayBookTitle`／`_displayBookAuthor` 三個私有 getter 收斂所有單書情境渲染點（頁首、底部工具列、單書搜尋標題、目錄、筆記）、`LibraryScreen` 新增 `_textConversion` 全域跨書情境狀態並接線至書架格狀/列表視圖、繼續閱讀列、書籍詳細資料對話框、單書動作選單、`BookCover`／`CoverPlaceholder`。獨立程式審查（`reviews/review-issue-3.md`）：實際執行全部 6 個目標測試檔（401 項）與 `flutter analyze`，確認 0 Critical／1 Important（TTS 背景播放系統通知欄/鎖定畫面書名〔`reader_screen.dart:3145`〕未轉換，此呼叫點從未列於本 Issue 範圍，屬 issues.md 原始範圍疏漏而非實作偏離）／1 Minor（Task 4 兩則測試斷言需依 C-1 修正後的真實畫面結構訂正，屬合理修正），Important 發現已於審查後追加 commit 補上（`fix(reader): TTS 系統通知/鎖定畫面書名接上簡繁顯示轉換`，並新增對應測試），結論 Ready to merge: Yes。**已知範圍落差（非本 Issue 遺漏，供未來參考）**：issues.md 原始範圍「劃線清單摘要片段」需轉換一項，經查證 `Highlight` model 從未儲存原文片段（`markdown_export.dart` 既有設計決策）故無對應程式碼可改；`BookSearchScreen` 的書名/作者轉換僅涵蓋 `ReaderScreen._buildSearchableBook()` 單書搜尋入口，`LibrarySearchScreen` 全庫搜尋下鑽入口維持不轉換，留待 Issue 4 或另立工單處理。）

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

**Status:** completed（**2026-09-16 已完成並合併回 `main`（PR [#250](https://git.jigong.org/huthief/elinkBook/pulls/250)，分支 `feat/epic-42-issue-4`）**：`plans/plan-issue-4.md`（經 `reviews/review-plan-issue-4.md` 審查修正 1 項 Critical（C-1 `LibrarySearchScreen` 的 `BookCover` 漏傳 `textConversion` 導致封面縮略字與標題字形矛盾）、3 項 Important（I-1 `initState()` 用 `unawaited` 造成偏好載入與初始查詢並行競態、I-2 `BookSearchScreen` AppBar 單書情境轉換改為畫面自行解析而非依賴呼叫端預先轉換、I-3 缺少 `splitHighlightSegments` 跨字形命中純函式單元測試）與 2 項 Minor（M-1 `_buildHighlightedText` 重複呼叫 `queryVariants`、M-3 `tokenizedVariants` 去重防禦）後定案）4 個 Task 全數完成：新增共用純函式模組 `search_query_variants.dart`（`queryVariants()`／`findMatchingVariant()`，正向產生原文/繁體/簡體三個變體，不做反向字典轉換）；`SqliteSearchRepository` 三個查詢方法（`searchTitleAuthor`／`searchContent`／`searchContentInBook`）與 `_truncate()` 改用多變體查詢，修正跨字形命中時的截斷定位；`BookSearchScreen` 內容匹配摘要片段套用全域（跨書情境）顯示轉換、關鍵字高亮改用跨字形變體比對，AppBar 標題／工具列作者改為畫面自行解析單書情境轉換模式；`LibrarySearchScreen` 書名/作者匹配區、內容匹配區書籍標頭與摘要片段套用全域顯示轉換，含 `BookCover.textConversion`。獨立程式審查（`reviews/review-issue-4.md`）：實際執行全部 5 個目標測試檔（84 項）與 `flutter analyze`，確認 0 Critical／0 Important／1 Minor（整個 repo 相對目前 Dart SDK 版本存在既有格式化工具鏈落差，經交叉驗證與本次異動無關），結論 Ready to merge: Yes，未產生任何審查後追加 commit。）

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
