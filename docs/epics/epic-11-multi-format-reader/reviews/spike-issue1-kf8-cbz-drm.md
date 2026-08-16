# Epic 11 Issue 1 — Spike：KF8/CBZ 開書可行性與 DRM 偵測驗證報告

**驗證日期：** 2026-08-16
**驗證裝置：** `3CEF42ECD491687`，Hera_Vis_WIFI (9491G)，Android 15 / API 35，1600×2400
**釘定 commit：** `dd71f2be356563c16a23272686189fcfb45d0b82`
**KF8 測試素材：** Standard Ebooks《The Time Machine》(h-g-wells_the-time-machine.azw3)，DRM-free 公版授權，545452 bytes
**CBZ 測試素材：** Python 合成的 cbz_padded.cbz／cbz_unpadded.cbz（各 10 頁純色 PNG，400×600）

---

## KF8 開書/渲染/導覽（Task 2）

`makeBook()` 成功自動分派至 `mobi.js`（無需手動判斷格式）。

- `SPIKE_BOOK_METADATA`: `title: "The Time Machine"`, `hasTransformTarget: true`
- `SPIKE_OPENED`: `ok: true`, `isFixedLayout: false`（KF8 為 reflowable，非固定版面）
- `SPIKE_RELOCATE` 事件正確觸發，`fraction` 隨翻頁方向遞增/遞減

**6 次連續翻頁驗證**：3 次 `next` + 3 次 `prev`，`fraction` 從 0.0075 → 0.0343 → 0.0527 → 0.0712 → 0.0527 → 0.0343 → 0.0075，內容連續無跳過/重複。截圖確認第 3 次 next 後顯示 Chapter 1 對話內容，第 3 次 prev 回到版權頁。

**結論：通過** ✓

---

## KF8 × 直排覆蓋組合性（Task 3）

沿用 `epic-17` Issue 1 已驗證技術：透過 `book.transformTarget.addEventListener('data', ...)` 在 CSS 資源文字被解析前附加 `writing-mode: vertical-rl !important`。

- `SPIKE_OPENED`: `ok: true`, `isFixedLayout: false`
- 截圖確認文字已改為直排（欄由右至左排列、每欄文字由上至下），與 Task 2 橫排截圖形成明確對照
- 無 `SPIKE_ERROR`

**結論：通過** ✓ — KF8 內容能正確流入既有的直排管線

---

## CBZ 頁序驗證（Task 4 Step 3-4）

### 零填補版本（cbz_padded.cbz）

`SPIKE_CBZ_SECTIONS.ids`: `["001.png","002.png","003.png","004.png","005.png","006.png","007.png","008.png","009.png","010.png"]`

頁序正確。截圖驗證：第 1 頁紅色 (200,0,0) → 第 2 頁橘色 (200,80,0) → 第 3 頁金色 (200,160,0) → 第 4 頁黃綠色 (160,200,0)，符合 COLORS 陣列順序。

### 非零填補版本（cbz_unpadded.cbz）

`SPIKE_CBZ_SECTIONS.ids`: `["1.png","10.png","2.png","3.png","4.png","5.png","6.png","7.png","8.png","9.png"]`

**頁序錯誤**：`"10.png"` 被排到 `"2.png"` 前面（字典序排序：`"1" < "2"` in ASCII）。印證 `comic-book.js` 使用 `.sort()`（純字典序）而非自然排序的查證結論。

`SPIKE_CBZ_RENDITION.layout`: `"pre-paginated"` ✓

**結論：通過（附條件）** ✓ — CBZ 開書/渲染正確，但**需在匯入管線對 CBZ 內部圖片檔名做自然排序**後重建索引，不能依賴 `comic-book.js` 內建排序。

---

## CBZ RTL 覆蓋可行性（Task 4 Step 5）

- `SPIKE_CBZ_DIR_BEFORE.dir`: `undefined`（確認 `comic-book.js` 原始未設定 `dir`，佐證查證結論）
- `SPIKE_OPENED.rtl`: `true`（確認 `book.dir = 'rtl'` 覆寫生效）
- 點擊左側熱區後 `SPIKE_TRIGGER.direction: "prev"`（因 Harness 的 `btn-prev` handler 硬編碼呼叫 `view.prev()`，RTL 行為需由 `view.js` 內部的 `goLeft()` 處理，非本 Spike 範圍）

**結論：可行** ✓ — 呼叫端手動覆寫 `book.dir` 機制可正確傳遞至 `fixed-layout.js`，Architecting 階段可依 PRD FR-43「翻頁方向切換」需求設計 UI 覆寫機制。

---

## KF8 DRM 位元組偵測可行性（Task 5）

### Python 合成標頭驗證

```
unencrypted: encryption=0 (expect 0)
encrypted:   encryption=2 (expect 2)
legacy:      encryption=1 (expect 1)
PASS: 位元組解析邏輯正確區分 0/1/2 三種 encryption 旗標值
```

### Node.js 交叉驗證（DataView 預設大端序）

```
expected=0 actual=0 OK
expected=1 actual=1 OK
expected=2 actual=2 OK
PASS: JS 版本（DataView 預設大端序）與 Python 版本結論一致
```

兩版皆通過，確認 offset 邏輯（PDB header → 首筆 record offset → `+12` 兩位元組大端序）可直接移植到 Dart（`ByteData.getUint16(record0Offset + 12, Endian.big)`）。

**結論：可行** ✓

---

## 判準分類

| 驗證項目 | 結果 |
|---|---|
| KF8 開書/渲染/導覽 | 通過 ✓ |
| KF8 × 直排覆蓋組合性 | 通過 ✓ |
| CBZ 開書/渲染（`pre-paginated`） | 通過 ✓ |
| CBZ 零填補頁序 | 正確 ✓ |
| CBZ 非零填補頁序 | 錯誤（預期）— 字典序排序 |
| CBZ RTL 覆蓋可行性 | 可行 ✓ |
| DRM 位元組偵測可行性 | 可行 ✓ |

---

## GO / NO-GO 決策

**結論：GO**

所有核心判準通過。CBZ 非零填補頁序問題屬已知限制（`comic-book.js` 用 `.sort()`），非阻斷性失敗——可在 Architecting 階段於 Dart 端匯入管線處理自然排序。

下一步進入完整 Architecting 階段。

---

## Architecting 階段待落實事項

1. **CBZ 自然排序**：需在匯入管線（Dart 端）對 CBZ 內部圖片檔名做自然排序後重新命名/重建索引，不能依賴 `comic-book.js` 內建排序。
2. **CBZ RTL 覆寫**：需在 `main.js` 整合層依使用者偏好（PRD FR-43「翻頁方向切換」）於 `makeComicBook()` 之後、`view.open(book)` 之前設定 `book.dir`。
3. **KF8 DRM 偵測**：Dart 端偵測邏輯可直接採用 Task 5 驗證過的 offset（`ByteData.getUint16(record0Offset + 12, Endian.big)`），偵測到非 0 即拋出 `DrmProtectedException`。
