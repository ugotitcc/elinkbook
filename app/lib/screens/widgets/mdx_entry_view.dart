// MDX 詞條顯示元件（epic-63 Issue 6a Task 7）。
//
// 詞條 HTML 一律在「JavaScript 關閉、禁止檔案與網路存取」的 WebView 內顯示：
// - 只載入我們自己傳入的字串，baseUrl 固定為 [kMdxBaseUrl]，頁內錨點由
//   WebView 原生處理。
// - `shouldOverrideUrlLoading` 只放行頁內錨點；`entry://`／`bword://` 轉成
//   詞條查詢（回傳給面板推入返回堆疊），其餘一律取消。
// - `shouldInterceptRequest` 除了 `data:` 初始文件外，任何請求都回 404 空內容，
//   永不回傳 `null`（回 `null` 會讓 WebView 走真實網路）。圖片與外部 CSS 的
//   實際回傳是 Issue 6b，這裡先留好呼叫點。
//
// 決策邏輯是靜態純函式，單元測試不必建 WebView。
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../dictionary/mdx_html_prepare.dart';
import '../../dictionary/mdx_link_policy.dart';

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
  });

  final String sourceId;

  /// 詞條原始 HTML（尚未補外殼；由 [prepareEntryHtml] 處理）。
  final String html;

  /// 使用者點了 `entry://`／`bword://` 連結時呼叫，參數是已解碼的詞條文字。
  final void Function(String word) onEntryLink;
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
  const MdxRequestDecision({required this.statusCode, this.body = ''});

  final int statusCode;

  /// 回應本文；本 Issue 恆為空字串。
  final String body;
}

/// 單一詞條的 WebView。同一時間畫面上最多一個（由面板控制）。
class MdxEntryView extends StatefulWidget {
  const MdxEntryView({
    super.key,
    required this.config,
    this.onWebViewCreated,
    this.onRequestIntercepted,
  });

  final MdxEntryViewConfig config;

  /// 取得底層 controller 的測試掛鉤（整合測試用來讀標題／觸發導覽）；
  /// 正式流程不需要。
  final void Function(InAppWebViewController controller)? onWebViewCreated;

  /// 測試掛鉤：回報每個被攔截的請求與決策（`data:` 初始文件不會回報）。
  /// 正式流程不需要。
  final void Function(Uri url, MdxRequestDecision decision)?
      onRequestIntercepted;

  /// 點擊連結時的處理方式：詞條連結取消導航並回傳詞；錨點放行；其餘取消。
  static MdxNavigationDecision decideNavigation(String url) {
    return switch (classifyLink(url)) {
      MdxEntryLink(:final word) => MdxNavigationDecision.cancel(word),
      MdxAnchorLink() => const MdxNavigationDecision.allow(),
      MdxBlockedLink() => const MdxNavigationDecision.cancel(),
    };
  }

  /// 任何資源請求都回 404 空本文，只有 `data:` 例外。
  ///
  /// `data:` 是 [InAppWebViewInitialData]（`loadDataWithBaseURL`）提供的初始
  /// 文件，必須交還 WebView 自己載入；若也回 404，整頁會變成「網頁無法使用」
  ///（Task 9 真機確認）。`data:` 不涉及網路或檔案存取，放行沒有安全疑慮。
  static MdxRequestDecision? decideRequest(String url) {
    if (url.startsWith('data:')) return null;
    return const MdxRequestDecision(statusCode: 404);
  }

  @override
  State<MdxEntryView> createState() => _MdxEntryViewState();
}

class _MdxEntryViewState extends State<MdxEntryView> {
  InAppWebViewController? _controller;

  @override
  void didUpdateWidget(covariant MdxEntryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 詞條連結跳到另一筆詞條時是同一個元件、新的 HTML：重新載入文件，
    // 不要沿用舊頁面（也不需要重建整個 WebView）。
    if (oldWidget.config.html != widget.config.html) {
      _loadHtml();
    }
  }

  Future<void> _loadHtml() async {
    await _controller?.loadData(
      data: prepareEntryHtml(widget.config.html),
      mimeType: 'text/html',
      encoding: 'utf8',
      baseUrl: WebUri(kMdxBaseUrl),
      historyUrl: WebUri(kMdxBaseUrl),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      key: const Key('mdx_entry_view'),
      initialData: InAppWebViewInitialData(
        data: prepareEntryHtml(widget.config.html),
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
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        widget.onWebViewCreated?.call(controller);
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString() ?? '';
        final decision = MdxEntryView.decideNavigation(url);
        final word = decision.entryWord;
        if (word != null) widget.config.onEntryLink(word);
        return decision.allow
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      shouldInterceptRequest: (controller, request) async {
        final decision = MdxEntryView.decideRequest(
          request.url.toString(),
        );
        // `data:` 初始文件交還 WebView；其他請求一律由我們回應，永不連網。
        if (decision == null) return null;
        widget.onRequestIntercepted?.call(request.url, decision);
        // statusCode 有值時 `headers`／`reasonPhrase` 也必須有值。
        return WebResourceResponse(
          contentType: 'text/plain',
          contentEncoding: 'utf-8',
          data: Uint8List(0),
          statusCode: decision.statusCode,
          reasonPhrase: 'Not Found',
          headers: const {'Content-Type': 'text/plain'},
        );
      },
    );
  }
}
