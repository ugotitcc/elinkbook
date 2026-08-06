import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'column_mode.dart';
import 'custom_font.dart';
import 'dual_page_mode.dart';
import 'epub_decoration.dart';
import 'epub_position_info.dart';
import 'epub_selection_info.dart';
import 'epub_text_align.dart';
import 'foliate_bridge_codec.dart';
import 'foliate_native_bridge.dart';
import 'page_turn_mode.dart';
import 'percent_rect.dart';
import 'reader_console_log.dart';
import 'toc_entry.dart';
import 'writing_mode.dart';
import 'zone_action.dart';

/// 【診斷修正——真機回報：Mobiscribe WAVE（Android 12，
/// `com.android.webview` 版本 91.0.4472.114）開啟流式 EPUB 時畫面永遠停在
/// 轉圈圈載入指示器，且沒有任何可觀察的例外/console 訊息（這台裝置的
/// WebView 建置沒有開啟 `setWebContentsDebuggingEnabled`，無法遠端連接
/// DevTools 檢視實際拋出的例外）】`epub.js`／`epubcfi.js`／`paginator.js`
/// （`readest/foliate-js` 釘定版本）在開書必經路徑（`loadItem()`／
/// `loadReplaced()` 讀取 spine 資源、`paginator.js` 分頁計算）無條件使用
/// 三個較新的 ES 內建方法，較舊的 Android System WebView 統統沒有：
///
/// - `Object.groupBy`／`Map.groupBy`（ES2024，需 Chromium 117+）
/// - `Array.prototype.at()`（ES2022，需 Chromium 92+）
/// - `Array.prototype.findLastIndex()`（ES2023，需 Chromium 97+）
///
/// 這台裝置的 Chromium 91（已用 `dumpsys package com.android.webview` 與
/// `adb logcat` 的 `cr_LibraryLoader` 訊息雙重確認版本號）三個都不支援；
/// `Object.groupBy` 那部分已在前一輪診斷修正過，這次追加 `.at()`／
/// `findLastIndex()` 的 polyfill——已用 `@xmldom/xmldom` + 未經修改的實際
/// epub.js／epubcfi.js 驗證這兩個方法確實會在 Node.js 移除該內建方法後
/// 拋出對應的 `TypeError`。僅在缺席時才定義（不覆蓋原生實作，等原生
/// WebView 支援後行為與新版一致），透過 [UserScript] 在文件載入最早期
/// 注入，不修改 `readest/foliate-js` 釘定版本本身（比照既有 ADR 0011
/// 「不修改釘定版本」的既有限制）。
///
/// 【epic-18-reader-device-qa Issue 38，2026-08-05 追加發現】本腳本自身
/// 曾在 `Object.groupBy` polyfill 內用了 `??=`（邏輯 nullish 賦值，ES2021，
/// 需 Chromium 85+）——JS 引擎會在執行任何程式碼之前完整解析整份腳本，
/// 任何一處語法錯誤都會讓整份腳本（含本檔案其餘 3 個 polyfill）完全不
/// 執行。iReader Ocean 4 Plus 的系統 WebView 為 Chromium 83（早於 85），
/// 代表上面 4 個 polyfill 在這台裝置上其實從未真正生效過。已改寫為
/// ES5 相容語法（`if (!x) x = []` 取代 `x ??= []`）。**本腳本後續新增的
/// 任何 polyfill 本體，禁止使用 ES2020 之後的語法糖**（包括 `??=`／`||=`／
/// `&&=`／選用鏈結 `?.` 需 Chromium 80+、標籤模板等），因為這份腳本存在
/// 的唯一目的就是在不支援新語法的舊版 WebView 上執行。
///
/// 【epic-18-reader-device-qa Issue 41】`epub.js` 的字型反混淆
/// （`deobfuscators`）用了 `String.prototype.replaceAll`（ES2021，需
/// Chromium 85+）；`view.js` 的 Media Overlays 用了 `WeakRef`（ES2021，需
/// Chromium 84+）。iReader Ocean 4 Plus 的 Chromium 83 兩者皆不支援。兩者
/// 皆只在特定書籍功能（含混淆內嵌字型／含 media overlay）才會執行到，非
/// 通用開書路徑，故不像 Issue 38 的 `??=` 語法解析失敗那樣影響「每一本
/// 書」，但仍是真實存在的崩潰風險，一併補上防護。
const _esCompatPolyfillJs = '''
if (!Object.groupBy) {
  Object.groupBy = function (items, keyFn) {
    const result = Object.create(null);
    let index = 0;
    for (const item of items) {
      const key = keyFn(item, index++);
      if (!result[key]) result[key] = [];
      result[key].push(item);
    }
    return result;
  };
}
if (!Map.groupBy) {
  Map.groupBy = function (items, keyFn) {
    const result = new Map();
    let index = 0;
    for (const item of items) {
      const key = keyFn(item, index++);
      if (!result.has(key)) result.set(key, []);
      result.get(key).push(item);
    }
    return result;
  };
}
if (!Array.prototype.at) {
  Array.prototype.at = function (index) {
    const len = this.length;
    const relativeIndex = index < 0 ? len + index : index;
    return (relativeIndex >= 0 && relativeIndex < len) ? this[relativeIndex] : undefined;
  };
}
if (!Array.prototype.findLastIndex) {
  Array.prototype.findLastIndex = function (predicate, thisArg) {
    for (let i = this.length - 1; i >= 0; i--) {
      if (predicate.call(thisArg, this[i], i, this)) return i;
    }
    return -1;
  };
}
if (!String.prototype.replaceAll) {
  String.prototype.replaceAll = function (search, replacement) {
    if (search instanceof RegExp) {
      if (!search.global) {
        throw new TypeError('replaceAll must be called with a global RegExp');
      }
      return this.replace(search, replacement);
    }
    if (typeof replacement === 'function') {
      // 目前 vendor 用法（epub.js 的字型反混淆）只會傳入字串
      // replacement，故不實作函式型 replacement——若未來真的用到，寧可
      // 在這裡明確拋出例外，也不要靜默產生錯誤結果（原本的寫法用
      // Array.prototype.join(fn)，join() 對非字串參數只會呼叫
      // fn.toString()，不會逐一呼叫該函式，等於把函式原始碼文字字面
      // 插入結果字串，是難以排查的靜默錯誤）。
      throw new TypeError(
        'replaceAll polyfill 尚未實作函式型 replacement（目前 vendor 用法不需要）'
      );
    }
    // 展開 \$\$（字面 \$ 符號）／\$&（比對到的子字串）兩種替換樣式，比照
    // 原生 String.prototype.replaceAll 規格常見用法；不支援比對前/後文字
    // 這兩種樣式——這兩者需要逐一追蹤每次匹配在原字串中的位置，split/join
    // 這種一次切割做法無法簡單支援，目前 vendor 用法也用不到，暫不實作。
    const expanded = String(replacement).replace(
      /\\\$(\\\$|&)/g,
      function (_, token) { return token === '\$' ? '\$' : String(search); }
    );
    return this.split(search).join(expanded);
  };
}
if (typeof WeakRef === 'undefined') {
  window.WeakRef = function (target) {
    // 注意：僅用強參照模擬 deref()，不具備真正的弱參照／GC 語意，只用於
    // 避免 ReferenceError；已知影響範圍：view.js 的 Media Overlays
    // lastActive 單一插槽變數（見上方文件註解），該變數在下一次
    // 'highlight' 事件觸發時會被覆寫，不會無限累積記憶體。
    this._target = target;
  };
  window.WeakRef.prototype.deref = function () {
    return this._target;
  };
}
''';

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

/// 全局 JS 錯誤捕捉（epic-18-reader-device-qa Issue 33，真機使用回報：
/// iReader Ocean 4 Plus 開啟書籍時畫面永遠停在載入指示器，5 個推測根因
/// 皆無真機診斷資料佐證）。`main.js` 本身的 `openBook()` 已用 try/catch
/// 涵蓋自身執行期間拋出的例外並回報 `onError`，但無法涵蓋：(1) 釘定的
/// vendor 腳本（`view.js`／`epub.js`／`paginator.js`）在文件載入極早期、
/// `main.js` 的 try/catch 尚未有機會執行前就拋出的例外（例如缺少 ES
/// 內建方法時的 `TypeError`，見上方 `_esCompatPolyfillJs` 的既有診斷紀
/// 錄——這正是舊版 WebView 最典型的失敗模式）；(2) 未被 await 的 Promise
/// rejection。透過 `window.onerror`／`window.onunhandledrejection` 補上
/// 這兩類涵蓋範圍，並在 `AT_DOCUMENT_START`（比任何 vendor 腳本都早）
/// 注入，重用既有的 `onError` JS↔Dart bridge channel（見
/// `_onWebViewCreated` 的 'onError' handler），不需要新增任何 Dart 端
/// 接線或新的 channel。
const _globalErrorCaptureJs = '''
window.onerror = function (message, source, lineno, colno, error) {
  if (window.flutter_inappwebview) {
    window.flutter_inappwebview.callHandler('onError', 'JS Error: ' + message + ' (' + source + ':' + lineno + ')');
  }
};
window.onunhandledrejection = function (event) {
  if (window.flutter_inappwebview) {
    var reason = event && event.reason;
    var message = (reason && reason.message) || String(reason);
    window.flutter_inappwebview.callHandler('onError', 'Unhandled Promise Rejection: ' + message);
  }
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
void handleFoliateConsoleMessage(String message, String levelName) {
  ReaderConsoleLog.add('[$levelName] $message');
}

/// 把 [Color] 轉換為 CSS 合法的 6 位十六進位色碼字串（`#RRGGBB`，不含
/// alpha）。**不可直接對 [Color.value] 呼叫 `toRadixString(16)`**：
/// `Color.value` 是 32 位 `AARRGGBB`（alpha 在前），CSS 標準的 8 位
/// 十六進位色碼是 `#RRGGBBAA`（alpha 在後），順序相反，直接轉換會產生
/// 錯誤顏色而非只是格式問題（epic-22-reader-theme-integration Issue 1，
/// 程式碼審查發現）。做法：先補零到 8 碼（`padLeft(8, '0')`，避免
/// RGB 帶前導零時被截斷成較短字串），再捨棄前 2 碼 alpha，只保留後
/// 6 碼 RGB。
String colorToCssHex(Color color) {
  final hex = color.value.toRadixString(16).padLeft(8, '0');
  return '#${hex.substring(2)}';
}

/// 把目前所有非 null 的偏好參數組成一個 map，key 名稱與 `main.js`
/// `window.applyPreferences`/`window.FoliateBridge` 契約一致（取代原本
/// `_FoliateEpubReaderViewState._buildPreferencesMap()` 私有方法，改為
/// 公開頂層純函式以便不透過 `InAppWebView` 直接單元測試，見
/// docs/epics/epic-18-reader-device-qa/plans/plan-issue-10.md Task 4）。
/// `null` 值的欄位完全不出現在 map 中。
Map<String, Object?> buildFoliatePreferencesMap(FoliateEpubReaderView view) {
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
  if (view.dualPageMode != null) map['dualPageMode'] = view.dualPageMode!.name;
  map['isLandscape'] = view.isLandscape;
  return map;
}

/// 比較兩次 widget 建構參數，判斷是否需要重新呼叫
/// `window.applyPreferences()`（取代原本
/// `_FoliateEpubReaderViewState._preferencesChanged()`）。
bool foliatePreferencesChanged(
  FoliateEpubReaderView oldView,
  FoliateEpubReaderView newView,
) {
  return oldView.writingMode != newView.writingMode ||
      oldView.pageTurnMode != newView.pageTurnMode ||
      oldView.fontFamily != newView.fontFamily ||
      oldView.fontSize != newView.fontSize ||
      oldView.fontWeight != newView.fontWeight ||
      oldView.lineHeight != newView.lineHeight ||
      oldView.paragraphSpacing != newView.paragraphSpacing ||
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
      oldView.dualPageMode != newView.dualPageMode ||
      oldView.isLandscape != newView.isLandscape;
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
class FoliateEpubReaderView extends StatefulWidget {
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
  final bool isLandscape;
  final List<CustomFont> customFonts;
  final List<ZoneAction> navZoneActions;
  final ValueChanged<ZoneAction>? onZoneAction;
  final bool showNavZoneDebugOverlay;
  final String? initialLocatorJson;
  final ValueChanged<EpubPositionInfo>? onLocatorChanged;
  final ValueChanged<EpubSelectionInfo>? onSelectionChanged;
  final VoidCallback? onSelectionCleared;
  final ValueChanged<String>? onAnnotationActivated;

  const FoliateEpubReaderView({
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
    this.isLandscape = false,
    this.customFonts = const [],
    this.navZoneActions = const [
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ],
    this.onZoneAction,
    this.showNavZoneDebugOverlay = false,
    this.initialLocatorJson,
    this.onLocatorChanged,
    this.onSelectionChanged,
    this.onSelectionCleared,
    this.onAnnotationActivated,
  });

  static void nextPage(GlobalKey<State<FoliateEpubReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._evaluate('window.nextPage()');
    }
  }

  static void previousPage(GlobalKey<State<FoliateEpubReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._evaluate('window.previousPage()');
    }
  }

  static void jumpToProgression(
    GlobalKey<State<FoliateEpubReaderView>> key,
    double progression,
  ) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._evaluate('window.jumpToFraction($progression)');
    }
  }

  static void jumpToLocator(
    GlobalKey<State<FoliateEpubReaderView>> key,
    String locatorJson,
  ) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      final cfi = extractCfi(locatorJson);
      if (cfi != null) {
        state._evaluate('window.jumpToLocator(${jsonEncode(cfi)})');
      }
    }
  }

  static Future<List<TocEntry>> loadTableOfContents(
    GlobalKey<State<FoliateEpubReaderView>> key,
  ) async {
    final state = key.currentState;
    if (state is! _FoliateEpubReaderViewState) return const [];
    return state._requestTableOfContents();
  }

  static void setDecorations(
    GlobalKey<State<FoliateEpubReaderView>> key,
    List<EpubDecoration> decorations,
  ) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      final entries = buildDecorationEntries(decorations);
      state._evaluate('window.setDecorations(${jsonEncode(entries)})');
    }
  }

  @override
  State<FoliateEpubReaderView> createState() => _FoliateEpubReaderViewState();
}

class _FoliateEpubReaderViewState extends State<FoliateEpubReaderView> {
  InAppWebViewController? _controller;
  Completer<List<TocEntry>>? _pendingToc;

  /// 每個 widget 實例獨立的快取子目錄路徑，供 `InternalStoragePathHandler` 使用。
  /// null 表示快取尚未完成或失敗。
  String? _bookCacheDir;

  /// 本實例的唯一 ID，用於區隔快取子目錄（避免螢幕轉場期間的競態）。
  late final String _instanceId = identityHashCode(this).toString();

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
        widget.onError('無法快取書籍檔案');
      }
    } catch (e) {
      if (!mounted) return;
      widget.onError('快取書籍失敗: $e');
    }
  }

  Uri _buildIndexUri() {
    final params = <String, String>{
      'prefs': jsonEncode(buildFoliatePreferencesMap(widget)),
      'fontFaceCss': buildFontFaceCss(customFonts: widget.customFonts),
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
    final completer = Completer<List<TocEntry>>();
    _pendingToc = completer;
    _evaluate('window.getTableOfContents()');
    return completer.future;
  }

  Future<void> _onWebViewCreated(InAppWebViewController controller) async {
    _controller = controller;
    controller.addJavaScriptHandler(
      handlerName: 'onPageRendered',
      callback: (args) {
        widget.onPageRendered();
        final writingModeStr =
            args.isNotEmpty ? args[0] as String : 'horizontal';
        widget.onLayoutResolved?.call(EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: writingModeStr == 'vertical'
              ? WritingMode.vertical
              : WritingMode.horizontal,
        ));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onError',
      callback: (args) {
        widget.onError(args.isNotEmpty ? args[0] as String : '未知錯誤');
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onLocatorChanged',
      callback: (args) {
        // 審查修正：main.js 目前以 `fraction ?? 0`／`location?.current ?? 0`／
        // `location?.total ?? 0` 保底，理論上不會送出 null；但改用 `as num?`
        // + `?? 0` 防禦性轉型，與本檔案其餘 handler（onPageRendered/onError/
        // onTableOfContentsReady 的 `args.isNotEmpty` 檢查）保持一致的防禦
        //風格，避免未來 main.js 若不慎移除 `?? 0` 保底時整個閱讀畫面直接
        // 因 TypeError 崩潰。
        widget.onLocatorChanged?.call(EpubPositionInfo(
          locatorJson: args.isNotEmpty ? args[0] as String : '',
          progression:
              (args.length > 1 ? args[1] as num? : null)?.toDouble() ?? 0.0,
          pageIndex:
              (args.length > 2 ? args[2] as num? : null)?.toInt() ?? 0,
          totalPages:
              (args.length > 3 ? args[3] as num? : null)?.toInt() ?? 0,
        ));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onTableOfContentsReady',
      callback: (args) {
        final completer = _pendingToc;
        _pendingToc = null;
        final json = args.isNotEmpty ? args[0] as String : '[]';
        completer?.complete(parseTableOfContents(json));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onSelectionChanged',
      callback: (args) {
        // 審查修正：同 onLocatorChanged，改用防禦性轉型取代直接強制轉型。
        num? argAt(int index) =>
            args.length > index ? args[index] as num? : null;
        widget.onSelectionChanged?.call(EpubSelectionInfo(
          locatorJson: args.isNotEmpty ? args[0] as String : '',
          progression: argAt(1)?.toDouble() ?? 0.0,
          rect: PercentRect(
            left: argAt(2)?.toDouble() ?? 0.0,
            top: argAt(3)?.toDouble() ?? 0.0,
            right: argAt(4)?.toDouble() ?? 0.0,
            bottom: argAt(5)?.toDouble() ?? 0.0,
          ),
        ));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onSelectionCleared',
      callback: (args) {
        widget.onSelectionCleared?.call();
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onAnnotationActivated',
      callback: (args) {
        widget.onAnnotationActivated?.call(args[0] as String);
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
    const fontsPrefix = '/assets/fonts/';
    if (path.startsWith(fontsPrefix)) {
      final relative = 'assets/fonts/${path.substring(fontsPrefix.length)}';
      final bytes = await loadFlutterFontAsset(relative);
      if (bytes == null) return null;
      return WebResourceResponse(contentType: 'font/ttf', data: bytes);
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
  void didUpdateWidget(covariant FoliateEpubReaderView oldWidget) {
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
              ],
            ),
          ),
          // 【診斷修正】見上方 _esCompatPolyfillJs 註解——在文件載入最早期
          // 注入 Object.groupBy/Map.groupBy/Array.prototype.at/
          // Array.prototype.findLastIndex 的 polyfill，避免舊版 WebView 開
          // 啟 EPUB 時因 epub.js/epubcfi.js/paginator.js 呼叫這些較新的 ES
          // 內建方法而拋出例外、導致畫面卡在載入指示器。
          initialUserScripts: UnmodifiableListView<UserScript>([
            UserScript(
              source: _esCompatPolyfillJs,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // epic-18-reader-device-qa Issue 39：見上方
            // _applyPreferencesQueueShimJs 註解。
            UserScript(
              source: _applyPreferencesQueueShimJs,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // epic-18-reader-device-qa Issue 33：見上方 _globalErrorCaptureJs
            // 註解。順序在 polyfill 之後無妨——兩者皆於 AT_DOCUMENT_START
            // 注入，實際執行順序不影響彼此（各自只是定義全局函式/監聽器）。
            UserScript(
              source: _globalErrorCaptureJs,
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
                      child: _NavZoneTapDetector(
                        key: Key('nav_zone_$index'),
                        onTap: () => widget.onZoneAction?.call(action),
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.white24))
                              : null,
                          alignment: Alignment.center,
                          child: widget.showNavZoneDebugOverlay
                              ? Text(
                                  _zoneActionLabel(action),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10),
                                )
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

  String _zoneActionLabel(ZoneAction action) {
    switch (action) {
      case ZoneAction.previousPage:
        return '上一頁';
      case ZoneAction.nextPage:
        return '下一頁';
      case ZoneAction.menu:
        return '選單';
      case ZoneAction.none:
        return '無動作';
    }
  }
}

/// 九宮格導覽熱區的單一格子，取代原本的 `GestureDetector(onTap: ...)`
/// （/diagnose 2026-07-27 真機診斷發現的根因修正）。
///
/// 根因：`GestureDetector` 的 `TapGestureRecognizer` 沒有時長上限——即使按住
/// 800ms 才放開，仍會被判定為一次有效的 tap。`InAppWebView`（Hybrid
/// Composition 平台視圖）與這個 `GestureDetector` 在同一個 Stack 位置競爭
/// 手勢競技場時，只要有任何 Flutter 側的手勢辨識器參與競爭，平台視圖自己
/// 的原生觸控轉發就會等待競技場裁定結果——`TapGestureRecognizer` 一路持有
/// 到放開才裁定為「是」，導致 `InAppWebView` 從頭到尾都沒收到這次觸控序列，
/// 長按選字的原生選取 UI（控點）完全不會出現（真機 `adb shell input
/// touchscreen swipe` 模擬長按已驗證：拿掉這層 `GestureDetector` 或改用本
/// 類別後，選字/控點/劃線皆恢復正常；只有 `HitTestBehavior` 從 opaque 改
/// translucent 並不夠，因為問題不在 hit-test 可見性、而在手勢競技場裁定）。
///
/// 改用 [Listener] 直接觀察原始 pointer 事件、自行判斷「是否為一次快速點擊」
/// （位移在 [_tapSlop] 內、耗時在 [_tapMaxDurationMs] 內），完全不註冊
/// `GestureRecognizer`、不參與手勢競技場，讓 `InAppWebView` 的原生觸控轉發
/// 不再被攔截。原本 `_hasActiveSelection` 這個只放行「已有選取範圍時的拖曳」
/// 的權宜旗標（Issue 8/ADR 0013）已不再需要——本類別從一開始就不會攔截任何
/// 非「快速點擊」手勢，選字/拖曳控點/翻頁滑動皆可直接穿透到 `InAppWebView`。
class _NavZoneTapDetector extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  const _NavZoneTapDetector({
    super.key,
    required this.onTap,
    required this.child,
  });

  @override
  State<_NavZoneTapDetector> createState() => _NavZoneTapDetectorState();
}

class _NavZoneTapDetectorState extends State<_NavZoneTapDetector> {
  Offset? _downPosition;
  int? _downTimeMs;

  static const _tapSlop = 18.0;
  static const _tapMaxDurationMs = 400;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _downPosition = event.position;
        _downTimeMs = DateTime.now().millisecondsSinceEpoch;
      },
      onPointerUp: (event) {
        final downPosition = _downPosition;
        final downTimeMs = _downTimeMs;
        if (downPosition == null || downTimeMs == null) return;
        final elapsed = DateTime.now().millisecondsSinceEpoch - downTimeMs;
        final distance = (event.position - downPosition).distance;
        if (elapsed <= _tapMaxDurationMs && distance <= _tapSlop) {
          widget.onTap();
        }
      },
      child: widget.child,
    );
  }
}
