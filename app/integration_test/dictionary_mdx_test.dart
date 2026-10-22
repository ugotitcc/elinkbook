// epic-63 Issue 6a Task 9 / Issue 6b Task 8：MDX 詞條 WebView 的真機驗證。
//
// 直接用 `html.mdx` 與 `images.mdx`／`images.mdd` fixture 開啟 [MdxReader]，
// 把詞條 HTML 交給 [MdxEntryView]，不經檔案選擇器與字典匯入流程。驗證重點是
// WebView 層級的安全性、導覽、圖片攔截與配色行為：JavaScript 不執行、對外與
// 缺檔請求被攔成 404、`entry://` 可點可返回、錨點（含 `entry://#錨點` 改寫後）
// 可跳轉、`.mdd` 圖片（含空白與子目錄路徑）回 200 並渲染、深色與 E-Ink 覆寫
// 樣式注入後可讀，以及 `blockNetworkLoads: true` 下初始文件與攔截圖片皆正常。
//
// 這個測試刻意只觀察「原生端看得到」的狀態（`getTitle`、`getScrollY`、
// `getUrl`、`getContentHeight`、`getSettings` 與攔截回呼），不呼叫
// `evaluateJavascript`：頁面 JavaScript 關閉後，Android WebView 連
// `evaluateJavascript` 都不執行（Task 9 真機確認），用 JS 讀 DOM 會讓測試
// 驗證到錯誤的前提。
import 'dart:async';
import 'dart:io';

import 'package:elinkbook/dictionary/dictionary_service.dart';
import 'package:elinkbook/dictionary/mdx_html_prepare.dart';
import 'package:elinkbook/dictionary/mdx_link_policy.dart';
import 'package:elinkbook/dictionary/mdx_theme_override.dart';
import 'package:elinkbook/dictionary/models/dictionary_entry.dart';
import 'package:elinkbook/dictionary/models/lookup_request.dart';
import 'package:elinkbook/dictionary/models/lookup_result.dart';
import 'package:elinkbook/dictionary/storage/mdx_reader.dart';
import 'package:elinkbook/screens/widgets/dictionary_lookup_sheet.dart';
import 'package:elinkbook/screens/widgets/eb_sheet_shell.dart';
import 'package:elinkbook/screens/widgets/mdx_entry_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/pump_localized_widget.dart';

/// fixture 內 `apple` 詞條的 `<title>`；頁面 JavaScript 若執行會改成 `JS_RAN`。
const String _appleTitle = 'MDX 詞條 apple';
const String _bananaTitle = 'MDX 詞條 banana';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 輪詢原生 WebView 狀態，直到 [until] 為真或逾時。
///
/// 頁面載入是非同步的，剛開始 `getTitle` 會是空字串、`getScrollY` 可能是 0；
/// 整合測試跑在 live binding，等待期間要讓畫面有機會重繪。
Future<T> _waitFor<T>(
  WidgetTester tester,
  Future<T?> Function() read,
  bool Function(T value) until,
  String description, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  T? last;
  while (DateTime.now().isBefore(deadline)) {
    final value = await read();
    if (value != null) {
      last = value;
      if (until(value)) return value;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
  fail('等待逾時：$description（最後觀察值：$last）');
}

/// 等到頁面標題變成 [title]（代表該詞條的文件已載入完成）。
Future<void> _waitForTitle(
  WidgetTester tester,
  InAppWebViewController controller,
  String title,
) async {
  await _waitFor<String>(
    tester,
    controller.getTitle,
    (value) => value == title,
    '頁面標題「$title」',
  );
}

/// 以 WebView 高度的比例點擊頁面，用來點 fixture 安排的 20vh 區塊連結。
///
/// 座標點擊才會觸發 `shouldOverrideUrlLoading`；程式呼叫 `loadUrl` 不會。
Future<void> _tapAtHeightFraction(WidgetTester tester, double fraction) async {
  final rect = tester.getRect(find.byType(MdxEntryView));
  await tester.tapAt(Offset(rect.center.dx, rect.top + rect.height * fraction));
  await tester.pump();
}

/// 測試用宿主：保存詞條堆疊，模擬面板的「點交叉參照 → 返回上一筆」。
class _MdxHarness extends StatefulWidget {
  const _MdxHarness({
    required this.entries,
    required this.onCreated,
    this.onRequestIntercepted,
  });

  final Map<String, String> entries;
  final void Function(InAppWebViewController controller) onCreated;
  final void Function(Uri url, MdxRequestDecision decision)?
      onRequestIntercepted;

  @override
  State<_MdxHarness> createState() => _MdxHarnessState();
}

class _MdxHarnessState extends State<_MdxHarness> {
  final List<String> _stack = ['apple'];

  String get _word => _stack.last;

  void _open(String word) {
    if (!widget.entries.containsKey(word)) return;
    setState(() => _stack.add(word));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MdxEntryView(
        config: MdxEntryViewConfig(
          sourceId: 'fixture',
          html: widget.entries[_word]!,
          onEntryLink: _open,
        ),
        onWebViewCreated: widget.onCreated,
        onRequestIntercepted: widget.onRequestIntercepted,
      ),
      floatingActionButton: _stack.length > 1
          ? FloatingActionButton(
              key: const Key('mdx_test_back'),
              onPressed: () => setState(() => _stack.removeLast()),
              child: const Icon(Icons.arrow_back),
            )
          : null,
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String mdxPath;
  late String imagesMdxPath;
  late String imagesMddPath;
  late MdxReader imagesReader;
  late String picHtml;
  late Map<String, String> entries;

  setUpAll(() async {
    mdxPath = await _stageAssetAsFile(
      'test/fixtures/mdx/html.mdx',
      'dictionary_mdx_test.mdx',
    );
    final reader = await MdxReader.open(mdxPath);
    entries = {
      'apple': (await reader.lookupAll('apple')).first,
      'banana': (await reader.lookupAll('banana')).first,
    };
    await reader.close();

    imagesMdxPath = await _stageAssetAsFile(
      'test/fixtures/mdx/images.mdx',
      'images.mdx',
    );
    imagesMddPath = await _stageAssetAsFile(
      'test/fixtures/mdx/images.mdd',
      'images.mdd',
    );
    imagesReader = await MdxReader.open(imagesMdxPath);
    picHtml = (await imagesReader.lookupAll('pic')).first;
  });

  tearDownAll(() async {
    await imagesReader.close();
    for (final path in [mdxPath, imagesMdxPath, imagesMddPath]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  });

  /// 建好畫面並取得 controller。
  Future<InAppWebViewController> pumpEntry(
    WidgetTester tester, {
    void Function(Uri url, MdxRequestDecision decision)?
        onRequestIntercepted,
  }) async {
    final created = Completer<InAppWebViewController>();
    await pumpLocalizedWidget(
      tester,
      _MdxHarness(
        entries: entries,
        onCreated: (controller) {
          if (!created.isCompleted) created.complete(controller);
        },
        onRequestIntercepted: onRequestIntercepted,
      ),
    );
    return created.future.timeout(const Duration(seconds: 15));
  }

  testWidgets('MDX 詞條在 WebView 顯示，且頁面 JavaScript 不執行', (tester) async {
    final controller = await pumpEntry(tester);
    await _waitForTitle(tester, controller, _appleTitle);

    // fixture 的 <script> 第一句就是 `document.title="JS_RAN"`。標題停在
    // `<title>` 的原值，代表頁面 JavaScript 完全沒有執行。先等一拍再確認，
    // 避免只抓到腳本執行前的短暫原值。
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await tester.pump();
    expect(await controller.getTitle(), _appleTitle);
  });

  testWidgets('對外網路請求被攔截成 404，不會真的連網', (tester) async {
    final probe = Completer<MdxRequestDecision>();
    final controller = await pumpEntry(
      tester,
      onRequestIntercepted: (url, decision) {
        if (url.toString() == 'https://example.com/mdx-probe.png' &&
            !probe.isCompleted) {
          probe.complete(decision);
        }
      },
    );
    await _waitForTitle(tester, controller, _appleTitle);

    final decision = await probe.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => fail('詞條內的遠端圖片請求沒有被攔截'),
    );
    expect(decision.statusCode, 404);

    // 文件本身仍是虛擬來源，沒有被導到真實網址。
    expect((await controller.getUrl()).toString(), kMdxBaseUrl);
  });

  testWidgets('entry:// 交叉參照可點，返回後回到上一筆詞條', (tester) async {
    final controller = await pumpEntry(tester);
    await _waitForTitle(tester, controller, _appleTitle);

    // fixture 的第一個區塊就是 `entry://banana`（高度 20vh）。
    await _tapAtHeightFraction(tester, 0.1);
    await _waitForTitle(tester, controller, _bananaTitle);

    await tester.tap(find.byKey(const Key('mdx_test_back')));
    await tester.pump();
    await _waitForTitle(tester, controller, _appleTitle);
  });

  testWidgets('#錨點與 entry://#錨點（改寫後）都能跳轉', (tester) async {
    final controller = await pumpEntry(tester);
    await _waitForTitle(tester, controller, _appleTitle);

    // 初始位置在頁首。
    await _waitFor<int>(
      tester,
      controller.getScrollY,
      (value) => value == 0,
      '頁面回到頁首',
    );

    // 第二個區塊是純錨點 `#n1`，目標在頁面下方（3000px 空白之後）。
    await _tapAtHeightFraction(tester, 0.3);
    await _waitFor<int>(
      tester,
      controller.getScrollY,
      (value) => value > 0,
      '`#n1` 錨點跳轉',
    );

    // 回到頁首，再點第三個區塊：`entry://#n1` 應被改寫成純錨點，
    // 因此同樣只是頁內捲動，而不是被取消或開啟新頁。
    await controller.scrollTo(x: 0, y: 0);
    await _waitFor<int>(
      tester,
      controller.getScrollY,
      (value) => value == 0,
      '頁面回到頁首',
    );
    await _tapAtHeightFraction(tester, 0.5);
    await _waitFor<int>(
      tester,
      controller.getScrollY,
      (value) => value > 0,
      '`entry://#n1` 改寫後的錨點跳轉',
    );
  });

  testWidgets('長詞條放在可拖曳的底部面板內，垂直拖曳會捲動詞條而不是關面板', (tester) async {
    // 200 段文字，內容遠高於面板。
    final longHtml =
        '<html><head><meta charset="utf-8"><title>long</title></head><body>'
        '${List.generate(200, (i) => '<p>第 $i 段　長詞條測試內容</p>').join()}'
        '</body></html>';
    final controllerReady = Completer<InAppWebViewController>();
    final response = Future.value(
      LookupCompleted(
        result: LookupResult(
          request: const LookupRequest('詞'),
          outcomes: [
            ProviderOutcome(
              providerId: 'long',
              displayName: '長字典',
              status: OutcomeStatus.found,
              entries: [
                DictionaryEntry(
                  sourceId: 'long',
                  headword: '詞',
                  body: longHtml,
                  bodyKind: EntryBodyKind.html,
                ),
              ],
            ),
          ],
        ),
        hasEnabledDictionary: true,
      ),
    );

    await pumpLocalizedWidget(
      tester,
      const Scaffold(body: SizedBox.expand()),
    );
    // 真實的底部面板（可拖曳關閉）＋真實的 DictionaryLookupSheet，
    // 詞條元件用預設的 MdxEntryView（只多接一個取得 controller 的掛鉤）。
    unawaited(
      EBSheetShell.show<void>(
        tester.element(find.byType(Scaffold)),
        title: '查詢',
        builder: (context) => DictionaryLookupSheet(
          selectedText: '詞',
          response: response,
          isEinkMode: false,
          mdxEntryViewBuilder: (context, config) => MdxEntryView(
            config: config,
            onWebViewCreated: (controller) {
              if (!controllerReady.isCompleted) {
                controllerReady.complete(controller);
              }
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final controller =
        await controllerReady.future.timeout(const Duration(seconds: 15));
    await _waitForTitle(tester, controller, 'long');
    await _waitFor<int>(
      tester,
      controller.getContentHeight,
      (value) => value > 500,
      '長詞條內容高度已排版完成',
    );
    await _waitFor<int>(
      tester,
      controller.getScrollY,
      (value) => value == 0,
      '頁面在頁首',
    );

    // 在 WebView 中央向上拖曳 400 像素。
    await tester.drag(find.byType(MdxEntryView), const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 300));

    final scrollY = await _waitFor<int>(
      tester,
      controller.getScrollY,
      (value) => value > 0,
      '垂直拖曳後詞條捲動（scrollY > 0）',
    );
    debugPrint('垂直拖曳後 scrollY = $scrollY');
    // 面板沒有被拖曳關掉。
    expect(find.byType(DictionaryLookupSheet), findsOneWidget);
    expect(find.byType(MdxEntryView), findsOneWidget);
  });

  testWidgets('圖片在 JavaScript 關閉下顯示', (tester) async {
    final spaceImage = Completer<MdxRequestDecision>();
    final created = Completer<InAppWebViewController>();

    await pumpLocalizedWidget(
      tester,
      Scaffold(
        body: MdxEntryView(
          config: MdxEntryViewConfig(
            sourceId: 'images',
            html: picHtml,
            onEntryLink: (_) {},
            resolveResource: imagesReader.readResource,
          ),
          onWebViewCreated: (controller) {
            if (!created.isCompleted) created.complete(controller);
          },
          onRequestIntercepted: (url, decision) {
            if (url.toString() == 'https://dict.local/pic/a%20b.png' &&
                !spaceImage.isCompleted) {
              spaceImage.complete(decision);
            }
          },
        ),
      ),
    );

    final controller =
        await created.future.timeout(const Duration(seconds: 15));
    final settings = await controller.getSettings();
    expect(settings?.javaScriptEnabled, isFalse);

    final decision = await spaceImage.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => fail('pic/a b.png 沒有被攔截'),
    );
    expect(decision.statusCode, 200);
    expect(decision.contentType, 'image/png');
    expect(decision.bytes, isNotNull);
    expect(
      decision.bytes!.sublist(0, 8),
      [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
    );
  });

  testWidgets('路徑帶空白與子目錄的圖片各回 200', (tester) async {
    final intercepted = <String, MdxRequestDecision>{};
    final created = Completer<InAppWebViewController>();

    await pumpLocalizedWidget(
      tester,
      Scaffold(
        body: MdxEntryView(
          config: MdxEntryViewConfig(
            sourceId: 'images',
            html: picHtml,
            onEntryLink: (_) {},
            resolveResource: imagesReader.readResource,
          ),
          onWebViewCreated: (controller) {
            if (!created.isCompleted) created.complete(controller);
          },
          onRequestIntercepted: (url, decision) {
            intercepted[url.toString()] = decision;
          },
        ),
      ),
    );

    await created.future.timeout(const Duration(seconds: 15));
    await _waitFor<bool>(
      tester,
      () async =>
          intercepted['https://dict.local/pic/a%20b.png'] != null &&
          intercepted['https://dict.local/pic/sub/c.png'] != null,
      (ready) => ready,
      '空白路徑與子目錄圖片皆被攔截',
    );

    final spaceDecision = intercepted['https://dict.local/pic/a%20b.png']!;
    final subDecision = intercepted['https://dict.local/pic/sub/c.png']!;
    expect(spaceDecision.statusCode, 200);
    expect(spaceDecision.contentType, 'image/png');
    expect(subDecision.statusCode, 200);
    expect(subDecision.contentType, 'image/png');
  });

  testWidgets('找不到的圖片與 favicon 回 404，不連網', (tester) async {
    final intercepted = <String, MdxRequestDecision>{};
    final created = Completer<InAppWebViewController>();
    const htmlWithMissingAndFavicon =
        '<html><head><title>missing-test</title>'
        '<link rel="icon" href="/favicon.ico">'
        '</head><body>'
        '<img src="pic/missing.png">'
        '<img src="/favicon.ico">'
        '</body></html>';

    await pumpLocalizedWidget(
      tester,
      Scaffold(
        body: MdxEntryView(
          config: MdxEntryViewConfig(
            sourceId: 'images',
            html: htmlWithMissingAndFavicon,
            onEntryLink: (_) {},
            resolveResource: imagesReader.readResource,
          ),
          onWebViewCreated: (controller) {
            if (!created.isCompleted) created.complete(controller);
          },
          onRequestIntercepted: (url, decision) {
            intercepted[url.toString()] = decision;
          },
        ),
      ),
    );

    final controller =
        await created.future.timeout(const Duration(seconds: 15));
    await _waitForTitle(tester, controller, 'missing-test');
    await _waitFor<bool>(
      tester,
      () async =>
          intercepted['https://dict.local/pic/missing.png'] != null &&
          intercepted['https://dict.local/favicon.ico'] != null,
      (ready) => ready,
      '找不到的圖片與 favicon.ico 皆被攔截',
    );

    final missingDecision = intercepted['https://dict.local/pic/missing.png']!;
    final faviconDecision = intercepted['https://dict.local/favicon.ico']!;
    expect(missingDecision.statusCode, 404);
    expect(missingDecision.bytes, isNull);
    expect(faviconDecision.statusCode, 404);
    expect(faviconDecision.bytes, isNull);
    expect((await controller.getUrl()).toString(), kMdxBaseUrl);
  });

  testWidgets('深色與 E-Ink 下可讀：colors 注入後標題正常且覆寫樣式存在於載入文件',
      (tester) async {
    final darkColors = mdxColorsFor(
      isEinkMode: false,
      brightness: Brightness.dark,
      scheme: ThemeData.dark().colorScheme,
    )!;
    final einkColors = mdxColorsFor(
      isEinkMode: true,
      brightness: Brightness.light,
      scheme: ThemeData.light().colorScheme,
    )!;

    final created = Completer<InAppWebViewController>();
    await pumpLocalizedWidget(
      tester,
      Scaffold(
        body: MdxEntryView(
          config: MdxEntryViewConfig(
            sourceId: 'fixture',
            html: entries['apple']!,
            onEntryLink: (_) {},
            colors: darkColors,
          ),
          onWebViewCreated: (controller) {
            if (!created.isCompleted) created.complete(controller);
          },
        ),
      ),
    );

    final controller =
        await created.future.timeout(const Duration(seconds: 15));
    await _waitForTitle(tester, controller, _appleTitle);

    final darkWebView =
        tester.widget<InAppWebView>(find.byType(InAppWebView));
    final darkInitialHtml = darkWebView.platform.params.initialData?.data ?? '';
    expect(darkInitialHtml, contains(mdxOverrideCss(darkColors)));
    expect(
      darkInitialHtml,
      contains('img{background-color:#ffffff !important'),
    );

    // 切換為 E-Ink 配色並同時換詞條標題確認重載完成。
    await pumpLocalizedWidget(
      tester,
      Scaffold(
        body: MdxEntryView(
          config: MdxEntryViewConfig(
            sourceId: 'fixture',
            html: entries['banana']!,
            onEntryLink: (_) {},
            colors: einkColors,
          ),
        ),
      ),
    );
    await _waitForTitle(tester, controller, _bananaTitle);

    final einkPrepared = prepareEntryHtml(
      entries['banana']!,
      overrideCss: mdxOverrideCss(einkColors),
    );
    expect(
      einkPrepared,
      contains('html,body{background:#ffffff !important;color:#000000 !important}'),
    );
    expect(
      einkPrepared,
      contains('text-decoration:underline !important'),
    );
  });

  testWidgets('blockNetworkLoads 啟用下：data: 初始文件與攔截圖片皆正常載入渲染',
      (tester) async {
    final intercepted = <String, MdxRequestDecision>{};
    final created = Completer<InAppWebViewController>();
    // 兩張 64×64 PNG 設為寬 300px、高 auto（1:1 比例解碼後各佔 300px 高）；
    // 若圖片未載入或被 blockNetworkLoads 擋下，高度不會撐開。
    const probeHtml =
        '<html><head><meta charset="utf-8"><title>block-probe</title></head>'
        '<body style="margin:0">'
        '<img src="pic/a b.png" style="display:block;width:300px;height:auto">'
        '<img src="pic/sub/c.png" style="display:block;width:300px;height:auto">'
        '</body></html>';

    await pumpLocalizedWidget(
      tester,
      Scaffold(
        body: MdxEntryView(
          config: MdxEntryViewConfig(
            sourceId: 'images',
            html: probeHtml,
            onEntryLink: (_) {},
            resolveResource: imagesReader.readResource,
          ),
          onWebViewCreated: (controller) {
            if (!created.isCompleted) created.complete(controller);
          },
          onRequestIntercepted: (url, decision) {
            intercepted[url.toString()] = decision;
          },
        ),
      ),
    );

    final controller =
        await created.future.timeout(const Duration(seconds: 15));
    await _waitForTitle(tester, controller, 'block-probe');
    await _waitFor<bool>(
      tester,
      () async =>
          intercepted['https://dict.local/pic/a%20b.png'] != null &&
          intercepted['https://dict.local/pic/sub/c.png'] != null,
      (ready) => ready,
      'blockNetworkLoads 啟用下兩張圖片皆被攔截',
    );
    final contentHeight = await _waitFor<int>(
      tester,
      controller.getContentHeight,
      (height) => height >= 600,
      '兩張 300px 1:1 圖片解碼渲染撐開頁面高度（>= 600）',
    );
    final settings = await controller.getSettings();
    expect(settings?.blockNetworkLoads, isTrue);
    expect(intercepted['https://dict.local/pic/a%20b.png']!.statusCode, 200);
    expect(intercepted['https://dict.local/pic/sub/c.png']!.statusCode, 200);
    expect(contentHeight, greaterThanOrEqualTo(600));
  });
}
