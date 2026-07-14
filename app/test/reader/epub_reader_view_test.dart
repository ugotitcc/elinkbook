import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';

/// 驅動 [EpubReaderView] 底層 AndroidView 完成建立流程所需的最小 mock：
/// 攔截 `SystemChannels.platform_views` 的 `'create'` 呼叫並回傳假的
/// textureId，讓 `onPlatformViewCreated` 得以在沒有真實裝置的 `flutter
/// test` 環境下觸發；同時攔截該次建立實際使用的 per-instance 頻道
/// （`cc.ugotit.elinkbook/epub_reader_view_$id`），記錄所有外送的
/// MethodCall 供測試斷言。view id 由 Flutter 內部計數器決定、跨測試遞增，
/// 因此從 `'create'` 呼叫的 `arguments['id']` 動態取得，不可寫死為固定
/// 數字。
Future<List<MethodCall>> _pumpEpubReaderView(
  WidgetTester tester,
  EpubReaderView widget,
) async {
  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final instanceCalls = <MethodCall>[];

  binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
      (call) async {
    if (call.method == 'create') {
      final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
      binaryMessenger.setMockMethodCallHandler(
        MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id'),
        (call) async {
          instanceCalls.add(call);
          return null;
        },
      );
      return 0; // textureId
    }
    return null;
  });

  await tester.pumpWidget(MaterialApp(home: widget));
  await tester.pumpAndSettle();
  return instanceCalls;
}

void main() {
  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含所有非 null 建構參數',
      (tester) async {
    final calls = await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
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
        pageMargins: 1.3333,
        textAlign: EpubTextAlign.justify,
        publisherStyles: false,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['path'], '/tmp/sample.epub');
    expect(openBookCall.arguments['initialPreferences'], {
      'writingMode': 'vertical',
      'pageTurnMode': 'scroll',
      'fontFamily': 'SourceHanSansTC',
      'fontSize': 1.125,
      'fontWeight': 1.75,
      'lineHeight': 1.6,
      'paragraphSpacing': 1.2,
      'pageMargins': 1.3333,
      'textAlign': 'justify',
      'publisherStyles': false,
      'dualPageMode': 'auto',
      'isLandscape': false,
    });
  });

  testWidgets('所有偏好欄位皆為 null 時，initialPreferences 只含 dualPageMode/isLandscape',
      (tester) async {
    final calls = await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {
      'dualPageMode': 'auto',
      'isLandscape': false,
    });
  });

  testWidgets(
      '任一偏好欄位變動時，didUpdateWidget 呼叫 setPreferences 並帶入目前所有非 null 欄位',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(const MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.125,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.25, // 變動
        writingMode: WritingMode.vertical, // 新增一個原本是 null 的欄位
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPreferences');
    expect(instanceCalls.single.arguments, {
      'fontSize': 1.25,
      'writingMode': 'vertical',
      'dualPageMode': 'auto',
      'isLandscape': false,
    });
  });

  testWidgets('偏好欄位皆未變動時，didUpdateWidget 不觸發任何 setPreferences 呼叫',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    const widget = EpubReaderView(
      filePath: '/tmp/sample.epub',
      onPageRendered: _noop,
      onError: _noopError,
      fontSize: 1.125,
    );

    await tester.pumpWidget(const MaterialApp(home: widget));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(home: widget));
    await tester.pumpAndSettle();

    expect(instanceCalls, isEmpty);
  });

  testWidgets('dualPageMode/isLandscape 一律出現在 initialPreferences（非 null 慣例）',
      (tester) async {
    final calls = await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
        isLandscape: true,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    final prefs = openBookCall.arguments['initialPreferences'] as Map;
    expect(prefs['dualPageMode'], 'always');
    expect(prefs['isLandscape'], true);
  });

  testWidgets('dualPageMode 變動時 didUpdateWidget 觸發 setPreferences',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(const MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
        isLandscape: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPreferences');
    expect(instanceCalls.single.arguments['dualPageMode'], 'always');
    expect(instanceCalls.single.arguments['isLandscape'], true);
  });

  testWidgets(
      'FXL 三欄熱區：isFixedLayout 變為 true 後，左/右/中熱區分別觸發 previousPage/nextPage/onToggleFixedLayoutControls',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];
    late MethodChannel instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
          instanceChannel,
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    var toggleCalled = 0;
    var pageTurnCalled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: '/tmp/sample_fixed_layout.epub',
          onPageRendered: _noop,
          onError: _noopError,
          onToggleFixedLayoutControls: () => toggleCalled++,
          onFixedLayoutPageTurn: () => pageTurnCalled++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    instanceCalls.clear();

    // 模擬原生端 reportLayoutResolved() 回報 isFixedLayout=true——真機上這是
    // EpubReaderView.kt 在 onPageLoaded() 首次觸發時主動送出的，這裡以正確編碼
    // 的 MethodCall 直接送進 per-instance 頻道模擬同一件事。
    final byteData = instanceChannel.codec.encodeMethodCall(
      const MethodCall('onLayoutResolved', {
        'isFixedLayout': true,
        'writingMode': 'horizontal',
      }),
    );
    await binaryMessenger.handlePlatformMessage(
      instanceChannel.name,
      byteData,
      (data) {},
    );
    await tester.pump();

    expect(find.byKey(const Key('epub_fxl_tap_zone_previous')), findsOneWidget);
    expect(find.byKey(const Key('epub_fxl_tap_zone_next')), findsOneWidget);
    expect(
      find.byKey(const Key('epub_fxl_tap_zone_toggle_controls')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('epub_fxl_tap_zone_next')));
    await tester.tap(find.byKey(const Key('epub_fxl_tap_zone_previous')));
    await tester.tap(find.byKey(const Key('epub_fxl_tap_zone_toggle_controls')));
    await tester.pump();

    expect(instanceCalls.map((c) => c.method).toList(),
        ['nextPage', 'previousPage']);
    expect(toggleCalled, 1);
    expect(pageTurnCalled, 2,
        reason: '左右熱區各觸發一次換頁，onFixedLayoutPageTurn 應各被呼叫一次，'
            '中間熱區（純顯示切換）不應觸發它');
  });

  testWidgets('isFixedLayout 維持預設 false 時，不疊加三欄熱區', (tester) async {
    await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );
    expect(find.byKey(const Key('epub_fxl_tap_zone_previous')), findsNothing);
    expect(find.byKey(const Key('epub_fxl_tap_zone_next')), findsNothing);
    expect(
      find.byKey(const Key('epub_fxl_tap_zone_toggle_controls')),
      findsNothing,
    );
  });
}

void _noop() {}
void _noopError(String message) {}
