# Epic 16 — 橫向雙頁顯示：設計 (Design)

> 本文件由 `/grill-with-docs` 2026-07-11 逐項確認產生，結合 `/domain-modeling` 詞彙表維護。

## 問題陳述

FR-41 要求 EPUB 固定版面（漫畫類）與 PDF 在裝置橫向時，支援同時並排顯示兩頁（左右頁中間不留空白），並可與單頁模式切換。此功能橫跨 EPUB（Readium）與 PDF（PdfRenderer）兩條渲染管線，決議從 epic-4-pdf-enhance 獨立成專屬 Epic。

## 範圍界定

### 包含範圍

- **EPUB 固定版面（FXL）**：所有 FXL EPUB，不做內容啟發式判斷（決策 #1）。
- **PDF**：所有 PDF，不做內容啟發式判斷（決策 #1）。

### 明確排除

- **流式 EPUB（Reflowable）**：FR-41 字面未提及；流式 EPUB 的「多欄」與「雙頁」是不同概念，若有需求應另立 Epic（決策 #11）。
- **epic-14-system-settings 的全域預設層**：雙頁相關設定皆為單書持久化，不併入 epic-14。

> **頁碼索引慣例**：本文件與 `spec.md` 全文一律採用 **0-indexed**（程式碼慣例）。決策 #5 表格中的「第 1 頁」「(2,3)(4,5)」為口語化的 1-indexed 敘述範例，換算為 0-indexed 後等同「第 0 頁獨立、之後 (1,2)(3,4)…」，與 `spec.md` 的頁碼描述一致（見審查意見 M-1）。

## 決策紀錄（Discovery 逐項確認）

| # | 決策點 | 採用結果 |
|---|---|---|
| 1 | 適用格式的精確邊界 | 所有 PDF 與所有 EPUB FXL 一律可啟用雙頁模式，不做內容啟發式判斷，使用者手動選擇 |
| 2 | 觸發機制 | 混合模式：`DualPageMode` 三態 enum（`auto`／`always`／`never`），單書持久化，null = `auto`（橫向自動啟用雙頁、直向回到單頁） |
| 3 | EPUB FXL 實作路線 | 優先啟用 Readium 內建 `spread` 偏好支援（`EpubPreferences.spread`——經反編譯 `readium-navigator` 確認其型別為 `Spread` **enum**〔`AUTO`/`NEVER`/`ALWAYS`〕，非 Boolean，與 `dualPageMode` 三態一一對應），驗證後若不符需求再退回自行實作。「驗證」的具體判準與收斂關卡見 `spec.md`「待驗證風險與收斂關卡」一節 |
| 4 | PDF 雙頁原生端實作策略 | 拼接 Bitmap——`renderCurrentPage()` 演化為 `renderCurrentSpread()`，雙頁模式下渲染兩頁 Bitmap 拼接成一張，塞進現有 `imageView`，下游管線（`applyFitMode`/`applyFilters`/`CropOverlayView`）不變 |
| 5 | 頁面配對語意（1-indexed 口語範例，見上方「頁碼索引慣例」） | 可切換「封面獨立」開關（`dualPageCoverAlone: bool?`，預設 `true`）：開啟時第 1 頁獨立、之後 (2,3)(4,5)…；關閉時 (1,2)(3,4)…。EPUB FXL 的配對交由 Readium spread metadata（`page-spread-left/right`）處理 |
| 6a | 裁切與雙頁的交互 | 裁切矩形（0.0-1.0 相對座標）語意不變——各頁獨立套用裁切後再拼接，不重新定義為「相對於雙頁畫面」 |
| 6b | 濾鏡與雙頁的交互 | 拼接後統一套用——先各頁渲染（含裁切），拼接成大 Bitmap，再統一做 `applyBoldEffect()` 與 `colorFilter` |
| 6c | Fit 模式與雙頁的交互 | 三種 Fit 模式語意不變，`applyFitMode()` 對拼接後的 Bitmap 自然正確運作 |
| 7 | 設定 UI 入口位置 | 放進既有設定入口——PDF 放 `PdfSettingsSheet`「顯示」分頁；EPUB FXL 新建精簡版 `FxlSettingsSheet`（雙頁模式 + 未來 FR-42 全螢幕開關）。由於 EPUB FXL（漫畫）會隱藏 Scaffold AppBar，設定入口齒輪按鈕將以右上角半透明圓形懸浮按鈕（與左上角返回按鈕對稱）呈現 |
| 8a | 翻頁步進（0-indexed，見上方慣例） | 步進 2——一次翻一個完整 spread，`[1,2] → [3,4]`；封面獨立時往返封面的對稱步進規則（避免負索引）見 `spec.md` 審查修正 C-4 |
| 8b | 頁碼回報 | `onPageChanged` 回報 spread 錨點 `currentPageIndex`（`ltr` 下為左頁、`rtl` 下為右頁——原「左頁（較小的）」措辭在 RTL 下自相矛盾，已於 `spec.md` 審查修正 I-7 訂正），Dart 端依 `dualPageDirection` 自行推算配對頁 |
| 8c | 邊界處理 | 最後一頁如果落單（奇數總頁數），右側留白（白色背景） |
| 9 | 雙頁閱讀方向（LTR/RTL） | PDF 新增獨立設定 `dualPageDirection: DualPageDirection?`（`ltr`／`rtl`），預設 `ltr`，僅 PDF 有效；EPUB FXL 由 Readium 依 `page-progression-direction` metadata 自動處理 |
| 10 | 手動裁切互動與雙頁的交互 | 進入裁切編輯模式時自動切回單頁渲染（與 `renderFullPageForCropPreview()` 同一概念），`CropOverlayView` 不需改動，裁切確認後回到雙頁 |
| 11 | 流式 EPUB 排除確認 | 明確排除——流式 EPUB 的「多欄」與「雙頁」是不同概念 |

## 使用者流程（概要）

### PDF

1. 使用者開啟一本 PDF，將裝置轉為橫向（或螢幕方向已鎖定為橫向）。
2. 若 `dualPageMode` 為 `auto`（預設），畫面自動從單頁切換為雙頁並排——封面獨立顯示（預設），之後每翻一頁換一個完整 spread。
3. 若使用者想調整，點擊齒輪「版面設定」→「顯示」分頁：
   - **雙頁模式**：自動（預設）／永遠雙頁／永遠單頁
   - **封面獨立**：開關（預設開啟）
   - **頁面方向**：左→右（預設）／右→左（日漫用）
4. 所有設定單書持久化，下次開同一本書沿用。

### EPUB 固定版面（漫畫）

1. 使用者開啟一本漫畫 EPUB（FXL），將裝置轉為橫向。
2. 若 `dualPageMode` 為 `auto`，Readium 的 `spread` 偏好被啟用，自動並排顯示兩頁。
3. 點擊右上角半透明圓形懸浮設定按鈕（對稱於左上角返回鍵），開啟 `FxlSettingsSheet` 調整雙頁模式。
4. 閱讀方向由 EPUB metadata 的 `page-progression-direction` 自動決定，不需使用者手動設定。

## 新增的 BookReaderPrefs 欄位

| 欄位 | 型別 | 預設值（null 語意） | 適用格式 |
|------|------|-------------------|---------|
| `dualPageMode` | `DualPageMode?` | `auto`（橫向自動雙頁） | PDF + EPUB FXL |
| `dualPageCoverAlone` | `bool?` | `true`（封面獨立） | PDF（EPUB FXL 由 Readium metadata 處理） |
| `dualPageDirection` | `DualPageDirection?` | `ltr` | 僅 PDF |

## 新增的 Enum 定義

```
DualPageMode: auto | always | never
DualPageDirection: ltr | rtl
```

## 架構影響摘要

| 模組 | 異動類型 | 說明 |
|------|---------|------|
| `BookReaderPrefs` | 擴充 | 新增 3 個 nullable 欄位 + `copyWith` / `toMap` / `fromMap` |
| `BookReaderPrefsRepository` | 擴充 | SQLite schema migration 新增 3 欄 |
| `ReaderScreen` | 擴充 | 新增方向偵測（`MediaQuery.orientation` 或 `OrientationBuilder`）並透過 `isLandscape` 參數下傳（見 `spec.md`「方向偵測契約」）；3 個雙頁欄位新增 `_resolved…` null-合併 getter（見 `spec.md` I-3）；EPUB FXL 時於畫面右上角顯示半透明懸浮齒輪按鈕（對稱於左上角返回鍵），點擊開啟 `FxlSettingsSheet` |
| `PdfReaderView.dart` | 擴充 | 新增 `dualPageMode`/`dualPageCoverAlone`/`dualPageDirection`/`isLandscape` 建構參數，`didUpdateWidget` 偵測變動送出 `setPdfPreferences` |
| `PdfReaderView.kt` | 核心改動 | `renderCurrentPage()` → `renderCurrentSpread()`（含 5 處呼叫點同步改名，見 `spec.md` M-2）；雙頁模式下拼接兩頁 Bitmap＋拼接階段 OOM 回退單頁；`nextPage`/`previousPage` 前進步進 2、後退對稱處理封面邊界（避免負索引，見 `spec.md` C-4）；`enterCropEditMode()` 暫時切回單頁 |
| `EpubReaderView.dart` | 擴充 | 新增 `dualPageMode`、`isLandscape` 建構參數 |
| `EpubReaderView.kt` | 擴充 | `buildPreferencesFromMap()` 新增 `dualPageMode` → Readium `Spread` **enum**（`AUTO`/`ALWAYS`/`NEVER`，非 Boolean，見 `spec.md` C-1）映射邏輯 |
| `PdfSettingsSheet` | 擴充 | 「顯示」分頁新增雙頁模式/封面獨立/頁面方向三個控制項 |
| `FxlSettingsSheet`（新建） | 新建 | 精簡版設定面板：雙頁模式（+ 未來 FR-42 全螢幕開關） |

## 已知風險 / 待 Architecting 階段確認的技術細節

> 本節所列風險已於 `/superpowers:requesting-code-review`（2026-07-11，`tmp/epic-16/reviews/review-design-spec.md`）審查中被指出：`spec.md` 初版曾把部分風險改寫為「已解決」的完成式描述，卻未真正提出演算法或收斂判準。以下風險項目均已在 `spec.md` 補上具體演算法／收斂關卡／限制聲明，本節維持風險原貌（供追溯 Discovery 階段的判斷），實作前請以 `spec.md` 對應章節為準：

- **Readium spread 行為驗證**（決策 #3）：需要在真機上驗證 Readium 的 `spread` 偏好啟用後，頁間是否有間距（FR-41 要求「不留空白」）、`Spread.AUTO` 是否等同「橫向才雙頁」、縮放是否與既有 `applyFxlFitScale()` 衝突、`page-spread-left/right` metadata 的配對是否正確。若驗證失敗需退回自行實作。**收斂關卡**：見 `spec.md`「待驗證風險與收斂關卡」——本風險須在進入 Scrum Master 拆解前以 spike 驗證並回填結論，不得留待實作階段才發現。
- **拼接 Bitmap 記憶體壓力**（決策 #4）：雙頁拼接後 Bitmap 像素量理論上接近翻倍，但橫向螢幕每頁高度縮小可部分抵銷。需要在記憶體受限的 E-Ink 裝置上實測，確認既有的 `OutOfMemoryError` catch + 回退機制是否足夠。**收斂位置**：`spec.md` `renderCurrentSpread()` 演算法已明訂拼接階段 OOM 時回退為單頁渲染的具體步驟（原「已知限制」僅口頭宣稱、未落實於演算法的問題已修正）。
- **方向偵測新增**（決策 #2）：目前 App 完全沒有偵測當前螢幕方向的程式碼，`auto` 模式需要新增 `MediaQuery.of(context).orientation` 或 `OrientationBuilder`，並確保方向變化時的 rebuild 不會造成原生 PlatformView 重建（效能風險）。**收斂位置**：`spec.md`「方向偵測契約」一節已定案 Method Channel 傳遞方式與 PlatformView 不重建的要求（原設計曾在「模組」與「介面」兩節互相矛盾，已修正）。
- **`applyFxlFitScale()` 雙頁適配**：epic-3 Issue 10 建立的「全書統一縮放比例」快取機制，在雙頁模式下需要重新計算（兩頁並排的可用空間與單頁不同）；現行 per-WebView 置中邏輯（各自置中於整個 container）在雙頁下會讓兩頁互相重疊，必須改為以半寬為基準各自置中。**收斂位置**：`spec.md` `EpubReaderView.kt` 模組段落已補上具體演算法與快取失效時機。
- **自動裁切偵測時序**：當啟用 `autoDetect` 且尚無快取矩形時，若開啟雙頁模式，系統依然優先對 `currentPageIndex`（第 0 頁封面）進行單頁白邊偵測與快取，計算完成後才套用於左右頁拼接。**重要澄清**：`PdfReaderView.kt` 現行 `cropRect` 是**全書共用單一矩形**，並非逐頁偵測——雙頁模式下左右頁套用的是同一個矩形，左右頁天然白邊不同時可能裁切不理想；本 epic 不做 per-page 偵測（YAGNI），已於 `spec.md`「已知限制」明列。

## 範圍外 (Out of Scope)

- 流式 EPUB（Reflowable）的多欄顯示——與「雙頁」是不同概念（決策 #11）。
- `epic-14-system-settings` 的全域預設層——雙頁設定皆為單書持久化。
- 翻頁動畫——目前 PDF 翻頁無動畫，本 epic 不新增。
- 內容啟發式判斷（自動偵測是否為漫畫）——使用者手動控制（決策 #1）。
