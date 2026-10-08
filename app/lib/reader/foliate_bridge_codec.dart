import 'dart:convert';

import 'epub_decoration.dart';
import 'epub_position_info.dart';
import 'toc_entry.dart';
import 'tts_segment_cfi.dart';
import 'writing_mode.dart';

/// 從 `locatorJson` 取出章節/spine index
int? extractChapterIndex(String? locatorJson) {
  if (locatorJson == null) return null;
  try {
    final obj = jsonDecode(locatorJson);
    if (obj is Map && obj['index'] is num) {
      return (obj['index'] as num).toInt();
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 解析 JSON 為 TtsSegmentCfi 清單
List<TtsSegmentCfi> parseTtsSegments(String segmentsJson) {
  try {
    final array = jsonDecode(segmentsJson) as List<dynamic>;
    return array
        .map((e) => TtsSegmentCfi.fromWire(e as Map<Object?, Object?>))
        .toList();
  } catch (_) {
    return const [];
  }
}

/// 解析/擷取 epic-17-epub-render-migration Issue 6 新增的定位 JSON 格式
/// （`{"cfi":"epubcfi(...)","index":N,"fraction":F}`），取代原本
/// `FoliateLocatorCodec.kt`（純函式，不觸碰 `InAppWebView`，見
/// epic-18-reader-device-qa plans/plan-issue-10.md ADR 0013 後續遷移）。
/// 同時支援直接傳入 raw CFI 字串（如 `epubcfi(...)`，epic-10-search Issue 5
/// 搜尋跳轉傳入之格式）。
/// [locatorJson] 為 `null`、非 CFI 之 JSON 格式錯誤、或既有流式書籍留下的舊格式
/// Readium Locator JSON（無 `cfi` 鍵）皆回傳 `null`，供呼叫端優雅退回。
String? extractCfi(String? locatorJson) {
  if (locatorJson == null) return null;
  final trimmed = locatorJson.trim();
  if (trimmed.startsWith('epubcfi(') && trimmed.endsWith(')')) {
    return trimmed;
  }
  try {
    final obj = jsonDecode(trimmed);
    if (obj is Map && obj['cfi'] is String) return obj['cfi'] as String;
    return null;
  } catch (_) {
    return null;
  }
}

/// 把 `main.js` `window.getTableOfContents()` 回傳的 JSON 陣列字串解析為
/// [TocEntry] 清單（取代原本 Kotlin 端 `FoliateLocatorCodec.parseTocEntries`
/// + `tocEntryFromJsonObject`）。`jsonDecode` 產生的 `Map<String, dynamic>`
/// 依 Dart 泛型協變規則可直接滿足 [TocEntry.fromWire] 要求的
/// `Map<Object?, Object?>` 型別（`String <: Object?`、`dynamic <: Object?`），
/// 不需要額外轉型。[tocJson] 格式錯誤時回傳空清單，不拋出例外——目錄讀取
/// 失敗不應該讓已成功開啟的書籍畫面顯示錯誤，比照原 Kotlin 實作的既有
/// 錯誤處理原則。
List<TocEntry> parseTableOfContents(String tocJson) {
  try {
    final array = jsonDecode(tocJson) as List<dynamic>;
    return array
        .map((e) => TocEntry.fromWire(e as Map<Object?, Object?>))
        .toList();
  } catch (_) {
    return const [];
  }
}

/// 把 `main.js` `onLocatorChanged` relocate handler 送出的 JS→Dart 橋接
/// 參數（epic-26-architecture-hardening Issue 10，取代原本 4 個 positional
/// 參數混用 pageIndex/location 語意的舊格式）解析為 [EpubPositionInfo]。
/// [args] 恰好 2 個元素：`args[0]` 為 [EpubPositionInfo.locatorJson]（含
/// cfi 的字串，原樣不動，見 [extractCfi]）；`args[1]` 為具名 JSON 物件
/// 字串，包含 `fraction`／`locationIndex`／`locationTotal`／
/// `visualPageIndex`／`visualTotalPages` 五個鍵，依書籍是否為固定版面
/// （FXL／CBZ）互斥填值。[args] 元素不足、`args[1]` 缺席或格式錯誤時，
/// 位置相關欄位一律回傳 `null`，不拋出例外（比照 [extractCfi] 既有的優雅
/// 退回原則）。
EpubPositionInfo parseLocatorChanged(List<dynamic> args) {
  final locatorJson =
      args.isNotEmpty && args[0] is String ? args[0] as String : '';
  Map<String, dynamic> position = const {};
  if (args.length > 1 && args[1] is String) {
    try {
      final decoded = jsonDecode(args[1] as String);
      if (decoded is Map<String, dynamic>) position = decoded;
    } catch (_) {
      // 格式錯誤時維持空 map，位置相關欄位一律回傳 null。
    }
  }
  return EpubPositionInfo(
    locatorJson: locatorJson,
    progression: (position['fraction'] as num?)?.toDouble() ?? 0.0,
    locationIndex: (position['locationIndex'] as num?)?.toInt(),
    locationTotal: (position['locationTotal'] as num?)?.toInt(),
    visualPageIndex: (position['visualPageIndex'] as num?)?.toInt(),
    visualTotalPages: (position['visualTotalPages'] as num?)?.toInt(),
    // epic-54 Issue 20：foliate 以 live DOM 判定的目前目錄項 id（可為 null）。
    tocItemId: (position['tocItemId'] as num?)?.toInt(),
  );
}

/// 把 `main.js` `onPageRendered` handler 送出的 JS→Dart 橋接參數解析為
/// [EpubLayoutInfo]（epic-54 Issue 18，取代原本寫死
/// `EpubLayoutInfo(isFixedLayout: false, …)` 的匿名 closure 內聯邏輯）。
/// [args] 第 0 個元素為排版方向字串（`'vertical'` 即直排，其餘視為橫排）；
/// 第 1 個元素（epic-54 Issue 18 起 `main.js` 主動回報）為 `view.isFixedLayout`
/// 布林值。舊版參數（無第 1 個元素，或其值非布林）時退回 [isFixedLayoutHint]
/// （開書當下已知的值），仍無則為 `false`。任何形狀錯誤皆不拋出例外。
EpubLayoutInfo parseFoliateLayoutResolved(
  List<dynamic> args, {
  bool? isFixedLayoutHint,
}) {
  final writingModeStr =
      args.isNotEmpty && args[0] is String ? args[0] as String : 'horizontal';
  final reported =
      args.length > 1 && args[1] is bool ? args[1] as bool : null;
  return EpubLayoutInfo(
    isFixedLayout: reported ?? isFixedLayoutHint ?? false,
    writingMode: writingModeStr == 'vertical'
        ? WritingMode.vertical
        : WritingMode.horizontal,
  );
}

/// 把 Dart `Color.toARGB32()`／Android `Color` int 皆採用的 0xAARRGGBB
/// 版面轉換為 SVG fill/stroke 屬性可直接使用的 `rgba()` CSS 字串（取代原本
/// `FoliateDecorationCodec.argbIntToCssColor`）。
String argbToCssColor(int argb) {
  final a = (argb >> 24) & 0xFF;
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 'rgba($r, $g, $b, ${a / 255.0})';
}

/// 把 Dart 端的完整標記清單轉換為 `main.js window.setDecorations()` 所需的
/// `{"id","cfi","color","isUnderline"}` 清單（取代原本
/// `FoliateDecorationCodec.buildDecorationEntries`）。單筆 [EpubDecoration]
/// 的 `locatorJson` 解析失敗（[extractCfi] 回傳 `null`——缺席、格式錯誤、
/// 或既有流式書籍留下的舊格式 Readium Locator JSON）時該筆略過，不影響
/// 其餘標記，比照原 Kotlin 實作的既有非致命錯誤略過原則。與原 Kotlin 版本
/// 不同：本函式直接操作 [EpubDecoration] 物件，不再需要先序列化為 wire
/// map 再解析回來（呼叫端與本函式同在 Dart 執行環境內）。
List<Map<String, Object?>> buildDecorationEntries(
  List<EpubDecoration> decorations,
) {
  final entries = <Map<String, Object?>>[];
  for (final decoration in decorations) {
    final cfi = extractCfi(decoration.locatorJson);
    if (cfi == null) continue;
    entries.add({
      'id': decoration.id,
      'cfi': cfi,
      'color': argbToCssColor(decoration.tint),
      'isUnderline': decoration.isUnderline,
    });
  }
  return entries;
}

/// 判斷「已正規化」的請求路徑是否真的落在允許根目錄之內（含根目錄本身）
/// （取代原本 `FoliatePathValidator.isPathWithinRoot`，純字串邊界比對，
/// 不做任何檔案系統 I/O）。刻意不用單純的
/// `requestedCanonicalPath.startsWith(allowedRootCanonicalPath)`——會誤判
/// 「同前綴但其實是不同目錄」的情況（例如 allowedRoot=".../files"，
/// requestedPath=".../files_evil/x" 純 startsWith 會誤判為合法）。必須
/// 額外要求邊界字元本身也對得上：完全相等，或後面緊接著路徑分隔符。
///
/// 審查修正：兩個參數先正規化為一律以 `/` 為分隔符再比對，而非直接假設
/// 呼叫端一定是 `/`。開發機（Windows）執行 `flutter test` 時，
/// `File.resolveSymbolicLinksSync()`（Task 3 `loadBookBytes` 呼叫）回傳的
/// 是反斜線路徑，若這裡的邊界字元寫死 `/`，Task 3 Step 12「允許目錄內的
/// 真實檔案」測試會在 Windows 開發機上直接判定為「不在允許範圍內」而失敗
/// ——本專案目標平台（Android）恆為 `/`，正規化為 `/` 不影響正式環境行為，
/// 只讓本函式在任何開發機平台上都能被正確測試。
bool isPathWithinRoot(
  String requestedCanonicalPath,
  String allowedRootCanonicalPath,
) {
  final normalizedRequested = requestedCanonicalPath.replaceAll('\\', '/');
  final normalizedRoot = allowedRootCanonicalPath.replaceAll('\\', '/');
  if (normalizedRequested == normalizedRoot) return true;
  return normalizedRequested.startsWith('$normalizedRoot/');
}
