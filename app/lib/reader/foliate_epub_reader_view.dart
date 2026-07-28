import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app_font.dart';
import 'column_mode.dart';
import 'epub_decoration.dart';
import 'epub_position_info.dart';
import 'epub_selection_info.dart';
import 'epub_text_align.dart';
import 'foliate_bridge_codec.dart';
import 'foliate_native_bridge.dart';
import 'page_turn_mode.dart';
import 'percent_rect.dart';
import 'toc_entry.dart';
import 'writing_mode.dart';
import 'zone_action.dart';

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
  if (view.fontFamily != null) map['fontFamily'] = view.fontFamily!.familyName;
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
      oldView.showFooter != newView.showFooter;
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
  final AppFont? fontFamily;
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

  late final Uri _initialIndexUri = _buildIndexUri();

  Uri _buildIndexUri() {
    final params = <String, String>{
      'prefs': jsonEncode(buildFoliatePreferencesMap(widget)),
      'fontFaceCss': buildFontFaceCss(),
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
    if (path == '/book/current.epub') {
      final bytes = await loadBookBytes(widget.filePath);
      if (bytes == null) return null;
      return WebResourceResponse(
          contentType: 'application/epub+zip', data: bytes);
    }
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
    detachReaderView();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri.uri(_initialIndexUri)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useShouldInterceptRequest: true,
          ),
          onWebViewCreated: _onWebViewCreated,
          shouldInterceptRequest: _shouldInterceptRequest,
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
