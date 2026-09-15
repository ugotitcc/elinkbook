# ADR 0030：簡繁轉換採 1:1 字元轉換以保護 CFI 座標系（`epic-42-text-conversion`）

## 狀態

被 [ADR 0032](./0032-text-conversion-taiwan-phrases-with-piecewise-offset-map.md) 取代（由 1:1 純字元對照升級為支援台灣常用詞之雙向分段偏移映射架構）

## 背景

`docs/prd.md` FR-48（簡繁轉換）要求閱讀畫面提供「原文／轉換為繁體／轉換為簡體」三態顯示切換，純顯示層轉換、不修改原始檔案內容，且**不可影響既有 CFI 定位／劃線座標的精確度**（見 `epic-42-text-conversion` `design.md`）。

`epic-42-text-conversion` Discovery（`/grill-with-docs`，2026-09-14／2026-09-15）原先定案轉換精細度採「詞彙/片語＋兩岸慣用詞感知等級」（等同 OpenCC `s2twp`/`tw2sp`），技術路線為 WebView JS 顯示層直接替換 live DOM 文字節點內容。2026-09-15 審查（`docs/epics/epic-42-text-conversion/reviews/review-epic-and-design.md` C-2，該檔案依專案慣例不進版控，本 ADR 摘要其論證供未來讀者理解決策脈絡）指出：`app/android/app/src/main/assets/foliate/epubcfi.js` 的 `fromRange`/`toRange`（302-334 行）直接依賴 live DOM 當下的 Range/Selection offset；詞彙級轉換必然產生非等長字元變化（例如「字节」2 字 →「位元組」3 字），會讓同一個 offset 在「轉換後畫面」與「原文 DOM」之間指向不同字元，導致既有劃線/書籤位移，甚至讓 `toRange()` 在節點末端因 offset 超出範圍拋出 `IndexSizeError`——該方法內部 `try { ... } catch { return null }` 會把例外靜默吞掉，使用者的劃線/書籤因此在畫面上徹底消失且無任何錯誤提示。

人類確認後，2026-09-15 推翻 Discovery 原案，退回字元對字元 1:1 轉換。

## 決策

1. **轉換精細度定案為字元對字元 1:1 轉換**（等同 OpenCC `s2t`/`t2s` 等級），不做詞彙/片語＋兩岸慣用詞感知轉換（`s2twp`/`tw2sp`）。
2. **WebView 端自行實作 DOM Walker**，無條件走訪可見文字節點、逐字元查表替換（排除 `<rt>`／`<script>`／`<style>` 等標籤），不依賴任何第三方套件內建的語系標籤（`lang`/`xml:lang`）匹配機制。
3. **CFI 生成與解析（`epubcfi.js`）永遠只對「原文」DOM 結構運作，不感知目前顯示模式**——這個不變量之所以能夠成立，前提是決策 1 保證每個文字節點轉換前後長度恆等（ΔL=0），同一個 Range offset 在轉換後畫面與原文 DOM 之間才會指向同一個字元位置。
4. **實作限制**：轉換邏輯必須逐字元查表替換，不得做任何多字元 pattern 比對或長度改變的轉換規則。未來若要提升轉換品質（詞彙/慣用詞），必須先設計解決 CFI offset 映射問題的機制（見「曾考慮的替代方案」的雙向偏移映射表選項），不得逕自繞過本 ADR 直接換更豐富的字典。

## 曾考慮的替代方案

- **維持詞彙/片語＋兩岸慣用詞感知轉換（`s2twp`/`tw2sp`）**：轉換品質更自然（例如「软件」正確轉為「軟體」而非單純字形轉換），但如「背景」所述會破壞 CFI 座標系，予以排除。
- **雙向字元偏移映射表（Bi-directional Offset Map）**：文字節點轉換時記錄前後字元索引映射，`fromRange` 產生 CFI 前將轉換後 offset 反查回原文 offset，`toRange` 還原 Range 時正向映射回轉換後 offset。技術上可保留轉換品質，但複雜度高、需要涵蓋節點合併、跨節點選取等邊界情況，任何映射邏輯疏漏都會重新引入同樣的靜默失敗風險。本輪 Discovery／Architecting 階段選擇不承擔這個複雜度與風險，留待未來若確有強烈品質需求且有餘裕做完整技術驗證時，另立 Epic／ADR 重新評估。
- **Dart 端預轉換後整份改寫餵給 WebView**：同樣是非等長替換，且額外引入「渲染 DOM」與「CFI 依據內容」之間的落差，問題本質相同，予以排除。

## 後果

- `epic-42-text-conversion` `design.md` 第 1 點 Discovery 原始決定（Q1）被本 ADR 推翻，本 ADR 為權威記錄。
- 使用者體驗上，轉換不含兩岸慣用詞在地化（例如「軟件」不會被轉換為「軟體」），僅做字形轉換。
- `main.js` 需新增一個不依賴語系標籤的 DOM Walker 模組，且必須嚴格保證「逐字元 1:1 替換、不做任何多字元 pattern 比對」，供後續程式碼審查作為明確查核依據。
- `epubcfi.js`（釘定版本）本身不需修改——本 ADR 規範的是「如何在既有 CFI 契約下安全地做顯示層轉換」，不涉及修改釘定版本，與 ADR 0011「不修改釘定版本」原則不衝突。

## 相關佐證

- `docs/epics/epic-42-text-conversion/design.md`
- `docs/adr/0011-epub-reflowable-migrate-to-foliate-js.md`（釘定版本不可修改原則）
- `app/android/app/src/main/assets/foliate/epubcfi.js`（`fromRange`/`toRange` 現行實作）
