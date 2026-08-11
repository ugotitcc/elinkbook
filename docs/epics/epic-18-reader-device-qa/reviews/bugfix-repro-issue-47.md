# Bugfix Repro：Issue 47 — 流式 EPUB 劃線拖曳選取時頁面亂跳

## 症狀

使用者回報：劃線拖曳選取時頁面亂跳（截圖 `tmp/images/畫線亂跳.jpg`），原判定為 PDF 專屬（`epic-24-pdf-engine-rebuild` Issue 9），追加確認流式 EPUB 也會發生同一症狀（與 PDF 版本根因不同）。

## 重現方式

`tmp/epic-18-issue-47-harness/repro.mjs`（Puppeteer + headless Chromium，未進版控），透過 request interception 直接伺服 `app/android/app/src/main/assets/foliate/` 真實 vendored 資源與既有測試 fixture `issue9_vertical_pagejump.epub`，在書本內文的 iframe 文件上透過 CDP `Input.dispatchTouchEvent` 注入真實觸控事件，測試 `paginator.js` 已註冊的 `'touchmove'` 監聽器邏輯本身，量測「選取尚未建立」與「選取已確立」兩種情境下同樣小幅位移是否分別造成內容位移。

## 量測數據（連續 3 次重跑結果一致）

- 情境 A（橫排、無選取）：`containerPositionBefore=100`、`containerPositionAfter=50`、`scrollByCalls=3`（全部 `moved: true`）
- 情境 B（橫排、已有選取，對照組）：`scrollByCalls=0`（selection guard 完全阻擋）
- 情境 C（直排、無選取）：真機驗證確認——長按開始後、選取反白出現前，頁面內容即位移（`reproducedVertical=true`）
- 情境 D（直排、已有選取）：未獨立量測（真機觀察：選取確立後守衛應同樣有效，待後續確認）
- 判讀：`reproduced=true`、`guardWorksWhenSelected=true`、`reproducedVertical=true`（真機驗證）

### 詳細量測數據

#### 情境 A：橫排、無選取（長按候選期間）

```
containerPosition: 100 → 77 → 65 → 50（3 次 scrollBy，全部實際移動）
scrollBy calls:
  dx=-23: position 100→77 (moved=true)
  dx=-12: position 77→65 (moved=true)
  dx=-15: position 65→50 (moved=true)
selection: rangeCount=0 (全程無選取)
transform: matrix(1, 0, 0, 1, 28.9, 0)（snap() 動畫殘留）
```

#### 情境 B：橫排、已有選取（對照組）

```
containerPosition: 100 → 0（由 snap() 在 touchEnd 重置，非 scrollBy）
scrollBy calls: 0（完全阻擋）
selection: rangeCount=1, collapsed=false（選取成功建立）
```

## 根因確認

`paginator.js` 第 2191-2194 行的選取守衛：

```javascript
const doc = this.#primaryView?.document
const selection = doc?.getSelection()
if (selection && selection.rangeCount > 0 && !selection.isCollapsed) {
    return
}
```

此守衛僅在 `selection.rangeCount > 0 && !selection.isCollapsed` 時阻擋。在「長按已開始、但瀏覽器原生選取尚未建立」的空窗期，`selection` 為空或塌縮（`isCollapsed === true`），守衛不成立，`#onTouchMove` 直接放行到位移邏輯（第 2229-2237 行）。

### 觸控事件注入方式

原始計畫使用 synthetic `TouchEvent` dispatch（`new TouchEvent()` + `el.dispatchEvent()`），但此方式無法觸發 paginator 的 touch handler（原因：synthetic TouchEvent 在 headless Chromium 中不走瀏覽器的 input pipeline，handler 收不到事件）。

改用 CDP `Input.dispatchTouchEvent` 後，觸控事件走瀏覽器原生 input pipeline，正確觸發 paginator 註冊的 `touchstart`/`touchmove`/`touchend` handler。

## 結論

**完整重現（橫排＋直排）**。橫排模式下，「選取尚未建立」的空窗期會位移內容（`reproduced=true`），「選取已確立」後守衛正常擋下（`guardWorksWhenSelected=true`）。直排模式經真機驗證同樣確認：長按開始後、選取反白出現前，頁面內容即位移（`reproducedVertical=true`）。

### 直排模式真機驗證

直排情境 C/D 未能在 headless Chromium 中完成量測（`#scrollBounds` 為 null），改以真機測試。結果：長按一個字詞開始選取，在選取反白出現前，頁面內容即發生位移——與橫排模式同一症狀。修復範圍應同時涵蓋橫排與直排模式。

## 下一步

1. **建立 Issue 修復工單**：在 `issues.md` 將 Issue 47 狀態改為 `ready-for-agent`，附量測證據摘要
2. **修復方案**：在 `#onTouchMove` 的 selection guard 中，增加「長按空窗期」的額外守衛——例如追蹤 `#touchState.blocked` 或新增 `#longPressPending` flag，在 `#onTouchStart` 設定、selection 確立後清除
3. **回歸測試**：修復後需確認正常選取拖曳（Scenario B）不受影響
