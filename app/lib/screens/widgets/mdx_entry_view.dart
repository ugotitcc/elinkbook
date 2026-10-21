// MDX 詞條顯示元件（epic-63 Issue 6a Task 7 / Issue 6b Task 5）。
//
// 詞條 HTML 一律在「JavaScript 關閉、禁止檔案與網路存取」的 WebView 內顯示：
// - 只載入我們自己傳入的字串，baseUrl 固定為 [kMdxBaseUrl]，頁內錨點由
//   WebView 原生處理。
// - `shouldOverrideUrlLoading` 只放行頁內錨點；`entry://`／`bword://` 轉成
//   詞條查詢（回傳給面板推入返回堆疊），其餘一律取消。
// - `shouldInterceptRequest` 回應由 `decideRequest` 決定：`data:` 初始文件交還
//   WebView；屬 [kMdxBaseUrl] 且解析成功的 MDD 資源回傳 200 二進位內容；
//   其餘請求一律回傳 404，永不回傳 `null`（回 `null` 會讓 WebView 走真實網路）。
//   外部 CSS 已在上游（Issue 6b Task 2）內聯，配色覆寫由 [prepareEntryHtml] 注入。
// - 只有主框架且有使用者手勢的導覽才會帶出詞條查詢；`Safe Browsing` 關閉。
//   `blockNetworkLoads` 未啟用：未能在真機驗證它不影響 `data:` 初始文件與
//   攔截回應，留待 Task 8 真機驗證確認（審查 I-7）。
//
// 決策邏輯是靜態純函式，單元測試不必建 WebView。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../dictionary/mdx_html_prepare.dart';
import '../../dictionary/mdx_link_policy.dart';
import '../../dictionary/mdx_resource.dart';
import '../../dictionary/mdx_theme_override.dart';

/// 建立 MDX 詞條顯示元件的函式；面板用注入的版本測試版面與返回堆疊。
typedef MdxEntryViewBuilder = Widget Function(
  BuildContext context,
  MdxEntryViewConfig config,
);

/// 一筆要顯示的 MDX 詞條。
class MdxEntryViewConfig {
  const MdxEntryViewConfig({
    required this.sourceId,
    required this.html,
    required this.onEntryLink,
    this.resolveResource,
    this.colors,
  });

  final String sourceId;

  /// 詞條原始 HTML（尚未補外殼；由 [prepareEntryHtml] 處理）。
  final String html;

  /// 使用者點了 `entry://`／`bword://` 連結時呼叫，參數是已解碼的詞條文字。
  final void Function(String word) onEntryLink;

  /// 讀取此詞條所屬字典資源（如圖片）的回呼；`null` 時資源請求回傳 404。
  final Future<MdxResource?> Function(String url)? resolveResource;

  /// 詞條在特定主題模式下的覆寫色彩配置；`null` 表示使用原生樣式。
  final MdxColors? colors;
}

/// `shouldOverrideUrlLoading` 的決策結果。
class MdxNavigationDecision {
  const MdxNavigationDecision.allow()
      : allow = true,
        entryWord = null;

  const MdxNavigationDecision.cancel([this.entryWord]) : allow = false;

  /// `true` 表示交給 WebView 導航（頁內錨點）。
  final bool allow;

  /// 要查詢的詞條文字；只有 `entry://`／`bword://` 才有值。
  final String? entryWord;
}

/// `shouldInterceptRequest` 的決策結果。
class MdxRequestDecision {
  const MdxRequestDecision({
    required this.statusCode,
    this.body = '',
    this.bytes,
    this.contentType = 'text/plain',
  });

  final int statusCode;

  /// 回應本文；本 Issue 恆為空字串。
  final String body;

  /// 二進位資源資料（如圖片）；404 時為 null。
  final Uint8List? bytes;

  /// MIME 內容型別（例如 `image/png`），預設 `text/plain`。
  final String contentType;
}

/// 單一詞條的 WebView。同一時間畫面上最多一個（由面板控制）。
class MdxEntryView extends StatefulWidget {
  const MdxEntryView({
    super.key,
    required this.config,
    this.onWebViewCreated,
    this.onRequestIntercepted,
    @visibleForTesting this.onLoadHtml,
  });

  final MdxEntryViewConfig config;

  /// 取得底層 controller 的測試掛鉤（整合測試用來讀標題／觸發導覽）；
  /// 正式流程不需要。
  final void Function(InAppWebViewController controller)? onWebViewCreated;

  /// 測試掛鉤：回報每個被攔截的請求與決策（`data:` 初始文件不會回報）。
  /// 正式流程不需要。
  final void Function(Uri url, MdxRequestDecision decision)?
      onRequestIntercepted;

  /// 測試掛鉤：當 [_loadHtml] 被呼叫時觸發（用來驗證組態變更觸發重載）。
  /// 正式流程不需要。
  final VoidCallback? onLoadHtml;

  /// WebView 要主動搶下的手勢。
  ///
  /// 詞條放在可拖曳關閉的底部面板內，面板的垂直拖曳辨識器會在手勢競技場
  /// 贏過原生 WebView，WebView 永遠收不到垂直拖曳、長詞條捲不動。
  /// `InAppWebView` 只會替 `gestureRecognizers` 內的辨識器搶手勢，所以這裡
  /// 加入垂直拖曳；點擊與長按不在集合內，仍照原本的方式送進 WebView
  /// （`entry://` 連結與錨點的點擊不受影響），面板把手與標題列不在 WebView
  /// 範圍內，照常可以拖曳或關閉。
  static final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers = {
    Factory<VerticalDragGestureRecognizer>(VerticalDragGestureRecognizer.new),
  };

  /// 導覽時的處理方式：詞條連結取消導航並回傳詞；錨點放行；其餘取消。
  ///
  /// 只有「主框架」且「使用者真的點了」的導覽才可能帶出詞條或放行錨點：
  /// - [isForMainFrame] 為 false（`<iframe src="entry://x">` 這類子框架）一律取消，
  ///   不回傳詞條。
  /// - [hasGesture] 為 false（`<meta refresh>` 之類沒有使用者操作的跳轉）時，
  ///   詞條連結取消且不回傳詞條。平台沒提供（null，例如 iOS）時視為通過。
  /// 頁內錨點只要在主框架就放行（它不會觸發查詢）。
  static MdxNavigationDecision decideNavigation(
    String url, {
    bool isForMainFrame = true,
    bool? hasGesture,
  }) {
    if (!isForMainFrame) return const MdxNavigationDecision.cancel();
    return switch (classifyLink(url)) {
      MdxEntryLink() when hasGesture == false =>
        const MdxNavigationDecision.cancel(),
      MdxEntryLink(:final word) => MdxNavigationDecision.cancel(word),
      MdxAnchorLink() => const MdxNavigationDecision.allow(),
      MdxBlockedLink() => const MdxNavigationDecision.cancel(),
    };
  }

  /// 攔截資源請求的決策：`data:` 放行；屬 [kMdxBaseUrl] 的資源請求以
  /// [resolveResource] 解析，成功回傳 200，其餘一律 404 空內容。
  ///
  /// `data:` 是 [InAppWebViewInitialData]（`loadDataWithBaseURL`）提供的初始
  /// 文件，必須交還 WebView 自己載入；若也回 404，整頁會變成「網頁無法使用」
  ///（Task 9 真機確認）。`data:` 不涉及網路或檔案存取，放行沒有安全疑慮。
  static Future<MdxRequestDecision?> decideRequest(
    String url, {
    Future<MdxResource?> Function(String url)? resolveResource,
  }) async {
    if (url.startsWith('data:')) return null;
    if (!url.startsWith(kMdxBaseUrl)) {
      return const MdxRequestDecision(statusCode: 404);
    }
    if (resolveResource == null) {
      return const MdxRequestDecision(statusCode: 404);
    }
    try {
      final resource = await resolveResource(url);
      if (resource == null) {
        return const MdxRequestDecision(statusCode: 404);
      }
      return MdxRequestDecision(
        statusCode: 200,
        bytes: resource.bytes,
        contentType: resource.contentType,
      );
    } catch (_) {
      return const MdxRequestDecision(statusCode: 404);
    }
  }

  /// 將 [MdxRequestDecision] 轉換為 WebView 的 [WebResourceResponse]。
  ///
  /// `decision` 為 `null` 時回傳 `null`（放行請求，由 WebView 自行載入）。
  /// 200 回應時 [WebResourceResponse.contentEncoding] 必須為 `null`，二進位
  /// 資料（如圖片）若帶 `utf-8` 會讓部分 WebView 拒絕渲染。
  /// 404 回應維持現有格式（`text/plain`、`utf-8`）。
  static WebResourceResponse? responseFor(MdxRequestDecision? decision) {
    if (decision == null) return null;
    if (decision.statusCode == 200) {
      return WebResourceResponse(
        contentType: decision.contentType,
        contentEncoding: null,
        data: decision.bytes ?? Uint8List(0),
        statusCode: 200,
        reasonPhrase: 'OK',
        headers: {'Content-Type': decision.contentType},
      );
    }
    return WebResourceResponse(
      contentType: 'text/plain',
      contentEncoding: 'utf-8',
      data: Uint8List(0),
      statusCode: decision.statusCode,
      reasonPhrase: 'Not Found',
      headers: const {'Content-Type': 'text/plain'},
    );
  }

  @override
  State<MdxEntryView> createState() => _MdxEntryViewState();
}

class _MdxEntryViewState extends State<MdxEntryView> {
  InAppWebViewController? _controller;

  @override
  void didUpdateWidget(covariant MdxEntryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 詞條連結跳到另一筆詞條時是同一個元件、新的 HTML；或主題／E-Ink 模式
    // 切換時色彩覆寫改變：重新載入文件，不要沿用舊頁面。
    if (oldWidget.config.html != widget.config.html ||
        oldWidget.config.colors != widget.config.colors) {
      _loadHtml();
    }
  }

  Future<void> _loadHtml() async {
    widget.onLoadHtml?.call();
    final colors = widget.config.colors;
    final overrideCss = colors == null ? null : mdxOverrideCss(colors);
    await _controller?.loadData(
      data: prepareEntryHtml(widget.config.html, overrideCss: overrideCss),
      mimeType: 'text/html',
      encoding: 'utf8',
      baseUrl: WebUri(kMdxBaseUrl),
      historyUrl: WebUri(kMdxBaseUrl),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.config.colors;
    final overrideCss = colors == null ? null : mdxOverrideCss(colors);
    return InAppWebView(
      key: const Key('mdx_entry_view'),
      gestureRecognizers: MdxEntryView.gestureRecognizers,
      initialData: InAppWebViewInitialData(
        data: prepareEntryHtml(widget.config.html, overrideCss: overrideCss),
        mimeType: 'text/html',
        encoding: 'utf8',
        baseUrl: WebUri(kMdxBaseUrl),
        historyUrl: WebUri(kMdxBaseUrl),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: false,
        allowFileAccess: false,
        allowContentAccess: false,
        cacheEnabled: false,
        useShouldOverrideUrlLoading: true,
        useShouldInterceptRequest: true,
        // 不讓 Safe Browsing 連 Google 檢查網址（審查 I-7）。
        safeBrowsingEnabled: false,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        widget.onWebViewCreated?.call(controller);
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString() ?? '';
        final decision = MdxEntryView.decideNavigation(
          url,
          isForMainFrame: navigationAction.isForMainFrame,
          hasGesture: navigationAction.hasGesture,
        );
        final word = decision.entryWord;
        if (word != null) widget.config.onEntryLink(word);
        return decision.allow
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      shouldInterceptRequest: (controller, request) async {
        final decision = await MdxEntryView.decideRequest(
          request.url.toString(),
          resolveResource: widget.config.resolveResource,
        );
        // `data:` 初始文件交還 WebView；其他請求一律由我們回應，永不連網。
        if (decision == null) return null;
        widget.onRequestIntercepted?.call(request.url, decision);
        return MdxEntryView.responseFor(decision);
      },
    );
  }
}
