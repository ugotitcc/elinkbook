import 'dart:typed_data';

import 'package:elinkbook/dictionary/mdx_resource.dart';
import 'package:elinkbook/dictionary/mdx_theme_override.dart';
import 'package:elinkbook/screens/widgets/mdx_entry_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_inappwebview_platform.dart';
import '../../support/pump_localized_widget.dart';

/// Epic 63 Issue 6a Task 7 / Issue 6b Task 5：`MdxEntryView` 的決策函式與回應轉換。
void main() {
  setUpAll(() {
    InAppWebViewPlatform.instance = FakeInAppWebViewPlatform();
  });
  group('decideNavigation', () {
    test('entry://apple 取消導航並帶出詞條文字', () {
      final decision = MdxEntryView.decideNavigation('entry://apple');

      expect(decision.allow, isFalse);
      expect(decision.entryWord, 'apple');
    });

    test('entry:// 的 percent-encoding 與結尾斜線都會還原', () {
      final decision = MdxEntryView.decideNavigation(
        'entry://%E5%A4%A9%E5%9C%B0/',
      );

      expect(decision.allow, isFalse);
      expect(decision.entryWord, '天地');
    });

    test('bword:// 與 entry:// 同樣視為詞條連結', () {
      final decision = MdxEntryView.decideNavigation('bword://apple');

      expect(decision.allow, isFalse);
      expect(decision.entryWord, 'apple');
    });

    test('entry://#錨點 是頁內錨點，交給 WebView 放行', () {
      final decision = MdxEntryView.decideNavigation('entry://#x');

      expect(decision.allow, isTrue);
      expect(decision.entryWord, isNull);
    });

    test('#x 放行', () {
      final decision = MdxEntryView.decideNavigation('#x');

      expect(decision.allow, isTrue);
      expect(decision.entryWord, isNull);
    });

    test('外部、檔案與音訊連結一律取消且不帶詞條', () {
      for (final url in [
        'https://example.com',
        'http://example.com/a',
        'file:///x',
        'sound://a',
        'javascript:alert(1)',
        'data:text/html,hi',
        '',
      ]) {
        final decision = MdxEntryView.decideNavigation(url);
        expect(decision.allow, isFalse, reason: url);
        expect(decision.entryWord, isNull, reason: url);
      }
    });
  });

  group('decideNavigation：自動觸發的導覽（I-7）', () {
    test('子框架（iframe）的 entry:// 取消且不帶詞條', () {
      final decision = MdxEntryView.decideNavigation(
        'entry://apple',
        isForMainFrame: false,
        hasGesture: true,
      );

      expect(decision.allow, isFalse);
      expect(decision.entryWord, isNull);
    });

    test('子框架的錨點也不放行', () {
      final decision = MdxEntryView.decideNavigation(
        '#x',
        isForMainFrame: false,
      );

      expect(decision.allow, isFalse);
    });

    test('主框架但沒有使用者手勢（hasGesture == false）的 entry:// 不帶詞條', () {
      final decision = MdxEntryView.decideNavigation(
        'entry://apple',
        isForMainFrame: true,
        hasGesture: false,
      );

      expect(decision.allow, isFalse);
      expect(decision.entryWord, isNull);
    });

    test('主框架且有手勢：照常帶出詞條', () {
      final decision = MdxEntryView.decideNavigation(
        'entry://apple',
        isForMainFrame: true,
        hasGesture: true,
      );

      expect(decision.entryWord, 'apple');
    });

    test('平台沒有提供 hasGesture（null）時，只看是否為主框架', () {
      final decision = MdxEntryView.decideNavigation(
        'entry://apple',
        isForMainFrame: true,
        hasGesture: null,
      );

      expect(decision.entryWord, 'apple');
    });

    test('主框架錨點不受 hasGesture 影響', () {
      expect(
        MdxEntryView.decideNavigation('#x', hasGesture: false).allow,
        isTrue,
      );
    });
  });

  group('gestureRecognizers', () {
    test('包含垂直拖曳辨識器，詞條才捲得動（底部面板內）', () {
      final recognizers = MdxEntryView.gestureRecognizers
          .map((factory) => factory.constructor())
          .toList();

      expect(recognizers.whereType<VerticalDragGestureRecognizer>(), hasLength(1));
      // 不搶點擊與長按，entry:// 連結與錨點照常運作。
      expect(recognizers.whereType<TapGestureRecognizer>(), isEmpty);
      expect(recognizers.whereType<LongPressGestureRecognizer>(), isEmpty);
    });
  });

  group('decideRequest', () {
    test('data: 初始文件交還 WebView（回傳 null）', () async {
      expect(
        await MdxEntryView.decideRequest(
          'data:text/html;charset=utf-8;base64,PGh0bWw+',
        ),
        isNull,
      );
    });

    test('https://dict.local/pic/a.png 有資源時回傳 200、contentType、位元組相同', () async {
      final sampleBytes = Uint8List.fromList([1, 2, 3, 4]);
      final decision = await MdxEntryView.decideRequest(
        'https://dict.local/pic/a.png',
        resolveResource: (url) async => MdxResource(
          bytes: sampleBytes,
          contentType: 'image/png',
        ),
      );

      expect(decision, isNotNull);
      expect(decision!.statusCode, 200);
      expect(decision.contentType, 'image/png');
      expect(decision.bytes, sampleBytes);
    });

    test('資源回傳 null 時回傳 404 空內容', () async {
      final decision = await MdxEntryView.decideRequest(
        'https://dict.local/pic/missing.png',
        resolveResource: (url) async => null,
      );

      expect(decision, isNotNull);
      expect(decision!.statusCode, 404);
      expect(decision.body, isEmpty);
      expect(decision.bytes, isNull);
    });

    test('resolveResource 丟出例外時回傳 404 不拋出例外', () async {
      final decision = await MdxEntryView.decideRequest(
        'https://dict.local/pic/error.png',
        resolveResource: (url) async => throw StateError('讀取失敗'),
      );

      expect(decision, isNotNull);
      expect(decision!.statusCode, 404);
      expect(decision.body, isEmpty);
    });

    test('非 dict.local 網址、檔案與其他協定回傳 404 且不呼叫 resolveResource', () async {
      var callCount = 0;
      Future<MdxResource?> fakeResolver(String url) async {
        callCount++;
        return null;
      }

      for (final url in [
        'https://evil.example/a.png',
        'http://example.com/b.png',
        'file:///x',
        'http://dict.local/x',
        'entry://apple',
      ]) {
        final decision = await MdxEntryView.decideRequest(
          url,
          resolveResource: fakeResolver,
        );
        expect(decision, isNotNull, reason: url);
        expect(decision!.statusCode, 404, reason: url);
        expect(decision.body, isEmpty, reason: url);
      }
      expect(callCount, 0, reason: '非合法 origin 不得呼叫 resolveResource');
    });

    test('resolveResource 為 null 時回傳 404', () async {
      for (final url in [
        'https://dict.local/pic/a.png',
        'https://dict.local/favicon.ico',
        'https://dict.local/style.css',
      ]) {
        final decision = await MdxEntryView.decideRequest(url);
        expect(decision, isNotNull, reason: url);
        expect(decision!.statusCode, 404, reason: url);
        expect(decision.body, isEmpty, reason: url);
      }
    });
  });

  group('responseFor', () {
    test('decision 為 null 時回傳 null', () {
      expect(MdxEntryView.responseFor(null), isNull);
    });

    test('200 決策轉換為 WebResourceResponse：contentEncoding 為 null，帶 contentType 與 bytes', () {
      final bytes = Uint8List.fromList([10, 20, 30]);
      final response = MdxEntryView.responseFor(
        MdxRequestDecision(
          statusCode: 200,
          contentType: 'image/png',
          bytes: bytes,
        ),
      );

      expect(response, isNotNull);
      expect(response!.statusCode, 200);
      expect(response.reasonPhrase, 'OK');
      expect(response.contentType, 'image/png');
      expect(response.contentEncoding, isNull);
      expect(response.headers, {'Content-Type': 'image/png'});
      expect(response.data, bytes);
    });

    test('404 決策轉換為 WebResourceResponse：維持 text/plain 與 utf-8', () {
      final response = MdxEntryView.responseFor(
        const MdxRequestDecision(statusCode: 404),
      );

      expect(response, isNotNull);
      expect(response!.statusCode, 404);
      expect(response.reasonPhrase, 'Not Found');
      expect(response.contentType, 'text/plain');
      expect(response.contentEncoding, 'utf-8');
      expect(response.headers, {'Content-Type': 'text/plain'});
      expect(response.data, isEmpty);
    });
  });

  group('colors 覆寫與重新載入', () {
    testWidgets('config 帶 colors 時 initialData 含覆寫樣式；colors == null 時不含',
        (tester) async {
      const colors = MdxColors(
        background: Color(0xFF112233),
        foreground: Color(0xFFEEEEEE),
        link: Color(0xFF4488FF),
        underlineLinks: false,
      );

      await pumpLocalizedWidget(
        tester,
        MdxEntryView(
          config: MdxEntryViewConfig(
            sourceId: 'src1',
            html: '<p>內容</p>',
            onEntryLink: (_) {},
            colors: colors,
          ),
        ),
      );

      var webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      expect(
        webView.platform.params.initialData?.data,
        contains('background:#112233 !important'),
      );

      await pumpLocalizedWidget(
        tester,
        MdxEntryView(
          config: MdxEntryViewConfig(
            sourceId: 'src1',
            html: '<p>內容</p>',
            onEntryLink: (_) {},
            colors: null,
          ),
        ),
      );

      webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      expect(
        webView.platform.params.initialData?.data,
        isNot(contains('!important')),
      );
    });

    testWidgets('colors 變更會觸發重新載入，colors 相等時不重載', (tester) async {
      var reloadCount = 0;
      const colorsA = MdxColors(
        background: Color(0xFF000000),
        foreground: Color(0xFFFFFFFF),
        link: Color(0xFF0088FF),
        underlineLinks: false,
      );
      const colorsASame = MdxColors(
        background: Color(0xFF000000),
        foreground: Color(0xFFFFFFFF),
        link: Color(0xFF0088FF),
        underlineLinks: false,
      );
      const colorsB = MdxColors(
        background: Color(0xFFFFFFFF),
        foreground: Color(0xFF000000),
        link: Color(0xFF000000),
        underlineLinks: true,
      );

      await pumpLocalizedWidget(
        tester,
        MdxEntryView(
          config: MdxEntryViewConfig(
            sourceId: 'src',
            html: '<p>同內容</p>',
            onEntryLink: (_) {},
            colors: null,
          ),
          onLoadHtml: () => reloadCount++,
        ),
      );
      expect(reloadCount, 0, reason: '初始載入不觸發 didUpdateWidget 的 _loadHtml');

      // 更新為 colorsA：觸發重新載入
      await pumpLocalizedWidget(
        tester,
        MdxEntryView(
          config: MdxEntryViewConfig(
            sourceId: 'src',
            html: '<p>同內容</p>',
            onEntryLink: (_) {},
            colors: colorsA,
          ),
          onLoadHtml: () => reloadCount++,
        ),
      );
      expect(reloadCount, 1, reason: 'colors 從 null 換為 colorsA 應觸發 reload');

      // 更新為數值相等的 colorsASame：不觸發重新載入
      await pumpLocalizedWidget(
        tester,
        MdxEntryView(
          config: MdxEntryViewConfig(
            sourceId: 'src',
            html: '<p>同內容</p>',
            onEntryLink: (_) {},
            colors: colorsASame,
          ),
          onLoadHtml: () => reloadCount++,
        ),
      );
      expect(reloadCount, 1, reason: '數值相等的 colors 不應重載');

      // 更新為不同配置 colorsB：觸發重新載入
      await pumpLocalizedWidget(
        tester,
        MdxEntryView(
          config: MdxEntryViewConfig(
            sourceId: 'src',
            html: '<p>同內容</p>',
            onEntryLink: (_) {},
            colors: colorsB,
          ),
          onLoadHtml: () => reloadCount++,
        ),
      );
      expect(reloadCount, 2, reason: 'colors 改變應再次觸發 reload');
    });
  });
}
