# Epic 2 — 排版切換與直排核心：規格 (Spec)

這是實作 `epic-2-vertical-core` 的唯一事實來源。問題/解法的完整敘述請見 `design.md`，`EpubReaderView` 契約擴充的完整理由請見 `docs/adr/0003-epub-reader-writing-mode-contract.md`。

## 模組 (Modules)

- **`WritingMode`／`EpubLayoutInfo`**（Dart，新增，`app/lib/reader/writing_mode.dart`）—— 橫直排狀態列舉與開書後一次性回報的版面資訊。
- **`EpubReaderView`**（Dart，異動既有 `app/lib/reader/epub_reader_view.dart`）—— 新增 `writingMode` 輸入參數與 `onLayoutResolved` 回呼，串接 ADR 0003 新增的 method channel 指令。
- **`EpubReaderView.kt`**（Android，異動既有）—— 依 ADR 0003 新增 `setWritingMode` 處理與 `onLayoutResolved` 回呼；持有目前 navigator 實例參照供切換時呼叫 `submitPreferences()`。
- **`ReaderScreen`**（Dart，異動既有 `app/lib/screens/reader_screen.dart`）—— 當格式為 EPUB 時，內部管理 `WritingMode?` 狀態並顯示橫排/直排切換按鈕（沿用 `prototype/index.html:1481-1482` 視覺）；`isFixedLayout` 為 `true` 時不顯示切換按鈕。**對外公開建構參數維持只有 `filePath` 不變**，橫直排切換純屬 `ReaderScreen` 內部狀態管理，不新增對外建構參數/callback（呼應 `CLAUDE.md` 既有的「`ReaderScreen` 唯一閱讀器 seam」約定）。

`PdfReaderView`、`detectBookFormat()` 不受影響。

## 介面 (Interfaces)

### `WritingMode`／`EpubLayoutInfo`

```dart
enum WritingMode { horizontal, vertical }

/// 開書完成後，原生端一次性回報的版面資訊。
class EpubLayoutInfo {
  final bool isFixedLayout; // true 時 ReaderScreen 不顯示橫直排切換按鈕
  final WritingMode writingMode; // Readium 依語言/閱讀方向自動判斷出的初始模式
  const EpubLayoutInfo({required this.isFixedLayout, required this.writingMode});
}
```

### `EpubReaderView`（新增輸入/輸出）

```dart
class EpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;

  /// null：開書當下不覆寫，交由 Readium 自動判斷（見 EpubLayoutInfo.writingMode）。
  /// 非 null 且與前次不同時：即時呼叫原生 setWritingMode 套用，不重新開書。
  final WritingMode? writingMode;

  /// 開書完成後觸發一次；用於讓呼叫端（ReaderScreen）決定是否顯示切換按鈕
  /// 及按鈕初始顯示狀態。
  final ValueChanged<EpubLayoutInfo>? onLayoutResolved;

  const EpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.writingMode,
    this.onLayoutResolved,
  });
}
```

- `didUpdateWidget` 中比較 `writingMode` 是否變動；變動且非 null 時透過既有 per-instance channel（`cc.ugotit.elinkbook/epub_reader_view_$id`）呼叫原生新增的 `setWritingMode`。
- `_handleMethodCall` 新增 `onLayoutResolved` case，解析後呼叫 `widget.onLayoutResolved?.call(...)`。

### 原生 method channel 契約異動（ADR 0003）

沿用既有 per-instance channel `cc.ugotit.elinkbook/epub_reader_view_$id`（不新增獨立 channel）：

- **Dart → 原生**：`setWritingMode`，參數 `{'mode': 'horizontal' | 'vertical'}`。原生端組出 `EpubPreferences(verticalText = mode == 'vertical')`，呼叫目前 navigator 的 `submitPreferences()`。
- **原生 → Dart**：`onLayoutResolved`，參數 `{'isFixedLayout': bool, 'writingMode': 'horizontal' | 'vertical'}`，在 `openBook` 完成、`onPageRendered` 觸發之後（同一次開書流程內）觸發一次。
  - `isFixedLayout`：讀取 Readium `Publication.metadata.presentation.layout`（fixed-layout 為 `true`）。
  - `writingMode`：讀取 `EpubSettingsResolver.resolveVerticalText(null, publication.metadata.language, publication.metadata.readingProgression)` 的解析結果。
- `openBook`/`onPageRendered`/`onError` 既有簽章與行為不變。

### `ReaderScreen` 內部行為異動

- 格式為 `epub` 時：內部持有 `WritingMode? _writingMode`（初始 `null`）與 `bool _isFixedLayout`（初始 `false`）。
- 收到 `onLayoutResolved` 後：`_isFixedLayout = info.isFixedLayout`；`_writingMode = info.writingMode`（僅用於初始化按鈕顯示狀態，不觸發 `setWritingMode` 呼叫，因為此值本來就是原生端已套用的自動判斷結果）。
- `_isFixedLayout == false` 時顯示切換按鈕；按下時翻轉 `_writingMode` 並 `setState`，觸發 `EpubReaderView` 以新的 `writingMode` 值重建。
- 對外公開建構參數 `ReaderScreen(filePath: String)` 不變。

## 測試決策 (Testing Decisions)

- **`WritingMode`／`EpubLayoutInfo`**：純 Dart unit test（建構、相等性）。
- **`EpubReaderView`**：widget test，透過假的 `MethodChannel` handler 驗證：
  - `writingMode` 由 `null` 變為非 `null`／由一個值變為另一個值時，會呼叫原生 `setWritingMode` 且參數正確。
  - 收到原生端 `onLayoutResolved` 呼叫時，`onLayoutResolved` callback 會以正確解析出的 `EpubLayoutInfo` 觸發。
- **`ReaderScreen`**：widget test 驗證，`_isFixedLayout` 為 `true`/`false` 時切換按鈕是否顯示；按下切換按鈕後 `EpubReaderView` 收到的 `writingMode` 是否正確翻轉。沿用假的 `EpubReaderView`／channel 驅動，不需真實裝置。
- **`integration_test/`（真實裝置）**：
  - 驗證真實 EPUB 開書後，`onLayoutResolved` 有觸發且畫面持續渲染成功（既有「等待 loading indicator 消失且無 error」斷言模式）。
  - 新增「開書後呼叫 `setWritingMode` 切換」的案例，驗證切換後畫面仍成功渲染（不進一步斷言直排視覺細節，視覺細節見下方獨立驗證項）。
  - **獨立驗證項（非自動化測試，人工視覺 QA）**：使用一本 XHTML 正確標記 `lang="zh"` 的直排 CJK 範例書，人工比對 Readium `cjk-vertical` ReadiumCSS 的標點轉向/避頭尾換行是否符合 CNS 11643；若發現落差，記錄具體差異字元，另立後續 issue 處理（不阻塞本 epic 其餘 issue 的實作與合併）。
  - 需要至少一本語言中繼資料完整（`lang="zh"` 或 `zh-TW`）的直排 CJK 範例 EPUB fixture；現有 `app/test/fixtures/sample.epub` 是否符合待第一個實作 issue 確認，不符合則需另尋或製作新 fixture。

## 已驗證的技術基礎（Architecting 階段靜態分析結果）

解壓 `readium-navigator-3.3.0.aar`（本機 Gradle cache）檢視內建 `assets/readium/readium-css/cjk-vertical/*.css` 後確認：

- **FR-05 圖片/標題不跨頁**：ReadiumCSS 對 `img/svg/audio/video` 與 `h1-h6/figure/dt/tr` 已內建 `break-inside: avoid` 等規則，**本 epic 不需要為此另外開發**。
- **FR-32 避頭尾**：ReadiumCSS 對 `:lang(zh)`（含 ja/ko）已內建 `line-break: strict`，會啟用瀏覽器引擎的嚴格換行邏輯。**風險**：(a) 僅在書本 XHTML 正確標記 `lang="zh"` 時生效；(b) Chromium 的 `line-break:strict` 實際字元表是否精確對齊 CNS 11643 無法透過靜態檢查確認，需實機視覺 QA（見上方測試決策）。

## 範圍外 (Out of Scope)

- TXT 格式的橫直排——延後至 `epic-11-txt-engine`。
- 定樣式（fixed-layout）EPUB 的橫直排切換——偵測到後隱藏切換按鈕，維持原始版面，不做任何額外處理。
- PDF——無 writing-mode 概念。
- 版面其餘控制項（行距、段落間距、邊距、字型、換頁模式、文字對齊等）——`epic-3-fonts-layout`。
- 九宮格導航熱區在直排模式下的左右鏡像映射邏輯——`epic-7-interaction`。
- **橫直排選擇的持久化與「採用書籍排版／強制直排／強制橫排」三態覆寫 UI（FR-10）**——`epic-3-fonts-layout`。Issue 2 的切換按鈕僅限當次 session 即時切換，不寫入任何持久化儲存；`EpubReaderView` 的 `writingMode`/`onLayoutResolved` 介面已足夠讓 `epic-3` 之後讀取持久化設定並直接呼叫套用。
- 若實機 QA 發現 Readium 內建樣式與 CNS 11643 有落差，具體覆寫方案的設計與實作——另立後續 issue，不阻塞本 epic 其餘 issue。
