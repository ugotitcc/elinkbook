import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/epub_decoration.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';
import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/reader/zone_action.dart';

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
      'navZoneActions': List.filled(9, 'none'),
    });
  });

  testWidgets(
      '所有偏好欄位皆為 null 時，initialPreferences 只含 dualPageMode/isLandscape/navZoneActions',
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
      'navZoneActions': List.filled(9, 'none'),
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
      'navZoneActions': List.filled(9, 'none'),
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
      'FXL 9 宮格熱區：isFixedLayout 變為 true 後，9 個 Key(nav_zone_\$index) 皆存在，點擊觸發對應 onZoneAction',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late MethodChannel instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
          instanceChannel,
          (call) async => null,
        );
        return 0;
      }
      return null;
    });

    final capturedActions = <ZoneAction>[];
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: '/tmp/sample_fixed_layout.epub',
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
    await tester.pumpAndSettle();

    // 模擬原生端回報 isFixedLayout=true
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

    for (var index = 0; index < 9; index++) {
      expect(find.byKey(Key('nav_zone_$index')), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('nav_zone_0')));
    await tester.pump();
    expect(capturedActions, [ZoneAction.previousPage]);

    await tester.tap(find.byKey(const Key('nav_zone_4')));
    await tester.pump();
    expect(capturedActions, [ZoneAction.previousPage, ZoneAction.menu]);
  });

  testWidgets(
      'FXL 9 宮格熱區：isFixedLayout 一旦變為 true，後續 native 回報 false 不會覆蓋（Issue 19 防禦性修法回歸測試）',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late MethodChannel instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
          instanceChannel,
          (call) async => null,
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: '/tmp/sample_fixed_layout.epub',
          onPageRendered: _noop,
          onError: _noopError,
          navZoneActions: const [
            ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
            ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
            ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
          ],
          onZoneAction: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Step 1: 模擬原生端回報 isFixedLayout=true
    var byteData = instanceChannel.codec.encodeMethodCall(
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

    // 斷言 9 宮格熱區 Key 皆存在
    for (var index = 0; index < 9; index++) {
      expect(find.byKey(Key('nav_zone_$index')), findsOneWidget);
    }

    // Step 2: 模擬原生端回報 isFixedLayout=false（修復前會發生、修復後屬邊界情況）
    byteData = instanceChannel.codec.encodeMethodCall(
      const MethodCall('onLayoutResolved', {
        'isFixedLayout': false,
        'writingMode': 'horizontal',
      }),
    );
    await binaryMessenger.handlePlatformMessage(
      instanceChannel.name,
      byteData,
      (data) {},
    );
    await tester.pump();

    // 斷言 9 宮格熱區 Key **仍然**皆存在（未被移除）
    for (var index = 0; index < 9; index++) {
      expect(find.byKey(Key('nav_zone_$index')), findsOneWidget);
    }
  });

  testWidgets('isFixedLayout 維持預設 false 時，不疊加 9 宮格熱區', (tester) async {
    await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );
    for (var index = 0; index < 9; index++) {
      expect(find.byKey(Key('nav_zone_$index')), findsNothing);
    }
  });

  testWidgets('showNavZoneDebugOverlay=true 時，格子顯示對應動作文字標籤', (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late MethodChannel instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
          instanceChannel,
          (call) async => null,
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
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
    await tester.pumpAndSettle();

    // 模擬原生端回報 isFixedLayout=true
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

    expect(find.text('上一頁'), findsWidgets);
    expect(find.text('選單'), findsWidgets);
    expect(find.text('下一頁'), findsWidgets);
  });

  testWidgets(
      'EpubReaderView.nextPage() / previousPage()（強型別 static helper）呼叫原生端對應 method channel',
      (tester) async {
    final key = GlobalKey<State<EpubReaderView>>();
    final instanceCalls = await _pumpEpubReaderView(
      tester,
      EpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );
    instanceCalls.clear();

    EpubReaderView.nextPage(key);
    await tester.pump();
    expect(instanceCalls.any((c) => c.method == 'nextPage'), isTrue);

    EpubReaderView.previousPage(key);
    await tester.pump();
    expect(instanceCalls.any((c) => c.method == 'previousPage'), isTrue);
  });

  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialLocatorJson 非 null 時正確帶入',
      (tester) async {
    final calls = await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        initialLocatorJson: '{"href":"/chap1.xhtml"}',
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialLocatorJson'], '{"href":"/chap1.xhtml"}');
  });

  testWidgets('initialLocatorJson 為 null 時，openBook 的 arguments 不包含該 key',
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
    expect(
      (openBookCall.arguments as Map<Object?, Object?>)
          .containsKey('initialLocatorJson'),
      isFalse,
    );
  });

  testWidgets('收到原生端 onLocatorChanged 事件時正確解析 EpubPositionInfo',
      (tester) async {
    EpubPositionInfo? received;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onLocatorChanged: (info) => received = info,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onLocatorChanged', {
      'locatorJson': '{"href":"/chap2.xhtml"}',
      'progression': 0.35,
    }));
    await binaryMessenger.handlePlatformMessage(
        instanceChannel!.name, data, (_) {});

    expect(
      received,
      const EpubPositionInfo(
        locatorJson: '{"href":"/chap2.xhtml"}',
        progression: 0.35,
      ),
    );
  });

  testWidgets('收到原生端 onSelectionChanged 事件時正確解析 EpubSelectionInfo',
      (tester) async {
    EpubSelectionInfo? received;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onSelectionChanged: (info) => received = info,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onSelectionChanged', {
      'locatorJson': '{"href":"/c1.xhtml"}',
      'progression': 0.2,
      'leftPct': 0.1,
      'topPct': 0.2,
      'rightPct': 0.3,
      'bottomPct': 0.4,
    }));
    await binaryMessenger.handlePlatformMessage(
        instanceChannel!.name, data, (_) {});

    expect(
      received,
      const EpubSelectionInfo(
        locatorJson: '{"href":"/c1.xhtml"}',
        progression: 0.2,
        rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
      ),
    );
  });

  testWidgets('收到原生端 onSelectionCleared 事件時觸發 callback', (tester) async {
    var cleared = false;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onSelectionCleared: () => cleared = true,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onSelectionCleared', null));
    await binaryMessenger.handlePlatformMessage(instanceChannel!.name, data, (_) {});

    expect(cleared, isTrue);
  });

  testWidgets('收到原生端 onAnnotationActivated 事件時傳回標記 id 字串',
      (tester) async {
    String? activatedId;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onAnnotationActivated: (id) => activatedId = id,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data =
        codec.encodeMethodCall(const MethodCall('onAnnotationActivated', 'highlight:12'));
    await binaryMessenger.handlePlatformMessage(instanceChannel!.name, data, (_) {});

    expect(activatedId, 'highlight:12');
  });

  testWidgets('setDecorations 呼叫原生端時正確序列化 EpubDecoration 清單',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(instanceChannel!, (call) async {
          instanceCalls.add(call);
          return null;
        });
        return 0;
      }
      return null;
    });

    final key = GlobalKey<State<EpubReaderView>>();
    await tester.pumpWidget(MaterialApp(
      home: EpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();

    EpubReaderView.setDecorations(key, [
      EpubDecoration.forHighlight(
        highlightId: 1,
        locatorJson: '{"href":"/c1.xhtml"}',
        tint: 0x73FDE047,
        isUnderline: false,
      ),
      EpubDecoration.forHighlight(
        highlightId: 2,
        locatorJson: '{"href":"/c2.xhtml"}',
        tint: 0xFF6750A4,
        isUnderline: true,
      ),
    ]);

    final call = instanceCalls.singleWhere((c) => c.method == 'setDecorations');
    final decorations =
        (call.arguments as Map<Object?, Object?>)['decorations'] as List<Object?>;
    expect(decorations, hasLength(2));
    expect((decorations[0] as Map<Object?, Object?>)['id'], 'highlight:1');
    expect((decorations[1] as Map<Object?, Object?>)['isUnderline'], isTrue);
  });

  testWidgets(
      'navZoneActions 變動時，didUpdateWidget 呼叫 setPreferences 並帶入新的動作陣列',
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
        navZoneActions: [
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPreferences');
    expect(instanceCalls.single.arguments['navZoneActions'], [
      'previousPage', 'menu', 'nextPage',
      'previousPage', 'menu', 'nextPage',
      'previousPage', 'menu', 'nextPage',
    ]);
  });

  testWidgets('收到原生端 onZoneTapped 事件時，傳回 cellIndex 整數', (tester) async {
    int? tappedIndex;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onZoneTapped: (index) => tappedIndex = index,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(
      const MethodCall('onZoneTapped', {'cellIndex': 4}),
    );
    await binaryMessenger.handlePlatformMessage(instanceChannel!.name, data, (_) {});

    expect(tappedIndex, 4);
  });
}

void _noop() {}
void _noopError(String message) {}
