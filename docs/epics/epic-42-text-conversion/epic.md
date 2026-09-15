# Epic 42：簡繁轉換（FR-48）

## 背景

`docs/prd.md` FR-48 定義了「簡繁轉換」功能：閱讀 ePub3、KF8 (AZW3)、TXT、Markdown (MD) 時，提供「原文／轉換為繁體／轉換為簡體」三態顯示切換，支援雙向轉換；純顯示層轉換，不修改原始檔案內容；可於系統設定提供全域預設，個別書籍可覆寫（比照 FR-10／FR-37／FR-38 全域預設＋單書覆寫雙層模式）。CBZ（純圖像格式）、PDF（非可重排文字渲染架構）不適用。與 TXT 匯入既有之編碼偵測（FR-12）為不同層級的獨立功能。

PRD 明確記載「簡繁轉換（FR-48）之技術架構：尚無研究報告⋯留待該功能啟動 Discovery／Architecting 階段（`/grill-with-docs`／`/to-spec`）決定」。2026-09-14 透過 `/grill-with-docs` 展開 Discovery。

## 目標

1. 釐清轉換精細度、執行位置、與既有 CFI 定位／劃線座標的相容性策略。
2. 確認資料儲存歸屬（全域預設＋單書覆寫）與 UI 入口位置。
3. 界定與全文檢索（FTS5）、TTS 朗讀等既有功能的互動邊界。
4. 產出 `design.md`，作為後續 Architecting（`spec.md`）與 Issue 拆分的依據。

## Discovery 結論（2026-09-14／2026-09-15 `/grill-with-docs`；2026-09-15 審查修訂）

三態顯示切換（原文／轉換為繁體／轉換為簡體），採 WebView JS 顯示層轉換、逐 section lazy 轉換；資料沿用 `GlobalReaderPrefs`＋`book_reader_prefs` 既有雙層模式、不同步雲端；各畫面依「單書情境」／「跨書情境」分流轉換規則，使用者自建備註文字與 Markdown 匯出永遠維持原文。**2026-09-15 審查（[review-epic-and-design.md](./reviews/review-epic-and-design.md)）推翻並修正兩項原案**：(1) 轉換精細度由「詞彙/片語＋兩岸慣用詞感知（`s2twp`/`tw2sp`）」退回「字元對字元 1:1 轉換（`s2t`/`t2s`）」——詞彙級轉換的非等長字元變化會讓 `epubcfi.js` 的 Range/Selection offset 在轉換前後失真，只有 1:1 轉換（ΔL 恆為 0）才能讓「CFI 永遠對原文運作」這個核心限制真正成立；(2) 函式庫選型由 vendor `opencc-js` 套件改為 vendor OpenCC 最底層的原始字元對照表，JS 端與 Dart 端共用同一份資料來源各自實作輕量查找（Dart AOT 執行環境無法直接呼叫 JS 函式庫，原案「Dart 端也呼叫 opencc-js」在架構上不成立）。另修正全文檢索為「索引維持原文、查詢端做 Query Expansion」（避免使用者照畫面顯示的字搜尋卻 0 筆結果）、TTS 朗讀文字轉換為明確的額外字串轉換步驟（非自動繼承畫面顯示狀態）。完整定案細節見 [design.md](./design.md)。

## 目前狀態

Architecting 完成，`spec.md` 已產出（自此為本 Epic 唯一事實來源），並記錄兩項 ADR：[ADR 0030](../../adr/0030-text-conversion-character-level-for-cfi-safety.md)（1:1 字元轉換定案）、[ADR 0031](../../adr/0031-text-conversion-dual-runtime-dictionary-not-opencc-js.md)（雙端共用原始字元表、不 vendor `opencc-js`）。Scrum Master 階段完成並經一輪審查修訂，已拆分 Issue 0-5（`issues.md`）：Issue 0 優先開始，Issue 1 依賴 Issue 0（`TextConversionMode` enum，審查修正原「彼此獨立」誤判），Issue 2-5 阻塞於 0＋1、彼此獨立可平行。審查另修正 Issue 2 閱讀中即時切換機制（`view.renderer.getContents()` 取代無效的 `view.goTo()`）、Issue 4 補齊跨字形搜尋摘要截斷/高亮連動、Issue 3 補齊 `ReaderScreen` 頁首/導覽列書名轉換、Issue 0 補齊字典來源規範。

**2026-09-15 Issue 0 已完成並合併回 `main`（PR [#245](https://git.jigong.org/huthief/elinkBook/pulls/245)，分支 `feat/epic-42-issue-0`，合併後 main 為 `a06307e1`）**：`plans/plan-issue-0.md` 5 個 Task 全數完成——`check_foliate_es_compat.js` 常數引用漂移修復、`TextConversionMode` enum、`parseCharTable()`／`toMapLiteral()` 字典生成純函式（兩層長度防護：code point 數、UTF-16 length，保護 ADR 0030 的 ΔL=0 前提）、vendor OpenCC 原始字元表並產生 JS／Dart 雙端同源查找表、`convertText()` 純函式，供 Issue 1-5 消費。`flutter analyze`／`flutter test`／`node` 腳本測試全數通過零回歸。獨立程式審查（`reviews/review-issue-0.md`）確認 0 Critical／0 Important／2 Minor，皆已修訂（移除生成腳本註解對 `epubcfi.js:266` 的行號耦合、vendor OpenCC Apache-2.0 LICENSE 全文至 `app/tool/opencc_data/`），結論 Ready to merge: Yes。Issue 1（依賴 Issue 0 的 `TextConversionMode` enum）已可開工。

**2026-09-15（PR #245 合併之後）方案升級：ADR 0030 → [ADR 0032](../../adr/0032-text-conversion-taiwan-phrases-with-piecewise-offset-map.md)（commit `0d2a1e90`「簡轉繁的部份，改為轉換為台灣常用語」）**：對 OpenCC 完整詞庫（54,506 條）全量掃描後（`opencc/` 目錄下分析腳本與報告），確認詞彙級轉換僅 2.4% 條目造成非等長字元變化，可用雙向分段偏移映射（`TextOffsetMap`，見新增的 [`offset-mapping-spec.md`](./offset-mapping-spec.md)）在不修改釘定版 `epubcfi.js` 的前提下安全支援——遂推翻 ADR 0030「1:1 字元轉換」的限制，改採非對稱方案：簡轉繁 `s2twp`（含 `TWPhrases` 817 條台灣慣用語在地化，如「記憶體」、「軟體」）、繁轉簡維持 `tw2s`（不套用大陸用語，保留原著文風）。**此次升級只更新了 `spec.md`／`issues.md` 兩份文件與新增 ADR 0032／`offset-mapping-spec.md`，未同步修改 `design.md`（Discovery 階段歷史記錄，其「轉換精細度採字元對字元 1:1 轉換」段落現已由 ADR 0032 取代，不再是有效決策，但依專案慣例保留原文作歷史記錄，不回頭改寫）；亦未同步更新 Issue 0 的完成狀態，也未觸碰任何 `app/` 程式碼**——PR #245 實際合併的程式碼是**改寫前**依 ADR 0030 完成的純字元 1:1 版本（`app/tool/opencc_data/` 僅有 `STCharacters.txt`／`TSCharacters.txt`，尚無 `TWPhrases.txt`；全專案尚無 `TextOffsetMap` 類別）。2026-09-15 事後盤點（`git pull` 後重新檢視）發現此落差並修正：`issues.md` Issue 0 段落「Status」已更正為明確標註「僅涵蓋舊方案 ADR 0030」，新增 **Issue 0b** 承接 ADR 0032 新增的字典與 `TextOffsetMap` 落差（`issues.md` 已補上），並將 Issue 2 的依賴清單補上 Issue 0b。`docs/epics.md` 摘要同步更新反映此狀態。Issue 1（資料模型＋UI）範圍不涉及轉換演算法，不受此次升級影響，可依原計畫開工。

**2026-09-15 Issue 0b 已完成並合併回 `main`（PR [#246](https://git.jigong.org/huthief/elinkBook/pulls/246)，分支 `feat/epic-42-issue-0b`，合併後 main 為 `51fa644e`）**：`plans/plan-issue-0b.md`（經 `review-plan-issue-0b.md`／`rereview-plan-issue-0b.md` 兩輪審查修正 2 項 Critical——C-1 `toTraditional`／`toSimplified` 片語比對基準不對稱、C-2 `origToDisplay` 縮短區段須夾在顯示詞邊界內——與多項 Important／Minor 後定案）7 個 Task 全數完成：vendor `TWPhrases.txt`（818 條）／`TSPhrases.txt`（480 條，刻意排除 `STPhrases`／`TWVariantsRev*`）、`generate_conversion_dicts.js` 新增 `parsePhraseTable()`／`assertMaxPhraseKeyLength()`、雙端字典新增 `s2twpPhraseDict`／`tw2sPhraseDict`、`TextOffsetMap`／`OffsetEntry`／`OffsetMapBuilder`（Dart＋JS 各一份）、`convertText()` 改為片語優先轉換並新增 `convertTextDetailed()`／`applyTextConversionToString()`。獨立程式審查（`reviews/review-issue-0b.md`）：實際執行全部測試/檢查腳本驗證（非僅比對程式碼與計畫一致），確認 0 Critical／0 Important／1 Minor（README.md 詞條數量估計值與實際解析結果有微小落差，已修訂），結論 Ready to merge: Yes。至此 Issue 0＋0b 補齊 ADR 0032 完整方案，Issue 2（JS 端 DOM Walker，直接消費本 Issue 的 `TextOffsetMap`／字典）已可開工。

**2026-09-15 Issue 1 已完成並合併回 `main`（PR [#247](https://git.jigong.org/huthief/elinkBook/pulls/247)，分支 `feat/epic-42-issue-1`，合併後 main 為 `05015c5f`）**：`plans/plan-issue-1.md`（經 `review-plan-issue-1.md` 審查修正 0 Critical／3 Important／4 Minor 後定案）8 個 Task 全數完成——`BookReaderPrefs.textConversionOverride`（nullable 單書覆寫欄位）、SQLite `book_reader_prefs` v25→v26 遷移（`text_conversion_override TEXT`）、`ReadingDefaults.textConversion`（non-nullable 全域預設，硬編碼預設 `original`）、`resolveTextConversion()` 頂層純函式（`book.textConversionOverride ?? global.textConversion`）、`ReaderPrefsManagerImpl` 全域讀寫、`ReadingDefaultsScreen` 三態選擇器、`ReaderSettingsSheet`／`FxlSettingsSheet`（＋新建構參數 `showTextConversion`，CBZ 隱藏）四態覆寫選擇器。獨立程式審查（`reviews/review-issue-1.md`）：逐 Task 核對程式碼與計畫一致、Global Constraints 全數落實（SQLite 遷移位置、nullable/non-nullable 欄位語意、`PdfSettingsSheet`／`TextConversionMode` enum 未被觸碰），確認 0 Critical／0 Important／2 Minor（`dart format` 既有落差、`resolveTextConversion()` 尚無畫面消費屬刻意範圍），結論 Ready to merge: Yes；9 個目標測試檔合計 525 項全數通過，`flutter analyze` 零警示。此 Issue 只交付偏好設定管線＋UI，切換偏好尚不改變畫面文字（轉換效果留給 Issue 2-5）。Issue 2（JS 端 DOM Walker）已可開工。
