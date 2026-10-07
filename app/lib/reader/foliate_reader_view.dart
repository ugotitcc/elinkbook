import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../l10n/app_localizations.dart';
import 'app_font.dart';
import 'column_mode.dart';
import 'custom_font.dart';
import 'dual_page_mode.dart';
import 'dual_page_direction.dart';
import 'epub_decoration.dart';
import 'epub_position_info.dart';
import 'epub_selection_info.dart';
import 'epub_text_align.dart';
import 'foliate_bridge_codec.dart';
import 'foliate_bridge_handlers.dart';
import 'foliate_native_bridge.dart';
import 'js_bridge_gateway.dart';
import 'page_turn_mode.dart';
import 'percent_rect.dart';
import 'reader_console_log.dart';
import 'tap_zone_detector.dart';
import 'toc_entry.dart';
import 'tts_segment_cfi.dart';
import 'writing_mode.dart';
import 'text_conversion_mode.dart';
import 'zone_action.dart';

/// `window.applyPreferences` 過早呼叫佇列 shim（epic-18-reader-device-qa
/// Issue 39，真機使用回報：ViWoods Air Reader C，`Uncaught TypeError:
/// window.applyPreferences is not a function`）。`didUpdateWidget()`
/// （見下方）只要 Dart 端偏好狀態變動（例如螢幕方向鎖定套用、既有書籍的
/// 非同步 FXL 判斷完成）就會呼叫 `window.applyPreferences(...)`，這個呼叫
/// 跟 `main.js`（ES module）是否已載入完成、真正定義出這個函式完全無關，
/// 時機上必然存在競速。在 `AT_DOCUMENT_START`（比 `main.js` 更早）注入這個
/// 佔位 shim，把 `window.applyPreferences` 暫時定義成「先把傳入值存起
/// 來」；`main.js` 真正的賦值執行時會直接覆蓋掉這個 shim，並緊接著檢查
/// 有沒有暫存值、有的話立刻補套用（見 main.js 對應修改）。不論 Dart 端
/// 呼叫發生在 main.js 載入完成前後都不會出錯、也不會遺漏。
const _applyPreferencesQueueShimJs = '''
window.__pendingApplyPreferences = null;
window.applyPreferences = function (prefs) {
  window.__pendingApplyPreferences = prefs;
};
''';

/// 於診斷日誌開頭記錄 `navigator.userAgent`（epic-18-reader-device-qa
/// Issue 33，程式碼審查建議）：定位「舊版 WebView 引擎不支援特定 API」
/// 這類相容性缺口時，User Agent 字串（含 Chromium 版本號）是最直接的
/// 起點線索。透過標準 `console.log` 輸出，直接沿用既有、已測試過的
/// `onConsoleMessage` → [handleFoliateConsoleMessage] → `ReaderConsoleLog`
/// 管線，不需要新增 bridge channel。
const _userAgentLogJs = '''
console.log('[UserAgent] ' + navigator.userAgent);
''';

/// `InAppWebView.onConsoleMessage` 的訊息處理邏輯（epic-18-reader-device-qa
/// Issue 33，真機使用回報）。抽成頂層純函式獨立測試——原因與
/// [resolveCustomFontUri] 相同：`FakePlatformInAppWebViewWidget`
/// （`test/support/fake_inappwebview_platform.dart`）底下無法真正觸發完整
/// 的 `onConsoleMessage` callback 型別鏈（需要一個真實 `InAppWebViewController`
/// 實例），這段訊息格式化邏輯抽出後才能脫離該型別鏈直接測試。
///
/// epic-28-reader-settings-enhancements Issue 2：[consoleLogEnabled] 為
/// `false` 時，只有 `ERROR` 等級（WebView 自動鏡射的未捕捉例外，崩潰診斷
/// 用途）強制記錄；`LOG`/`WARNING`/`DEBUG`/`TIP` 等一般等級一律略過。
/// `levelName` 來自 `ConsoleMessageLevel.toString()`，恆為大寫字串
/// （已用套件原始碼確認：`'ERROR'`/`'LOG'`/`'WARNING'`/`'DEBUG'`/`'TIP'`
/// 五種）。
void handleFoliateConsoleMessage(
  String message,
  String levelName, {
  required bool consoleLogEnabled,
}) {
  if (!consoleLogEnabled && levelName != 'ERROR') return;
  ReaderConsoleLog.add('[$levelName] $message');
}

/// [FoliateBridgeHandlers.onError] JS handler 的訊息解析邏輯，抽成頂層純函式
/// 獨立測試——原因同 [handleFoliateConsoleMessage]：
/// `FakePlatformInAppWebViewWidget`（`test/support/fake_inappwebview_platform.dart`）
/// 無法真正觸發完整的 `addJavaScriptHandler` 回呼型別鏈，抽出後才能脫離該型別鏈
/// 直接測試。main.js 的 `openBook()` 失敗時透過 `args[0]` 傳入原始技術性錯誤文字
/// （可能是英文 JS Error message，見 main.js `String((e && e.message) || e)`），
/// 依 `spec.md` §6「禁止在使用者可見文字中出現例外物件的原始文字內容」，這段原始
/// 文字只能寫入 [ReaderConsoleLog]，回傳給使用者的一律是固定在地化訊息。[args] 可能
/// 帶 `null` 或純空白字串（JS 端未附帶有意義的錯誤描述時），一併過濾為 `(no detail)`，
/// 避免 Console Log 診斷輸出淪為無意義的 `"null"`/空白。
String resolveFoliateOpenBookErrorMessage(
  List<dynamic> args,
  AppLocalizations l10n,
) {
  final raw = args.isNotEmpty ? args[0]?.toString().trim() : null;
  final detail = (raw != null && raw.isNotEmpty) ? raw : '(no detail)';
  ReaderConsoleLog.add('[FoliateReaderView] openBook 失敗: $detail');
  return l10n.readerFailedToLoadBookMessage;
}

/// 把 [Color] 轉換為 CSS 合法的 6 位十六進位色碼字串（`#RRGGBB`，不含
/// alpha）。**不可直接呼叫 `color.value.toRadixString(16)`**：
/// `Color` 內部 32 位值是 `AARRGGBB`（alpha 在前），CSS 標準的 8 位
/// 十六進位色碼是 `#RRGGBBAA`（alpha 在後），順序相反，直接轉換會產生
/// 錯誤顏色而非只是格式問題（epic-22-reader-theme-integration Issue 1，
/// 程式碼審查發現）。做法：先補零到 8 碼（`padLeft(8, '0')`，避免
/// RGB 帶前導零時被截斷成較短字串），再捨棄前 2 碼 alpha，只保留後
/// 6 碼 RGB。
String colorToCssHex(Color color) {
  final hex = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${hex.substring(2)}';
}

/// 把目前所有非 null 的偏好參數組成一個 map，key 名稱與 `main.js`
/// `window.applyPreferences`/`window.FoliateBridge` 契約一致（取代原本
/// `_FoliateReaderViewState._buildPreferencesMap()` 私有方法，改為
/// 公開頂層純函式以便不透過 `InAppWebView` 直接單元測試，見
/// docs/epics/epic-18-reader-device-qa/plans/plan-issue-10.md Task 4）。
/// `null` 值的欄位完全不出現在 map 中。
Map<String, Object?> buildFoliatePreferencesMap(FoliateReaderView view) {
  final map = <String, Object?>{};
  if (view.writingMode != null) {
    map['writingMode'] =
        view.writingMode == WritingMode.vertical ? 'vertical' : 'horizontal';
  }
  if (view.pageTurnMode != null) {
    map['pageTurnMode'] =
        view.pageTurnMode == PageTurnMode.scroll ? 'scroll' : 'paginated';
  }
  if (view.fontFamily != null) map['fontFamily'] = view.fontFamily!;
  if (view.fontSize != null) map['fontSize'] = view.fontSize;
  if (view.fontWeight != null) map['fontWeight'] = view.fontWeight;
  if (view.lineHeight != null) map['lineHeight'] = view.lineHeight;
  if (view.paragraphSpacing != null) {
    map['paragraphSpacing'] = view.paragraphSpacing;
  }
  if (view.letterSpacing != null) map['letterSpacing'] = view.letterSpacing;
  if (view.marginTop != null) map['marginTop'] = view.marginTop;
  if (view.marginBottom != null) map['marginBottom'] = view.marginBottom;
  if (view.marginLeft != null) map['marginLeft'] = view.marginLeft;
  if (view.marginRight != null) map['marginRight'] = view.marginRight;
  if (view.textAlign != null) map['textAlign'] = view.textAlign!.name;
  if (view.publisherStyles != null) {
    map['publisherStyles'] = view.publisherStyles;
  }
  if (view.columnMode != null) map['columnMode'] = view.columnMode!.name;
  if (view.columnSize != null) map['columnSize'] = view.columnSize;
  if (view.showFooter != null) map['showFooter'] = view.showFooter;
  if (view.isFixedLayoutHint != null) map['isFixedLayoutHint'] = view.isFixedLayoutHint;
  if (view.textColor != null) {
    map['textColor'] = colorToCssHex(view.textColor!);
  }
  if (view.backgroundColor != null) {
    map['backgroundColor'] = colorToCssHex(view.backgroundColor!);
  }
  if (view.dualPageMode != null) map['dualPageMode'] = view.dualPageMode!.name;
  if (view.textConversion != null) {
    map['textConversion'] = view.textConversion!.name;
  }
  map['isLandscape'] = view.isLandscape;
  map['isComicBookHint'] = view.isComicBookHint;
  if (view.dualPageDirection != null) {
    map['dualPageDirection'] =
        view.dualPageDirection == DualPageDirection.rtl ? 'rtl' : 'ltr';
  }
  return map;
}

/// 比較兩次 widget 建構參數，判斷是否需要重新呼叫
/// `window.applyPreferences()`（取代原本
/// `_FoliateReaderViewState._preferencesChanged()`）。
bool foliatePreferencesChanged(
  FoliateReaderView oldView,
  FoliateReaderView newView,
) {
  return oldView.writingMode != newView.writingMode ||
      oldView.pageTurnMode != newView.pageTurnMode ||
      oldView.fontFamily != newView.fontFamily ||
      oldView.fontSize != newView.fontSize ||
      oldView.fontWeight != newView.fontWeight ||
      oldView.lineHeight != newView.lineHeight ||
      oldView.paragraphSpacing != newView.paragraphSpacing ||
      oldView.letterSpacing != newView.letterSpacing ||
      oldView.marginTop != newView.marginTop ||
      oldView.marginBottom != newView.marginBottom ||
      oldView.marginLeft != newView.marginLeft ||
      oldView.marginRight != newView.marginRight ||
      oldView.textAlign != newView.textAlign ||
      oldView.publisherStyles != newView.publisherStyles ||
      oldView.columnMode != newView.columnMode ||
      oldView.columnSize != newView.columnSize ||
      oldView.showFooter != newView.showFooter ||
      oldView.isFixedLayoutHint != newView.isFixedLayoutHint ||
      oldView.textColor != newView.textColor ||
      oldView.backgroundColor != newView.backgroundColor ||
      oldView.dualPageMode != newView.dualPageMode ||
      oldView.textConversion != newView.textConversion ||
      oldView.isLandscape != newView.isLandscape ||
      oldView.isComicBookHint != newView.isComicBookHint ||
      oldView.dualPageDirection != newView.dualPageDirection;
}

/// 從 `InAppWebView.shouldInterceptRequest` 攔截到的請求路徑，判斷是否為
/// 自訂字型虛擬路徑（`/assets/custom-fonts/<URL 編碼後的 family name>`），
/// 若是則從 [customFonts] 找出對應項目並回傳其 `fontUri`；路徑不符前綴、
/// 或找不到符合的 family name，回傳 `null`。抽成獨立頂層純函式（而非直接
/// 寫在 `_shouldInterceptRequest` 內）的原因：`FakePlatformInAppWebViewWidget`
/// （`test/support/fake_inappwebview_platform.dart`）只回傳固定尺寸
/// placeholder，不會觸發真實 `shouldInterceptRequest` 回呼，
/// `_shouldInterceptRequest` 整個私有方法在目前 widget test 環境下無法被
/// 觸發到——這段路由/查找邏輯抽出後才能脫離 `InAppWebViewController`／
/// `WebResourceRequest` 直接測試。`_shouldInterceptRequest` 攔截的是
/// WebView 的全部請求（非僅我們自己產生的 URL），畸形百分號跳脫序列會讓
/// `Uri.decodeComponent` 拋出 `FormatException` 或 `ArgumentError`，包
/// try/catch 統一視為「不符合自訂字型路徑」回傳 `null`，避免例外冒出到
/// 攔截回呼（審查修正，
/// 見 tmp/epic-14/review-plan-issue-3.md Important 1）。
String? resolveCustomFontUri(String path, List<CustomFont> customFonts) {
  const prefix = '/assets/custom-fonts/';
  if (!path.startsWith(prefix)) return null;
  try {
    final familyName = Uri.decodeComponent(path.substring(prefix.length));
    for (final font in customFonts) {
      if (font.familyName == familyName) return font.fontUri;
    }
    return null;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

/// 包裝 readest/foliate-js（釘定 commit
/// dd71f2be356563c16a23272686189fcfb45d0b82）的 Flutter widget，供流式
/// （reflowable）EPUB 使用。原生嵌入元件為 `flutter_inappwebview` 的
/// `InAppWebView`（epic-18-reader-device-qa Issue 10，取代原本的
/// `AndroidView`+自建 `android.webkit.WebView`，見 ADR 0013）——本次遷移
/// 只換底層嵌入/JS 橋接機制，公開建構參數與 callback 契約與遷移前完全
/// 相同，`ReaderScreen` 等呼叫端不需要任何修改。
class FoliateReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final ValueChanged<EpubLayoutInfo>? onLayoutResolved;
  final WritingMode? writingMode;
  final PageTurnMode? pageTurnMode;
  final String? fontFamily;
  final double? fontSize;
  final double? fontWeight;
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? letterSpacing;
  final double? marginTop;
  final double? marginBottom;
  final double? marginLeft;
  final double? marginRight;
  final EpubTextAlign? textAlign;
  final bool? publisherStyles;
  final ColumnMode? columnMode;
  final double? columnSize;
  final bool? showFooter;
  final bool? isFixedLayoutHint;
  final DualPageMode? dualPageMode;

  /// 簡繁顯示轉換模式（FR-48，epic-42-text-conversion Issue 2）：呼叫端
  /// （[ReaderScreen]）傳入 `resolveTextConversion()` 解析後的該書生效值
  /// （[BookReaderPrefs.textConversionOverride] ?? 全域
  /// [ReadingDefaults.textConversion]）。`null` 時 main.js 端沿用
  /// `initialPrefs.textConversion` 的既有預設（`'original'`，見 main.js
  /// `currentTextConversion` 模組變數宣告）。
  final TextConversionMode? textConversion;

  /// CBZ 專屬提示（epic-11-multi-format-reader Issue 3）：main.js 僅在此為
  /// `true` 時才覆寫 `book.dir`／虛擬頁碼目錄，避免誤觸 EPUB 固定版面既有
  /// 的 page-progression-direction 自動偵測（見該檔案 openBook() 對應段落
  /// 註解）。預設 `false`，比照 [isLandscape] 既有非 nullable＋預設值模式
  /// ——本欄位並非「格式未知時省略」的選填語意，而是「明確告知這是不是
  /// 漫畫」的必要旗標。
  final bool isComicBookHint;

  /// CBZ 翻頁方向（RTL/LTR），重用既有 [DualPageDirection]（原僅 PDF
  /// 適用，見該檔案文件註解，epic-11-multi-format-reader Issue 3 起擴大
  /// 適用於 CBZ）。**僅在書籍開啟當下讀取一次**（main.js 的 openBook()，
  /// 於 `view.open(book)` 之前設定 `book.dir`）——`fixed-layout.js` 的
  /// `open()` 只在當下一次性讀取 `book.dir` 決定 `this.rtl`（見
  /// Global Constraints 已查證事實 #2），之後不會重新推導，故本欄位變動
  /// 不會在既有書籍開啟期間即時生效，需重新開啟該書才會套用新方向
  /// （比照既有 [isFixedLayoutHint] 同樣「僅開書當下生效」的既有限制，
  /// 非本 Issue 新增的例外）。
  final DualPageDirection? dualPageDirection;
  final bool isLandscape;
  final Color? textColor;
  final Color? backgroundColor;
  final List<CustomFont> customFonts;
  /// 已下載的內建字型（epic-49）。只替這些字型輸出 `@font-face`；開書時決定，
  /// 之後不會重算（見 `_FoliateReaderViewState._initialIndexUri`），所以
  /// `ReaderScreen` 必須等清單讀完才建構本 widget。
  final Set<AppFont> installedFonts;

  /// 已下載字型的存放目錄（`DownloadableFontStore.directory`）。不為 null 時才註冊
  /// `/downloaded-fonts/` 的 `InternalStoragePathHandler`，由原生端直接串流字型檔，
  /// 不經過 Dart（ADR 0035）。
  final String? downloadedFontsDirectory;
  final List<ZoneAction> navZoneActions;
  final ValueChanged<ZoneAction>? onZoneAction;
  final bool showNavZoneDebugOverlay;
  final bool consoleLogEnabled;
  final String? initialLocatorJson;
  final ValueChanged<EpubPositionInfo>? onLocatorChanged;
  final ValueChanged<EpubSelectionInfo>? onSelectionChanged;
  final VoidCallback? onSelectionCleared;

  /// 安全視窗跟隨翻頁（epic-34-tts-readalong Issue 8）：main.js
  /// draw-annotation 監聽器偵測到目前朗讀高亮超出安全視窗（可視範圍
  /// 20%～80%）時觸發，帶入 `'next'` 或 `'prev'`（main.js 依 isVertical
  /// 分流判斷出的方向）。呼叫端（[ReaderScreen]）收到後呼叫
  /// [FoliateReaderView.nextPage]/[previousPage] 觸發一次性翻頁——本欄位
  /// 只負責回報「超出範圍了、該往哪個方向」這個事實，不自行決定要不要
  /// 真的翻頁，比照 [onLocatorChanged]/[onSelectionChanged] 既有的
  /// 「JS 回報事實、Dart 決定政策」分工慣例。
  final ValueChanged<String>? onTtsHighlightOutOfSafeWindow;

  const FoliateReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onLayoutResolved,
    this.writingMode,
    this.pageTurnMode,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.letterSpacing,
    this.marginTop,
    this.marginBottom,
    this.marginLeft,
    this.marginRight,
    this.textAlign,
    this.publisherStyles,
    this.columnMode,
    this.columnSize,
    this.showFooter,
    this.isFixedLayoutHint,
    this.dualPageMode,
    this.textConversion,
    this.isComicBookHint = false,
    this.dualPageDirection,
    this.textColor,
    this.backgroundColor,
    this.isLandscape = false,
    this.customFonts = const [],
    this.installedFonts = const {},
    this.downloadedFontsDirectory,
    this.navZoneActions = const [
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ],
    this.onZoneAction,
    this.showNavZoneDebugOverlay = false,
    this.consoleLogEnabled = false,
    this.initialLocatorJson,
    this.onLocatorChanged,
    this.onSelectionChanged,
    this.onSelectionCleared,
    this.onTtsHighlightOutOfSafeWindow,
  });

  static void nextPage(GlobalKey<State<FoliateReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate('window.nextPage()');
    }
  }

  static void previousPage(GlobalKey<State<FoliateReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate('window.previousPage()');
    }
  }

  static void jumpToProgression(
    GlobalKey<State<FoliateReaderView>> key,
    double progression,
  ) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate('window.jumpToFraction($progression)');
    }
  }

  static void jumpToLocator(
    GlobalKey<State<FoliateReaderView>> key,
    String locatorJson,
  ) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      final cfi = extractCfi(locatorJson);
      if (cfi != null) {
        state._evaluate('window.jumpToLocator(${jsonEncode(cfi)})');
      }
    }
  }

  static Future<List<TocEntry>> loadTableOfContents(
    GlobalKey<State<FoliateReaderView>> key,
  ) async {
    final state = key.currentState;
    if (state is! _FoliateReaderViewState) return const [];
    return state._requestTableOfContents();
  }

  static Future<List<TtsSegmentCfi>> loadTtsSegments(
    GlobalKey<State<FoliateReaderView>> key,
    int sectionIndex,
  ) async {
    final state = key.currentState;
    if (state is! _FoliateReaderViewState) return const [];
    return state._requestTtsSegments(sectionIndex);
  }

  /// 依「畫面目前可視位置」cfi 反查對應或緊隨其後的第一個朗讀段索引
  /// （epic-34-tts-readalong Issue 4）。[segmentCfis] 為呼叫端
  /// （[TtsController] 透過 [ReaderScreen] 注入的 `lookupStartIndex`
  /// callback）目前持有、已依文件順序排序的朗讀段 cfi 清單。WebView 尚未
  /// 就緒／JS 端回傳 -1（無法判斷順序，例如 [segmentCfis] 為空）／5 秒
  /// 逾時，皆安全退回 `0`（從第一段開始），不拋出例外——比照
  /// [loadTtsSegments] 逾時時退回空清單的既有優雅退回慣例。
  static Future<int> lookupSegmentByCfi(
    GlobalKey<State<FoliateReaderView>> key,
    String visibleCfi,
    List<String> segmentCfis,
  ) async {
    final state = key.currentState;
    if (state is! _FoliateReaderViewState) return 0;
    final index = await state._requestTtsSegmentIndex(visibleCfi, segmentCfis);
    return index < 0 ? 0 : index;
  }

  static void setDecorations(
    GlobalKey<State<FoliateReaderView>> key,
    List<EpubDecoration> decorations,
  ) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      final entries = buildDecorationEntries(decorations);
      state._evaluate('window.setDecorations(${jsonEncode(entries)})');
    }
  }

  /// 顯示朗讀高亮（epic-34-tts-readalong Issue 3，ADR 0026）：呼叫 main.js
  /// window.showTtsHighlight()，使用與劃線/備註分開的獨立 annotation key
  /// 空間（見 main.js 該函式註解），不寫入任何資料表。[vertical] 由呼叫端
  /// （[ReaderScreen]）依目前實際生效的排版方向傳入，供 main.js
  /// draw-annotation 監聽器決定 Overlayer.highlight() 的 vertical 參數，
  /// 直排/橫排皆正確跟隨。
  static void showTtsHighlight(
    GlobalKey<State<FoliateReaderView>> key,
    String cfi, {
    required bool vertical,
    required bool einkMode,
  }) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate(
        'window.showTtsHighlight(${jsonEncode(cfi)}, $vertical, $einkMode)',
      );
    }
  }

  /// 清除目前的朗讀高亮（epic-34-tts-readalong Issue 3）。朗讀段切換時不
  /// 需要呼叫端先呼叫這個方法再呼叫 [showTtsHighlight]——main.js
  /// window.showTtsHighlight() 內部已處理「顯示新的之前先清除舊的」，本
  /// 方法只在播放結束（不再有下一段可顯示）時由 [ReaderScreen] 呼叫。
  static void clearTtsHighlight(GlobalKey<State<FoliateReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate('window.clearTtsHighlight()');
    }
  }

  /// 顯示搜尋跳轉的暫態高亮（epic-10-search Issue 5，spec.md §6）：呼叫
  /// main.js window.showSearchHighlight()，底層走 view.js 既有的
  /// `foliate-search:` 前綴（固定紅色外框樣式，無法客製化顏色/直排橫排/
  /// E-Ink 樣式，見 main.js 該函式上方的完整查證註解與本計畫 Global
  /// Constraints），與 [showTtsHighlight] 使用的 `foliate-note:` 完全
  /// 獨立的 key 空間——兩者的生命週期與觸發時機互不相干，混用會互相
  /// 汙染。
  static void showSearchHighlight(
    GlobalKey<State<FoliateReaderView>> key,
    String cfi,
  ) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate('window.showSearchHighlight(${jsonEncode(cfi)})');
    }
  }

  /// 清除目前的搜尋跳轉暫態高亮，由 [ReaderScreen] 的 Dart 端 Timer
  /// （3 秒）或使用者提前翻頁/點擊畫面時呼叫。
  static void clearSearchHighlight(GlobalKey<State<FoliateReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate('window.clearSearchHighlight()');
    }
  }

  /// 主動清除 WebView 原生文字選取狀態（epic-25 Issue 3，見 main.js
  /// window.clearSelection 註解）。
  static void clearSelection(GlobalKey<State<FoliateReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate('window.clearSelection()');
    }
  }


  @override
  State<FoliateReaderView> createState() => _FoliateReaderViewState();
}

class _FoliateReaderViewState extends State<FoliateReaderView> {
  InAppWebViewController? _controller;
  late final JsBridgeGateway _gateway;

  /// 每個 widget 實例獨立的快取子目錄路徑，供 `InternalStoragePathHandler` 使用。
  /// null 表示快取尚未完成或失敗。
  String? _bookCacheDir;

  /// 本實例的唯一 ID，用於區隔快取子目錄（避免螢幕轉場期間的競態）。
  late final String _instanceId = identityHashCode(this).toString();

  /// Epic 25 Issue 1 修法：目前 WebView 內是否有文字選取範圍存在，供
  /// `TapZoneDetector` 判斷是否要抑制翻頁動作（見下方 onTap 說明）。
  /// 由 `onSelectionChanged`/`onSelectionCleared` JS 橋接 handler 直接維護，
  /// 不透過 setState——這個欄位只在使用者放開手指的那一刻被讀取一次
  /// （事件觸發時的即時值），不影響任何一次 build() 的輸出，不需要為它
  /// 觸發重繪。
  bool _hasActiveSelection = false;

  late final Uri _initialIndexUri = _buildIndexUri();

  @override
  void initState() {
    super.initState();
    _cacheBook();
  }

  /// 非同步前置快取步驟：將 EPUB 檔案複製到原生端快取目錄，
  /// 供 `WebViewAssetLoader.InternalStoragePathHandler` 串流服務。
  Future<void> _cacheBook() async {
    try {
      final cacheFn = cacheBookForServing;
      final cachedPath = await cacheFn(widget.filePath, _instanceId);
      if (!mounted) {
        // 217MB 檔案複製可能耗時數秒，若使用者已離開畫面，需主動清理快取
        if (cachedPath != null) {
          final cacheDir = Directory(File(cachedPath).parent.path);
          if (cacheDir.existsSync()) {
            cacheDir.deleteSync(recursive: true);
          }
        }
        return;
      }
      if (cachedPath != null) {
        // cacheBookForServing 回傳的是檔案絕對路徑，InternalStoragePathHandler 要的是目錄
        setState(() {
          _bookCacheDir = File(cachedPath).parent.path;
        });
      } else {
        ReaderConsoleLog.add('[FoliateReaderView] _cacheBook 失敗：cacheBookForServing 回傳 null');
        widget.onError(AppLocalizations.of(context)!.readerFailedToLoadBookMessage);
      }
    } catch (e) {
      if (!mounted) return;
      ReaderConsoleLog.add('[FoliateReaderView] _cacheBook 拋出例外: $e');
      widget.onError(AppLocalizations.of(context)!.readerFailedToLoadBookMessage);
    }
  }

  Uri _buildIndexUri() {
    final params = <String, String>{
      'prefs': jsonEncode(buildFoliatePreferencesMap(widget)),
      'fontFaceCss': buildFontFaceCss(
        installedFonts: widget.installedFonts,
        customFonts: widget.customFonts,
      ),
      // epic-11-multi-format-reader Issue 3：讓 main.js 的 fetch URL 反映
      // 真實副檔名（見 foliate_native_bridge.dart cacheFileExtension()
      // 文件註解——CBZ 需要 view.js 的 isCBZ() 對檔名做副檔名判斷）。
      'bookFileName': 'current.${cacheFileExtension(widget.filePath)}',
    };
    final cfi = extractCfi(widget.initialLocatorJson);
    if (cfi != null) params['initialCfi'] = cfi;
    return Uri.https(
      'appassets.androidplatform.net',
      '/assets/foliate/index.html',
      params,
    );
  }

  void _evaluate(String source) {
    _controller?.evaluateJavascript(source: source);
  }

  Future<List<TocEntry>> _requestTableOfContents() {
    if (_controller == null) return Future.value(const []);
    return _gateway.request<List<TocEntry>>(
      jsCall: 'window.getTableOfContents()',
      handlerName: FoliateBridgeHandlers.onTableOfContentsReady,
    );
  }

  Future<List<TtsSegmentCfi>> _requestTtsSegments(int sectionIndex) {
    if (_controller == null) return Future.value(const []);
    return _gateway.request<List<TtsSegmentCfi>>(
      jsCall: 'window.buildTtsSegments($sectionIndex)',
      handlerName: FoliateBridgeHandlers.onTtsSegmentsReady,
      timeout: const Duration(seconds: 5),
    );
  }

  Future<int> _requestTtsSegmentIndex(
    String visibleCfi,
    List<String> segmentCfis,
  ) {
    if (_controller == null) return Future.value(0);
    return _gateway.request<int>(
      jsCall:
          'window.lookupTtsSegmentIndex(${jsonEncode(visibleCfi)}, ${jsonEncode(segmentCfis)})',
      handlerName: FoliateBridgeHandlers.onTtsSegmentIndexReady,
      timeout: const Duration(seconds: 5),
    );
  }

  Future<void> _onWebViewCreated(InAppWebViewController controller) async {
    _controller = controller;
    _gateway = JsBridgeGateway(
      evaluate: _evaluate,
      registerHandler: (name, callback) => controller.addJavaScriptHandler(
        handlerName: name,
        callback: callback,
      ),
    );
    _gateway.register<List<TocEntry>>(
      handlerName: FoliateBridgeHandlers.onTableOfContentsReady,
      parse: (args) =>
          parseTableOfContents(args.isNotEmpty ? args[0] as String : '[]'),
      fallback: const [],
    );
    _gateway.register<List<TtsSegmentCfi>>(
      handlerName: FoliateBridgeHandlers.onTtsSegmentsReady,
      parse: (args) =>
          parseTtsSegments(args.length > 1 ? args[1] as String : '[]'),
      fallback: const [],
    );
    _gateway.register<int>(
      handlerName: FoliateBridgeHandlers.onTtsSegmentIndexReady,
      parse: (args) => args.isNotEmpty ? (args[0] as num).toInt() : 0,
      fallback: 0,
    );
    controller.addJavaScriptHandler(
      handlerName: FoliateBridgeHandlers.onPageRendered,
      callback: (args) {
        widget.onPageRendered();
        // epic-54 Issue 18：回報 `main.js` 的真實 `view.isFixedLayout`
        //（此前寫死 false 的契約前提已隨 epic-20 失效，見
        // parseFoliateLayoutResolved 文件）。
        widget.onLayoutResolved?.call(
          parseFoliateLayoutResolved(args, isFixedLayoutHint: widget.isFixedLayoutHint),
        );
      },
    );
    controller.addJavaScriptHandler(
      handlerName: FoliateBridgeHandlers.onError,
      callback: (args) {
        if (!mounted) return;
        widget.onError(
          resolveFoliateOpenBookErrorMessage(args, AppLocalizations.of(context)!),
        );
      },
    );
    controller.addJavaScriptHandler(
      handlerName: FoliateBridgeHandlers.onLocatorChanged,
      // epic-26-architecture-hardening Issue 10：解析邏輯抽成
      // foliate_bridge_codec.dart 的 parseLocatorChanged() 純函式（比照
      // extractCfi()/parseTableOfContents() 既有慣例），可脫離 WebView
      // 直接單元測試，不再是這個 widget 內無法獨立驗證的匿名 closure。
      callback: (args) =>
          widget.onLocatorChanged?.call(parseLocatorChanged(args)),
    );
    controller.addJavaScriptHandler(
      handlerName: FoliateBridgeHandlers.onTtsHighlightOutOfSafeWindow,
      callback: (args) {
        // 審查修正（review-plan-issue-8.md Important #3）：比照既有
        // onSelectionChanged 的防禦性轉型慣例（見上方 argAt()），用
        // `is String` 檢查取代直接 `as String` 強制轉型——main.js 端目前
        // 恆傳字串常值，但若未來橋接參數格式意外變動（例如傳入 null 或
        // 未定義物件），直接強制轉型會拋出執行期 TypeError。
        final direction = (args.isNotEmpty && args[0] is String)
            ? args[0] as String
            : 'next';
        widget.onTtsHighlightOutOfSafeWindow?.call(direction);
      },
    );
    controller.addJavaScriptHandler(
      handlerName: FoliateBridgeHandlers.onSelectionChanged,
      callback: (args) {
        // 審查修正：同 onLocatorChanged，改用防禦性轉型取代直接強制轉型。
        num? argAt(int index) =>
            args.length > index ? args[index] as num? : null;
        _hasActiveSelection = true;
        widget.onSelectionChanged?.call(EpubSelectionInfo(
          locatorJson: args.isNotEmpty ? args[0] as String : '',
          progression: argAt(1)?.toDouble() ?? 0.0,
          rect: PercentRect(
            left: argAt(2)?.toDouble() ?? 0.0,
            top: argAt(3)?.toDouble() ?? 0.0,
            right: argAt(4)?.toDouble() ?? 0.0,
            bottom: argAt(5)?.toDouble() ?? 0.0,
          ),
          // epic-27-reader-device-compat Issue 11：main.js 新增送出的選取
          // 文字與 hit-test 結果，見上方 JS 端 reportSelection() 註解。
          text: args.length > 6 ? (args[6] as String? ?? '') : '',
          existingAnnotationId: args.length > 7 ? args[7] as String? : null,
        ));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: FoliateBridgeHandlers.onSelectionCleared,
      callback: (args) {
        _hasActiveSelection = false;
        widget.onSelectionCleared?.call();
      },
    );
    await attachReaderView();
  }

  Future<WebResourceResponse?> _shouldInterceptRequest(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) async {
    final path = request.url.path;
    // `/book/current.epub` 請求已改由原生 `WebViewAssetLoader.InternalStoragePathHandler` 串流服務，
    // 不再需要 Dart callback 攔截（見 Issue 8 Task 3）。
    const foliateAssetsPrefix = '/assets/foliate/';
    if (path.startsWith(foliateAssetsPrefix)) {
      final relative = 'foliate/${path.substring(foliateAssetsPrefix.length)}';
      final bytes = await loadAndroidAsset(relative);
      if (bytes == null) return null;
      final contentType =
          path.endsWith('.js') ? 'text/javascript' : 'text/html';
      return WebResourceResponse(contentType: contentType, data: bytes);
    }
    final customFontUri = resolveCustomFontUri(path, widget.customFonts);
    if (customFontUri != null) {
      final bytes = await loadCustomFontBytes(customFontUri);
      if (bytes == null) return null;
      return WebResourceResponse(contentType: 'font/ttf', data: bytes);
    }
    return null;
  }

  @override
  void didUpdateWidget(covariant FoliateReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (foliatePreferencesChanged(oldWidget, widget)) {
      _evaluate(
        'window.applyPreferences(${jsonEncode(buildFoliatePreferencesMap(widget))})',
      );
    }
  }

  @override
  void dispose() {
    // 清理本實例的快取子目錄（避免孤兒子目錄累積）
    if (_bookCacheDir != null) {
      final cacheDir = Directory(_bookCacheDir!);
      if (cacheDir.existsSync()) {
        cacheDir.deleteSync(recursive: true);
      }
    }
    detachReaderView();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 快取未完成前不掛載 InAppWebView（外層 ReaderScreen 已負責視覺載入狀態）
    if (_bookCacheDir == null) {
      return const SizedBox.shrink();
    }
    // epic-35-design-system-tokens Issue 7：3×3 導覽熱區除錯疊層（見下方
    // showNavZoneDebugOverlay 分支）原本寫死 Colors.white24／white70，
    // 換主題／開啟 E-Ink 模式時不會跟著換；改讀 colorScheme.onSurface，
    // 呼應 nav_zone_settings_screen.dart（epic-35 Issue 5）同一組熱區格線
    // 已採用的同一個角色，維持同一功能兩處視覺語彙一致。
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri.uri(_initialIndexUri)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useShouldInterceptRequest: true,
            webViewAssetLoader: WebViewAssetLoader(
              pathHandlers: [
                InternalStoragePathHandler(
                    path: '/book/', directory: _bookCacheDir!),
                if (widget.downloadedFontsDirectory != null)
                  InternalStoragePathHandler(
                      path: kDownloadedFontsPathPrefix,
                      directory: widget.downloadedFontsDirectory!),
              ],
            ),
          ),
          // 【診斷修正】見上方 esCompatPolyfillJs 註解——在文件載入最早期
          // 注入 Object.groupBy/Map.groupBy/Array.prototype.at/
          // Array.prototype.findLastIndex 的 polyfill，避免舊版 WebView 開
          // 啟 EPUB 時因 epub.js/epubcfi.js/paginator.js 呼叫這些較新的 ES
          // 內建方法而拋出例外、導致畫面卡在載入指示器。
          initialUserScripts: UnmodifiableListView<UserScript>([
            UserScript(
              source: esCompatPolyfillJs,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // epic-18-reader-device-qa Issue 39：見上方
            // _applyPreferencesQueueShimJs 註解。
            UserScript(
              source: _applyPreferencesQueueShimJs,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // epic-18-reader-device-qa Issue 33：見上方 globalErrorCaptureJs
            // 註解。順序在 polyfill 之後無妨——兩者皆於 AT_DOCUMENT_START
            // 注入，實際執行順序不影響彼此（各自只是定義全局函式/監聽器）。
            UserScript(
              source: globalErrorCaptureJs,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // epic-18-reader-device-qa Issue 33（程式碼審查建議）：見上方
            // _userAgentLogJs 註解。
            UserScript(
              source: _userAgentLogJs,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          ]),
          onWebViewCreated: _onWebViewCreated,
          shouldInterceptRequest: _shouldInterceptRequest,
          // epic-18-reader-device-qa Issue 33：見上方
          // handleFoliateConsoleMessage 註解。
          onConsoleMessage: (controller, consoleMessage) =>
              handleFoliateConsoleMessage(
            consoleMessage.message,
            consoleMessage.messageLevel.toString(),
            consoleLogEnabled: widget.consoleLogEnabled,
          ),
        ),
        Positioned.fill(
          child: Column(
            children: List.generate(3, (row) {
              return Expanded(
                child: Row(
                  children: List.generate(3, (col) {
                    final index = row * 3 + col;
                    final action = widget.navZoneActions[index];
                    return Expanded(
                      child: TapZoneDetector(
                        key: Key('nav_zone_$index'),
                        // Epic 26 Issue 1 校準值（epic-25 Issue 1 六輪
                        // 真機診斷得出，見 TapZoneDetector class doc）。
                        // tapSlop／tapDebounceMs 改用建構子預設值
                        // （kTapZoneSlop／kTapZoneDebounceMs，epic-31
                        // Issue 3 常數收斂），不再各自宣告字面值。
                        nowMs: () => DateTime.now().millisecondsSinceEpoch,
                        tapMaxDurationMs: 700,
                        onTap: () {
                          // Epic 25 Issue 1：真機診斷（見
                          // docs/epics/epic-25-annotation-interaction-qa/issues.md
                          // Issue 1）證實長按選字手勢即使成功讓 WebView
                          // 建立選取範圍，放開手指的那個動作仍可能同時滿足
                          // TapZoneDetector 自己的「快速點擊」門檻而觸發
                          // 翻頁——TapZoneDetector 刻意使用 Listener、不
                          // 加入手勢競技場（見 class doc），WebView 贏得
                          // 選取不會讓這裡的 Tap 判定被取消，兩者是完全
                          // 獨立、各自判讀同一組觸控事件的路徑。若目前有
                          // 文字選取範圍存在，代表使用者這次觸控是劃線/
                          // 選字手勢的一部分，不應該連帶觸發翻頁。
                          if (_hasActiveSelection) return;
                          widget.onZoneAction?.call(action);
                        },
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(
                                      color: onSurfaceColor.withValues(
                                          alpha: 0.24)))
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
