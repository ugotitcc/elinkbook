# `pdfrx` 與 `saber-notes/saber` 影像濾鏡/裁切架構調查報告

> 調查目的：`epic-24-pdf-engine-rebuild` Issue 3（E-Ink 影像濾鏡/裁切功能對等）規劃階段，需確認 `pdfrx` 的 `PdfViewer` widget 是否有公開機制可以攔截/替換它自己渲染的頁面點陣圖，並參考同樣使用 `pdfrx` 的既有開源專案 `saber-notes/saber` 的實際做法，作為 `docs/epics/epic-24-pdf-engine-rebuild/plans/plan-issue-3.md` 架構決策的依據。本文件記錄調查過程與結論，供該計畫回頭核對，也供日後 Issue 4/7/8 需要類似「自訂 PDF 頁面渲染」時參考。

**調查方式**：直接讀取本機 `pub cache`（`pdfrx-2.4.7`／`pdfrx_engine-0.4.5` 套件原始碼）與透過 GitHub API／raw content 讀取 `saber-notes/saber`（`main` 分支）實際原始碼，皆為第一手程式碼查證，非轉述文件或臆測。

---

## 一、`pdfrx` 套件：`PdfViewer` 沒有「替換頁面點陣圖」的公開掛鉤

查證版本：`pdfrx` 2.4.7（`app/pubspec.yaml` 目前鎖定版本）。

### 1.1 `PdfViewerParams` 提供的自訂化掛鉤

檢視 `lib/src/widgets/pdf_viewer_params.dart` 建構子參數清單，與頁面渲染/顯示相關的掛鉤只有：

| 掛鉤 | 型別/時機 | 能做什麼 |
|---|---|---|
| `layoutPages` | `PdfPageLayoutFunction`，`(List<PdfPage>, PdfViewerParams) → PdfPageLayout` | 自訂每頁在文件座標系中的**版面尺寸與位置**（`epic-24` Issue 2 雙頁並列已使用） |
| `calculateCurrentPageNumber` | 覆寫目前頁碼推算邏輯（Issue 2 已使用） | 不影響渲染內容 |
| `pageBackgroundPaintCallbacks` | 在頁面內容畫**之前**於 Canvas 上畫東西 | 只能畫背景裝飾（陰影等），無法阻止/修改之後的頁面渲染 |
| `pagePaintCallbacks` | 在頁面內容畫**之後**於 Canvas 上畫東西 | 只能疊加內容，官方範例（見下方）只拿來畫搜尋結果高亮/書籤色塊 |
| `pageOverlaysBuilder` | `(BuildContext, Rect pageRectInViewer, PdfPage) → List<Widget>` | 回傳的 widget 會被 `pdfrx` 自動包一層 `Positioned(left/top/width/height = pageRectInViewer)` 疊在該頁上方 |

### 1.2 實測：`pagePaintCallbacks` 在頁面點陣圖畫完「之後」才觸發

直接讀 `lib/src/widgets/pdf_viewer.dart` 的頁面繪製流程（約 1540-1601 行）：

```dart
// 先畫背景裝飾
if (widget.params.pageBackgroundPaintCallbacks != null) { ... }
// 畫低解析度預覽或白底
canvas.drawImageRect(...) / canvas.drawRect(...)
// *** 這裡才是真正的頁面點陣圖 ***
if ((!enableLowResolutionPagePreview || pageScale > previewScaleLimit) && partial != null) {
  partial.draw(canvas, filterQuality);   // ← pdfrx 自己渲染的頁面內容，畫在這裡
}
// 文字選取高亮、連結高亮
...
// pagePaintCallbacks 在這裡才被呼叫——已經在頁面內容畫完之後
if (widget.params.pagePaintCallbacks != null) {
  for (final callback in widget.params.pagePaintCallbacks!) {
    callback(canvas, rect, page);
  }
}
```

**結論**：`pagePaintCallbacks`／`pageBackgroundPaintCallbacks` 都只能在 `pdfrx` 自己畫的頁面點陣圖之前或之後「疊加」內容，**無法攔截、修改、或跳過**這次內部渲染。`PdfViewerParams` 全部建構子參數逐一核對後，沒有任何一個是「提供自訂點陣圖來源取代內部渲染」這種語意（`getPageRenderingScale` 只調整渲染解析度，不改變內容）。

### 1.3 可行替代方案：`pageOverlaysBuilder` + 自行 `PdfPage.render()`

`pdfrx` 官方 API 本身有提供「自行渲染單一頁面點陣圖」的公開方法，且套件內建的縮圖/單頁檢視 widget 就是這樣實作的——不是我們自己發明的偏門用法：

```dart
// lib/src/widgets/pdf_widgets.dart 的 _PdfPageViewState._updateImage()（節錄）
final pageImage = await page.render(
  fullWidth: pageSize.width,
  fullHeight: pageSize.height,
  ...
);
final newImage = await pageImage.createImage(); // → ui.Image
// 顯示：RawImage(image: newImage, ...)
```

`PdfImage`（`pdfrx_engine-0.4.5/lib/src/pdf_image.dart`）進一步確認：

```dart
abstract class PdfImage {
  int get width;
  int get height;
  Uint8List get pixels;      // BGRA8888 原始像素，可讀可寫
  void dispose();
  static PdfImage createFromBgraData(Uint8List bgraPixels, {required int width, required int height});
}
```

`pixels` 是可直接存取的 `Uint8List`（BGRA8888），且有 `createFromBgraData()` 靜態工廠可以把處理過的位元組包回 `PdfImage`，再呼叫 `.createImage()`（`pdfrx_flutter.dart` 的 `PdfImageExt` extension）轉成 `ui.Image` 顯示。

**因此 `epic-24` Issue 3 採用的架構**：`page.render()` 取得原始像素 → 背景處理（裁切/加粗）→ `createFromBgraData()` → `.createImage()` → 透過 `pageOverlaysBuilder` 疊一張不透明 `RawImage` 蓋住該頁——`pdfrx` 底層仍會渲染原始頁面但被完全遮住（視覺正確、運算有浪費但可接受）。這條路徑用的每一個 API 都是 `pdfrx` 自己的縮圖/單頁 widget 在用的同一套，不是繞過套件限制的 hack。

### 1.4 官方範例中沒有找到的東西

另外查了 `pdfrx` GitHub repo（`packages/pdfrx/example/viewer`，不含在 pub.dev 套件本體、只在原始碼庫）的 `main.dart` 與 `thumbnails_view.dart`：`pagePaintCallbacks` 官方範例只拿來畫搜尋結果高亮與使用者自訂色塊標記，**沒有**任何 `ColorFilter`、灰階、對比度、或裁切相關程式碼——這印證了設計文件（`spec.md`）當初「研究報告承認這是缺口、未給具體方案」的判斷是正確的，`pdfrx` 官方範例確實沒有現成配方可以直接抄。

---

## 二、`saber-notes/saber`：真實的同套件（`pdfrx`）生產案例

`saber-notes/saber` 是一款開源手寫筆記/PDF 標註 App，`pubspec.yaml` 確認其 PDF 渲染同樣使用 **`pdfrx: ^2.4.2`**（與本專案鎖定的 2.4.7 是同一大版本系列，API 相容）。這是一個真實跑在生產環境、同樣基於 `pdfrx` 的參考案例，價值在於「別人怎麼把 `pdfrx` 的原始頁面點陣圖接進自己的濾鏡/合成邏輯」，而不是抽象的官方文件。

### 2.1 對比度/亮度等價功能：深色模式圖片反相（`invert_widget.dart`）

`lib/components/canvas/invert_widget.dart` 是一個 `StatelessWidget`，深色模式下用來讓筆記/PDF/圖片反相顯示（README 原文：「it can invert your notes when you're in dark mode... Images and PDFs are also inverted」）。實作方式：

```dart
// 節錄自 lib/components/canvas/invert_widget.dart
ColorFiltered(
  colorFilter: ColorFilter.matrix(<double>[
    1 - 2 * lumaR,     -2 * lumaG,     -2 * lumaB, 0, 255,
        -2 * lumaR, 1 - 2 * lumaG,     -2 * lumaB, 0, 255,
        -2 * lumaR,     -2 * lumaG, 1 - 2 * lumaB, 0, 255,
                 0,              0,              0, 1,   0,
  ]),
  child: child,
)
// lumaR = 0.2126, lumaG = 0.7152, lumaB = 0.0722（Rec.709 亮度係數）
```

**這與 `epic-24` Issue 3 計畫（`plan-issue-3.md`）採用的做法完全一致**：整個 `ColorFiltered` 包住子樹（含底下所有 PDF 頁面渲染與任何疊加圖層）、矩陣格式與 Flutter `ColorFilter.matrix` 4x5 row-major 慣例相同。差異只在矩陣公式本身——saber 做的是「保留亮度、反轉色度」的反相效果（用於深色模式），我們做的是「對比度/亮度調整」（`contrastBrightnessColorMatrix()`，沿用已歸檔原生 `PdfImageProcessor.contrastBrightnessColorMatrix()` 公式）——**兩者是同一種技術手段（`ColorFiltered`／`ColorFilter.matrix`），套用在不同的矩陣公式上**。

**這是本次調查對 Issue 3 架構決策最直接的佐證**：一個真實生產中的 `pdfrx` 應用，用同一種 widget 包裝技巧對「圖片與 PDF」做即時色彩處理，沒有用 Isolate、沒有防手震延遲（因為 `ColorFiltered` 是每幀即時 GPU 合成，沒有背景運算可言）——與本專案计畫中「對比度/亮度改用 `ColorFiltered` 即時渲染、不需要 Isolate/debounce」的偏離決策方向一致。

### 2.2 單頁 PDF 渲染：`pdf_editor_image.dart`

`lib/components/canvas/image/pdf_editor_image.dart`（PDF 頁面轉換成筆記畫布內可標註的「圖片物件」）：

```dart
PdfPageView(
  document: pdfDocument,
  pageNumber: pdfPage + 1,
  decoration: const BoxDecoration(),
)
```

直接使用 `pdfrx` 內建的 `PdfPageView` widget（與第一節分析的同一個類別），**印證第一節的判斷**：`PdfPageView`／`page.render()` 這條路徑確實是 `pdfrx` 生態圈裡「單獨渲染一頁成靜態圖片」的標準做法，不是我們自己發明的偏門用法。

`dispose()` 明確釋放 `_pdfDocument`，`PdfDocumentCache`（`pdf_document_cache.dart`）用路徑當 key 快取已載入的 `PdfDocument` 避免重複解析——這與本專案既有的資源釋放紀律（`PdfReaderView.dispose()`／頁碼縮圖快取需 `dispose()` 等，`spec.md` 已明文要求）一致，沒有新發現需要調整既有計畫。

### 2.3 saber 沒有做的部分（誠實記錄，避免誤導）

- **裁切**：`pdf_editor_image.dart` 中 `srcRect` 欄位存在但恆為 `.zero`，代表 saber **沒有**實作任何 PDF 裁切功能。`epic-24` Issue 3 的裁切（智慧自動/手動選區）是本專案自行從 `pdfrx` 原始 API（`page.render()` 回傳的 BGRA 像素可直接切片）推導出的做法，**沒有** saber 或 `pdfrx` 官方範例可以直接參照，這部分風險評估維持計畫原文「留待真機驗證」的態度，不因本次調查而降低。
- **加粗（型態學膨脹）／任何逐像素背景運算**：`PdfDocumentCache` 與整個 `pdf_editor_image.dart` 皆未使用 `Isolate`／`compute()`，saber 完全沒有這類逐像素運算需求（他們只做全域反相，`ColorFiltered` 就能一次搞定）。因此 Issue 3 計畫中「加粗透過 `Isolate.run()` 背景執行＋防手震延遲」這部分**沒有** saber 的實作可以參照驗證，是本專案基於 `pdfrx` 公開 API（`PdfImage.pixels`／`createFromBgraData`）獨立設計、並移植已歸檔原生 `PdfImageProcessor.dilatePixels()` 演算法而成，架構上站得住腳（API 存在、資料格式相容），但**效能表現未經任何現成案例驗證**，`plan-issue-3.md` 文末「效能未知數」段落的保留態度應繼續維持。

---

## 三、結論與對 `plan-issue-3.md` 的影響

1. **`pdfrx` 的 `PdfViewer` 確實沒有替換頁面點陣圖的公開掛鉤**——這是第一手原始碼查證的事實，不是猜測，`plan-issue-3.md` 選擇「`pageOverlaysBuilder` 疊不透明覆蓋圖」這個折衷做法是目前唯一可行路徑，並非工程偷懶。
2. **`ColorFiltered`／`ColorFilter.matrix` 即時渲染對比度/亮度的架構決策，獲得真實生產案例（saber-notes/saber，同版本系列 `pdfrx`）的直接佐證**——不是本專案自創的未驗證想法，是同生態圈已有專案在用的成熟技術，且用法（整個子樹包一層 `ColorFiltered`）與 `plan-issue-3.md` 目前寫法一致。
3. **加粗與裁切在 saber 找不到對應實作**——這兩項功能在 `pdfrx` 生態圈內目前仍是本專案獨有的需求，`plan-issue-3.md` 已有的「效能未知數，留待真機驗證」保留態度應維持，不宜因為對比度/亮度部分獲得驗證就連帶放鬆對加粗/裁切效能風險的戒心。

**本次調查沒有發現任何需要回頭修改 `plan-issue-3.md` 既有架構決策的理由**——純粹是為既有決策補上外部佐證，供日後複查追溯。
