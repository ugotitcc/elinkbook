# Epic 46 Issue 1 — 排版方向自動偵測改為全書預掃 計畫審查報告

> **審查日期：** 2026-09-24  
> **審查對象：** `docs/epics/epic-46-writing-mode-autodetect/plans/plan-issue-1.md`  
> **審查結論：** 🟡 建議修正後執行（Important 修正 3 項，無 Critical 阻礙）  
> **問題統計：** Critical: 0 | Important: 3 | Minor: 4

---

## 審查摘要

本實作計畫針對 Issue 1（排版方向自動偵測改為開書前全書預掃，不再隨閱讀位置改變）提出了乾淨且專注的架構設計。核心修改集中於 `app/android/app/src/main/assets/foliate/main.js`，完全不破壞 vendor 釘定檔案，且與既有的 transformTarget 延遲偵測形成了良好的主路徑/回退路徑對稱。

審查發現的 3 項 Important 問題主要集中在**規格相容性（EPUB 3 metadata 格式）**、**極端長文正則回溯與測試覆蓋（行內 style 屬性）**，以及**預掃 spine 資源時的 MIME 類型防護**。這些問題修正難度低，但能顯著提升在真實各類 EPUB 上的穩定性與相容性。

---

## 審查問題清單

### 1. Critical（嚴重問題，阻止執行）

*無*

---

### 2. Important（重要問題，建議在實作前或實作中修正）

> [!WARNING]
> ### I-1：OPF `primary-writing-mode` 漏判 EPUB 3 標準 property 語法
> - **位置：** `plan-issue-1.md` Task 2 Step 3（`detectBookWritingMode` 實作）、Task 1 Step 1（案例 D）
> - **分析：**  
>   計畫中的 OPF 查詢寫為：  
>   ```js
>   const meta = resources.opf
>     ?.querySelector('meta[name="primary-writing-mode"]')
>     ?.getAttribute('content')
>   ```  
>   在 EPUB 2 或舊版自訂中繼資料中，常使用 `<meta name="primary-writing-mode" content="vertical-rl"/>`。但依據 **EPUB 3 核心規格**（EPUB Packages 3.3），自訂中繼資料標準寫法為：  
>   ```xml
>   <meta property="primary-writing-mode">vertical-rl</meta>
>   ```  
>   其值位於標籤的文字節點（`textContent`），且屬性名稱是 `property` 而非 `name`。若僅查詢 `meta[name="..."]`，遇到符合標準 EPUB 3 的直排書籍時將會完全漏判。
> - **建議修正：**  
>   1. 將選擇器擴充為同時涵蓋 `property` 與 `name`：  
>      ```js
>      const metaEl = resources.opf?.querySelector(
>        'meta[property="primary-writing-mode"], meta[name="primary-writing-mode"]'
>      )
>      const meta = metaEl?.getAttribute('content') || metaEl?.textContent
>      if (meta && /^\s*vertical/i.test(meta)) return 'vertical'
>      ```  
>   2. Task 1 Step 1 案例 D 的合成 fixture 亦可同時加入或並列測試 EPUB 3 的 `<meta property="...">` 語法。

---

> [!WARNING]
> ### I-2：`INLINE_STYLE_RE` 正則在長文 XHTML 中有回溯風險，且 Task 1 缺少 `style=""` 行內樣式測試
> - **位置：** `plan-issue-1.md` Task 2 Step 3（`INLINE_STYLE_RE`）、Task 1 Step 1（測試案例）
> - **分析：**  
>   1. 計畫的正則式為：  
>      ```js
>      const INLINE_STYLE_RE = /<style[^>]*>([\s\S]*?)<\/style>|\sstyle\s*=\s*(["'])([\s\S]*?)\2/gi
>      ```  
>      第二分支使用跨行的任意字元非貪婪匹配 `([\s\S]*?)`。在真實小說中，單一章節 XHTML 可能長達數十至數百 KB。若標籤語法存在未閉合引號或複雜混排，`[\s\S]*?` 會越過標籤邊界持續回溯，產生不必要的效能開銷。事實上 HTML 屬性值由引號界定，屬性值內部不可能包含未轉義的同類型引號。  
>   2. 此外，Task 1 的 5 個案例中，案例 C 僅驗證了 `<head><style>` 標籤，完全**沒有任何案例驗證 `style="..."` 行內樣式**（例如 `<div style="-webkit-writing-mode: vertical-rl">` 或 `<p style="...">`）。使得第二分支在實作時缺乏 TDD 紅綠燈保護。
> - **建議修正：**  
>   1. 將正則式的屬性值部分收緊為引號邊界：  
>      ```js
>      const INLINE_STYLE_RE = /<style[^>]*>([\s\S]*?)<\/style>|\sstyle\s*=\s*(["'])([^"']*)\2/gi
>      ```  
>   2. 在 Task 1 案例 C 補上一段帶有 `style="...writing-mode:..."` 屬性的元素，或追加為 C-2 案例，確保行內屬性與 `<style>` 標籤皆受驗證。

---

> [!WARNING]
> ### I-3：內嵌樣式預掃時 `spine` 走訪未過濾 MIME Type，非文字資源會被計入上限
> - **位置：** `plan-issue-1.md` Task 2 Step 3（`for (const { idref } of resources.spine)` 迴圈）
> - **分析：**  
>   在走訪 spine 掃描內嵌樣式時：  
>   ```js
>   for (const { idref } of resources.spine) {
>     if (scanned >= INLINE_STYLE_SCAN_LIMIT) break
>     const item = resources.getItemByID(idref)
>     if (!item) continue
>     scanned++
>     const xhtml = await book.loadText(item.href).catch(() => null)
>   ```  
>   若書籍的 spine 包含非 HTML/XHTML 資源（例如純 SVG 封面頁、特殊 XML 頁面），程式碼在檢查其檔案類型前就執行了 `scanned++`，白白耗損了 20 個章節的檢查上限；且對非文字或二進位項目呼叫 `book.loadText` 亦無意義。
> - **建議修正：**  
>   在遞增計數前加入 MIME 類型過濾：  
>   ```js
>   const item = resources.getItemByID(idref)
>   if (!item) continue
>   if (item.mediaType !== 'application/xhtml+xml' && item.mediaType !== 'text/html') continue
>   scanned++
>   ```

---

### 3. Minor（次要觀察與建議）

> [!NOTE]
> ### M-1：CSS 去註解替換為空字串可能導致相鄰 token 黏連
> - **位置：** `plan-issue-1.md` Task 2 Step 1（`declaresVerticalWritingMode`）
> - **分析：**  
>   `String(cssText).replace(/\/\*[\s\S]*?\*\//g, '')` 替換為空字串。若遇到作者寫成 `div/*comment*/-webkit-writing-mode`，去註解後會變成 `div-webkit-writing-mode`，前面的 `[^-]` 會因為字元黏連而無法匹配開頭；或是 `div{/*comment*/writing-mode:...}`。雖然罕見，但標準做法是替換為單一空格 `' '`，更加穩固。

> [!NOTE]
> ### M-2：`item.mediaType` 建議增加大小寫防禦
> - **位置：** `plan-issue-1.md` Task 2 Step 3（`manifest` 遍歷）
> - **分析：**  
>   `if (item.mediaType !== 'text/css') continue`  
>   少數由較舊或非標準工具轉出的 EPUB 中，MIME 類型可能出現 `text/CSS` 或 `Text/css`。建議統一使用 `item.mediaType?.toLowerCase() !== 'text/css'`。

> [!NOTE]
> ### M-3：註解中排除 `-ms-` 前綴與舊式 `tb-rl` 支援的設計意圖
> - **位置：** `plan-issue-1.md` Task 2 Step 1 註解
> - **分析：**  
>   註解說明「邊界字元維持 [^-]：避免其他廠商前綴（例如 -ms-）被誤認為標準屬性」。但本 Issue 同時擴充了對舊式 IE 屬性值 `tb-rl`／`tb` 的支援。若書籍源自舊微軟工具鏈並宣告了 `-ms-writing-mode: tb-rl`，將會被目前的 Regex 忽略。建議確認此處是刻意不支援 `-ms-` 前綴，或僅是延續既有註解措辭。

> [!NOTE]
> ### M-4：Task 1 Step 2 紅燈預期行為說明可更細緻
> - **位置：** `plan-issue-1.md` Task 1 Step 2
> - **分析：**  
>   Step 2 寫道：「預期：A、B、C、D、E 全部 FAIL」。其中案例 E 是反例（註解包著直排宣告、實際上是橫排），修改前的既有程式碼因為未去註解，會誤判為 `vertical`，而測試斷言預期為 `horizontal`，故修改前亦會 FAIL。此邏輯完全正確，但在說明中若能提示「案例 E 是因舊代碼誤判直排而 FAIL」，能避免實作者在看紅燈時產生困惑。

---

## 優良架構與亮點

1. **時序與資料流清晰**：在 `makeBook()` 之後、`view.open(book)` 之前執行 `await detectBookWritingMode(book)`，直接從 zip entries 讀取文本，完全避開了 Loader 與 transformTarget 的生命週期事件，不會提早引發任何副作用。
2. **回退路徑完整**：保留 transformTarget 的延遲偵測，並將其定位為「無 manifest 時（如 KF8）或預掃失敗」時的回退機制，且 `if (detectedBookWritingMode === null)` 條件自然接軌，零破壞性。
3. **效能約束合理**：外部 CSS 數量少、解壓便宜；針對正文 XHTML 設立 `INLINE_STYLE_SCAN_LIMIT = 20` 上限，有效防範數百章大型小說開書卡頓。
4. **符合專案規範**：嚴格遵循 ADR 0011 不修改 vendor 釘定檔案，且全面使用 ES 相容性安全的語法。
