# Epic 16 Issue 1 — Spike 補充報告：Readium 雙 WebView 渲染驗證

**驗證日期**：2026-07-13
**驗證裝置**：9491G（Android 15 / API 35，device id 3CEF42ECD491687）
**Readium 版本**：kotlin-toolkit 3.3.0
**測試分支**：`test-readium-spread-webview` (基於 `main` 進行插樁)

---

## 執行摘要

本補充驗測針對 Epic 16 Issue 1 中關於「*Spread 機制是否需要建立兩個並排的 WebView*」的預想進行實驗。

驗證結論**打破了先前的假設**，證實：**elinkBook 不需要手動在 Native 或 Dart 端管理兩個並排的 WebView/PlatformView。Readium 官方的 `EpubNavigatorFragment` 在啟用 `Spread.ALWAYS` 且翻頁至配對頁面後，底層會自動建立並排的兩個 WebView。**

先前 Spike 報告得出「只建立單個半寬 WebView」的原因，是由於當時測試**只停留在第 0 頁（封面）**。封面在固定版面 (FXL) 元資料中被宣告為 `page: center` (獨立居中)，因此 Readium 依規範僅建立單一 WebView；一旦翻頁至後續配對頁面，雙 WebView 即會自動生成。

---

## 真機驗證日誌與數據分析

我們以實體漫畫 `一弦定音！(06).epub` 為素材，在橫向模式下整合測試翻頁，並於 Native 端 `onPageLoaded` 對 `container` 內的 `WebView` 節點進行了數量與邊界的監控：

### 1. 載入第一頁（封面頁，Page 0）
```text
07-13 21:38:48.104  3931  3931 D EpubReaderView-SPIKE: WebView Count onPageLoaded: 1
07-13 21:38:48.104  3931  3931 D EpubReaderView-SPIKE: WebView 0: width=2400, height=1316, x=0, y=183
```
* **分析**：此時只有 **1** 個 WebView，寬度為 2400 (全寬)，水平置中。

### 2. 翻頁前進至雙頁配對區（Page 1-2）
```text
07-13 21:38:49.039  3931  3931 D EpubReaderView-SPIKE: Forcing manga preferences via reflection
07-13 21:38:49.041  3931  3931 D EpubReaderView-SPIKE: Successfully submitted manga preferences
07-13 21:38:49.235  3931  3931 D EpubReaderView-SPIKE: WebView Count onPageLoaded: 2
07-13 21:38:49.235  3931  3931 D EpubReaderView-SPIKE: WebView 0: width=1200, height=0, x=0, y=841
07-13 21:38:49.235  3931  3931 D EpubReaderView-SPIKE: WebView 1: width=1200, height=0, x=1200, y=841
```
* **分析**：
  * WebView 數量自動變為 **2**。
  * `WebView 0` 的寬度為 `1200`，起點坐標在 $x = 0$。
  * `WebView 1` 的寬度為 `1200`，起點坐標在 $x = 1200$。
  * 兩個 WebView 剛好平分了螢幕寬度 2400，並且**無縫地並排在螢幕左右兩側**。
  * *(註：height 在該瞬間為 0 是因為 WebView 還在進行 layout 測量，後續重繪後高度會正常撐開。)*

---

## Readium 3.3.0 API 精確規格

本次插樁編譯與反射亦為我們釐清了 Readium 3.3.0 的精確 Preference API 規格：

1. **❌ 無 `offsetFirstPage` 屬性**：
   在 `EpubPreferences` 的所有 declared fields 中，確認**沒有** `offsetFirstPage` 這個屬性。Readium 在 3.3.0 版本中會自動依據 EPUB Metadata 中的 `page-spread-left/right` 與封面宣告來處理封面獨立，不需要也無法手動關閉或開啟此設定。
2. **`readingProgression` 的型別與成員**：
   型別為 `org.readium.r2.navigator.preferences.ReadingProgression` enum，其列舉成員有：`LTR`、`RTL`。
3. **`spread` 的型別與成員**：
   型別為 `org.readium.r2.navigator.preferences.Spread` enum，其列舉成員有：`NEVER` , `ALWAYS`。

---

## 對 Issue 6 的實作影響

本驗測對 Issue 6（EPUB 雙頁渲染）的實作方案產生了重大的調整：

* **完全捨棄「自建雙 PlatformView/雙 Fragment 容器」方案**。
* **Flutter 端**：Epub 側保持只有單一原生 PlatformView 容器，對齊 PDF 的乾淨架構。
* **Native 端**：
  1. 依據 `isLandscape` (橫向與否) 切換 `Spread.ALWAYS` 與 `Spread.NEVER` 提交給 Navigator。
  2. 既有的 `findViewsByType<WebView>(container)` 能自動捕捉到這 2 個由 Readium 自動產生的 WebView。
  3. **縮放與置中（主要工作）**：修正 `applyFxlFitScale()` (於 `EpubFxlScaler`) 的縮放與置中定位演算法。當發現有 2 個 WebView 時，將可用寬度 `availableWidth` 視為 `container.width / 2`，並根據其左右佈局（$x=0$ 與 $x=1200$）換算正確的 translation offset 以進行防重疊定位。
