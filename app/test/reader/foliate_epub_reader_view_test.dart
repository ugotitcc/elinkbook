import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
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
      // isLandscape 為非 nullable 必要參數，預設 false，恆定出現在 map
      expect(buildFoliatePreferencesMap(view), {'isLandscape': false});
    });

    test('columnMode: single 時 map 含 columnMode: single', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        columnMode: ColumnMode.single,
      );
      expect(buildFoliatePreferencesMap(view), {
        'columnMode': 'single',
        'isLandscape': false,
      });
    });

    test('showFooter: false 時 map 含 showFooter: false', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        showFooter: false,
      );
      expect(buildFoliatePreferencesMap(view), {
        'showFooter': false,
        'isLandscape': false,
      });
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
        'isLandscape': false,
      });
    });

    test('writingMode: horizontal 時 map 含 writingMode: horizontal', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.horizontal,
      );
      expect(buildFoliatePreferencesMap(view), {
        'writingMode': 'horizontal',
        'isLandscape': false,
      });
    });

    test('isFixedLayoutHint: true 時 map 含 isFixedLayoutHint: true', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isFixedLayoutHint: true,
      );
      expect(buildFoliatePreferencesMap(view), {
        'isFixedLayoutHint': true,
        'isLandscape': false,
      });
    });

    test('isFixedLayoutHint: false 時 map 含 isFixedLayoutHint: false', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isFixedLayoutHint: false,
      );
      expect(buildFoliatePreferencesMap(view), {
        'isFixedLayoutHint': false,
        'isLandscape': false,
      });
    });

    test('isFixedLayoutHint 未設定（null）時 map 不含該 key', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isFixedLayoutHint: null,
      );
      expect(
        buildFoliatePreferencesMap(view).containsKey('isFixedLayoutHint'),
        isFalse,
      );
    });

    // Epic 20 Issue 3：dualPageMode／isLandscape 單元測試
    test('dualPageMode: always 時 map 含 dualPageMode: always', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
      );
      expect(buildFoliatePreferencesMap(view), {
        'dualPageMode': 'always',
        'isLandscape': false,
      });
    });

    test('dualPageMode: auto 時 map 含 dualPageMode: auto', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.auto,
      );
      expect(buildFoliatePreferencesMap(view), {
        'dualPageMode': 'auto',
        'isLandscape': false,
      });
    });

    test('dualPageMode: never 時 map 含 dualPageMode: never', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.never,
      );
      expect(buildFoliatePreferencesMap(view), {
        'dualPageMode': 'never',
        'isLandscape': false,
      });
    });

    test('dualPageMode 未設定（null）時 map 不含該 key', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: null,
      );
      expect(
        buildFoliatePreferencesMap(view).containsKey('dualPageMode'),
        isFalse,
      );
    });

    test('isLandscape: true 時 map 含 isLandscape: true', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isLandscape: true,
      );
      expect(buildFoliatePreferencesMap(view), {'isLandscape': true});
    });

    test('isLandscape 預設值（false）時 map 含 isLandscape: false', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      expect(buildFoliatePreferencesMap(view), {'isLandscape': false});
    });

    test('dualPageMode + isLandscape 同時設定時兩者皆出現在 map', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
        isLandscape: true,
      );
      expect(buildFoliatePreferencesMap(view), {
        'dualPageMode': 'always',
        'isLandscape': true,
      });
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

    test('isFixedLayoutHint 變動回傳 true', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isFixedLayoutHint: false,
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isFixedLayoutHint: true,
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

    // Epic 20 Issue 3：dualPageMode／isLandscape 變動偵測
    test('dualPageMode 變動回傳 true', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.never,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('dualPageMode 從 null 變為 always 回傳 true', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      const newView = FoliateEpubReaderView(
       filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('isLandscape 變動回傳 true', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isLandscape: false,
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isLandscape: true,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('dualPageMode + isLandscape 同時變動回傳 true', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.auto,
        isLandscape: false,
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
        isLandscape: true,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('dualPageMode + isLandscape 未變動回傳 false', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.auto,
        isLandscape: true,
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.auto,
        isLandscape: true,
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

  group('ES 相容性 polyfill（診斷修正）', () {
    // 根因：epub.js/epubcfi.js/paginator.js（readest/foliate-js 釘定版本）
    // 在開書必經路徑無條件使用三個較新的 ES 內建方法——Object.groupBy／
    // Map.groupBy（ES2024，需 Chromium 117+）、Array.prototype.at()
    // （ES2022，需 Chromium 92+）、Array.prototype.findLastIndex()
    // （ES2023，需 Chromium 97+）。較舊的 Android System WebView（例如
    // 真機回報的 Mobiscribe WAVE，Chromium 91）三個都不支援：groupBy 那部
    // 分會讓任何 EPUB 直接拋出可觀察的例外；.at()/findLastIndex() 那部分
    // 則是在 loadItem()/loadReplaced()/分頁計算等更深層的呼叫點，這台裝置
    // 的 WebView 建置沒有開啟遠端 DevTools 除錯、無法直接看到例外訊息，
    // 症狀純粹是「畫面永遠停在載入指示器」。已用 @xmldom/xmldom 及未經修
    // 改的實際 epub.js／epubcfi.js 重現並驗證這三個 polyfill 可修復（見
    // 診斷紀錄）。這裡只驗證 InAppWebView 確實在文件載入最早期
    // （AT_DOCUMENT_START）注入了含這三個 polyfill 的腳本；polyfill 本身
    // 的 JS 邏輯正確性已在 Node 環境對照真實 epub.js 驗證過，不在 widget
    // test 範圍內重複驗證。
    testWidgets(
        'InAppWebView 於 AT_DOCUMENT_START 注入 Object.groupBy/Map.groupBy/'
        'Array.prototype.at/Array.prototype.findLastIndex polyfill',
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
      expect(script.source, contains('Array.prototype.at'));
      expect(script.source, contains('Array.prototype.findLastIndex'));
    });
  });

  // Epic 20 Issue 3 計畫審查 Minor #1：isDualPageEnabled 的 Dart 端 truth
  // table 測試——移植自 EpubReaderView.kt:149-151 既有的 Kotlin 邏輯，
  // 與 main.js 的 JS 版本邏輯完全一致。本測試無法直接驗證 JS 端行為（無
  // JS 測試框架），但作為可執行文件確保四種組合的預期結果被記錄且可回歸
  // 檢查；若未來 Dart 端需要相同邏輯（例如 PDF 路徑），可直接參考此處。
  group('isDualPageEnabled truth table（可執行文件）', () {
    /// 等效於 main.js 的 isDualPageEnabled(dualPageMode, isLandscape)
    /// 與 EpubReaderView.kt:149-151 的邏輯
    bool isDualPageEnabled(String dualPageMode, bool isLandscape) {
      return dualPageMode == 'always' ||
          (dualPageMode == 'auto' && isLandscape);
    }

    test('always + landscape → true', () {
      expect(isDualPageEnabled('always', true), isTrue);
    });

    test('always + portrait → true', () {
      expect(isDualPageEnabled('always', false), isTrue);
    });

    test('auto + landscape → true', () {
      expect(isDualPageEnabled('auto', true), isTrue);
    });

    test('auto + portrait → false', () {
      expect(isDualPageEnabled('auto', false), isFalse);
    });

    test('never + landscape → false', () {
      expect(isDualPageEnabled('never', true), isFalse);
    });

    test('never + portrait → false', () {
      expect(isDualPageEnabled('never', false), isFalse);
    });
  });
}
