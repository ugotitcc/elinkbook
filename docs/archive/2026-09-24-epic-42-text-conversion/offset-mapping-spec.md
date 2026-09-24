# Epic 42 — 簡繁轉換：雙向字元偏移映射規格 (Offset Mapping Specification)

本規格定義在 `epic-42-text-conversion` 中引入「台灣常用詞轉換（`s2twp` / `tw2sp`）」時，解決 DOM Range、EPUB CFI、TTS 朗讀高亮及搜尋 Snippet 座標漂移（Offset Drift）的標準演算法與實作規則。

---

## 1. 問題成因與數據分析

### 1.1 座標漂移的本質
在 EPUB 閱讀器（`foliate-js`）中，EPUB CFI、選取範圍（Selection Range）、劃線（Highlight）與書籤（Bookmark）底層均嚴格依賴 live DOM 樹中 `TextNode` 的字元偏移量（`offset`）。
- **JavaScript `String.length` 與 DOM Range offset**：均以 **UTF-16 Code Units** 為單位計量。
- **Dart `String.length`**：同樣以 **UTF-16 Code Units** 為單位計量。

當採用 `s2twp`（簡體轉台灣繁體含常用詞）或 `tw2sp`（台灣繁體轉簡體含大陸用語）時，會發生**非等長字元置換（$\Delta L \neq 0$）**。

### 1.2 OpenCC 全量掃描統計（opencc-js v1.4.2）

根據對 OpenCC 完整詞庫的精確分析：

| 轉換管線 | 總詞條數 | 🔴 UTF-16 長度改變 (漂移) | 🟡 CP 改變但 UTF-16 不變 | 🟢 長度完全不變 |
| :--- | :--- | :--- | :--- | :--- |
| **`s2twp` (全量管線)** | 54,506 | **1,304 (2.392%)** | 0 (0.000%) | 53,202 (97.608%) |
| └─ **`TWPhrases` (台灣常用詞庫)** | 817 | **237 (29.01%)** | 0 (0.000%) | 580 (70.99%) |
| **`tw2s` (標準台繁轉簡，無詞彙)** | 5,135 | **220 (4.284%)** | 0 (0.000%) | 4,915 (95.716%) |
| **`tw2sp` (含台灣詞彙轉大陸用語)** | 5,937 | **443 (7.462%)** | 0 (0.000%) | 5,494 (92.538%) |

#### 漂移的兩大成因拆解：
1. **台灣常用詞語意替換（Phrase Length Diff）**：
   - 核心詞庫 817 條中有 **237 條（29.01%）** 長度不相等。
   - 字數增加（+）：如 `内存` (2) → `記憶體` (3) [+1]、`编程` (2) → `程式設計` (4) [+2]、`主板` (2) → `主機板` (3) [+1]、`SQL注入` (5) → `SQL隱碼攻擊` (7) [+2]、`算法` (2) → `演算法` (3) [+1]。
   - 字數減少（-）：如 `方便面` (3) → `泡麵` (2) [-1]、`公共汽车` (4) → `公車` (2) [-2]、`可执行文件` (5) → `執行檔` (3) [-2]。
2. **Unicode 代理對替換（Surrogate Pairs / Astral Plane）**：
   - 簡體中生僻字（位於 SIP 擴展區，UTF-16 佔 2 code units）被繁體標準字（位於 BMP，佔 1 code unit）替換，產生 855 筆 `2→1` 或 `1→2`。在 Code Point 上相同，但在 UTF-16 上同樣會引發實質的 DOM Offset 漂移！

---

## 2. 雙向分段偏移映射演算法 (Piecewise Offset Mapping)

為保證 CFI 座標恆對應「未轉換之原始 EPUB 文字」，且 live DOM 渲染「含台灣常用詞之在地化文字」，在節點轉換層引入 **`TextOffsetMap`**。

### 2.1 資料結構

每個發生長度變化的 `TextNode` 綁定一個 `OffsetDelta` 稀疏陣列：

```typescript
interface OffsetEntry {
  origOffset: number;   // 原文字元起始 offset (UTF-16)
  origLen: number;      // 原文被置換詞長度 (UTF-16)
  dispOffset: number;   // 畫面顯示字元起始 offset (UTF-16)
  dispLen: number;      // 轉換後詞長度 (UTF-16)
  delta: number;        // dispLen - origLen (長度增減量)
  accumDelta: number;   // 此區段之前的累計 delta
}
```

> **記憶體最佳化**：對於 97.6% 長度不變的節點，`node._elinkOffsetMap` 保持 `null`，完全零記憶體與運算開銷。

### 2.2 雙向查詢演算法

#### 1. 原文座標轉顯示座標（`origToDisplay`）
用於 **CFI 還原劃線（`toRange`）**、**搜尋結果高亮**、**TTS 朗讀進度定位**：

```javascript
function origToDisplay(offsetMap, origOffset) {
  if (!offsetMap || offsetMap.entries.length === 0) return origOffset;
  
  // 二分搜尋尋找首個 origOffset >= entry.origOffset 的區段
  let low = 0, high = offsetMap.entries.length - 1;
  let matchedIndex = -1;
  
  while (low <= high) {
    const mid = (low + high) >> 1;
    const entry = offsetMap.entries[mid];
    if (entry.origOffset <= origOffset) {
      matchedIndex = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  
  if (matchedIndex === -1) return origOffset; // 在第一個置換詞之前
  
  const entry = offsetMap.entries[matchedIndex];
  // 檢查是否剛好落在置換詞中間
  if (origOffset < entry.origOffset + entry.origLen) {
    // 位於置換詞內部：依比例或貼齊到顯示詞起點
    const intraOffset = origOffset - entry.origOffset;
    return entry.dispOffset + intraOffset;
  }
  
  // 位於置換詞之後：加上該詞及其前所有詞的累計 delta
  return origOffset + entry.accumDelta + entry.delta;
}
```

#### 2. 顯示座標轉原文座標（`displayToOrig`）
用於 **使用者螢幕選取文字建立劃線（`fromRange`）時生成標準 CFI**：

```javascript
function displayToOrig(offsetMap, dispOffset, snapPolicy = 'floor') {
  if (!offsetMap || offsetMap.entries.length === 0) return dispOffset;
  
  let low = 0, high = offsetMap.entries.length - 1;
  let matchedIndex = -1;
  
  while (low <= high) {
    const mid = (low + high) >> 1;
    const entry = offsetMap.entries[mid];
    if (entry.dispOffset <= dispOffset) {
      matchedIndex = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  
  if (matchedIndex === -1) return dispOffset;
  
  const entry = offsetMap.entries[matchedIndex];
  // 檢查是否落在轉換後的顯示詞內部
  if (dispOffset < entry.dispOffset + entry.dispLen) {
    // 邊界對齊原則：
    // 若為選取起點 (startOffset)，floor 貼齊置換詞起點；
    // 若為選取終點 (endOffset)，ceil 貼齊置換詞終點。
    return snapPolicy === 'ceil' 
      ? entry.origOffset + entry.origLen 
      : entry.origOffset;
  }
  
  return dispOffset - (entry.accumDelta + entry.delta);
}
```

---

## 3. foliate-js (WebView DOM) 整合架構

### 3.1 轉換與 Offset Map 產製
在 `main.js` 的 `applyTextConversion(root, mode)` 走訪節點時：
1. 備份原始文字至 `node._elinkOrigText`（若未備份過）。
2. 使用 OpenCC `s2twp` Trie 樹進行斷詞替換時，同步收集置換區間 `[i, i + origLen]` 與 `[j, j + dispLen]`。
3. 若 `dispText.length !== origText.length`，建立 `TextOffsetMap` 並綁定於 `node._elinkOffsetMap`；否則設為 `null`。
4. 原地更新 `node.nodeValue = dispText`。

### 3.2 攔截 CFI 生成與還原

#### 1. 劃線建立 (`fromRange`)
在呼叫 `epubcfi.fromRange(range)` 之前，建立一個原文 Range 複本：
```javascript
function getOriginalRange(liveRange) {
  const origRange = liveRange.cloneRange();
  
  if (liveRange.startContainer.nodeType === Node.TEXT_NODE) {
    const map = liveRange.startContainer._elinkOffsetMap;
    if (map) {
      const origStart = displayToOrig(map, liveRange.startOffset, 'floor');
      origRange.setStart(liveRange.startContainer, origStart);
    }
  }
  
  if (liveRange.endContainer.nodeType === Node.TEXT_NODE) {
    const map = liveRange.endContainer._elinkOffsetMap;
    if (map) {
      const origEnd = displayToOrig(map, liveRange.endOffset, 'ceil');
      origRange.setEnd(liveRange.endContainer, origEnd);
    }
  }
  
  return origRange;
}
```
**保證**：產生的 CFI 永遠 100% 依據原始文本，儲存在 SQLite 的資料不會因模式切換而損壞。

#### 2. 劃線還原 (`toRange`)
在 `epubcfi.toRange(doc, cfi)` 返回 Range 後，調整其 offset 以適應 live DOM：
```javascript
function adjustRangeToDisplay(origRange) {
  if (!origRange) return null;
  
  if (origRange.startContainer.nodeType === Node.TEXT_NODE) {
    const map = origRange.startContainer._elinkOffsetMap;
    if (map) {
      const dispStart = origToDisplay(map, origRange.startOffset);
      origRange.setStart(origRange.startContainer, Math.min(dispStart, origRange.startContainer.nodeValue.length));
    }
  }
  
  if (origRange.endContainer.nodeType === Node.TEXT_NODE) {
    const map = origRange.endContainer._elinkOffsetMap;
    if (map) {
      const dispEnd = origToDisplay(map, origRange.endOffset);
      origRange.setEnd(origRange.endContainer, Math.min(dispEnd, origRange.endContainer.nodeValue.length));
    }
  }
  
  return origRange;
}
```
**保證**：還原劃線時不會發生 `IndexSizeError`，高亮矩形精確包裹在台灣常用詞上方。

---

## 4. Dart 端整合架構 (TTS 與全文檢索)

### 4.1 TTS 朗讀段落
1. `extractSegmentsForSection()` 產生的段落錨點 CFI 維持對應原文。
2. 餵入語音引擎的字串轉為台灣用語（如讀出「記憶體」而非「內存」）。
3. 如需單字級（Word-level）高亮，利用 Dart 端的 `TextOffsetMap` 將 TTS 回報的進度反向映射至原文 CFI。

### 4.2 全文檢索 (SearchRepository)
1. FTS5 索引庫恆為**原文**。
2. 查詢字串進行多變體擴充（`Multi-variant Query Expansion`）：
   - `variants = distinct([q, convertText(q, toTraditional), convertText(q, toSimplified)])`
   - 使用 SQLite FTS5 `MATCH '("var1" OR "var2")'` 查詢。
3. 搜尋結果片段（Snippet）在呈現給 UI 前轉換為台灣常用詞，高亮匹配位置經 `origToDisplay` 修正，確保劃線底色不偏斜。
