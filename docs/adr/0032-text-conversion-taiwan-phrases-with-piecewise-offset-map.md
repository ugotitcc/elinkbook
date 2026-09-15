# ADR 0032：簡繁轉換採非對稱方案（簡轉繁 `s2twp`＋雙向偏移映射，繁轉簡 `tw2s` 保留原著文風）

## 狀態

已採納（取代 [ADR 0030](./0030-text-conversion-character-level-for-cfi-safety.md)）

## 背景

在 [ADR 0030](./0030-text-conversion-character-level-for-cfi-safety.md) 中，為了保護 EPUB CFI 座標系不因非等長字元置換（$\Delta L \neq 0$）而產生漂移或 `IndexSizeError` 崩潰，專案曾暫時退回「1:1 純字元對照轉換（`s2t` / `t2s`）」，放棄了詞彙級與兩岸慣用詞感知轉換。ADR 0030 明確指出：
> 「未來若要提升轉換品質（詞彙/慣用詞），必須先設計解決 CFI offset 映射問題的機制（見「曾考慮的替代方案」的雙向偏移映射表選項），不得逕自繞過本 ADR 直接換更豐富的字典。」

elinkBook 的產品核心差異化在於**「直排繁體中文排版」**與提供優質的在地化閱讀體驗。若簡繁轉換僅停留在字形替換（如將簡體「内存」轉為繁體字形「內存」而非台灣習慣的「記憶體」；「软件」轉為「軟件」而非「軟體」），會嚴重損害台灣與繁體讀者的閱讀沉浸感。

同時，針對繁轉簡的方向，若盲目套用大陸用語轉換（`tw2sp`），則會發生**過度替換（Over-translation）**，將台灣原作者的文筆、生活詞彙及台灣審定譯名（如「妥瑞氏症」被強制改成「抽动秽语综合征」、「好市多」變成「开市客」、「計程車」變成「出租车」）粗暴抹煞。

經過對 OpenCC 完整詞庫（54,506 條）的精確全量掃描，我們完成了雙向偏移映射演算法的完整數學推導與規格制定（見 `docs/epics/epic-42-text-conversion/offset-mapping-spec.md`），使在不修改釘定版 `epubcfi.js` 的前提下安全支援詞彙轉換成為可能。

## 決策

1. **轉換策略採非對稱設計（方案 A）**：
   - **簡轉繁（`toTraditional`）**：採用 **`s2twp`**（包含 OpenCC `TWPhrases` 817 條核心台灣常用詞，如「記憶體」、「軟體」、「程式碼」、「伺服器」在地化）。
   - **繁轉簡（`toSimplified`）**：採用 **`tw2s`**（標準台繁轉簡體字形），專注於解決讀者的識字障礙，100% 忠實保留台灣原著作者的文筆用詞、生活習慣與譯名風格，不套用 `tw2sp` 大陸用語替換。
2. **引入雙向分段偏移映射（Piecewise Offset Mapping）**：
   - 依據 `offset-mapping-spec.md`，在 WebView DOM Walker 中為發生長度變化的 `TextNode` 綁定輕量稀疏結構 `node._elinkOffsetMap`。全書 97.6% 長度不變之節點保持 `null`，達到零額外開銷。
   - **CFI 建立（`fromRange`）**：透過 `displayToOrig` 與向外貼齊策略（Floor/Ceil Snap Policy），保證存入 SQLite 的 CFI 永遠指向**原始 EPUB 未轉換文本**。
   - **CFI 還原（`toRange`）**：透過 `origToDisplay` 動態校正 live DOM offset，劃線精確覆蓋台灣詞彙，且加入邊界保護，徹底杜絕 `IndexSizeError`。
3. **延續 ADR 0031 的輕量生成原則**：
   - 兩端不 vendor 龐大的 `opencc-js` npm 套件。由專案內建生成腳本直接從 OpenCC 字典源檔抽取 `TWPhrases.txt`（僅約 18KB）、`STCharacters.txt`、`TSCharacters.txt` 等，產出雙端同步的輕量查找表與前綴樹（Trie）。
4. **TTS 與全文檢索解耦**：
   - TTS 朗讀依賴原始段落 CFI 錨點，傳入語音合成的文字轉為台灣常用詞發音（讀出「記憶體」）。
   - 全文檢索（FTS5）索引原文，查詢端採多變體擴充（`Multi-variant Query Expansion`），結果 Snippet 經 `origToDisplay` 修正高亮位置。

## 後果

- 正式推翻並取代 [ADR 0030](./0030-text-conversion-character-level-for-cfi-safety.md)，簡轉繁品質躍升為真正的台灣在地化體驗。
- 繁轉簡維持最克制優雅的字形轉換，避免侵犯原作者著作風格。
- `main.js` 需要在 `applyTextConversion` 實作 `TextOffsetMap` 產製，並在 `epubcfi.fromRange` 與 `epubcfi.toRange` 呼叫點加入雙向座標校正。
- 儲存層（SQLite 資料庫）中儲存的既有 CFI 劃線資料 100% 向後相容，不需任何資料庫遷移。

## 相關佐證

- [ADR 0030](./0030-text-conversion-character-level-for-cfi-safety.md)（先前決策背景）
- [ADR 0031](./0031-text-conversion-dual-runtime-dictionary-not-opencc-js.md)（雙端輕量字典生成原則）
- `docs/epics/epic-42-text-conversion/offset-mapping-spec.md`（雙向字元偏移映射演算法規格）
- `opencc/OpenCC-TWPhrases-s2twp-LengthChanged.csv`（237 條長度改變詞彙清單）
- `opencc/OpenCC-Length-Diff-s2twp-SUMMARY.txt`（全量掃描報告）
