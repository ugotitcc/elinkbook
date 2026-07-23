import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/epub_decoration.dart';
import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/zone_action.dart';

/// 驅動 [FoliateEpubReaderView] 底層 AndroidView 完成建立流程所需的最小
/// mock，比照 app/test/reader/epub_reader_view_test.dart 既有的
/// _pumpEpubReaderView 模式。
Future<List<MethodCall>> _pumpFoliateEpubReaderView(
  WidgetTester tester,
  FoliateEpubReaderView widget,
) async {
  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final instanceCalls = <MethodCall>[];

  binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
      (call) async {
    if (call.method == 'create') {
      final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
      binaryMessenger.setMockMethodCallHandler(
        MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id'),
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

void _noop() {}
void _noopError(String message) {}

void main() {
  testWidgets('_onPlatformViewCreated 呼叫 openBook 並帶入正確的 path',
      (tester) async {
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      const FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['path'], '/tmp/sample.epub');
    expect(openBookCall.arguments['initialPreferences'], <String, Object?>{});
  });

  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含所有非 null 建構參數',
      (tester) async {
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      const FoliateEpubReaderView(
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
    });
  });

  testWidgets('所有偏好欄位皆為 null 時，initialPreferences 為空 map',
      (tester) async {
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      const FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], <String, Object?>{});
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
          MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    final key = GlobalKey<State<FoliateEpubReaderView>>();
    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.horizontal,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.vertical,
      ),
    ));
    await tester.pumpAndSettle();

    final setPreferencesCall =
        instanceCalls.firstWhere((c) => c.method == 'setPreferences');
    expect(setPreferencesCall.arguments, {'writingMode': 'vertical'});
  });

  testWidgets('偏好欄位皆未變動時，didUpdateWidget 不呼叫 setPreferences',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    final key = GlobalKey<State<FoliateEpubReaderView>>();
    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls.where((c) => c.method == 'setPreferences'), isEmpty);
  });

  testWidgets('原生端呼叫 onPageRendered 時，觸發 widget.onPageRendered',
      (tester) async {
    var rendered = false;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: () => rendered = true,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();

    await binaryMessenger.handlePlatformMessage(
      instanceChannel!.name,
      instanceChannel!.codec.encodeMethodCall(
          const MethodCall('onPageRendered')),
      (data) {},
    );

    expect(rendered, isTrue);
  });

  testWidgets('原生端呼叫 onError 時，觸發 widget.onError 並帶入錯誤訊息',
      (tester) async {
    String? errorMessage;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: (message) => errorMessage = message,
      ),
    ));
    await tester.pumpAndSettle();

    await binaryMessenger.handlePlatformMessage(
      instanceChannel!.name,
      instanceChannel!.codec.encodeMethodCall(
          const MethodCall('onError', '找不到檔案')),
      (data) {},
    );

    expect(errorMessage, '找不到檔案');
  });

  testWidgets(
      '原生端呼叫 onLayoutResolved 時，觸發 widget.onLayoutResolved 並正確解析欄位',
      (tester) async {
    EpubLayoutInfo? info;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onLayoutResolved: (value) => info = value,
      ),
    ));
    await tester.pumpAndSettle();

    await binaryMessenger.handlePlatformMessage(
      instanceChannel!.name,
      instanceChannel!.codec.encodeMethodCall(
        const MethodCall('onLayoutResolved', {
          'isFixedLayout': false,
          'writingMode': 'horizontal',
        }),
      ),
      (data) {},
    );

    expect(info, isNotNull);
    expect(info!.isFixedLayout, isFalse);
    expect(info!.writingMode, WritingMode.horizontal);
  });

  testWidgets(
      'FoliateEpubReaderView.nextPage()／previousPage()／jumpToProgression()'
      '（強型別 static helper）呼叫原生端對應 method channel',
      (tester) async {
    final key = GlobalKey<State<FoliateEpubReaderView>>();
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );
    calls.clear();

    FoliateEpubReaderView.nextPage(key);
    await tester.pump();
    expect(calls.any((c) => c.method == 'nextPage'), isTrue);

    FoliateEpubReaderView.previousPage(key);
    await tester.pump();
    expect(calls.any((c) => c.method == 'previousPage'), isTrue);

    FoliateEpubReaderView.jumpToProgression(key, 0.42);
    await tester.pump();
    final jumpCall = calls.firstWhere((c) => c.method == 'jumpToProgression');
    expect(jumpCall.arguments, {'progression': 0.42});
  });

  testWidgets(
      '3×3 導航熱區：9 個 Key(nav_zone_\$index) 皆存在，點擊觸發對應 onZoneAction',
      (tester) async {
    final capturedActions = <ZoneAction>[];
    await _pumpFoliateEpubReaderView(
      tester,
      FoliateEpubReaderView(
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
    );

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
    await _pumpFoliateEpubReaderView(
      tester,
      FoliateEpubReaderView(
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
    );

    expect(find.text('上一頁'), findsWidgets);
    expect(find.text('選單'), findsWidgets);
    expect(find.text('下一頁'), findsWidgets);
    expect(find.text('無動作'), findsWidgets);
  });

  testWidgets('openBook 呼叫時帶入 initialLocatorJson（非 null）',
      (tester) async {
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      const FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        initialLocatorJson: '{"cfi":"epubcfi(/4/2)","index":1,"fraction":0.3}',
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialLocatorJson'],
        '{"cfi":"epubcfi(/4/2)","index":1,"fraction":0.3}');
  });

  testWidgets('openBook 呼叫時不含 initialLocatorJson（null）', (tester) async {
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      const FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments.containsKey('initialLocatorJson'), false);
  });

  testWidgets('onLocatorChanged 收到原生端回報時觸發 callback',
      (tester) async {
    EpubPositionInfo? captured;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    int channelId = -1;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id =
            (call.arguments as Map<Object?, Object?>)['id'] as int;
        channelId = id;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id'),
          (call) async => null,
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onLocatorChanged: (info) => captured = info,
      ),
    ));
    await tester.pumpAndSettle();

    // 模擬原生端回報 onLocatorChanged
    final channel =
        MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$channelId');
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, channel.codec.encodeMethodCall(
          MethodCall('onLocatorChanged', {
            'locatorJson': '{"cfi":"epubcfi(/4/2)","index":1,"fraction":0.3}',
            'progression': 0.3,
            'pageIndex': 5,
            'totalPages': 20,
          }),
        ), (_) {});

    expect(captured, isNotNull);
    expect(captured!.locatorJson,
        '{"cfi":"epubcfi(/4/2)","index":1,"fraction":0.3}');
    expect(captured!.progression, 0.3);
    expect(captured!.pageIndex, 5);
    expect(captured!.totalPages, 20);
  });

  testWidgets('onLocatorChanged 為 null 時，原生端回報不觸發例外',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    int channelId = -1;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id =
            (call.arguments as Map<Object?, Object?>)['id'] as int;
        channelId = id;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id'),
          (call) async => null,
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: const FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        // onLocatorChanged 不提供
      ),
    ));
    await tester.pumpAndSettle();

    final channel =
        MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$channelId');
    // 不拋出例外即通過
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, channel.codec.encodeMethodCall(
          MethodCall('onLocatorChanged', {
            'locatorJson': '{"cfi":"epubcfi(/4/2)","index":1,"fraction":0.3}',
            'progression': 0.3,
            'pageIndex': 5,
            'totalPages': 20,
          }),
        ), (_) {});
  });

  testWidgets(
      'FoliateEpubReaderView.setDecorations() 呼叫原生端 setDecorations method channel',
      (tester) async {
    final key = GlobalKey<State<FoliateEpubReaderView>>();
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );
    calls.clear();

    FoliateEpubReaderView.setDecorations(key, [
      EpubDecoration.forHighlight(
        highlightId: 5,
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}',
        tint: 0xFFFF0000,
        isUnderline: false,
      ),
      EpubDecoration.forNote(
        noteId: 1,
        locatorJson: '{"cfi":"epubcfi(/6/6)","index":1,"fraction":0.5}',
        tint: 0x73D1D5DB,
      ),
    ]);
    await tester.pump();

    final call = calls.firstWhere((c) => c.method == 'setDecorations');
    expect(call.arguments['decorations'], [
      {
        'id': 'highlight:5',
        'locatorJson': '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}',
        'tint': 4294901760,
        'isUnderline': false,
      },
      {
        'id': 'note:1',
        'locatorJson': '{"cfi":"epubcfi(/6/6)","index":1,"fraction":0.5}',
        'tint': 1943131611,
        'isUnderline': false,
      },
    ]);
  });

  testWidgets('原生端呼叫 onSelectionChanged 時，觸發 widget.onSelectionChanged 並正確解析欄位',
      (tester) async {
    EpubSelectionInfo? captured;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    int channelId = -1;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        channelId = id;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id'),
          (call) async => null,
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onSelectionChanged: (info) => captured = info,
      ),
    ));
    await tester.pumpAndSettle();

    final channel = MethodChannel(
        'cc.ugotit.elinkbook/foliate_epub_reader_view_$channelId');
    await binaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('onSelectionChanged', {
          'locatorJson': '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}',
          'progression': 0.1,
          'leftPct': 0.1,
          'topPct': 0.2,
          'rightPct': 0.5,
          'bottomPct': 0.3,
        }),
      ),
      (_) {},
    );

    expect(captured, isNotNull);
    expect(captured!.locatorJson,
        '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}');
    expect(captured!.progression, 0.1);
    expect(captured!.rect.left, 0.1);
    expect(captured!.rect.top, 0.2);
    expect(captured!.rect.right, 0.5);
    expect(captured!.rect.bottom, 0.3);
  });

  testWidgets('原生端呼叫 onSelectionCleared 時觸發 widget.onSelectionCleared',
      (tester) async {
    var cleared = false;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    int channelId = -1;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        channelId = id;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id'),
          (call) async => null,
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onSelectionCleared: () => cleared = true,
      ),
    ));
    await tester.pumpAndSettle();

    final channel = MethodChannel(
        'cc.ugotit.elinkbook/foliate_epub_reader_view_$channelId');
    await binaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('onSelectionCleared')),
      (_) {},
    );

    expect(cleared, isTrue);
  });

  testWidgets('原生端呼叫 onAnnotationActivated 時帶入 id 並觸發 callback',
      (tester) async {
    String? activatedId;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    int channelId = -1;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        channelId = id;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id'),
          (call) async => null,
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onAnnotationActivated: (id) => activatedId = id,
      ),
    ));
    await tester.pumpAndSettle();

    final channel = MethodChannel(
        'cc.ugotit.elinkbook/foliate_epub_reader_view_$channelId');
    await binaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
          const MethodCall('onAnnotationActivated', 'highlight:5')),
      (_) {},
    );

    expect(activatedId, 'highlight:5');
  });

  test('EpubPositionInfo equals/hashCode/toString', () {
    const a = EpubPositionInfo(
      locatorJson: '{"cfi":"epubcfi(/4/2)","index":1,"fraction":0.3}',
      progression: 0.3,
      pageIndex: 5,
      totalPages: 20,
    );
    const b = EpubPositionInfo(
      locatorJson: '{"cfi":"epubcfi(/4/2)","index":1,"fraction":0.3}',
      progression: 0.3,
      pageIndex: 5,
      totalPages: 20,
    );
    const c = EpubPositionInfo(
      locatorJson: '{"cfi":"epubcfi(/4/3)","index":2,"fraction":0.6}',
    );

    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(equals(c)));
    expect(a.toString(), contains('locatorJson'));
    expect(a.toString(), contains('pageIndex: 5'));
  });
}
