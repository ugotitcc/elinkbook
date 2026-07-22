import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';

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
}
