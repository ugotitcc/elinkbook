# elinkBook 語音朗讀 (TTS) 與同步高亮 (Read-along) 架構技術研究報告——PDF 篇

> **專案定位**：elinkBook — 專注於「直排繁體中文排版」與「E-Ink 電子墨水螢幕最佳化」的 Flutter Android 電子書閱讀器。
> **與 Foliate 篇報告的關係**：本報告是 `docs/research/tts_integration_architecture_research.md`（以下稱「Foliate 篇」，涵蓋 EPUB／KF8／TXT／MD）的獨立姊妹報告。**Provider 抽象層、雲端/端側引擎比較、音訊快取模型、`audio_service` 背景播放、Dart 領域模型（`TtsProvider`/`TtsSynthesisResult`/`TtsWordTiming`）這幾塊與格式無關，完全共用 Foliate 篇第 2、4.1(1)(2)(4)、5.1 節，本報告不重複列出**，只聚焦 PDF 專屬的差異：**文字擷取、定位座標系、高亮渲染、閱讀順序風險、與現有 `pdfrx`/`PdfReaderView` 基礎設施的整合方式**。

---

## 1. 執行摘要 (Executive Summary)

PDF 沒有 DOM／CFI，`ReaderScreen` 對 PDF 走完全獨立的渲染路徑（`PdfReaderView`，底層 `pdfrx`／PDFium FFI，非 WebView），因此 Foliate 篇報告的整套「CFI ↔ Overlayer」架構**不能直接套用**，需要另一套以「頁碼 + 頁內文字座標」為核心的定位與高亮機制。四個核心差異點：

1. **定位座標系不同**：PDF 用「頁碼 + 頁內 bounding box」而非 CFI。本專案已用的 `pdfrx.loadStructuredText()` 回傳的 `PdfPageText`（`fullText`＋逐字元 `charRects`）已提供這個能力的全部基礎材料，不需要額外抽取邏輯。
2. **現有 `Highlight`／`PercentRect` 持久化模型不適合直接重用**：`app/lib/reader/highlight.dart` 的 `pdfPageIndex`＋`pdfRect`（`PercentRect`）是**單一矩形**，對應的是使用者「長按拖曳框選一塊矩形區域」這個既有互動（`PdfSelectionInfo`，見 `pdf_selection_info.dart`），不是「精確跟隨一句可能跨行的文字」。TTS 朗讀高亮需要逐行多矩形（比照 Foliate 篇 `Overlayer.#splitRange()` 避免整段誤框住行距空白的考量），且是**暫態 UI 疊加、不應寫入 `highlights` 資料表**——這是一個容易被誤用既有模型、實際上不適用的陷阱，需要特別提醒。
3. **PDF 文字擷取順序不保證等於視覺閱讀順序**：多欄排版、表格、浮動文字方塊在 PDF content stream 中的實際順序可能與人眼閱讀順序不同，`loadStructuredText()` 的 `fullText` 直接照抽取順序朗讀可能會錯亂，這是 PDF TTS 業界公認的難題，需要在範圍與使用者期待上明確設限。
4. **可高度重用既有 `pageOverlaysBuilder`／`PdfThumbnailCache` 基礎設施**：`pdf_reader_view.dart` 已有 `pageOverlaysBuilder: _buildProcessedOverlay`（逐頁疊加手勢層/裁切覆蓋圖）與 `PdfThumbnailCache<T>`（純 Dart LRU 快取模式）兩個現成 pattern，TTS 高亮疊加層與「頁面結構化文字」快取都應該直接沿用同一套 pattern，而非另起爐灶。

---

## 2. 核心技術挑戰：頁碼 + 文字座標定位

### 2.1 既有 `pdfrx` API 已提供所需能力，不需要新的文字抽取層

`PdfReaderView` 目前的內文搜尋功能（`pdf_reader_view.dart` 第 328-345 行）已經在用 `page.loadStructuredText()`，回傳的 `PdfPageText`（`package:pdfrx`）提供：

- `fullText`：整頁純文字（`String`）。
- `charRects`：逐字元的 `PdfRect` 列表，且提供 `boundingRect(start:, end:)` 直接取得一段文字範圍的合併包圍框。
- `PdfPageTextRange(pageText:, start:, end:)`／`getRangeFromAB()`：文字範圍的標準表示法（`pdfrx` 內部搜尋/選取功能已在用）。
- `PdfRect.toRectInDocument(page:, pageRect:)`：把 PDF 座標系的矩形換算成螢幕/Widget 座標系，`pdf_viewer.dart` 內部搜尋高亮／文字選取都是走這條路徑。

**TTS 的「句子 → 定位」對照表可以直接建立在這組既有 API 上**，不需要另外設計抽字元座標的邏輯：

```dart
/// 對目前頁呼叫一次，取得句子切分後的定位範圍（非每次高亮都重新呼叫
/// loadStructuredText——見 3.2 效能小節）。
Future<List<PdfTtsSegment>> extractSegmentsForPage(
  PdfPage page,
  int pageIndex,
) async {
  final text = await page.loadStructuredText();
  final sentences = splitIntoSentences(text.fullText); // 同 Foliate 篇建議用 Intl.Segmenter 概念，Dart 端可用等效的 CJK 句界規則
  return [
    for (final s in sentences)
      PdfTtsSegment(
        pageIndex: pageIndex,
        textStart: s.start,
        textEnd: s.end,
        text: text.fullText.substring(s.start, s.end),
      ),
  ];
}
```

### 2.2 高亮渲染：沿用 `pageOverlaysBuilder`，但不可套用 `Highlight`/`PercentRect` 持久化模型

`pdf_reader_view.dart` 第 924 行 `pageOverlaysBuilder: _buildProcessedOverlay` 已是「逐頁疊加額外 Widget」的既有 hook（目前用於裁切覆蓋圖與劃線/備註手勢層，見 CLAUDE.md「`pageOverlaysBuilder` 逐頁疊加手勢層使雙頁模式下座標歸屬單一頁面有構造性保證」）。TTS 目前朗讀句的高亮應該：

1. **不寫入 `highlights`/`notes` 資料表**：`Highlight.pdfRect` 是 `PercentRect`（單一矩形），語意是使用者手動框選的持久化標記；TTS 高亮是隨播放進度不斷變動的暫態狀態，混用會污染既有資料模型與 UI（例如使用者的「一鍵刪除所有劃線」會誤刪播放中的 TTS 高亮痕跡）。
2. **改用一組多矩形（逐行）**，取自 `text.charRects.boundingRect(start:, end:)` 或依換行位置拆成多段各自取 bounding rect（原理同 Foliate 篇 `Overlayer.#splitRange()`，避免一整段的包圍框把換行間距也框進去），透過 `PdfRect.toRectInDocument(page:, pageRect:)` 換算成螢幕座標，用 `CustomPaint`/`Positioned` 疊加在 `pageOverlaysBuilder` 回傳的 Widget 樹裡。
3. **雙頁模式**：`pageOverlaysBuilder` 逐頁呼叫的既有保證（見 CLAUDE.md）代表 TTS 高亮只要用同一個 hook，就自動獲得「雙頁模式下座標歸屬單一頁面」的正確性，不需要額外處理左右頁判斷。

```dart
Widget _buildTtsOverlay(PdfPage page, Rect pageRect) {
  final segment = _currentTtsSegment;
  if (segment == null || segment.pageIndex != page.pageNumber - 1) {
    return const SizedBox.shrink();
  }
  final rects = _rectsForSegment(segment) // 逐行 boundingRect，見上方說明
      .map((r) => r.toRectInDocument(page: page, pageRect: pageRect));
  return Stack(
    children: [
      for (final r in rects)
        Positioned.fromRect(
          rect: r,
          child: ColoredBox(color: _isEinkMode
              ? const Color(0xFFD0D0D0)
              : const Color(0x66FFEB3B)),
        ),
    ],
  );
}
```

### 2.3 閱讀順序風險：多欄/表格排版是已知限制，不是可以完全解決的問題

`loadStructuredText()` 的 `fullText` 順序來自 PDF content stream 的物件繪製順序，**不保證等於人類視覺閱讀順序**——雙欄排版、表格、頁首頁尾、註腳、浮水印文字方塊都可能被插進「錯誤」的順序中。這是 PDF TTS 領域公認的難題（沒有 DOM/CFI 那樣的語意結構可以依賴），業界方案（含 Adobe Reader、多數開源閱讀器）多半只承諾「單欄、線性排版」的 PDF 有良好朗讀順序，複雜排版則體驗打折。

**建議**：比照 CLAUDE.md 現有「Page Label 尚未支援」的先例，把此列為**明確記錄的已知限制**，而非在 MVP 階段投入大量工程去解多欄/表格重排序（那是獨立的版面分析問題，成本遠高於朗讀本身）。頁首/頁尾/頁碼等雜訊文字建議用簡單啟發式（例如同一頁重複出現在固定 y 座標區間、或內容比對相鄰頁高度相似的短字串）過濾，但同樣不追求 100% 準確。

### 2.4 分段單位：比照既有格式無關 `BookTocItem`，用 TOC 分組而非「章節」

PDF 沒有 EPUB 式的「章節檔案」，但 `PdfReaderView` 已有格式無關的 `BookTocItem` 抽象介面與 `PdfTocItem` 實作（大綱/書籤解析）。TTS 音訊快取的分組粒度建議：

- 沿用 Foliate 篇的 Cache Key 設計 `SHA256(text + voiceId + speed + pitch)`，「章節」維度改用 `pageIndex`（或有 TOC 時用 TOC 節點對應的頁碼區間），而非 CFI 基準。
- Prefetch 策略改為「目前頁 + 下 1～2 頁」，而非「章節」（PDF 分頁粒度本來就比 EPUB 章節細，逐頁 prefetch 更自然）。

### 2.5 效能：100MB+ PDF <2 秒開啟的 NFR 不可被 TTS 拖垮

`docs/prd.md` 對 PDF 有「100MB 以上檔案開啟速度小於 2 秒」的硬性指標。**TTS 文字擷取必須是 lazy、逐頁進行**，絕不可在開書當下就對整份文件跑一輪 `loadStructuredText()`。建議比照現有 `PdfThumbnailCache<T>`（純 Dart LRU 快取＋`page.render()`，見 CLAUDE.md）的既有 pattern，做一個「頁面結構化文字 LRU 快取」（`PdfPageTextCache`），只在使用者實際播放到該頁（或 prefetch 範圍內）時才呼叫 `loadStructuredText()`，並快取結果避免重複 FFI 呼叫。

### 2.6 跨頁與翻頁聯動

PDF 以整頁為顯示粒度，比 EPUB 連續捲動簡單：TTS segment 若不在目前顯示頁（單頁或雙頁其中一頁），呼叫既有的 `PdfReaderView.jumpToPage` 靜態 helper（見 CLAUDE.md「`PdfReaderView` 對外建構參數」）即可，不需要像 Foliate 篇 3.4 節那樣設計「安全視窗」內捲動判斷——頁面切換本身就是天然的安全視窗。E-Ink 模式下沿用既有的「停用平滑滾動」原則，翻頁時機採「目前朗讀句所在頁與顯示頁不同時才翻頁」，避免逐句都觸發整頁刷新造成閃爍。

---

## 3. 領域模型補充（PDF 專屬）

```dart
/// PDF 專屬的 TTS 分段定位——與 Foliate 篇的 TtsSegmentCfi 對應，
/// 但座標系是頁碼＋文字範圍，不是 CFI 字串。
class PdfTtsSegment {
  final int pageIndex; // 0-indexed，對齊 Book.pdfPageIndex 既有慣例
  final int textStart; // 相對該頁 PdfPageText.fullText 的字元偏移
  final int textEnd;
  final String text;

  const PdfTtsSegment({
    required this.pageIndex,
    required this.textStart,
    required this.textEnd,
    required this.text,
  });
}
```

其餘（`TtsProvider`、`TtsSynthesisResult`、`TtsWordTiming`、`TtsCacheManager`）與 Foliate 篇報告 5.1 節完全共用，此處不重複定義。

---

## 4. 分階段建議：排在 Foliate 篇之後、作為獨立 Phase

建議**不要**與 Foliate 篇的 Phase 1 並行開發：先在 EPUB／KF8／TXT／MD 上驗證 `TtsProvider`/`TtsCacheManager`/`TtsAudioPlayer`/`audio_service` 這條主幹（Foliate 篇 Phase 1-2），確認 Provider 抽象與播放/快取機制穩定後，PDF 只需要「替換定位/高亮層」（本報告第 2 節），大部分 UI 層（Mini Player、鎖定畫面控制、Provider 選擇）可以直接重用，不需要重新設計。PDF 專屬工作量集中在：

1. `PdfPageTextCache`（頁面結構化文字 LRU 快取，見 2.5 節）。
2. `PdfTtsSegment` 切分與逐頁擷取（2.1、2.4 節）。
3. `pageOverlaysBuilder` TTS 高亮疊加層（2.2 節，暫態、不寫入 `highlights` 表）。
4. 多欄/表格已知限制的使用者溝通（例如朗讀前偵測到疑似多欄版面時提示「此 PDF 排版較複雜，朗讀順序可能不完全正確」，而非試圖完美解決）。

---

## 5. 關鍵結論

1. **PDF TTS 是「換底層定位機制、重用上層播放/快取/UI」的工程，不是另立山頭**：Provider 抽象、音訊快取、`audio_service` 背景播放與 UI 控制項與 Foliate 篇完全共用；差異只在「文字從哪裡來、位置怎麼標」這一層。
2. **既有 `pdfrx.loadStructuredText()`／`charRects`／`toRectInDocument()` 已足夠支撐定位與高亮，不需要新的文字抽取引擎**。
3. **既有 `Highlight`/`PercentRect` 持久化模型不適用於 TTS 高亮**——這是本報告最重要的風險提醒：直接重用會把「使用者手動框選的持久化標記」與「播放中暫態高亮」兩個不同語意的東西混在一起，應該分開設計。
4. **PDF 文字閱讀順序是已知的業界難題，應明確設限（比照「Page Label 尚未支援」的既有先例），而非承諾對所有排版都完美**。
