import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/zone_action.dart';
import '../support/fake_inappwebview_platform.dart';

void _noop() {}
void _noopError(String message) {}

void main() {
  // Issue 10 審查修正：9 宮格導航熱區 tap／debug overlay 這兩項 widget
  // test 原本因「裸 InAppWebView 無法在 flutter_test 下 pump」被整批移除
  // （見 plan-issue-10.md「驗證紀錄」），比照
  // test/screens/reader_screen_test.dart 已驗證可行的作法，註冊
  // FakeInAppWebViewPlatform 後即可正常 pump，回補於下方
  // 「3×3 導航熱區」group。
  setUpAll(() {
    InAppWebViewPlatform.instance = FakeInAppWebViewPlatform();
  });

  group('buildFoliatePreferencesMap', () {
    test('所有偏好欄位皆為 null 時回傳空 map', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      expect(buildFoliatePreferencesMap(view), <String, Object?>{});
    });

    test('columnMode: single 時 map 含 columnMode: single', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        columnMode: ColumnMode.single,
      );
      expect(buildFoliatePreferencesMap(view), {'columnMode': 'single'});
    });

    test('showFooter: false 時 map 含 showFooter: false', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        showFooter: false,
      );
      expect(buildFoliatePreferencesMap(view), {'showFooter': false});
    });

    test('所有非 null 建構參數皆正確出現於 map', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.vertical,
        pageTurnMode: PageTurnMode.scroll,
        fontFamily: AppFont.sourceHanSans,
        fontSize: 1.125,
        fontWeight: 1.75,
        lineHeight: 1.6,
        paragraphSpacing: 1.2,
        marginTop: 72,
        marginBottom: 20,
        marginLeft: 30,
        marginRight: 30,
        textAlign: EpubTextAlign.justify,
        publisherStyles: false,
        columnMode: ColumnMode.single,
        columnSize: 600.0,
        showFooter: false,
      );
      expect(buildFoliatePreferencesMap(view), {
        'writingMode': 'vertical',
        'pageTurnMode': 'scroll',
        'fontFamily': 'SourceHanSansTC',
        'fontSize': 1.125,
        'fontWeight': 1.75,
        'lineHeight': 1.6,
        'paragraphSpacing': 1.2,
        'marginTop': 72.0,
        'marginBottom': 20.0,
        'marginLeft': 30.0,
        'marginRight': 30.0,
        'textAlign': 'justify',
        'publisherStyles': false,
        'columnMode': 'single',
        'columnSize': 600.0,
        'showFooter': false,
      });
    });

    test('writingMode: horizontal 時 map 含 writingMode: horizontal', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.horizontal,
      );
      expect(buildFoliatePreferencesMap(view), {'writingMode': 'horizontal'});
    });
  });

  group('foliatePreferencesChanged', () {
    test('完全相同的參數回傳 false', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      );
      expect(foliatePreferencesChanged(oldView, newView), isFalse);
    });

    test('writingMode 變動回傳 true', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.horizontal,
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.vertical,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('columnMode 變動回傳 true', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        columnMode: ColumnMode.single,
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('showFooter 變動回傳 true', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        showFooter: true,
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        showFooter: false,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('非偏好參數（filePath）變動不影響結果', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/old.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/new.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      );
      expect(foliatePreferencesChanged(oldView, newView), isFalse);
    });
  });

  group('3×3 導航熱區（InAppWebView）', () {
    // Issue 10 審查修正：改寫前（AndroidView）版本用
    // SystemChannels.platform_views/MethodChannel mock 驅動底層原生
    // PlatformView 建立流程（見 git 歷史 b2ea4a3 版本的
    // _pumpFoliateEpubReaderView），該機制已隨遷移完全消失；改用
    // setUpAll 註冊的 FakeInAppWebViewPlatform 讓 InAppWebView 可直接
    // pump，不需要任何 mock。pump 後接 runAsync(Future.delayed(Duration.zero))
    // 再 pump 一次，比照 test/screens/reader_screen_test.dart 已驗證可行
    // 的既有寫法。
    testWidgets(
        '3×3 導航熱區：9 個 Key(nav_zone_\$index) 皆存在，點擊觸發對應 onZoneAction',
        (tester) async {
      final capturedActions = <ZoneAction>[];
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateEpubReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
            navZoneActions: const [
              ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
              ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
              ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
            ],
            onZoneAction: capturedActions.add,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      for (var index = 0; index < 9; index++) {
        expect(find.byKey(Key('nav_zone_$index')), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('nav_zone_2')));
      await tester.pump();
      expect(capturedActions, [ZoneAction.nextPage]);

      await tester.tap(find.byKey(const Key('nav_zone_4')));
      await tester.pump();
      expect(capturedActions, [ZoneAction.nextPage, ZoneAction.menu]);

      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();
      expect(
        capturedActions,
        [ZoneAction.nextPage, ZoneAction.menu, ZoneAction.none],
      );
    });

    testWidgets('showNavZoneDebugOverlay=true 時，格子顯示對應動作文字標籤',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateEpubReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
            navZoneActions: const [
              ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
              ZoneAction.none, ZoneAction.none, ZoneAction.none,
              ZoneAction.none, ZoneAction.none, ZoneAction.none,
            ],
            showNavZoneDebugOverlay: true,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(find.text('上一頁'), findsWidgets);
      expect(find.text('選單'), findsWidgets);
      expect(find.text('下一頁'), findsWidgets);
      expect(find.text('無動作'), findsWidgets);
    });
  });

  group('Object.groupBy/Map.groupBy polyfill（診斷修正）', () {
    // 根因：epub.js（readest/foliate-js 釘定版本）的 OPF 詮釋資料解析無條
    // 件呼叫 Object.groupBy/Map.groupBy（ES2024），較舊的 Android System
    // WebView（Chromium < 117）尚未支援，開啟任何 EPUB 都會拋出
    // 「TypeError: Object.groupBy is not a function」（已用 @xmldom/xmldom
    // 及未經修改的實際 epub.js 重現並驗證 polyfill 可修復，見診斷紀錄）。
    // 這裡只驗證 InAppWebView 確實在文件載入最早期（AT_DOCUMENT_START）
    // 注入了含 Object.groupBy／Map.groupBy 的 polyfill 腳本；polyfill 本身
    // 的 JS 邏輯正確性已在 Node 環境對照真實 epub.js 驗證過，不在 widget
    // test 範圍內重複驗證。
    testWidgets('InAppWebView 於 AT_DOCUMENT_START 注入 Object.groupBy/Map.groupBy polyfill',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateEpubReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final scripts = webView.platform.params.initialUserScripts;
      expect(scripts, isNotNull);
      expect(scripts, hasLength(1));
      final script = scripts!.single;
      expect(script.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
      expect(script.source, contains('Object.groupBy'));
      expect(script.source, contains('Map.groupBy'));
    });
  });
}
