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

Architecting 完成，`spec.md` 已產出（自此為本 Epic 唯一事實來源），並記錄兩項 ADR：[ADR 0030](../../adr/0030-text-conversion-character-level-for-cfi-safety.md)（1:1 字元轉換定案）、[ADR 0031](../../adr/0031-text-conversion-dual-runtime-dictionary-not-opencc-js.md)（雙端共用原始字元表、不 vendor `opencc-js`）。尚未進入 Scrum Master 階段（`issues.md`）。
