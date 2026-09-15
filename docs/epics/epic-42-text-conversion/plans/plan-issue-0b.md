# Epic 42 Issue 0b — 台灣常用詞字典擴充＋`TextOffsetMap` 演算法 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 補齊 Issue 0（僅完成 ADR 0030 舊方案）與 ADR 0032 新方案之間的落差——vendor 台灣常用詞/片語原始字典（`TWPhrases.txt`／`TSPhrases.txt`），讓 `convertText()` 變成「片語優先、單字元其次」的轉換，並實作雙向分段偏移映射 `TextOffsetMap`（JS＋Dart 各一份），供 Issue 2 的 DOM Walker 直接消費、不需重新實作演算法。

**Architecture:** 兩個方向的轉換演算法**不對稱**——這不是隨意設計，而是直接對照真實 OpenCC（`opencc-js/dist/esm-lib/preset/full.js`）的 `conversionChain` 設定檔查證出來的結果（見下方 Self-Review「關鍵技術驗證」，**2026-09-15 依 `reviews/review-plan-issue-0b.md` Issue C-1 修訂**：先前草稿誤將兩個方向都套用相同的兩階段設計，已用 `opencc-js` 反查推翻）：
  - **`toTraditional`（s2twp）：兩階段**——真實設定 `conversionChain: [[STPhrases, STPhrases_GeneratedFromRegionalPhrases, STCharacters], [TWPhrases, TWVariantsPhrases, TWVariants]]` 是兩個獨立階段；本計畫排除 `STPhrases`/`TWVariantsPhrases`/`TWVariants`（見 Global Constraints），故化簡為：**Stage 1** 用 `kS2tDict`（Issue 0 既有，生成階段已保證 ΔL=0）逐字元轉換出「中繼文字」，中繼文字與輸入文字在 code point 索引與 UTF-16 offset 上完全對齊；**Stage 2** 在中繼文字上做 `kS2twpPhraseDict`（`TWPhrases`）最長匹配——`TWPhrases.txt` 的鍵本身就是**單字元轉換後**的繁體形態（例如鍵是「內存」不是「内存」，已用 `grep` 下載檔案＋`opencc-js` 實際輸出雙重驗證），必須先做字元轉換才能命中。
  - **`toSimplified`（tw2s）：單一階段**——真實設定 `conversionChain: [[TWVariantsRevPhrases, TWVariantsRev], [TSPhrases, TSCharacters]]`；本計畫排除 `TWVariantsRevPhrases`/`TWVariantsRev`（見 Global Constraints），故只保留第二階段 `[TSPhrases, TSCharacters]`——**兩個字典合併成同一個階段**，最長匹配優先，直接對**原始輸入**做（不是對字元轉換後的中繼文字），找不到片語才退回單字元 `kT2sDict[ch] ?? ch`。`TSPhrases.txt` 的鍵是**原始（未字元轉換）**的繁體形態（例如「乾隆\t乾隆」是保護「乾隆」這個固定用語不被 `kT2sDict` 的「乾→干」單字元規則誤轉成「干隆」的消歧規則）——若先做字元轉換再比對片語（如 `toTraditional` 那樣），片語字典的鍵永遠比對不到，繁轉簡消歧功能會被架構性地閹割掉。
  
  JS（`main.js` 之外的獨立模組，零 DOM 依賴，供 Node 直接測試，比照 `tts-safe-window.js` 既有慣例）與 Dart 各自實作同一份演算法（Dart AOT 無法呼叫 JS，見 ADR 0031），測試向量刻意保持一致。

**Tech Stack:** Node.js（內建 `fs`/`path`/`node:assert`，無 npm 依賴，比照 Issue 0）、Dart（`flutter_test`，Dart 3 record 型別）。

**Spec:** `docs/epics/epic-42-text-conversion/issues.md` Issue 0b（另見 [ADR 0032](../../adr/0032-text-conversion-taiwan-phrases-with-piecewise-offset-map.md)、`docs/epics/epic-42-text-conversion/offset-mapping-spec.md`、`docs/epics/epic-42-text-conversion/plans/plan-issue-0.md`——本計畫延伸其 `generate_conversion_dicts.js`／`text_conversion.dart`）。

## Global Constraints

- **範圍明確排除 `STPhrases`（簡轉繁片語消歧，約 49,000 條）與 `TWVariantsRev`／`TWVariantsRevPhrases`（台灣異體字正規化）**——這是本計畫撰寫前與人類確認過的刻意縮小範圍（見 Self-Review「範圍決策記錄」），不是遺漏。`toTraditional` 只用 `STCharacters`（Issue 0 既有）+ `TWPhrases`（本 Issue 新增）；`toSimplified` 只用 `TSCharacters`（Issue 0 既有）+ `TSPhrases`（本 Issue 新增）。
- **`toTraditional` 與 `toSimplified` 的片語比對基準不同，不可套用同一套邏輯（審查修正 C-1）**：`toTraditional` 對「字元轉換後的中繼文字」做片語比對；`toSimplified` 對「原始輸入」直接做片語比對（`TSPhrases` 與 `kT2sDict` 屬於同一個合併階段）。兩者皆已用 `opencc-js` 實際輸出＋原始字典檔內容雙重驗證（見 Self-Review「關鍵技術驗證」），順序寫反會讓 `TSPhrases` 的消歧規則（如「乾隆」「乾坤」「藉口」）全數失效，甚至產生「乾隆皇帝」被錯誤轉成「干隆皇帝」這種破壞性錯字。
- `convertText(String input, TextConversionMode mode)`（Issue 0 定案的固定介面）簽章與行為**不得更動**——`original` 原樣回傳、找不到的字元維持原樣——Issue 1-5 直接依賴此函式。本 Issue 新增的 `convertTextDetailed()` 是額外函式，不取代 `convertText()`。
- `kS2tDict`／`kT2sDict`／`s2tDict`／`t2sDict`（Issue 0 既有匯出）與 `parseCharTable()`／`toMapLiteral()`（Issue 0 既有函式簽章）不得更動；本 Issue 只新增匯出項目與新函式。
- `MAX_PHRASE_KEY_LENGTH`（生成腳本斷言用）／`kMaxPhraseKeyLength`（Dart 執行期常數）／`MAX_PHRASE_KEY_LENGTH`（JS 執行期常數）三處數值必須保持一致（`16`）——生成腳本的 `assertMaxPhraseKeyLength()` 是唯一防線，往後字典來源檔若新增更長詞條，生成階段會立刻拋例外中止，而非讓執行期演算法靜默漏未比對到。
- `parsePhraseTable()` 遇到重複鍵或空值須**拋例外中止**，不得靜默覆蓋/跳過（審查修正 I-3，`issues.md:48` 明訂「同一鍵不得重複、值不得為空字串」）——已用實際下載的 `TWPhrases.txt`／`TSPhrases.txt`／既有 `STCharacters.txt`／`TSCharacters.txt` 驗證過皆無重複鍵，加上此防護不影響現有生成流程。
- offset 一律以 **UTF-16 code unit** 為單位記錄（`String.length`／`.length`），但**逐 code point 走訪**輸入文字（Dart `input.runes`／JS `Array.from(text)`），避免在代理對（Surrogate Pair）中間切開比對窗口。
- `TextOffsetMap`／`offsetMap` 為 `null` 代表「這個節點轉換後長度完全不變」，呼叫端（`origToDisplay`／`displayToOrig`）對 `null` 一律原樣回傳輸入 offset，是零額外開銷的既定路徑（不是可選最佳化）。
- **`origToDisplay` 在片語「縮短」時必須把區段內位移量夾在顯示詞邊界內（審查修正 C-2）**：`intraOffset` 須以 `math.min(intraOffset, entry.dispLen)` 夾住，否則長度減少的片語（如「公共汽車」(4)→「公車」(2)，`TWPhrases.txt` 內實際存在 237 條此類詞彙）會讓計算出的 offset 超出顯示文字的實際長度，在 live DOM 呼叫 `range.setEnd()` 時直接拋出 `IndexSizeError` 崩潰。此為 `offset-mapping-spec.md` 原始演算法本身就有的邊界疏漏（本計畫忠實移植時一併繼承），修復僅限本計畫的 Dart／JS 實作，`offset-mapping-spec.md` 文件本身的修正不在本 Issue 範圍內。
- 新增的 JS 檔案不得使用 `app/tool/check_foliate_es_compat.js` 列出的較新 ES 內建方法（`Object.hasOwn`、`.at()`、`replaceAll` 等）——本計畫全程改用 `Object.prototype.hasOwnProperty.call(...)`／索引存取等舊式寫法，Task 3／7 皆有明確步驟重新執行這支腳本驗證。
- 不 vendor `opencc-js` npm 套件本身（ADR 0031）；`opencc-js` 只在**本機研究用**的 `opencc/` 目錄（不影響 `app/`）已安裝，僅用於本計畫撰寫前的行為驗證，不是本 Issue 交付物的一部分。

---

## File Structure

- Create: `app/tool/opencc_data/TWPhrases.txt` — vendor BYVoid/OpenCC 簡轉繁台灣常用詞原始表（Apache-2.0，817 條）。
- Create: `app/tool/opencc_data/TSPhrases.txt` — vendor BYVoid/OpenCC 繁轉簡片語原始表（Apache-2.0，477 條）。
- Modify: `app/tool/opencc_data/README.md` — 記錄新增兩個檔案的來源/授權/下載日期/用途。
- Modify: `app/tool/generate_conversion_dicts.js` — 新增 `parsePhraseTable()`（`parseCharTable()` 改為委派呼叫）、`assertMaxPhraseKeyLength()`，`main()` 擴充輸出 `s2twpPhraseDict`／`tw2sPhraseDict`。
- Modify: `app/tool/test_generate_conversion_dicts.js` — 新增 `parsePhraseTable()`／`assertMaxPhraseKeyLength()` 測試。
- Modify（由腳本重新產生）: `app/android/app/src/main/assets/foliate/text_conversion_dict.js` — 新增匯出 `s2twpPhraseDict`／`tw2sPhraseDict`。
- Modify（由腳本重新產生）: `app/lib/reader/text_conversion_dict.dart` — 新增匯出 `kS2twpPhraseDict`／`kTw2sPhraseDict`。
- Create: `app/lib/reader/text_offset_map.dart` — `OffsetEntry`／`TextOffsetMap`／`OffsetMapBuilder`／`origToDisplay()`／`displayToOrig()`。
- Create: `app/test/reader/text_offset_map_test.dart` — 對應單元測試。
- Create: `app/android/app/src/main/assets/foliate/text-offset-map.js` — JS 對應版本（零 DOM 依賴）。
- Create: `app/tool/test_text_offset_map.mjs` — 對應 Node 測試。
- Modify: `app/lib/reader/text_conversion.dart` — `convertText()` 改為片語優先轉換（`toTraditional` 兩階段／`toSimplified` 單一階段，審查修正 C-1）；新增 `convertTextDetailed()`。
- Modify: `app/test/reader/text_conversion_test.dart` — 新增片語轉換／`TextOffsetMap` 測試（既有 9 項測試不得修改，須全數維持通過）。
- Create: `app/android/app/src/main/assets/foliate/text-conversion.js` — JS 對應版本 `applyTextConversionToString()`，供 Issue 2 DOM Walker 直接呼叫。
- Create: `app/tool/test_text_conversion.mjs` — 對應 Node 測試，與 Dart 測試共用相同的中文範例（驗證雙端行為一致）。

---

### Task 1: Vendor 台灣常用詞/片語原始字典檔案

**Files:**
- Create: `app/tool/opencc_data/TWPhrases.txt`
- Create: `app/tool/opencc_data/TSPhrases.txt`
- Modify: `app/tool/opencc_data/README.md`

**Interfaces:**
- Consumes: 無。
- Produces: 兩份原始 TSV 檔案，供 Task 3 的 `generate_conversion_dicts.js` 讀取。

- [ ] **Step 1: 下載原始字典檔案**

```bash
curl -fsSL -o app/tool/opencc_data/TWPhrases.txt https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/TWPhrases.txt
curl -fsSL -o app/tool/opencc_data/TSPhrases.txt https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/TSPhrases.txt
```

Expected: 兩個檔案下載成功。若 URL 已失效，到 `https://github.com/BYVoid/OpenCC/tree/master/data/dictionary` 查證目前正確路徑後調整（比照 `plan-issue-0.md` Task 4 Step 1 既有提醒，不假設網址永久不變）。

- [ ] **Step 2: 核對下載內容行數與已知條目**

```bash
wc -l app/tool/opencc_data/TWPhrases.txt app/tool/opencc_data/TSPhrases.txt
grep -P '^內存\t' app/tool/opencc_data/TWPhrases.txt
grep -P '^一目瞭然\t' app/tool/opencc_data/TSPhrases.txt
```

Expected: `TWPhrases.txt` 約 825 行（含註解/空行，817 條實際詞條）、`TSPhrases.txt` 約 487 行（477 條實際詞條）；`grep` 找到 `內存\t記憶體`（鍵是繁體「內存」，見本計畫 Global Constraints 的關鍵驗證）、`一目瞭然\t一目了然`。

- [ ] **Step 3: 更新 `app/tool/opencc_data/README.md`**

在既有 `- 來源網址：` 列表中，於 `TSCharacters.txt` 那一行之後新增：

```markdown
  - https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/TWPhrases.txt
  - https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/TSPhrases.txt
```

在檔案末尾新增一段說明範圍決策（避免未來有人「順手」補齊 `STPhrases`／`TWVariantsRev` 而不知道這是刻意的範圍界定）：

```markdown

## `TWPhrases.txt`／`TSPhrases.txt`（epic-42-text-conversion Issue 0b，2026-09-15）

簡轉繁（`toTraditional`）採 `STCharacters.txt` + `TWPhrases.txt`（台灣在地化片語，
817 條）；繁轉簡（`toSimplified`）採 `TSCharacters.txt` + `TSPhrases.txt`
（片語消歧，477 條）。**刻意排除** `STPhrases.txt`（簡轉繁片語消歧，約
49,000 條，處理「幹/乾/干」這類依詞境選字，規模過大且非本 Epic 動機所在）
與 `TWVariantsRev.txt`／`TWVariantsRevPhrases.txt`（台灣異體字正規化，
`TWVariantsRev.txt` 甚至不是原始檔案，而是 OpenCC 自己用 `reverse.py` +
人工消歧義註記從 `TWVariants.txt` 動態產生的衍生檔案，正確重現其演算法的
成本與這兩個字典帶來的實際轉換品質提升不成比例）。這兩個排除項若未來要
重新評估，須另立 ADR，不是本 Issue 的「留待未來」既定計畫（比照
[ADR 0030](../../../adr/0030-text-conversion-character-level-for-cfi-safety.md)
排除詞彙轉換的先例，本 Epic 對「明確排除」一貫用同一個嚴謹度處理）。
```

- [ ] **Step 4: Commit**

```bash
git add app/tool/opencc_data/TWPhrases.txt app/tool/opencc_data/TSPhrases.txt app/tool/opencc_data/README.md
git commit -m "feat(reader): vendor TWPhrases/TSPhrases 台灣常用詞片語原始字典"
```

---

### Task 2: `parsePhraseTable()` 純函式，`parseCharTable()` 重構共用

**Files:**
- Modify: `app/tool/generate_conversion_dicts.js`
- Modify: `app/tool/test_generate_conversion_dicts.js`

**Interfaces:**
- Consumes: 無（純字串解析，不依賴檔案系統）。
- Produces: `parsePhraseTable(tsvContent: string): Record<string, string>`（不限字元數，取首個候選字），供 Task 3 的 `main()` 讀取片語表；`parseCharTable()` 對外行為與既有測試完全不變（內部改為呼叫 `parsePhraseTable()` 再疊加長度防護）。

- [ ] **Step 1: 寫失敗測試**

在 `app/tool/test_generate_conversion_dicts.js` 第 5 行 `const { parseCharTable } = require('./generate_conversion_dicts.js');` 改為：

```javascript
const { parseCharTable, parsePhraseTable, assertMaxPhraseKeyLength } =
  require('./generate_conversion_dicts.js');
```

在 `testSipToBmpPairSkipped()`（第 60-64 行）之後、`testBasicOneToOneMapping();`（第 66 行呼叫區塊）之前，新增：

```javascript
function testParsePhraseTableAllowsMultiCharKeyValue() {
  const result = parsePhraseTable('內存\t記憶體\n');
  assert.deepEqual(result, { 內存: '記憶體' });
}

function testParsePhraseTableTakesFirstCandidate() {
  // 真實 OpenCC TWPhrases.txt 資料：代碼\t程式碼 代碼（多候選字，取首個）。
  const result = parsePhraseTable('代碼\t程式碼 代碼\n');
  assert.deepEqual(result, { 代碼: '程式碼' });
}

function testParsePhraseTableCommentAndEmptyLinesSkipped() {
  const input = [
    '# Open Chinese Convert (OpenCC) Dictionary',
    '# File: TWPhrases.txt',
    '',
    '內存\t記憶體',
    '',
  ].join('\n');
  const result = parsePhraseTable(input);
  assert.deepEqual(result, { 內存: '記憶體' });
}

function testParsePhraseTableAllowsSingleCharEntry() {
  // TWPhrases.txt 實際含 12 條單字詞條（如「硅\t矽」）：parsePhraseTable
  // 不像 parseCharTable 那樣限制長度必須為 1，但也不排斥單字元鍵值——
  // 片語字典裡的單字詞條照樣要能正確解析。
  const result = parsePhraseTable('硅\t矽\n');
  assert.deepEqual(result, { 硅: '矽' });
}

function testParsePhraseTableAllowsLengthChangingEntry() {
  // 片語表跟字元表不同，長度本來就可能改變（TextOffsetMap 存在的理由），
  // parsePhraseTable 不應該對長度做任何檢查或跳過。
  const result = parsePhraseTable('內存\t記憶體\n方便麵\t泡麵\n');
  assert.deepEqual(result, { 內存: '記憶體', 方便麵: '泡麵' });
}

function testAssertMaxPhraseKeyLengthPassesUnderLimit() {
  assertMaxPhraseKeyLength({ 內存: '記憶體' }, 'TestDict');
  // 未拋例外即為通過。
}

function testAssertMaxPhraseKeyLengthThrowsOverLimit() {
  const longKey = '一'.repeat(17);
  assert.throws(
    () => assertMaxPhraseKeyLength({ [longKey]: '二' }, 'TestDict'),
    /超過 MAX_PHRASE_KEY_LENGTH/,
  );
}

function testParsePhraseTableThrowsOnDuplicateKey() {
  // 審查修正 I-3：issues.md 明訂「同一鍵不得重複」，靜默覆蓋會隱蔽上游
  // 資料的格式異常或鍵值衝突。
  assert.throws(
    () => parsePhraseTable('內存\t記憶體\n內存\t記憶體模組\n'),
    /片語字典鍵重複/,
  );
}

function testParsePhraseTableThrowsOnEmptyValue() {
  // 審查修正 I-3：issues.md 明訂「值不得為空字串」。
  assert.throws(
    () => parsePhraseTable('內存\t\n'),
    /片語字典值為空字串/,
  );
}
```

在檔案底部的呼叫區塊（第 66-72 行）之後、`console.log(...)`（第 74 行）之前，新增對應呼叫：

```javascript
testParsePhraseTableAllowsMultiCharKeyValue();
testParsePhraseTableTakesFirstCandidate();
testParsePhraseTableCommentAndEmptyLinesSkipped();
testParsePhraseTableAllowsSingleCharEntry();
testParsePhraseTableAllowsLengthChangingEntry();
testAssertMaxPhraseKeyLengthPassesUnderLimit();
testAssertMaxPhraseKeyLengthThrowsOverLimit();
testParsePhraseTableThrowsOnDuplicateKey();
testParsePhraseTableThrowsOnEmptyValue();
```

將第 74 行 `console.log('[test_generate_conversion_dicts] 7 項情境全數通過。');` 改為：

```javascript
console.log('[test_generate_conversion_dicts] 16 項情境全數通過。');
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `node app/tool/test_generate_conversion_dicts.js`
Expected: 拋出例外，訊息指出 `parsePhraseTable`／`assertMaxPhraseKeyLength` 不是函式（尚未從 `generate_conversion_dicts.js` 匯出）。

- [ ] **Step 3: 修改 `generate_conversion_dicts.js`，新增 `parsePhraseTable()` 並重構 `parseCharTable()`**

在 `parseCharTable()` 函式（第 43-92 行）**之前**新增：

```javascript
/**
 * 解析 OpenCC 字典表（TSV：key\tvalue1 value2 ...，'#' 開頭為註解行），
 * 不限字元數，右欄若有多個以半形空格分隔的候選字，只取第一個。片語表
 * （TWPhrases.txt／TSPhrases.txt）與字元表（STCharacters.txt／
 * TSCharacters.txt）共用同一套基礎解析規則——parseCharTable() 的長度
 * 限制／BMP↔輔助平面過濾是疊加在這個共用邏輯之上的額外約束（見下）。
 *
 * 同一鍵不得重複、值不得為空字串（`issues.md` 明訂的正規化約束，審查
 * 修正 I-3）——上游 OpenCC 資料若出現格式異常或鍵值衝突，直接拋例外
 * 中止生成，不靜默覆蓋/跳過（已用實際下載的 TWPhrases.txt／TSPhrases.txt
 * 與既有 STCharacters.txt／TSCharacters.txt 驗證過皆無重複鍵，此防護
 * 不影響既有生成流程）。
 * @param {string} tsvContent
 * @returns {Record<string, string>}
 */
function parsePhraseTable(tsvContent) {
  const dict = {};
  const lines = tsvContent.split('\n');
  for (const rawLine of lines) {
    // 審查修正 I-3 複審發現的邏輯短路：不可先對整行 rawLine.trim() 再找
    // tab 位置——'內存\t'.trim() 會把結尾的 '\t' 一併削掉（tab 是
    // trim() 認定的空白字元），導致值為空的行被誤判成「找不到 tab」而
    // 提前 continue，永遠到不了下面的空值拋例外檢查。改為：只用
    // rawLine（未 trim）找 tab 位置，trim 動作限定在切出來的 key／
    // candidates 各自身上。
    const trimmedForBlankCheck = rawLine.trim();
    if (!trimmedForBlankCheck || trimmedForBlankCheck.startsWith('#')) {
      continue;
    }
    const tabIndex = rawLine.indexOf('\t');
    if (tabIndex < 0) continue;
    const key = rawLine.slice(0, tabIndex).trim();
    if (!key) continue;
    const candidates = rawLine.slice(tabIndex + 1).trim();
    const value = candidates ? candidates.split(' ')[0] : '';
    if (!value) {
      throw new Error(`片語字典值為空字串："${key}"，原始行：${rawLine}`);
    }
    if (Object.prototype.hasOwnProperty.call(dict, key)) {
      throw new Error(
        `片語字典鍵重複："${key}"（舊值 "${dict[key]}" vs 新值 "${value}"）`,
      );
    }
    dict[key] = value;
  }
  return dict;
}
```

將 `parseCharTable()` 函式本體（第 66-92 行的 `function parseCharTable(tsvContent) { ... }`）改為：

```javascript
function parseCharTable(tsvContent) {
  const raw = parsePhraseTable(tsvContent);
  const dict = {};
  for (const [key, value] of Object.entries(raw)) {
    const keyCodepoints = Array.from(key).length;
    const valueCodepoints = Array.from(value).length;
    if (keyCodepoints !== 1 || valueCodepoints !== 1) {
      throw new Error(
        `字典項 code point 數不為 1：` +
        `"${key}"(${keyCodepoints}) -> "${value}"(${valueCodepoints})`,
      );
    }
    // UTF-16 code unit 數不相等（BMP ↔ 輔助平面配對）：跳過，不進字典。
    if (key.length !== value.length) continue;
    dict[key] = value;
  }
  return dict;
}
```

（函式上方原有的 JSDoc 註解——兩層長度防護說明——維持不動，只替換函式本體；**注意**：重構後錯誤訊息不再附帶「原始行：...」這段除錯資訊，因為此時已經是解析過的 key/value，不再持有原始行文字——這是刻意接受的小幅資訊量取捨，換取 `parsePhraseTable`／`parseCharTable` 共用同一套基礎解析邏輯，不必維護兩份幾乎相同的 TSV 解析程式碼；`key`/`value` 本身已足夠定位問題。）

新增 `assertMaxPhraseKeyLength()`（放在 `toMapLiteral()` 函式，即第 94-102 行，之後）：

```javascript
// 片語比對時，單一詞條 code point 數的安全上限——必須與
// app/lib/reader/text_conversion.dart 的 kMaxPhraseKeyLength、
// app/android/app/src/main/assets/foliate/text-conversion.js 的
// MAX_PHRASE_KEY_LENGTH 保持一致，三處數值目前皆為 16。
const MAX_PHRASE_KEY_LENGTH = 16;

/**
 * 確保 dict 內每一個鍵的 code point 數不超過 MAX_PHRASE_KEY_LENGTH——
 * 執行期演算法的最長匹配只會嘗試到這個長度，超過的詞條會被靜默漏未
 * 比對，必須在生成階段擋下來（見上方常數說明）。
 * @param {Record<string,string>} dict
 * @param {string} label
 */
function assertMaxPhraseKeyLength(dict, label) {
  for (const key of Object.keys(dict)) {
    const len = Array.from(key).length;
    if (len > MAX_PHRASE_KEY_LENGTH) {
      throw new Error(
        `${label} 詞條 "${key}" 長度 ${len} 超過 MAX_PHRASE_KEY_LENGTH=` +
        `${MAX_PHRASE_KEY_LENGTH}，需同步調高 text_conversion.dart 的 ` +
        'kMaxPhraseKeyLength 與 text-conversion.js 的 MAX_PHRASE_KEY_LENGTH。',
      );
    }
  }
}
```

將 `module.exports = { parseCharTable, toMapLiteral };`（第 133 行）改為：

```javascript
module.exports = {
  parseCharTable,
  parsePhraseTable,
  toMapLiteral,
  assertMaxPhraseKeyLength,
};
```

- [ ] **Step 4: 執行測試，確認通過（含既有 7 項情境零回歸）**

Run: `node app/tool/test_generate_conversion_dicts.js`
Expected: 印出「[test_generate_conversion_dicts] 16 項情境全數通過。」，結束碼 0——確認 Issue 0 既有的 7 項 `parseCharTable()` 測試（多候選字取首個、BMP↔輔助平面跳過等）在重構後依然全數通過。

- [ ] **Step 5: 重新執行已產生的字典檔案生成，確認既有輸出不受影響**

```bash
node app/tool/generate_conversion_dicts.js
```

Expected: 印出「[generate_conversion_dicts] 完成：s2t N 筆、t2s M 筆。」（`N`／`M` 與 Issue 0 完成時的數字相同，因為本步驟尚未修改 `main()`，Task 3 才會擴充輸出），結束碼 0；`git diff` 確認 `text_conversion_dict.js`／`text_conversion_dict.dart` 內容與重構前逐位元組相同（重構是純粹的內部實作重整，不改變任何輸出）。

- [ ] **Step 6: Commit**

```bash
git add app/tool/generate_conversion_dicts.js app/tool/test_generate_conversion_dicts.js
git commit -m "refactor(tool): parseCharTable 改為委派 parsePhraseTable，新增片語表解析與長度斷言"
```

---

### Task 3: 擴充 `generate_conversion_dicts.js` 主流程，產生 `s2twpPhraseDict`／`tw2sPhraseDict`

**Files:**
- Modify: `app/tool/generate_conversion_dicts.js`
- Modify（由本 Task 執行後產生）: `app/android/app/src/main/assets/foliate/text_conversion_dict.js`
- Modify（由本 Task 執行後產生）: `app/lib/reader/text_conversion_dict.dart`

**Interfaces:**
- Consumes: Task 1 的 `TWPhrases.txt`／`TSPhrases.txt`；Task 2 的 `parsePhraseTable()`／`assertMaxPhraseKeyLength()`。
- Produces: JS 檔新增 `export const s2twpPhraseDict`／`export const tw2sPhraseDict`；Dart 檔新增 `const Map<String, String> kS2twpPhraseDict`／`kTw2sPhraseDict`，供 Task 6（Dart）／Task 7（JS）消費。

- [ ] **Step 1: 修改 `generate_conversion_dicts.js` 的輸入路徑常數**

在 `T2S_INPUT` 宣告（第 27 行）之後新增：

```javascript
const TW_PHRASES_INPUT = path.join(DATA_DIR, 'TWPhrases.txt');
const TS_PHRASES_INPUT = path.join(DATA_DIR, 'TSPhrases.txt');
```

- [ ] **Step 2: 修改 `main()`，讀取片語表並輸出擴充後的字典檔案**

將整個 `main()` 函式（Task 2 重構後，原第 104-131 行）改為：

```javascript
function main() {
  const s2tSource = fs.readFileSync(S2T_INPUT, 'utf8');
  const t2sSource = fs.readFileSync(T2S_INPUT, 'utf8');
  const twPhrasesSource = fs.readFileSync(TW_PHRASES_INPUT, 'utf8');
  const tsPhrasesSource = fs.readFileSync(TS_PHRASES_INPUT, 'utf8');

  const s2tDict = parseCharTable(s2tSource);
  const t2sDict = parseCharTable(t2sSource);
  const s2twpPhraseDict = parsePhraseTable(twPhrasesSource);
  const tw2sPhraseDict = parsePhraseTable(tsPhrasesSource);
  assertMaxPhraseKeyLength(s2twpPhraseDict, 'TWPhrases');
  assertMaxPhraseKeyLength(tw2sPhraseDict, 'TSPhrases');

  const jsContent =
    GENERATED_FILE_HEADER +
    `export const s2tDict = ${toMapLiteral(s2tDict)};\n\n` +
    `export const t2sDict = ${toMapLiteral(t2sDict)};\n\n` +
    `export const s2twpPhraseDict = ${toMapLiteral(s2twpPhraseDict)};\n\n` +
    `export const tw2sPhraseDict = ${toMapLiteral(tw2sPhraseDict)};\n`;
  fs.writeFileSync(JS_OUTPUT, jsContent, 'utf8');

  const dartContent =
    GENERATED_FILE_HEADER +
    '// coverage:ignore-file\n' +
    '\n' +
    `const Map<String, String> kS2tDict = ${toMapLiteral(s2tDict)};\n\n` +
    `const Map<String, String> kT2sDict = ${toMapLiteral(t2sDict)};\n\n` +
    `const Map<String, String> kS2twpPhraseDict = ${toMapLiteral(s2twpPhraseDict)};\n\n` +
    `const Map<String, String> kTw2sPhraseDict = ${toMapLiteral(tw2sPhraseDict)};\n`;
  fs.writeFileSync(DART_OUTPUT, dartContent, 'utf8');

  console.log(
    `[generate_conversion_dicts] 完成：s2t ${Object.keys(s2tDict).length} ` +
    `筆、t2s ${Object.keys(t2sDict).length} 筆、s2twp 片語 ` +
    `${Object.keys(s2twpPhraseDict).length} 筆、tw2s 片語 ` +
    `${Object.keys(tw2sPhraseDict).length} 筆。`,
  );
}
```

- [ ] **Step 3: 執行生成腳本**

```bash
node app/tool/generate_conversion_dicts.js
```

Expected: 印出「[generate_conversion_dicts] 完成：s2t N 筆、t2s M 筆、s2twp 片語 817 筆、tw2s 片語 477 筆。」，結束碼 0。

- [ ] **Step 4: 人工核對產出的片語字典包含已知正確項目**

```bash
grep -o '"內存": "記憶體"' app/lib/reader/text_conversion_dict.dart
grep -o '"硅": "矽"' app/lib/reader/text_conversion_dict.dart
grep -o '"一目瞭然": "一目了然"' app/lib/reader/text_conversion_dict.dart
grep -o 's2twpPhraseDict' app/android/app/src/main/assets/foliate/text_conversion_dict.js
grep -o 'tw2sPhraseDict' app/android/app/src/main/assets/foliate/text_conversion_dict.js
grep -o '"內存": "記憶體"' app/android/app/src/main/assets/foliate/text_conversion_dict.js
```

Expected: 6 個 `grep` 皆有輸出（審查修正 M-3：原本只檢查 JS 檔案的變數名稱是否存在，補上一行實際內容核對，比照 Dart 檔案已有的核對方式）。

- [ ] **Step 5: 驗證 JS 產出檔案語法正確**

```bash
node --check app/android/app/src/main/assets/foliate/text_conversion_dict.js
```

Expected: 無輸出、結束碼 0。

- [ ] **Step 6: 重新執行 ES 相容性檢查腳本**

```bash
node app/tool/check_foliate_es_compat.js
```

Expected: 結束碼 0（新增內容仍只是物件字面量常數，不含任何 ES 內建方法呼叫）。

- [ ] **Step 7: 重新執行 `test_generate_conversion_dicts.js`，確認 Task 2 的測試仍全數通過**

```bash
node app/tool/test_generate_conversion_dicts.js
```

Expected: 印出「[test_generate_conversion_dicts] 16 項情境全數通過。」，結束碼 0。

- [ ] **Step 8: Commit**

```bash
git add app/tool/generate_conversion_dicts.js app/android/app/src/main/assets/foliate/text_conversion_dict.js app/lib/reader/text_conversion_dict.dart
git commit -m "feat(reader): generate_conversion_dicts.js 新增 s2twpPhraseDict/tw2sPhraseDict 輸出"
```

---

### Task 4: `TextOffsetMap`／`OffsetEntry`／`origToDisplay`／`displayToOrig`（Dart）

**Files:**
- Create: `app/lib/reader/text_offset_map.dart`
- Create: `app/test/reader/text_offset_map_test.dart`

**Interfaces:**
- Consumes: 無（純資料結構＋純函式，不依賴任何字典或轉換邏輯）。
- Produces: `OffsetEntry`、`TextOffsetMap`、`OffsetMapBuilder`、`int origToDisplay(TextOffsetMap? offsetMap, int origOffset)`、`int displayToOrig(TextOffsetMap? offsetMap, int dispOffset, {String snapPolicy})`，供 Task 6 的 `convertTextDetailed()` 與 Issue 2（JS 對應版本的移植依據／未來 Dart 端 TTS word-level highlight）消費。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/reader/text_offset_map_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/text_offset_map.dart';

void main() {
  group('offsetMap 為 null／空時的零開銷路徑', () {
    test('offsetMap 為 null 時，origToDisplay／displayToOrig 皆原樣回傳', () {
      expect(origToDisplay(null, 5), 5);
      expect(displayToOrig(null, 5), 5);
    });

    test('entries 為空的 TextOffsetMap 視同 null，原樣回傳', () {
      const map = TextOffsetMap([]);
      expect(origToDisplay(map, 5), 5);
      expect(displayToOrig(map, 5), 5);
    });

    test('OffsetMapBuilder 沒有任何區段時 build() 回傳 null', () {
      final builder = OffsetMapBuilder();
      expect(builder.build(), isNull);
    });
  });

  group('單一區段（模擬「abc內存def」轉換為「abc記憶體def」）', () {
    // 內存@origOffset=3,origLen=2 -> 記憶體@dispOffset=3,dispLen=3，
    // delta=+1，accumDelta=0（唯一一個區段）。
    late TextOffsetMap map;

    setUp(() {
      final builder = OffsetMapBuilder();
      builder.addSegment(origOffset: 3, origLen: 2, dispOffset: 3, dispLen: 3);
      map = builder.build()!;
    });

    test('origToDisplay：區段之前的 offset 原樣回傳', () {
      expect(origToDisplay(map, 0), 0);
      expect(origToDisplay(map, 2), 2);
    });

    test('origToDisplay：區段起點對應到顯示區段起點', () {
      expect(origToDisplay(map, 3), 3);
    });

    test('origToDisplay：區段內部依比例位移', () {
      expect(origToDisplay(map, 4), 4);
    });

    test('origToDisplay：區段之後的 offset 加上累計 delta', () {
      // 原文第 5 個 code unit 是 "d"，顯示文字對應到索引 6。
      expect(origToDisplay(map, 5), 6);
    });

    test('displayToOrig：區段之前的 offset 原樣回傳', () {
      expect(displayToOrig(map, 2), 2);
    });

    test('displayToOrig：floor 貼齊區段起點（選取起點用）', () {
      expect(displayToOrig(map, 4, snapPolicy: 'floor'), 3);
      expect(displayToOrig(map, 5, snapPolicy: 'floor'), 3);
    });

    test('displayToOrig：ceil 貼齊區段終點（選取終點用）', () {
      expect(displayToOrig(map, 4, snapPolicy: 'ceil'), 5);
      expect(displayToOrig(map, 3, snapPolicy: 'ceil'), 5);
    });

    test('displayToOrig：區段之後的 offset 減去累計 delta', () {
      expect(displayToOrig(map, 6), 5);
    });
  });

  group('多區段（驗證 accumDelta 正確累加）', () {
    // 第一段：origOffset=0,origLen=2 -> dispOffset=0,dispLen=3（delta=+1）。
    // 第二段：origOffset=10,origLen=3 -> dispOffset=11,dispLen=2（delta=-1，
    // accumDelta 必須是第一段的 delta=+1，而非 0）。
    late TextOffsetMap map;

    setUp(() {
      final builder = OffsetMapBuilder();
      builder.addSegment(origOffset: 0, origLen: 2, dispOffset: 0, dispLen: 3);
      builder.addSegment(origOffset: 10, origLen: 3, dispOffset: 11, dispLen: 2);
      map = builder.build()!;
    });

    test('第二段的 accumDelta 正確反映第一段的 delta', () {
      expect(map.entries[1].accumDelta, 1);
    });

    test('origToDisplay：兩段之後的 offset 套用兩段的總 delta（抵銷為 0）', () {
      expect(origToDisplay(map, 13), 13);
    });

    test('displayToOrig：兩段之後的 offset 正確還原（總 delta 抵銷為 0）', () {
      expect(displayToOrig(map, 13), 13);
    });
  });

  group('縮短區段（模擬「公共汽車」(4) 轉換為「公車」(2)，審查修正 C-2）', () {
    // origOffset=0,origLen=4（"公共汽車"）-> dispOffset=0,dispLen=2
    // （"公車"），delta=-2，accumDelta=0。TWPhrases.txt 實際存在 237 條
    // 這類長度減少的詞彙（如「公共汽車」「方便面」「可執行文件」）。
    late TextOffsetMap map;

    setUp(() {
      final builder = OffsetMapBuilder();
      builder.addSegment(origOffset: 0, origLen: 4, dispOffset: 0, dispLen: 2);
      map = builder.build()!;
    });

    test('origToDisplay：區段內未超出顯示詞長度時正常對應', () {
      expect(origToDisplay(map, 0), 0);
      expect(origToDisplay(map, 1), 1);
    });

    test(
        'origToDisplay：區段內超出顯示詞長度時必須夾住在顯示詞尾（審查修正 '
        'C-2 核心案例）', () {
      // 修正前會回傳 2、3——超出顯示文字「公車」實際長度 2 的有效範圍，
      // 在 live DOM 對長度僅 2 的文字節點呼叫 range.setEnd(node, 3) 會
      // 直接拋出 IndexSizeError。修正後皆夾住在 dispLen=2。
      expect(origToDisplay(map, 2), 2);
      expect(origToDisplay(map, 3), 2);
    });

    test('origToDisplay：維持弱單調遞增，不因夾住而在區段邊界前後產生數值倒退', () {
      // 修正前：origOffset=3 -> 3、origOffset=4（區段之後）-> 2，數值倒退
      // （單調性破壞，$x_1 \\le x_2$ 卻 $f(x_1) > f(x_2)$）。修正後兩者
      // 皆為 2，不倒退。
      final beforeBoundary = origToDisplay(map, 3);
      final afterBoundary = origToDisplay(map, 4);
      expect(afterBoundary, greaterThanOrEqualTo(beforeBoundary));
      expect(afterBoundary, 2);
    });

    test('displayToOrig：floor／ceil 在夾住後的顯示區段內仍正確框住整個原文區段', () {
      expect(displayToOrig(map, 1, snapPolicy: 'floor'), 0);
      expect(displayToOrig(map, 1, snapPolicy: 'ceil'), 4);
    });

    test('displayToOrig：區段之後的 offset 正確還原', () {
      expect(displayToOrig(map, 2), 4);
    });
  });
}
```

- [ ] **Step 2: 執行測試，確認失敗（找不到檔案）**

Run: `flutter test test/reader/text_offset_map_test.dart`
Expected: FAIL，錯誤訊息為找不到 `package:elinkbook/reader/text_offset_map.dart`。

- [ ] **Step 3: 建立 `app/lib/reader/text_offset_map.dart`**

```dart
import 'dart:math' as math;

/// 雙向分段偏移映射（Piecewise Offset Mapping，見
/// `docs/epics/epic-42-text-conversion/offset-mapping-spec.md` 第 2 節）：
/// 記錄一個文字節點中，長度會改變的置換區段（原文 offset/長度、顯示文字
/// offset/長度），供 [origToDisplay]／[displayToOrig] 在原文與顯示文字
/// 之間互相換算 UTF-16 offset，讓 EPUB CFI（恆依原文）與 live DOM（顯示
/// 轉換後文字）在座標系不同時仍能正確對應。
class OffsetEntry {
  /// 原文中，此置換區段的起始 offset（UTF-16 code unit）。
  final int origOffset;

  /// 原文中，此置換區段的長度（UTF-16 code unit）。
  final int origLen;

  /// 顯示文字中，此置換區段的起始 offset（UTF-16 code unit）。
  final int dispOffset;

  /// 顯示文字中，此置換區段的長度（UTF-16 code unit）。
  final int dispLen;

  /// dispLen - origLen（長度增減量）。
  final int delta;

  /// 此區段之前所有區段的累計 delta。
  final int accumDelta;

  const OffsetEntry({
    required this.origOffset,
    required this.origLen,
    required this.dispOffset,
    required this.dispLen,
    required this.delta,
    required this.accumDelta,
  });
}

/// 一個文字節點的完整偏移映射，`entries` 依 [OffsetEntry.origOffset]
/// 遞增排序。`null`（而非空的 [TextOffsetMap]）代表這個節點轉換後長度
/// 完全不變——[origToDisplay]／[displayToOrig] 對 `null` 一律原樣回傳輸入
/// offset，零額外開銷（見 offset-mapping-spec.md 2.1 節「記憶體最佳化」）。
class TextOffsetMap {
  final List<OffsetEntry> entries;
  const TextOffsetMap(this.entries);
}

/// 累加建構 [TextOffsetMap] 的可變 builder：呼叫端在掃描/替換文字的過程
/// 中，每遇到一個長度改變的置換區段就呼叫一次 [addSegment]，全部處理完
/// 後呼叫 [build]——沒有任何區段時回傳 `null`，代表這個節點可以走零開銷
/// 路徑（見 [TextOffsetMap] 文件）。
class OffsetMapBuilder {
  final List<OffsetEntry> _entries = [];
  int _accumDelta = 0;

  void addSegment({
    required int origOffset,
    required int origLen,
    required int dispOffset,
    required int dispLen,
  }) {
    final delta = dispLen - origLen;
    _entries.add(OffsetEntry(
      origOffset: origOffset,
      origLen: origLen,
      dispOffset: dispOffset,
      dispLen: dispLen,
      delta: delta,
      accumDelta: _accumDelta,
    ));
    _accumDelta += delta;
  }

  TextOffsetMap? build() => _entries.isEmpty ? null : TextOffsetMap(_entries);
}

/// 原文 offset → 顯示文字 offset（見 offset-mapping-spec.md 2.2 節第 1
/// 式）。用於 CFI 還原劃線（`toRange`）、搜尋結果高亮、TTS 朗讀進度定位。
/// [offsetMap] 為 `null`（或沒有任何區段）時直接原樣回傳（零開銷路徑）。
int origToDisplay(TextOffsetMap? offsetMap, int origOffset) {
  if (offsetMap == null || offsetMap.entries.isEmpty) return origOffset;

  final entries = offsetMap.entries;
  var low = 0;
  var high = entries.length - 1;
  var matchedIndex = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    final entry = entries[mid];
    if (entry.origOffset <= origOffset) {
      matchedIndex = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  if (matchedIndex == -1) return origOffset;

  final entry = entries[matchedIndex];
  if (origOffset < entry.origOffset + entry.origLen) {
    final intraOffset = origOffset - entry.origOffset;
    // 審查修正 C-2：片語「縮短」時（dispLen < origLen，例如「公共汽車」
    // (4) -> 「公車」(2)，TWPhrases.txt 實際存在 237 條此類詞彙），
    // intraOffset 可能超出顯示詞的實際長度（例如原文第 4 個字元的
    // intraOffset=3，但顯示詞只有 2 個字元）。必須夾在 [0, dispLen] 內，
    // 否則回傳值會指向顯示文字節點長度以外的位置，live DOM 呼叫
    // range.setEnd() 時直接拋出 IndexSizeError；夾住同時修復了單調性
    // 破壞（未夾住時，區段內最後一個 offset 的回傳值會大於區段之後緊接
    // 的 offset 回傳值）。
    final clampedIntra = math.min(intraOffset, entry.dispLen);
    return entry.dispOffset + clampedIntra;
  }

  return origOffset + entry.accumDelta + entry.delta;
}

/// 顯示文字 offset → 原文 offset（見 offset-mapping-spec.md 2.2 節第 2
/// 式）。用於使用者在畫面選取文字建立劃線（`fromRange`）時，換算出應
/// 存入 CFI 的原文 offset。[snapPolicy]（`'floor'`／`'ceil'`）決定 offset
/// 落在置換詞中間時要貼齊詞首還是詞尾——選取起點用 `'floor'`、選取終點
/// 用 `'ceil'`，確保框選結果涵蓋整個置換詞，不會切在詞彙中間。
int displayToOrig(
  TextOffsetMap? offsetMap,
  int dispOffset, {
  String snapPolicy = 'floor',
}) {
  assert(
    snapPolicy == 'floor' || snapPolicy == 'ceil',
    'snapPolicy 必須為 \'floor\' 或 \'ceil\'，收到："$snapPolicy"',
  );
  if (offsetMap == null || offsetMap.entries.isEmpty) return dispOffset;

  final entries = offsetMap.entries;
  var low = 0;
  var high = entries.length - 1;
  var matchedIndex = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    final entry = entries[mid];
    if (entry.dispOffset <= dispOffset) {
      matchedIndex = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  if (matchedIndex == -1) return dispOffset;

  final entry = entries[matchedIndex];
  if (dispOffset < entry.dispOffset + entry.dispLen) {
    return snapPolicy == 'ceil'
        ? entry.origOffset + entry.origLen
        : entry.origOffset;
  }

  return dispOffset - (entry.accumDelta + entry.delta);
}
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/reader/text_offset_map_test.dart`
Expected: PASS，19/19。

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/text_offset_map.dart app/test/reader/text_offset_map_test.dart
git commit -m "feat(reader): 新增 TextOffsetMap 雙向分段偏移映射（Dart）"
```

---

### Task 5: `text-offset-map.js`（JS 對應版本）

**Files:**
- Create: `app/android/app/src/main/assets/foliate/text-offset-map.js`
- Create: `app/tool/test_text_offset_map.mjs`

**Interfaces:**
- Consumes: 無（純函式，零 DOM 依賴）。
- Produces: `createOffsetMapBuilder()`、`origToDisplay(offsetMap, origOffset)`、`displayToOrig(offsetMap, dispOffset, snapPolicy)`，供 Task 7 的 `applyTextConversionToString()` 與 Issue 2 的 DOM Walker（`epubcfi.fromRange`／`toRange` 攔截點）直接引用。

- [ ] **Step 1: 寫失敗測試**

建立 `app/tool/test_text_offset_map.mjs`：

```javascript
// epic-42-text-conversion Issue 0b：TextOffsetMap 雙向偏移映射純邏輯
// 驗證腳本。零 DOM 依賴，可直接用 Node.js 執行（比照
// test_tts_safe_window.mjs 既有慣例），測試向量與
// app/test/reader/text_offset_map_test.dart 保持一致。
//
// 用法：node app/tool/test_text_offset_map.mjs

import assert from 'node:assert/strict'
import {
  createOffsetMapBuilder,
  origToDisplay,
  displayToOrig,
} from '../android/app/src/main/assets/foliate/text-offset-map.js'

// 零開銷路徑
assert.equal(origToDisplay(null, 5), 5)
assert.equal(displayToOrig(null, 5), 5)
assert.equal(origToDisplay({ entries: [] }, 5), 5)
assert.equal(displayToOrig({ entries: [] }, 5), 5)
{
  const builder = createOffsetMapBuilder()
  assert.equal(builder.build(), null)
}

// 單一區段：模擬「abc內存def」轉換為「abc記憶體def」
// 內存@origOffset=3,origLen=2 -> 記憶體@dispOffset=3,dispLen=3，delta=+1。
{
  const builder = createOffsetMapBuilder()
  builder.addSegment(3, 2, 3, 3)
  const map = builder.build()

  assert.equal(origToDisplay(map, 0), 0)
  assert.equal(origToDisplay(map, 2), 2)
  assert.equal(origToDisplay(map, 3), 3)
  assert.equal(origToDisplay(map, 4), 4)
  assert.equal(origToDisplay(map, 5), 6)

  assert.equal(displayToOrig(map, 2), 2)
  assert.equal(displayToOrig(map, 4, 'floor'), 3)
  assert.equal(displayToOrig(map, 5, 'floor'), 3)
  assert.equal(displayToOrig(map, 4, 'ceil'), 5)
  assert.equal(displayToOrig(map, 3, 'ceil'), 5)
  assert.equal(displayToOrig(map, 6), 5)
}

// 多區段：驗證 accumDelta 正確累加
{
  const builder = createOffsetMapBuilder()
  builder.addSegment(0, 2, 0, 3)
  builder.addSegment(10, 3, 11, 2)
  const map = builder.build()

  assert.equal(map.entries[1].accumDelta, 1)
  assert.equal(origToDisplay(map, 13), 13)
  assert.equal(displayToOrig(map, 13), 13)
}

// 縮短區段：模擬「公共汽車」(4) 轉換為「公車」(2)（審查修正 C-2）。
// origOffset=0,origLen=4 -> dispOffset=0,dispLen=2，delta=-2。
{
  const builder = createOffsetMapBuilder()
  builder.addSegment(0, 4, 0, 2)
  const map = builder.build()

  assert.equal(origToDisplay(map, 0), 0)
  assert.equal(origToDisplay(map, 1), 1)
  // 修正前會回傳 2、3，超出顯示文字「公車」實際長度 2 的有效範圍，
  // 在 live DOM 對長度僅 2 的文字節點呼叫 range.setEnd(node, 3) 會直接
  // 拋出 IndexSizeError。修正後皆夾住在 dispLen=2。
  assert.equal(origToDisplay(map, 2), 2)
  assert.equal(origToDisplay(map, 3), 2)
  // 弱單調遞增：區段邊界前後不應數值倒退（修正前 3->3、4->2 會倒退）。
  const beforeBoundary = origToDisplay(map, 3)
  const afterBoundary = origToDisplay(map, 4)
  assert.ok(afterBoundary >= beforeBoundary)
  assert.equal(afterBoundary, 2)

  assert.equal(displayToOrig(map, 1, 'floor'), 0)
  assert.equal(displayToOrig(map, 1, 'ceil'), 4)
  assert.equal(displayToOrig(map, 2), 4)
}

console.log('text-offset-map.js 雙向偏移映射驗證：全數通過')
```

- [ ] **Step 2: 執行測試，確認失敗（找不到模組）**

Run: `node app/tool/test_text_offset_map.mjs`
Expected: 拋出 `ERR_MODULE_NOT_FOUND`。

- [ ] **Step 3: 建立 `app/android/app/src/main/assets/foliate/text-offset-map.js`**

```javascript
// epic-42-text-conversion Issue 0b：雙向分段偏移映射（Piecewise Offset
// Mapping，見 docs/epics/epic-42-text-conversion/offset-mapping-spec.md
// 第 2 節）。零 DOM 依賴，可直接用 Node.js 執行（比照同目錄
// tts-safe-window.js 既有慣例），供 main.js 的 DOM Walker（Issue 2）
// 攔截 epubcfi.js 的 fromRange／toRange 呼叫點時使用。

/**
 * 累加建構偏移映射：呼叫端在掃描/替換文字的過程中，每遇到一個長度改變
 * 的置換區段就呼叫一次 addSegment，全部處理完後呼叫 build()——沒有任何
 * 區段時回傳 null，代表這個節點可以走零開銷路徑。
 */
export function createOffsetMapBuilder() {
  const entries = []
  let accumDelta = 0
  return {
    /**
     * @param {number} origOffset 原文中此區段的起始 offset（UTF-16）。
     * @param {number} origLen 原文中此區段的長度（UTF-16）。
     * @param {number} dispOffset 顯示文字中此區段的起始 offset（UTF-16）。
     * @param {number} dispLen 顯示文字中此區段的長度（UTF-16）。
     */
    addSegment(origOffset, origLen, dispOffset, dispLen) {
      const delta = dispLen - origLen
      entries.push({ origOffset, origLen, dispOffset, dispLen, delta, accumDelta })
      accumDelta += delta
    },
    /** @returns {{ entries: object[] } | null} 沒有任何區段時回傳 null。 */
    build() {
      return entries.length === 0 ? null : { entries }
    },
  }
}

/**
 * 原文 offset → 顯示文字 offset。用於 CFI 還原劃線（toRange）、搜尋結果
 * 高亮、TTS 朗讀進度定位。offsetMap 為 null（或沒有任何區段）時直接
 * 原樣回傳（零開銷路徑）。
 * @param {{ entries: object[] } | null | undefined} offsetMap
 * @param {number} origOffset
 * @returns {number}
 */
export function origToDisplay(offsetMap, origOffset) {
  if (!offsetMap || offsetMap.entries.length === 0) return origOffset

  const entries = offsetMap.entries
  let low = 0
  let high = entries.length - 1
  let matchedIndex = -1
  while (low <= high) {
    const mid = (low + high) >> 1
    const entry = entries[mid]
    if (entry.origOffset <= origOffset) {
      matchedIndex = mid
      low = mid + 1
    } else {
      high = mid - 1
    }
  }

  if (matchedIndex === -1) return origOffset

  const entry = entries[matchedIndex]
  if (origOffset < entry.origOffset + entry.origLen) {
    const intraOffset = origOffset - entry.origOffset
    // 審查修正 C-2：片語「縮短」時（dispLen < origLen，例如「公共汽車」
    // (4) -> 「公車」(2)，TWPhrases.txt 實際存在 237 條此類詞彙），
    // intraOffset 可能超出顯示詞的實際長度。必須夾在 [0, dispLen] 內，
    // 否則回傳值會指向顯示文字節點長度以外的位置，live DOM 呼叫
    // range.setEnd() 時直接拋出 IndexSizeError；夾住同時修復了單調性
    // 破壞。
    const clampedIntra = Math.min(intraOffset, entry.dispLen)
    return entry.dispOffset + clampedIntra
  }

  return origOffset + entry.accumDelta + entry.delta
}

/**
 * 顯示文字 offset → 原文 offset。用於使用者在畫面選取文字建立劃線
 * （fromRange）時，換算出應存入 CFI 的原文 offset。snapPolicy
 * （'floor'／'ceil'）決定 offset 落在置換詞中間時要貼齊詞首還是詞尾——
 * 選取起點用 'floor'、選取終點用 'ceil'。
 * @param {{ entries: object[] } | null | undefined} offsetMap
 * @param {number} dispOffset
 * @param {'floor' | 'ceil'} [snapPolicy]
 * @returns {number}
 */
export function displayToOrig(offsetMap, dispOffset, snapPolicy = 'floor') {
  if (!offsetMap || offsetMap.entries.length === 0) return dispOffset

  const entries = offsetMap.entries
  let low = 0
  let high = entries.length - 1
  let matchedIndex = -1
  while (low <= high) {
    const mid = (low + high) >> 1
    const entry = entries[mid]
    if (entry.dispOffset <= dispOffset) {
      matchedIndex = mid
      low = mid + 1
    } else {
      high = mid - 1
    }
  }

  if (matchedIndex === -1) return dispOffset

  const entry = entries[matchedIndex]
  if (dispOffset < entry.dispOffset + entry.dispLen) {
    return snapPolicy === 'ceil'
      ? entry.origOffset + entry.origLen
      : entry.origOffset
  }

  return dispOffset - (entry.accumDelta + entry.delta)
}
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `node app/tool/test_text_offset_map.mjs`
Expected: 印出「text-offset-map.js 雙向偏移映射驗證：全數通過」，結束碼 0。

- [ ] **Step 5: 執行 ES 相容性檢查腳本**

```bash
node app/tool/check_foliate_es_compat.js
```

Expected: 結束碼 0（本檔案只用 `for`／`while`／物件字面量／解構賦值等既有支援的基礎語法，未使用任何 `RISKY_APIS` 列出的較新方法）。

- [ ] **Step 6: Commit**

```bash
git add app/android/app/src/main/assets/foliate/text-offset-map.js app/tool/test_text_offset_map.mjs
git commit -m "feat(reader): 新增 text-offset-map.js 雙向分段偏移映射（JS）"
```

---

### Task 6: `convertText()` 改為片語優先轉換（不對稱設計），新增 `convertTextDetailed()`（Dart）

**Files:**
- Modify: `app/lib/reader/text_conversion.dart`
- Modify: `app/test/reader/text_conversion_test.dart`

**Interfaces:**
- Consumes: Issue 0 的 `kS2tDict`／`kT2sDict`；Task 3 的 `kS2twpPhraseDict`／`kTw2sPhraseDict`；Task 4 的 `OffsetMapBuilder`／`TextOffsetMap`。
- Produces: `String convertText(String input, TextConversionMode mode)`（Issue 0 定案簽章不變）；新增 `({String text, TextOffsetMap? offsetMap}) convertTextDetailed(String input, TextConversionMode mode)`，供 Issue 2／未來 Dart 端 TTS word-level highlight 消費。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/reader/text_conversion_test.dart` 頂部 import 區塊新增：

```dart
import 'package:elinkbook/reader/text_offset_map.dart';
```

現行檔案結尾三行（`app/test/reader/text_conversion_test.dart:64-66`）目前是：

```dart
      expect(converted.length, input.length);
    });
  });
}
```

——`test('含代理對字元...')` 的 `});`（第 64 行）、`group('convertText', ...)` 的 `});`（第 65 行）、`main()` 的 `}`（第 66 行）。本 Step 分兩處插入，**不要**把兩處誤合併成一處（合併會漏掉 `group('convertText', ...)` 自己的收尾 `});`，導致大括號數量對不上、編譯失敗）：

**插入點 A**——在第 64 行 `});` 之後、第 65 行 `});`（`group('convertText', ...)` 的收尾）**之前**，新增（既有 9 項測試維持不動，這 4 項是延伸同一個 `group('convertText', ...)`）：

```dart

    test('toTraditional 片語轉換：台灣常用詞優先於單字元查找表（Issue 0b）', () {
      // TWPhrases.txt：內存 -> 記憶體。純字元轉換只會得到「內存」，
      // 缺少台灣在地化，須靠片語比對。
      expect(convertText('内存', TextConversionMode.toTraditional), '記憶體');
    });

    test('toTraditional 片語轉換：單字元長度的 TWPhrases 詞條（Issue 0b）', () {
      // TWPhrases.txt 有 12 條單字詞條，「硅」不在 STCharacters.txt 中，
      // 純字元查找表無法轉換，須靠片語字典（即使長度為 1）才能正確轉換。
      expect(convertText('硅', TextConversionMode.toTraditional), '矽');
    });

    test(
        'toSimplified 片語轉換：TSPhrases 直接對原文做最長匹配（Issue 0b，'
        '審查修正 C-1）', () {
      // TSPhrases.txt：一目瞭然 -> 一目了然。toSimplified 與 toTraditional
      // 的片語比對基準不同（見本檔案頂部 Architecture 說明）——TSPhrases
      // 的鍵是「原始輸入」的形態，直接對 input 做最長匹配，不對字元轉換
      // 後的中繼文字做。
      expect(
        convertText('一目瞭然', TextConversionMode.toSimplified),
        '一目了然',
      );
    });

    test(
        'toSimplified 片語轉換：TSPhrases 保護固定用語不被單字元規則誤轉'
        '（Issue 0b，審查修正 C-1 核心回歸案例）', () {
      // kT2sDict 對「乾」的單字元規則是「乾->干」（TSCharacters.txt：
      // 乾\t干 乾，取首個候選字）。若先對原文做字元轉換再比對片語（錯誤
      // 的兩階段設計），「乾隆」會在字元轉換階段就被誤轉成「干隆」，
      // TSPhrases 的「乾隆->乾隆」保護規則永遠比對不到，最終輸出錯字
      // 「干隆皇帝」。必須直接對原文「乾隆」做片語最長匹配才能正確保護
      // （見 reviews/review-plan-issue-0b.md Issue C-1，已用 opencc-js
      // 實際輸出驗證：tw2s('乾隆皇帝') === '乾隆皇帝'）。
      expect(
        convertText('乾隆皇帝', TextConversionMode.toSimplified),
        '乾隆皇帝',
      );
      expect(
        convertText('乾坤大挪移', TextConversionMode.toSimplified),
        '乾坤大挪移',
      );
    });

    test(
        'toSimplified：妥瑞氏症原樣保留，不套用大陸用語替換（Issue 0b，審查修正 '
        'I-1，ADR 0032 靈魂驗證案例）', () {
      // 「妥瑞氏症」在 OpenCC 的 tw2sp（含大陸用語）會被強制改寫為
      // 「抽动秽语综合征」，但本 Epic 採 tw2s（不套用大陸用語），必須
      // 忠實保留台灣慣用譯名。
      expect(
        convertText('妥瑞氏症', TextConversionMode.toSimplified),
        '妥瑞氏症',
      );
    });

    test('convertText 對片語轉換的輸出與 convertTextDetailed 一致（Issue 0b）', () {
      const input = '把内存清空';
      expect(
        convertText(input, TextConversionMode.toTraditional),
        convertTextDetailed(input, TextConversionMode.toTraditional).text,
      );
    });
```

插入點 A 完成後，緊接著的第 65 行 `});`（原檔既有內容，不須改動）就會正確收尾 `group('convertText', ...)`（原 9 項＋本插入點新增 6 項＝15 項）。

**插入點 B**——在（插入點 A 完成後移動到新位置的）`group('convertText', ...)` 收尾 `});` 之後、`main()` 的收尾 `}` **之前**，新增一個獨立的姐妹 `group`（與 `group('convertText', ...)` 同一層級，皆在 `main()` 內）：

```dart

  group('convertTextDetailed（Issue 0b）', () {
    test('片語轉換長度改變時，產生正確的 TextOffsetMap', () {
      final result =
          convertTextDetailed('内存', TextConversionMode.toTraditional);
      expect(result.text, '記憶體');
      expect(result.offsetMap, isNotNull);
      expect(result.offsetMap!.entries, hasLength(1));
      final entry = result.offsetMap!.entries.single;
      expect(entry.origOffset, 0);
      expect(entry.origLen, 2);
      expect(entry.dispOffset, 0);
      expect(entry.dispLen, 3);
    });

    test('長度不變時，offsetMap 為 null（零開銷路徑）', () {
      final result =
          convertTextDetailed('国电脑', TextConversionMode.toTraditional);
      expect(result.text, '國電腦');
      expect(result.offsetMap, isNull);
    });

    test('original 模式：offsetMap 恆為 null', () {
      final result =
          convertTextDetailed('内存', TextConversionMode.original);
      expect(result.text, '内存');
      expect(result.offsetMap, isNull);
    });

    test('片語與前後文字混排時，offset 計算正確', () {
      // "把内存清空" -> "把記憶體清空"："内存"@origOffset=1,origLen=2 轉為
      // "記憶體"@dispOffset=1,dispLen=3；前後的「把」「清空」逐字元不變。
      final result =
          convertTextDetailed('把内存清空', TextConversionMode.toTraditional);
      expect(result.text, '把記憶體清空');
      final entry = result.offsetMap!.entries.single;
      expect(entry.origOffset, 1);
      expect(entry.origLen, 2);
      expect(entry.dispOffset, 1);
      expect(entry.dispLen, 3);
      // 原文「空」在 index 4，顯示文字中「空」在 index 5（多了一個字）。
      expect(origToDisplay(result.offsetMap, 4), 5);
    });

    test(
        '代理對字元位於片語前時，offset 以 UTF-16 code unit 正確計量'
        '（Issue 0b，審查修正 I-2）', () {
      // '𠮷'（U+20BB7）佔 2 個 UTF-16 code unit。"内存" 這個片語的
      // origOffset／dispOffset 必須是 2（UTF-16 offset）而非 1（code
      // point 索引）——Dart（runes）與 JS（Array.from）對代理對的正確
      // 處理，若把「code point 索引」與「UTF-16 offset」混淆會產生隱蔽
      // 的偏移 bug，此測試明確覆蓋這個邊界。
      final result =
          convertTextDetailed('𠮷内存', TextConversionMode.toTraditional);
      expect(result.text, '𠮷記憶體');
      expect(result.offsetMap, isNotNull);
      final entry = result.offsetMap!.entries.single;
      expect(entry.origOffset, 2);
      expect(entry.origLen, 2);
      expect(entry.dispOffset, 2);
      expect(entry.dispLen, 3);
    });
  });
```

插入點 B 完成後，緊接著的（原第 66 行）`}` 就會正確收尾 `main()`。完成後檔案結構為：`main() { group('convertText', () { ...15 項... }); group('convertTextDetailed（Issue 0b）', () { ...5 項... }); }`（總計 20 項）。

（最後一個新增的 `test` 呼叫了 `origToDisplay`，是從 Task 4 的 `text_offset_map.dart` 匯入的頂層函式，已在本 Step 頂部的 import 補上。）

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/reader/text_conversion_test.dart`
Expected: FAIL——編譯錯誤（`convertTextDetailed`／`kS2twpPhraseDict` 等尚未定義）或執行期斷言失敗（「内存」目前仍逐字元轉換為「內存」而非「記憶體」）。

- [ ] **Step 3: 修改 `app/lib/reader/text_conversion.dart`**

將整個檔案內容改為：

```dart
import 'dart:math' as math;

import 'text_conversion_dict.dart';
import 'text_conversion_mode.dart';
import 'text_offset_map.dart';

/// 片語比對時，單一詞條 code point 數的安全上限——必須與
/// `app/tool/generate_conversion_dicts.js` 的 `MAX_PHRASE_KEY_LENGTH`、
/// `text-conversion.js` 的 `MAX_PHRASE_KEY_LENGTH` 保持一致（目前皆為
/// 16）。目前已知最長詞條為 `TWPhrases.txt` 的 15 碼，留有餘裕；
/// `assertMaxPhraseKeyLength()`（生成腳本）是唯一防線，若字典來源檔未來
/// 新增更長詞條，生成階段會立刻拋例外中止，而非讓這裡靜默漏未比對到。
const int kMaxPhraseKeyLength = 16;

/// 依 [mode] 對 [input] 做簡繁字元/片語轉換，回傳最終顯示文字，與（若有
/// 任何區段長度改變）對應的 [TextOffsetMap]。
///
/// **`toTraditional` 與 `toSimplified` 的片語比對基準不同，兩者不對稱**
/// （2026-09-15 依 `reviews/review-plan-issue-0b.md` Issue C-1 修訂——先前
/// 草稿誤將兩者套用相同的兩階段設計，已對照真實 OpenCC
/// `conversionChain` 設定與 `opencc-js` 實際輸出推翻，見
/// `docs/epics/epic-42-text-conversion/plans/plan-issue-0b.md` Self-Review
/// 「關鍵技術驗證」）：
/// - **`toTraditional`（兩階段）**：**Stage 1** 逐 code point 以 [kS2tDict]
///   （Issue 0 既有，生成階段已保證 ΔL=0）轉換出「中繼文字」，與 [input]
///   在 code point 索引與 UTF-16 offset 上完全對齊；**Stage 2** 在中繼
///   文字上做 [kS2twpPhraseDict]（`TWPhrases`）最長匹配（由長至短嘗試，
///   長度上限 [kMaxPhraseKeyLength]）——`TWPhrases.txt` 的鍵是「單字元
///   轉換後」的繁體形態（例如鍵是「內存」不是「内存」），必須先做 Stage 1
///   才能命中。
/// - **`toSimplified`（單一階段）**：直接對**原始輸入** [input] 做
///   [kTw2sPhraseDict]（`TSPhrases`）最長匹配，找不到片語才逐 code point
///   退回 [kT2sDict] 單字元轉換——`TSPhrases.txt` 的鍵是**原始（未字元
///   轉換）**的繁體形態，且常用來保護固定用語不被單字元規則誤轉（例如
///   `TSCharacters.txt` 把「乾」轉成「干」，但「乾隆\t乾隆」這條 `TSPhrases`
///   規則保護「乾隆」這個詞不被誤轉成「干隆」）。若先做字元轉換再比對
///   片語（`toTraditional` 的做法），片語字典的鍵永遠比對不到，繁轉簡
///   消歧功能會被架構性地閹割掉。
({String text, TextOffsetMap? offsetMap}) convertTextDetailed(
  String input,
  TextConversionMode mode,
) {
  if (mode == TextConversionMode.original || input.isEmpty) {
    return (text: input, offsetMap: null);
  }

  final units = input.runes.map(String.fromCharCode).toList(growable: false);

  final List<String> matchUnits;
  final Map<String, String> charDict;
  final Map<String, String> phraseDict;
  if (mode == TextConversionMode.toTraditional) {
    charDict = kS2tDict;
    phraseDict = kS2twpPhraseDict;
    // Stage 1：先逐字元轉換出中繼文字，片語比對對中繼文字做（見上方
    // 文件註解）。
    matchUnits = units.map((ch) => charDict[ch] ?? ch).toList(growable: false);
  } else {
    charDict = kT2sDict;
    phraseDict = kTw2sPhraseDict;
    // toSimplified：片語比對直接對原始輸入做，不做字元轉換的中繼文字
    // （見上方文件註解，審查修正 C-1）。
    matchUnits = units;
  }

  final buffer = StringBuffer();
  final builder = OffsetMapBuilder();
  var origOffset = 0;
  var dispOffset = 0;
  var i = 0;

  while (i < matchUnits.length) {
    final maxLen = math.min(kMaxPhraseKeyLength, matchUnits.length - i);
    String? matchedValue;
    var matchedLen = 0;
    for (var len = maxLen; len >= 1; len--) {
      final candidate = matchUnits.sublist(i, i + len).join();
      final value = phraseDict[candidate];
      if (value != null) {
        matchedValue = value;
        matchedLen = len;
        break;
      }
    }

    final consumedCount = matchedValue != null ? matchedLen : 1;
    final origSegment = matchUnits.sublist(i, i + consumedCount).join();
    // toTraditional：origSegment 已是 Stage 1 轉換後的中繼文字，找不到
    // 片語時直接沿用。toSimplified：origSegment 是原始未轉換文字，找不到
    // 片語時才在此對單一 code point 套用 charDict。
    final dispSegment = matchedValue ??
        (mode == TextConversionMode.toTraditional
            ? origSegment
            : (charDict[origSegment] ?? origSegment));

    buffer.write(dispSegment);
    if (dispSegment.length != origSegment.length) {
      builder.addSegment(
        origOffset: origOffset,
        origLen: origSegment.length,
        dispOffset: dispOffset,
        dispLen: dispSegment.length,
      );
    }
    origOffset += origSegment.length;
    dispOffset += dispSegment.length;
    i += consumedCount;
  }

  return (text: buffer.toString(), offsetMap: builder.build());
}

/// 依 [mode] 對 [input] 做簡繁字元/片語轉換，只回傳顯示文字（不需要
/// [TextOffsetMap] 的既有呼叫端使用，例如目錄/書籤/劃線清單、書架書名、
/// 搜尋結果摘要片段、TTS 朗讀段——這些情境不涉及 DOM Range／CFI 座標
/// 換算）。此簽章為 Issue 0 定案的固定介面，不得更動參數順序或型別
/// （Issue 1-5 直接依賴）。
String convertText(String input, TextConversionMode mode) =>
    convertTextDetailed(input, mode).text;
```

- [ ] **Step 4: 執行測試，確認通過（含既有 9 項測試零回歸）**

Run: `flutter test test/reader/text_conversion_test.dart`
Expected: PASS，全數通過（Issue 0 既有 9 項＋本 Task 新增 11 項＝20 項）。

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/text_conversion.dart app/test/reader/text_conversion_test.dart
git commit -m "feat(reader): convertText 擴充為片語優先轉換（toTraditional 兩階段／toSimplified 單一階段），新增 convertTextDetailed()"
```

---

### Task 7: `text-conversion.js`（JS 對應版本，供 Issue 2 DOM Walker 直接呼叫）

**Files:**
- Create: `app/android/app/src/main/assets/foliate/text-conversion.js`
- Create: `app/tool/test_text_conversion.mjs`

**Interfaces:**
- Consumes: Task 3 的 `s2tDict`／`t2sDict`／`s2twpPhraseDict`／`tw2sPhraseDict`（`text_conversion_dict.js`）；Task 5 的 `createOffsetMapBuilder()`。
- Produces: `applyTextConversionToString(text, mode)` 回傳 `{ text, offsetMap }`，供 Issue 2 的 DOM Walker（`applyTextConversion(root, mode)`）逐文字節點呼叫——Issue 2 本身不重新實作這裡的最長匹配演算法。

- [ ] **Step 1: 寫失敗測試**

建立 `app/tool/test_text_conversion.mjs`：

```javascript
// epic-42-text-conversion Issue 0b：applyTextConversionToString() 片語
// 優先轉換驗證腳本（toTraditional 兩階段／toSimplified 單一階段）。零 DOM 依賴，測試向量與
// app/test/reader/text_conversion_test.dart 保持一致，驗證 JS／Dart
// 兩份獨立實作行為一致（見 ADR 0031：Dart AOT 無法呼叫 JS，兩邊各自
// 維護、不共用程式碼）。
//
// 用法：node app/tool/test_text_conversion.mjs

import assert from 'node:assert/strict'
import { applyTextConversionToString } from '../android/app/src/main/assets/foliate/text-conversion.js'

// original 模式／空字串：原樣回傳，offsetMap 為 null。
{
  const result = applyTextConversionToString('内存', 'original')
  assert.equal(result.text, '内存')
  assert.equal(result.offsetMap, null)
}
{
  const result = applyTextConversionToString('', 'toTraditional')
  assert.equal(result.text, '')
  assert.equal(result.offsetMap, null)
}

// 片語轉換：台灣常用詞優先於單字元查找表。
{
  const result = applyTextConversionToString('内存', 'toTraditional')
  assert.equal(result.text, '記憶體')
  assert.ok(result.offsetMap)
  assert.equal(result.offsetMap.entries.length, 1)
  const entry = result.offsetMap.entries[0]
  assert.equal(entry.origOffset, 0)
  assert.equal(entry.origLen, 2)
  assert.equal(entry.dispOffset, 0)
  assert.equal(entry.dispLen, 3)
}

// 單字元長度的 TWPhrases 詞條。
{
  const result = applyTextConversionToString('硅', 'toTraditional')
  assert.equal(result.text, '矽')
}

// toSimplified：TSPhrases 直接對原文做最長匹配（審查修正 C-1）。
{
  const result = applyTextConversionToString('一目瞭然', 'toSimplified')
  assert.equal(result.text, '一目了然')
}

// toSimplified：TSPhrases 保護固定用語不被單字元規則誤轉（審查修正 C-1
// 核心回歸案例）。kT2sDict 對「乾」的單字元規則是「乾->干」，若先做
// 字元轉換再比對片語，「乾隆」會被誤轉成「干隆」，TSPhrases 的
// 「乾隆->乾隆」保護規則永遠比對不到。已用 opencc-js 實際輸出驗證：
// tw2s('乾隆皇帝') === '乾隆皇帝'。
{
  const result = applyTextConversionToString('乾隆皇帝', 'toSimplified')
  assert.equal(result.text, '乾隆皇帝')
}
{
  const result = applyTextConversionToString('乾坤大挪移', 'toSimplified')
  assert.equal(result.text, '乾坤大挪移')
}

// toSimplified：妥瑞氏症原樣保留，不套用大陸用語替換（審查修正 I-1，
// ADR 0032 靈魂驗證案例）。
{
  const result = applyTextConversionToString('妥瑞氏症', 'toSimplified')
  assert.equal(result.text, '妥瑞氏症')
}

// 代理對字元位於片語前時，offset 以 UTF-16 code unit 正確計量（審查
// 修正 I-2）。'𠮷'（U+20BB7）佔 2 個 UTF-16 code unit。
{
  const result = applyTextConversionToString('𠮷内存', 'toTraditional')
  assert.equal(result.text, '𠮷記憶體')
  const entry = result.offsetMap.entries[0]
  assert.equal(entry.origOffset, 2)
  assert.equal(entry.origLen, 2)
  assert.equal(entry.dispOffset, 2)
  assert.equal(entry.dispLen, 3)
}

// 長度不變時，offsetMap 為 null（零開銷路徑）。
{
  const result = applyTextConversionToString('国电脑', 'toTraditional')
  assert.equal(result.text, '國電腦')
  assert.equal(result.offsetMap, null)
}

// 片語與前後文字混排時，offset 計算正確。
{
  const result = applyTextConversionToString('把内存清空', 'toTraditional')
  assert.equal(result.text, '把記憶體清空')
  const entry = result.offsetMap.entries[0]
  assert.equal(entry.origOffset, 1)
  assert.equal(entry.origLen, 2)
  assert.equal(entry.dispOffset, 1)
  assert.equal(entry.dispLen, 3)
}

// 查找表與片語表都找不到的字元維持原樣。
{
  const result = applyTextConversionToString('ABC123', 'toTraditional')
  assert.equal(result.text, 'ABC123')
  assert.equal(result.offsetMap, null)
}

console.log('text-conversion.js 片語優先轉換驗證：全數通過')
```

- [ ] **Step 2: 執行測試，確認失敗（找不到模組）**

Run: `node app/tool/test_text_conversion.mjs`
Expected: 拋出 `ERR_MODULE_NOT_FOUND`。

- [ ] **Step 3: 建立 `app/android/app/src/main/assets/foliate/text-conversion.js`**

```javascript
// epic-42-text-conversion Issue 0b：片語優先、單字元其次的簡繁轉換，
// 並在替換過程中同步收集區段供建構 TextOffsetMap（見
// docs/epics/epic-42-text-conversion/offset-mapping-spec.md 第 3.1
// 節）。與 app/lib/reader/text_conversion.dart 的 convertTextDetailed()
// 是同一份演算法的兩份獨立實作，測試向量刻意保持一致（見
// app/tool/test_text_conversion.mjs），兩邊各自維護、不共用程式碼
// （Dart AOT 無法呼叫 JS，見 ADR 0031）。
//
// 零 DOM 依賴，可直接用 Node.js 執行（比照同目錄 tts-safe-window.js 的
// 既有慣例），供 Issue 2 的 DOM Walker（applyTextConversion）逐文字節點
// 呼叫——Issue 2 本身不重新實作這裡的最長匹配演算法。

import { s2tDict, t2sDict, s2twpPhraseDict, tw2sPhraseDict } from './text_conversion_dict.js'
import { createOffsetMapBuilder } from './text-offset-map.js'

// 片語比對時，單一詞條 code point 數的安全上限——必須與
// app/tool/generate_conversion_dicts.js 的 MAX_PHRASE_KEY_LENGTH、
// app/lib/reader/text_conversion.dart 的 kMaxPhraseKeyLength 保持一致。
const MAX_PHRASE_KEY_LENGTH = 16

/**
 * 依 mode 對 text 做簡繁字元/片語轉換，回傳顯示文字與（若有任何區段長度
 * 改變）對應的 offsetMap。
 *
 * **toTraditional 與 toSimplified 的片語比對基準不同，兩者不對稱**
 * （2026-09-15 依 reviews/review-plan-issue-0b.md Issue C-1 修訂，與
 * Dart 版 convertTextDetailed() 完全相同的設計，見其文件註解的完整
 * 技術驗證說明）：
 * - toTraditional（兩階段）：Stage 1 逐 code point 用 s2tDict 轉換出
 *   中繼文字，與 text 逐字元等長；Stage 2 在中繼文字上做
 *   s2twpPhraseDict（TWPhrases）最長匹配——TWPhrases 的鍵是「單字元
 *   轉換後」的繁體形態，必須先做 Stage 1 才能命中。
 * - toSimplified（單一階段）：直接對「原始輸入」做 tw2sPhraseDict
 *   （TSPhrases）最長匹配，找不到片語才逐 code point 退回 t2sDict
 *   單字元轉換——TSPhrases 的鍵是原始（未字元轉換）的繁體形態，常用來
 *   保護固定用語不被單字元規則誤轉（例如「乾隆」不被誤轉成「干隆」）。
 *   若先做字元轉換再比對片語，片語字典的鍵永遠比對不到。
 *
 * @param {string} text
 * @param {'original' | 'toTraditional' | 'toSimplified'} mode
 * @returns {{ text: string, offsetMap: { entries: object[] } | null }}
 */
export function applyTextConversionToString(text, mode) {
  if (mode === 'original' || text.length === 0) {
    return { text, offsetMap: null }
  }

  const units = Array.from(text)

  let matchUnits
  let charDict
  let phraseDict
  if (mode === 'toTraditional') {
    charDict = s2tDict
    phraseDict = s2twpPhraseDict
    // Stage 1：先逐字元轉換出中繼文字，片語比對對中繼文字做。
    matchUnits = units.map((ch) => charDict[ch] || ch)
  } else {
    charDict = t2sDict
    phraseDict = tw2sPhraseDict
    // toSimplified：片語比對直接對原始輸入做（審查修正 C-1）。
    matchUnits = units
  }

  let result = ''
  const builder = createOffsetMapBuilder()
  let origOffset = 0
  let dispOffset = 0
  let i = 0
  while (i < matchUnits.length) {
    const maxLen = Math.min(MAX_PHRASE_KEY_LENGTH, matchUnits.length - i)
    let matchedValue = null
    let matchedLen = 0
    for (let len = maxLen; len >= 1; len--) {
      const candidate = matchUnits.slice(i, i + len).join('')
      if (Object.prototype.hasOwnProperty.call(phraseDict, candidate)) {
        matchedValue = phraseDict[candidate]
        matchedLen = len
        break
      }
    }

    const consumedCount = matchedValue !== null ? matchedLen : 1
    const origSegment = matchUnits.slice(i, i + consumedCount).join('')
    // toTraditional：origSegment 已是 Stage 1 轉換後的中繼文字，找不到
    // 片語時直接沿用。toSimplified：origSegment 是原始未轉換文字，找不到
    // 片語時才在此對單一 code point 套用 charDict。
    const dispSegment = matchedValue !== null
      ? matchedValue
      : (mode === 'toTraditional' ? origSegment : (charDict[origSegment] || origSegment))

    result += dispSegment
    if (dispSegment.length !== origSegment.length) {
      builder.addSegment(origOffset, origSegment.length, dispOffset, dispSegment.length)
    }
    origOffset += origSegment.length
    dispOffset += dispSegment.length
    i += consumedCount
  }

  return { text: result, offsetMap: builder.build() }
}
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `node app/tool/test_text_conversion.mjs`
Expected: 印出「text-conversion.js 片語優先轉換驗證：全數通過」，結束碼 0。

- [ ] **Step 5: 執行 ES 相容性檢查腳本**

```bash
node app/tool/check_foliate_es_compat.js
```

Expected: 結束碼 0（`Array.from`／`Object.prototype.hasOwnProperty.call`／`Math.min` 皆非 `RISKY_APIS` 清單項目）。

- [ ] **Step 6: 交叉核對 Dart／JS 兩份實作行為一致**

```bash
node app/tool/test_text_conversion.mjs && flutter test test/reader/text_conversion_test.dart
```

Expected: 兩者皆通過——`test_text_conversion.mjs` 與 `text_conversion_test.dart` 對「内存」「硅」「一目瞭然」「乾隆皇帝」「乾坤大挪移」「妥瑞氏症」「国电脑」「把内存清空」「𠮷内存」「ABC123」十個共用範例的輸出／offsetMap 結構完全一致（人工比對兩份測試檔的斷言值，確認沒有語言邊界造成的隱性差異）。

- [ ] **Step 7: Commit**

```bash
git add app/android/app/src/main/assets/foliate/text-conversion.js app/tool/test_text_conversion.mjs
git commit -m "feat(reader): 新增 text-conversion.js，applyTextConversionToString() 供 Issue 2 消費（不對稱片語比對設計）"
```

- [ ] **Step 8: 執行完整 `flutter test`（本計畫最後一個 Task，比照專案慣例跑一次全套）**

Run: `flutter test`
Expected: 全數通過（既有已知不穩定案例除外，例如 `adaptive_shell_scaffold_test.dart` 既有 2 個失敗案例，非本次異動引入）。

---

## Self-Review

**關鍵技術驗證（撰寫本計畫前完成，非事後合理化；2026-09-15 依 `reviews/review-plan-issue-0b.md` 複驗並修正第 2 點）**：撰寫本計畫前，先在 `opencc/`（研究用目錄，已有 `opencc-js` 及其 BYVoid/OpenCC 原始資料，不影響 `app/`）用 `opencc-js` 實際呼叫 `s2twp()`／`tw2s()` 驗證下列假設，全數通過驗證才動筆：
1. **`TWPhrases.txt` 的鍵是「單字元轉換後」的形態**：`grep` 下載的原始檔確認鍵是「內存」（繁體）而非「内存」（簡體）；`s2twp('内存')` 實際輸出 `記憶體`，證實真實 OpenCC 管線是「先用 `STCharacters` 逐字轉換出『內存』，再用 `TWPhrases` 比對『內存』得到『記憶體』」，不是直接拿簡體原文比對片語表。這是 `toTraditional`「Stage 1 字元轉換→Stage 2 片語比對」兩階段順序的直接依據，順序顛倒會讓片語字典完全比對不到任何東西。
2. **`TSPhrases.txt` 剛好相反——鍵是「原始輸入」的形態，不是字元轉換後的形態（審查修正 Issue C-1，原稿在此處犯了確認偏誤）**：原稿誤以「`tw2s('一目瞭然')` = `一目了然`」佐證 `TSPhrases` 與 `TWPhrases` 同一套「先字元轉換再片語比對」順序，但「瞭」恰好不在 `TSCharacters.txt` 中，字元轉換階段對這個例子完全不變動輸入，兩種假設（鍵是原文形態／鍵是轉換後形態）在這個例子上殊途同歸，無法區分——是嚴重的確認偏誤。複審時直接查對真實 OpenCC 設定檔（`opencc-js/dist/esm-lib/preset/full.js:65`）確認 `t2s` 的 `conversionChain` 是 `[[TSPhrases, TSCharacters]]`：**`TSPhrases` 與 `TSCharacters` 是同一個合併階段**，一起對原始輸入做最長匹配，不是先字元轉換再片語比對。用會被字元轉換規則影響的字重新驗證：`TSCharacters.txt` 有「乾\t干 乾」（單字元規則「乾→干」），但 `TSPhrases.txt` 有「乾隆\t乾隆」（identity，保護「乾隆」這個詞不被單字元規則誤轉）；`tw2s('乾隆皇帝')` 實際輸出 `乾隆皇帝`（未變）。若照原稿的兩階段設計，「乾隆」會在字元轉換階段先被誤轉成「干隆」，`TSPhrases` 的保護規則永遠比對不到，最終輸出錯字「干隆皇帝」。修正後 `toSimplified` 改為單一階段：直接對原始輸入做 `TSPhrases`／`TSCharacters` 合併最長匹配（見 Task 6／7 程式碼與其文件註解）。
3. **排除 `STPhrases`（人類已決定）**：真實 `s2twp` 管線是 `conversionChain: [[STPhrases, STPhrases_GeneratedFromRegionalPhrases, STCharacters], [TWPhrases, TWVariantsPhrases, TWVariants]]`（兩個獨立階段；`STPhrases` 約 49,000 條，處理「幹/乾/干」依詞境選字的問題），但這規模與本 Epic 動機（台灣在地化用詞，非通用簡繁消歧）不成比例，經與人類確認排除，只保留第一階段的 `STCharacters` 與第二階段的 `TWPhrases`（同步排除 `TWVariantsPhrases`／`TWVariants`，人類與審查者皆未對此提出異議）。
4. **排除 `TWVariantsRev`／`TWVariantsRevPhrases`（本計畫撰寫過程中新發現並排除）**：真實 `tw2s` 管線是 `conversionChain: [[TWVariantsRevPhrases, TWVariantsRev], [TSPhrases, TSCharacters]]`（兩個獨立階段）；原本規劃納入第一階段的 `TWVariantsRevPhrases`（1,128 條，皆為 ΔL=0），但實測驗證其字典內容多數詞條是 identity 佔位（如「一家三口→一家三口」），實質內容價值有限，且 `TWVariantsRev`（第一階段另一個字典）本身甚至不是原始檔案，是 OpenCC 用 `reverse.py` + `@reverse-prefer` 人工消歧義從 `TWVariants.txt` 動態產生的衍生檔，正確重現其演算法的成本與實際效益不成比例。決定將整個第一階段排除，`toSimplified` 只保留第二階段的 `TSPhrases + TSCharacters`（已用「乾隆皇帝」「一目瞭然」等案例驗證此階段本身的合併最長匹配行為正確）。

**審查修訂記錄**：2026-09-15 `reviews/review-plan-issue-0b.md`（0 Critical 已修訂為 2 Critical／3 Important／3 Minor 全數處理）已套用至本計畫——**C-1**（`toSimplified` 誤用與 `toTraditional` 相同的兩階段設計，導致 `TSPhrases` 消歧規則全數失效甚至產生「干隆皇帝」等破壞性錯字：已改為單一階段直接對原始輸入做合併最長匹配，Task 6／7 演算法與文件註解全面修訂，並補上「乾隆皇帝」「乾坤大挪移」回歸測試）；**C-2**（`origToDisplay` 在片語縮短時 `intraOffset` 未夾在顯示詞邊界內，導致 offset 溢出且破壞單調性，live DOM 會拋出 `IndexSizeError`：已用 `math.min(intraOffset, entry.dispLen)`／`Math.min(intraOffset, entry.dispLen)` 夾住，Task 4／5 補上「公共汽車→公車」縮短區段測試）；**I-1**（補上「妥瑞氏症」ADR 0032 靈魂驗證案例）；**I-2**（補上代理對字元位於片語前的 offset 邊界測試）；**I-3**（`parsePhraseTable()` 補上「同一鍵不得重複、值不得為空字串」防護與測試，Task 2；**2026-09-15 `reviews/rereview-plan-issue-0b.md` 複審發現此修訂本身有邏輯短路缺陷並已再次修正**：原寫法先對整行 `rawLine.trim()` 才找 tab 位置，但 `'內存\t'.trim()` 會把結尾的 `\t`〔trim() 認定的空白字元〕一併削掉，導致值為空的行被誤判成「找不到 tab」而提前 `continue`，永遠到不了空值拋例外檢查，`testParsePhraseTableThrowsOnEmptyValue` 會因收不到預期例外而測試失敗——已改為只用未 trim 的 `rawLine` 找 tab 位置，trim 動作限定在切出來的 key／candidates 各自身上，並逐一重新核對過全部既有 `parseCharTable()`／`parsePhraseTable()` 測試案例的手算結果，確認無回歸）；**M-1**（`displayToOrig` 補上 `snapPolicy` 執行期斷言，Task 4）；**M-3**（Task 3 Step 4 補上 JS 檔案的實際內容核對，不只檢查變數名稱存在）。**M-2**（PowerShell 相容指令）予以保留現狀不修改——本計畫全文的 shell 指令假設在 Git Bash／POSIX sh 環境下執行，是本專案既有計畫（`plan-issue-0.md`）已確立並經審查接受的慣例，非本計畫遺漏。

**Spec 覆蓋度**：對照 `issues.md` Issue 0b 的「範圍」逐項核對——(1) 補齊字典來源檔案 → Task 1；(2) 改寫 `generate_conversion_dicts.js` 依方案 A 輸出非對稱字典組合 → Task 2／3（範圍依上方「範圍決策記錄」縮小為 `STCharacters+TWPhrases`／`TSCharacters+TSPhrases`，已於 Task 1 Step 3 的 README 更新中明文記錄，不是靜默偏離）；(3) 新增 `TextOffsetMap` 演算法類別（Dart／JS 各一份，含縮短片語邊界防護）→ Task 4／5；(4) `convertText()`／JS 端轉換函式擴充為片語優先、單字元其次，`toTraditional`／`toSimplified` 各自對應真實 OpenCC 管線的正確階段劃分 → Task 6／7。四項單元測試要求（字典生成腳本驗證、片語最長匹配優先、`TextOffsetMap` 演算法逐一覆蓋、邊界案例）與 `issues.md` 明訂的正規化約束（鍵不重複、值不為空）皆已對應到具體 Task 步驟。無遺漏。

**佔位符掃描**：全文檢查過，沒有 TBD／「之後補上」／「類似 Task N」等字樣；所有程式碼步驟皆為可直接執行的完整程式碼，沒有省略號代表的未寫邏輯。

**型別一致性**：`TextOffsetMap`／`OffsetEntry`／`OffsetMapBuilder`（Task 4 定義）→ `convertTextDetailed()` 回傳型別（Task 6，`({String text, TextOffsetMap? offsetMap})`）→ 測試斷言（Task 6 Step 1）全程使用同一組型別/欄位名稱。JS 對應版本（Task 5／7）的 `{ entries: [...] }` 物件形狀、`origOffset`／`origLen`／`dispOffset`／`dispLen`／`delta`／`accumDelta` 欄位名稱與 Dart 版一一對應，無命名漂移。`convertText()` 簽章（`String convertText(String input, TextConversionMode mode)`）與 Issue 0 完全相同，未被本 Issue 更動。

**已知效能取捨（非本計畫範圍的最佳化留待未來）**：Task 6／7 的最長匹配演算法採「由長至短嘗試每個長度」（O(`kMaxPhraseKeyLength`) 次查找/串接每個位置），而非真正的 Trie（前綴樹，通常能在不匹配時提早中止，只需 1-2 次查找）。Issue 2 的呼叫粒度是「目前渲染中 section 的可見文字節點」（見 `spec.md`），不是整本書一次轉換，實務上輸入規模有界，暫不需要提前最佳化（YAGNI）；若未來真機效能量測顯示這裡是瓶頸，可在不變動 `convertText()`／`convertTextDetailed()`／`applyTextConversionToString()` 對外簽章的前提下，把內部比對邏輯換成真正的 Trie。
