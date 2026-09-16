// app/lib/search/foliate_content_indexer.dart
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../library/models/book.dart';
import '../reader/foliate_bridge_codec.dart';
import '../reader/foliate_bridge_handlers.dart';
import '../reader/foliate_native_bridge.dart';
import '../reader/js_bridge_gateway.dart';
import '../reader/tts_segment_cfi.dart';
import 'content_indexer.dart';

/// Foliate 格式（EPUB／KF8／CBZ／TXT／MD，皆經 readest/foliate-js 單引擎）
/// 的內容擷取器（epic-10-search Issue 1，見 spec.md §3.2、ADR 0027 決策 2）。
///
/// 驅動一個獨立於一般閱讀畫面之外的 `HeadlessInAppWebView`，載入與
/// `FoliateReaderView` 相同的 `assets/foliate/index.html` 資源，帶
/// `mode=index` 旗標進入索引模式。重用既有
/// `cacheBookForServing()`／`InternalStoragePathHandler` 三件套讓 headless
/// webview 能讀到書籍內容（不是單純帶 URL query 就能運作，見 spec.md §3.2）。
///
/// 單書處理完畢、被中斷或例外時**無條件**執行 dispose + 刪除快取子目錄
/// （比照 `foliate_reader_view.dart` 既有 `dispose()` 清理邏輯），避免磁碟
/// 空間洩漏；下一本書重新建立全新實例與快取子目錄（ADR 0027 決策 3）。
class FoliateContentIndexer implements ContentIndexer {
  const FoliateContentIndexer();

  @override
  Stream<IndexedSegment> indexBook(
    Book book, {
    int? resumeFromChapter,
  }) async* {
    final instanceId = 'index-${book.id}';
    String? cacheDir;
    HeadlessInAppWebView? headlessWebView;
    InAppWebViewController? controller;

    try {
      final cachedPath = await cacheBookForServing(book.filePath, instanceId);
      if (cachedPath == null) {
        throw StateError('無法快取書籍檔案：${book.filePath}');
      }
      cacheDir = File(cachedPath).parent.path;

      final readyCompleter = Completer<void>();
      late final JsBridgeGateway gateway;

      // 【review-plan-issue-1.md I-2】章節擷取專用的獨立完成狀態——刻意不
      // 透過 JsBridgeGateway._pending（以 handler name 為單一插槽鍵）處理
      // 這個會在同一次 indexBook() 呼叫內對同一個 handler name 循環發出
      // 多次請求的場景：若某一章逾時後 Dart 端已提早發出下一章請求，稍後
      // 遲到抵達的舊章節回應會被 gateway 誤判成「下一章的回應」而完成
      // 錯誤的 completer，造成章節資料互相錯位污染（審查已用具體時序
      // 證實這個競態可重現，不是理論疑慮）。改由本類別自行維護「目前
      // 預期的章節索引」與對應 completer，callback 內比對章節索引，不符
      // 就直接捨棄，不透過 gateway 的通用配對機制。
      int? expectedSectionIndex;
      Completer<List<TtsSegmentCfi>>? sectionCompleter;

      void evaluate(String js) => controller?.evaluateJavascript(source: js);

      headlessWebView = HeadlessInAppWebView(
        // 明確指定非退化尺寸，見 plan-issue-1.md Global Constraints——
        // 套件預設值 Size(-1,-1) 對 foliate-js 的版面初始化語意不明確。
        initialSize: const Size(800, 1280),
        initialUrlRequest: URLRequest(url: WebUri.uri(_buildIndexUri(book))),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          useShouldInterceptRequest: true,
          webViewAssetLoader: WebViewAssetLoader(
            pathHandlers: [
              InternalStoragePathHandler(path: '/book/', directory: cacheDir),
            ],
          ),
        ),
        // 【review-plan-issue-1.md I-1】與 FoliateReaderView 共用同一套
        // ES 相容性 polyfill／全域錯誤捕捉腳本（見 Step 0）——headless
        // webview 載入的是同一份 main.js／view.js／epub.js，在較舊 Android
        // System WebView 上會遇到完全相同的 ES2021+ API 缺席風險；缺少
        // globalErrorCaptureJs 時，vendor 腳本在文件載入極早期拋出的例外
        // 不會回報 onError，readyCompleter 會乾等滿 30 秒逾時才失敗，而非
        // 立即得知真正原因。
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(
            source: esCompatPolyfillJs,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
          UserScript(
            source: globalErrorCaptureJs,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        shouldInterceptRequest: _shouldInterceptIndexRequest,
        onWebViewCreated: (c) {
          controller = c;
          gateway = JsBridgeGateway(
            evaluate: evaluate,
            registerHandler: (name, callback) =>
                c.addJavaScriptHandler(handlerName: name, callback: callback),
          );
          gateway.register<int>(
            handlerName: FoliateBridgeHandlers.onSectionCountReady,
            parse: (args) =>
                args.isNotEmpty ? (args[0] as num).toInt() : 0,
            fallback: 0,
          );
          // 【review-plan-issue-1.md I-2】onSegmentsForSectionReady 刻意
          // 不透過 gateway.register()，改直接註冊原生 handler 自行比對
          // 章節索引（見上方 expectedSectionIndex 註解）。
          c.addJavaScriptHandler(
            handlerName: FoliateBridgeHandlers.onSegmentsForSectionReady,
            callback: (args) {
              final receivedIndex =
                  args.isNotEmpty ? (args[0] as num).toInt() : -1;
              if (receivedIndex != expectedSectionIndex) {
                // 過期或不相關的回呼（例如上一章逾時後才遲到抵達），直接
                // 捨棄，不完成任何 completer。
                return null;
              }
              final completer = sectionCompleter;
              sectionCompleter = null;
              completer?.complete(
                parseTtsSegments(args.length > 1 ? args[1] as String : '[]'),
              );
              return null;
            },
          );
          c.addJavaScriptHandler(
            handlerName: FoliateBridgeHandlers.onPageRendered,
            callback: (args) {
              if (!readyCompleter.isCompleted) readyCompleter.complete();
              return null;
            },
          );
          c.addJavaScriptHandler(
            handlerName: FoliateBridgeHandlers.onError,
            callback: (args) {
              if (!readyCompleter.isCompleted) {
                readyCompleter.completeError(
                  StateError(args.isNotEmpty ? args[0] as String : '未知錯誤'),
                );
              }
              return null;
            },
          );
        },
      );

      await headlessWebView.run();
      await readyCompleter.future.timeout(const Duration(seconds: 30));

      // 【review-plan-issue-1.md I-4 延伸，同一種「靜默吞掉錯誤」風險】
      // 若沿用 JsBridgeGateway.request() 內建的 timeout 參數，逾時後會
      // 靜默回退 fallback（0），讓下方 for 迴圈直接跑 0 次、整本書被誤判
      // 為「已完成」寫入 0 筆資料且永遠不會重試。改為不傳 gateway 的
      // timeout 參數，外層用 .timeout()＋onTimeout 主動 throw，取代靜默
      // 回退的既有行為。
      final sectionCount = await gateway
          .request<int>(
            jsCall: 'window.getSectionCount()',
            handlerName: FoliateBridgeHandlers.onSectionCountReady,
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () =>
                throw TimeoutException('window.getSectionCount() 逾時'),
          );

      final startSection = resumeFromChapter ?? 0;
      for (var sectionIndex = startSection;
          sectionIndex < sectionCount;
          sectionIndex++) {
        expectedSectionIndex = sectionIndex;
        final completer = Completer<List<TtsSegmentCfi>>();
        sectionCompleter = completer;
        evaluate('window.buildSegmentsForSection($sectionIndex)');
        // 【review-plan-issue-1.md I-2】逾時直接拋例外中斷整本書的處理
        // （由 ContentIndexingScheduler 既有的 catch 區塊標記
        // status='error'，下次排程可重新嘗試整本書），不可靜默回退空
        // 清單——那會讓這個章節的內容永久性、無聲地漏索引，且不會有任何
        // 錯誤訊號可供排查。逾時視窗放寬到 30 秒（原 15 秒對低階電子紙
        // 裝置的 headless WebView 解析大型章節可能過於嚴苛，見審查建議）。
        final segments = await completer.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            sectionCompleter = null;
            throw TimeoutException(
                'window.buildSegmentsForSection($sectionIndex) 逾時');
          },
        );
        for (final segment in segments) {
          if (segment.cfi.isEmpty || segment.text.trim().isEmpty) continue;
          yield IndexedSegment(
            chapterIndex: sectionIndex,
            locator: segment.cfi,
            rawText: segment.text,
          );
        }
      }
    } finally {
      await headlessWebView?.dispose();
      if (cacheDir != null) {
        final dir = Directory(cacheDir);
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      }
    }
  }

  Uri _buildIndexUri(Book book) {
    return Uri.https(
      'appassets.androidplatform.net',
      '/assets/foliate/index.html',
      {
        'bookFileName': 'current.${cacheFileExtension(book.filePath)}',
        'mode': 'index',
      },
    );
  }

  /// 索引模式只需要能載入 `assets/foliate/` 底下的靜態檔案（`index.html`／
  /// `main.js`／`view.js` 等），不需要字型攔截（索引模式不渲染任何可視文字，
  /// `prefs`/`fontFaceCss` 查詢參數皆未帶入，預設空值不會觸發字型請求）——
  /// 比照 `foliate_reader_view.dart` `_shouldInterceptRequest()` 精簡版。
  static Future<WebResourceResponse?> _shouldInterceptIndexRequest(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) async {
    final path = request.url.path;
    const foliateAssetsPrefix = '/assets/foliate/';
    if (path.startsWith(foliateAssetsPrefix)) {
      final relative = 'foliate/${path.substring(foliateAssetsPrefix.length)}';
      final bytes = await loadAndroidAsset(relative);
      if (bytes == null) return null;
      final contentType =
          path.endsWith('.js') ? 'text/javascript' : 'text/html';
      return WebResourceResponse(contentType: contentType, data: bytes);
    }
    return null;
  }
}
