import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_annotation_decoration.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/zone_action.dart';

/// 驅動 [PdfReaderView] 底層 AndroidView 完成建立流程所需的最小 mock，比照
/// `epub_reader_view_test.dart` 的 `_pumpEpubReaderView` 模式。
Future<List<MethodCall>> _pumpPdfReaderView(
  WidgetTester tester,
  PdfReaderView widget,
) async {
  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final instanceCalls = <MethodCall>[];

  binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
      (call) async {
    if (call.method == 'create') {
      final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
      binaryMessenger.setMockMethodCallHandler(
        MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
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
  testWidgets('_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含 fitMode',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        fitMode: PdfFitMode.fitWidth,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['path'], '/tmp/sample.pdf');
    expect(openBookCall.arguments['initialPreferences'], {
      'fitMode': 'fitWidth',
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'rtl',
      'isLandscape': false,
    });
  });

  testWidgets('fitMode 為 null 時，initialPreferences 僅包含雙頁/橫向的預設值（不再是空 map）',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'rtl',
      'isLandscape': false,
    });
  });

  testWidgets('fitMode 變動時，didUpdateWidget 呼叫 setPdfPreferences 並帶入新值',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
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
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        fitMode: PdfFitMode.pageFit,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        fitMode: PdfFitMode.actualSize, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPdfPreferences');
    expect(instanceCalls.single.arguments, {
      'fitMode': 'actualSize',
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'rtl',
      'isLandscape': false,
    });
  });

  testWidgets('fitMode 未變動時，didUpdateWidget 不觸發任何 setPdfPreferences 呼叫',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    final widget = const PdfReaderView(
      filePath: '/tmp/sample.pdf',
      onPageRendered: _noop,
      onError: _noopError,
      fitMode: PdfFitMode.pageFit,
    );
    await tester.pumpWidget(MaterialApp(home: widget));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(MaterialApp(home: widget));
    await tester.pumpAndSettle();

    expect(instanceCalls, isEmpty);
  });

  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含 contrast／brightness',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        contrast: 20.0,
        brightness: -15.0,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {
      'contrast': 20.0,
      'brightness': -15.0,
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'rtl',
      'isLandscape': false,
    });
  });

  testWidgets('contrast／brightness 變動時，didUpdateWidget 呼叫 setPdfPreferences',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
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
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        contrast: 10.0,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        contrast: 10.0,
        brightness: 25.0, // 新增一個原本是 null 的欄位
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPdfPreferences');
    expect(instanceCalls.single.arguments, {
      'contrast': 10.0,
      'brightness': 25.0,
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'rtl',
      'isLandscape': false,
    });
  });

  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含 boldStrength',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        boldStrength: 0.5,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {
      'boldStrength': 0.5,
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'rtl',
      'isLandscape': false,
    });
  });

  testWidgets('boldStrength 變動時，didUpdateWidget 呼叫 setPdfPreferences',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
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
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        boldStrength: 0.2,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        boldStrength: 0.8, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPdfPreferences');
    expect(instanceCalls.single.arguments, {
      'boldStrength': 0.8,
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'rtl',
      'isLandscape': false,
    });
  });

  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 包含 cropMode／cropRect',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        cropMode: PdfCropMode.autoDetect,
        cropRect: PdfCropRect(left: 0.05, top: 0.1, right: 0.95, bottom: 0.9),
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {
      'cropMode': 'autoDetect',
      'cropRect': {'left': 0.05, 'top': 0.1, 'right': 0.95, 'bottom': 0.9},
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'rtl',
      'isLandscape': false,
    });
  });

  testWidgets('cropMode 變動時，didUpdateWidget 呼叫 setPdfPreferences',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
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
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        cropMode: PdfCropMode.none,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        cropMode: PdfCropMode.autoDetect, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPdfPreferences');
    expect(instanceCalls.single.arguments, {
      'cropMode': 'autoDetect',
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'rtl',
      'isLandscape': false,
    });
  });

  testWidgets('收到原生端 onCropRectComputed 時，正確觸發回呼', (tester) async {
    PdfCropRect? received;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        onCropRectComputed: (rect) => received = rect,
      ),
    ));
    await tester.pumpAndSettle();

    // 模擬原生端主動呼叫 onCropRectComputed（比照 EpubReaderView 測試對
    // onLayoutResolved 的模擬方式：透過 binaryMessenger 直接送一個
    // MethodCall 給 Dart 端已註冊的 handler）。
    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onCropRectComputed', {
      'left': 0.02,
      'top': 0.03,
      'right': 0.98,
      'bottom': 0.97,
    }));
    await binaryMessenger.handlePlatformMessage(
        instanceChannel!.name, data, (_) {});

    expect(received,
        const PdfCropRect(left: 0.02, top: 0.03, right: 0.98, bottom: 0.97));
  });

  testWidgets('cropEditModeActive 由 false 變 true 時，didUpdateWidget 呼叫 enterCropEditMode',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
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
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        cropEditModeActive: true, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'enterCropEditMode');
    expect(instanceCalls.single.arguments, isNull);
  });

  testWidgets('cropEditModeActive 由 true 變 false 時，didUpdateWidget 呼叫 exitCropEditMode',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
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
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        cropEditModeActive: true,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        cropEditModeActive: false, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'exitCropEditMode');
    expect(instanceCalls.single.arguments, isNull);
  });

  testWidgets('cropEditModeActive 未變動時，不觸發 enterCropEditMode／exitCropEditMode',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    final widget = const PdfReaderView(
      filePath: '/tmp/sample.pdf',
      onPageRendered: _noop,
      onError: _noopError,
      cropEditModeActive: false,
    );
    await tester.pumpWidget(MaterialApp(home: widget));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(MaterialApp(home: widget));
    await tester.pumpAndSettle();

    expect(instanceCalls, isEmpty);
  });

  testWidgets('收到原生端 onCropRectSelected 時，正確觸發回呼', (tester) async {
    PdfCropRect? received;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        onCropRectSelected: (rect) => received = rect,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onCropRectSelected', {
      'left': 0.1,
      'top': 0.15,
      'right': 0.9,
      'bottom': 0.85,
    }));
    await binaryMessenger.handlePlatformMessage(
        instanceChannel!.name, data, (_) {});

    expect(received,
        const PdfCropRect(left: 0.1, top: 0.15, right: 0.9, bottom: 0.85));
  });

  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialPreferences 正確包含非預設的雙頁/橫向欄位',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
        dualPageCoverAlone: false,
        dualPageDirection: DualPageDirection.rtl,
        isLandscape: true,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {
      'dualPageMode': 'always',
      'dualPageCoverAlone': false,
      'dualPageDirection': 'rtl',
      'isLandscape': true,
    });
  });

  testWidgets('dualPageMode 變動時，didUpdateWidget 呼叫 setPdfPreferences 並帶入完整最新狀態',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
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
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPdfPreferences');
    expect(instanceCalls.single.arguments, {
      'dualPageMode': 'always',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'rtl',
      'isLandscape': false,
    });
  });

  testWidgets('isLandscape 變動時，didUpdateWidget 呼叫 setPdfPreferences',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
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
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        isLandscape: true, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPdfPreferences');
    expect(instanceCalls.single.arguments, {
      'dualPageMode': 'auto',
      'dualPageCoverAlone': true,
      'dualPageDirection': 'rtl',
      'isLandscape': true,
    });
  });

  testWidgets('dualPageCoverAlone／dualPageDirection 變動時，didUpdateWidget 呼叫 setPdfPreferences',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
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
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageCoverAlone: false, // 變動
        dualPageDirection: DualPageDirection.rtl, // 變動
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPdfPreferences');
    expect(instanceCalls.single.arguments, {
      'dualPageMode': 'auto',
      'dualPageCoverAlone': false,
      'dualPageDirection': 'rtl',
      'isLandscape': false,
    });
  });

  testWidgets('雙頁/橫向欄位皆未變動時，didUpdateWidget 不觸發任何 setPdfPreferences 呼叫',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    final widget = const PdfReaderView(
      filePath: '/tmp/sample.pdf',
      onPageRendered: _noop,
      onError: _noopError,
      dualPageMode: DualPageMode.always,
      dualPageCoverAlone: false,
      dualPageDirection: DualPageDirection.rtl,
      isLandscape: true,
    );
    await tester.pumpWidget(MaterialApp(home: widget));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(MaterialApp(home: widget));
    await tester.pumpAndSettle();

    expect(instanceCalls, isEmpty);
  });

  testWidgets('開書完成後，收到原生端 onPageChanged 事件時正確解析 PdfPageInfo',
      (tester) async {
    PdfPageInfo? received;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        onPageChanged: (info) => received = info,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onPageChanged', {
      'pageIndex': 3,
      'totalPages': 20,
    }));
    await binaryMessenger.handlePlatformMessage(
        instanceChannel!.name, data, (_) {});

    expect(received, const PdfPageInfo(pageIndex: 3, totalPages: 20));
  });

  testWidgets(
      'PdfReaderView.jumpToPage()（強型別 static helper）呼叫原生端 jumpToPage method channel',
      (tester) async {
    // 審查修正：測試改為驅動真正的公開 API（static helper + GlobalKey），
    // 而非只測 private State 的 `as dynamic` 呼叫——production code
    // （ReaderScreen）實際上會呼叫的是這個 static helper，測試應驗證這條
    // 真正會被使用的路徑。
    final key = GlobalKey<State<PdfReaderView>>();
    final calls = await _pumpPdfReaderView(
      tester,
      PdfReaderView(
        key: key,
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );
    calls.clear();

    PdfReaderView.jumpToPage(key, 7);
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'jumpToPage');
    expect(calls.single.arguments, 7);
  });

  testWidgets(
      '_onPlatformViewCreated 呼叫 openBook 時，initialPageIndex 非 null 時正確帶入',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        initialPageIndex: 4,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPageIndex'], 4);
  });

  testWidgets('initialPageIndex 為 null 時，openBook 的 arguments 不包含該 key',
      (tester) async {
    final calls = await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(
      (openBookCall.arguments as Map<Object?, Object?>)
          .containsKey('initialPageIndex'),
      isFalse,
    );
  });

  testWidgets('收到原生端 onSelectionRectComputed 事件時正確解析 PdfSelectionInfo',
      (tester) async {
    PdfSelectionInfo? received;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        onSelectionRectComputed: (info) => received = info,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onSelectionRectComputed', {
      'pageIndex': 2,
      'left': 0.1,
      'top': 0.2,
      'right': 0.3,
      'bottom': 0.4,
      // widget* 系列為相對整個 View（含 letterbox 留白）的百分比矩形，
      // 供浮動工具列定位使用（見 Finding 1 修正：原本誤用 content-relative
      // 的 rect 定位工具列，letterbox 情境下會偏移）；left/top/right/bottom
      // 維持 content-relative，供持久化/重繪使用，兩者刻意不同。
      'widgetLeft': 0.12,
      'widgetTop': 0.22,
      'widgetRight': 0.32,
      'widgetBottom': 0.42,
    }));
    await binaryMessenger.handlePlatformMessage(instanceChannel!.name, data, (_) {});

    expect(
      received,
      const PdfSelectionInfo(
        pageIndex: 2,
        rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
        widgetRect: PercentRect(left: 0.12, top: 0.22, right: 0.32, bottom: 0.42),
      ),
    );
  });

  testWidgets('收到原生端 onSelectionCanceled 事件時觸發 callback', (tester) async {
    var canceled = false;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        onSelectionCanceled: () => canceled = true,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onSelectionCanceled', null));
    await binaryMessenger.handlePlatformMessage(instanceChannel!.name, data, (_) {});

    expect(canceled, isTrue);
  });

  testWidgets('refreshAnnotations 呼叫 invokeMethod 並帶上序列化後的標記清單',
      (tester) async {
    final key = GlobalKey<State<PdfReaderView>>();
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: PdfReaderView(
        key: key,
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();

    PdfReaderView.refreshAnnotations(key, [
      PdfAnnotationDecoration.forHighlight(
        pageIndex: 1,
        rect: const PercentRect(left: 0, top: 0, right: 1, bottom: 0.1),
        tint: 0x73FDE047,
        isUnderline: false,
      ),
    ]);

    final call = instanceCalls.firstWhere((c) => c.method == 'refreshAnnotations');
    final annotations = call.arguments['annotations'] as List;
    expect(annotations.single['pageIndex'], 1);
    expect(annotations.single['isNoteOnly'], isFalse);
  });

  testWidgets(
      '長按拖曳觸發 beginAnnotationSelection／updateAnnotationSelection／endAnnotationSelection，'
      '座標為相對 widget 自身尺寸的百分比（審查修正 1.1：手勢辨識改由 Flutter 端主導）',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 200,
          height: 100,
          child: PdfReaderView(
            filePath: '/tmp/sample.pdf',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(20, 10));
    // 等待超過長按判定門檻（Flutter 預設 500ms），期間手指未移動，
    // GestureDetector 的 LongPressGestureRecognizer 應會勝出競技場。
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(60, 30));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final begin =
        instanceCalls.firstWhere((c) => c.method == 'beginAnnotationSelection');
    expect((begin.arguments as Map)['xPct'] as double, closeTo(20 / 200, 0.02));
    expect((begin.arguments as Map)['yPct'] as double, closeTo(10 / 100, 0.02));

    final update = instanceCalls
        .firstWhere((c) => c.method == 'updateAnnotationSelection');
    expect((update.arguments as Map)['xPct'] as double, closeTo(80 / 200, 0.02));
    expect((update.arguments as Map)['yPct'] as double, closeTo(40 / 100, 0.02));

    expect(instanceCalls.any((c) => c.method == 'endAnnotationSelection'), isTrue);
  });

  testWidgets('第二指觸碰時觸發 cancelAnnotationSelection（審查修正 1.1：多指偵測改由 Dart 端負責）',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 200,
          height: 100,
          child: PdfReaderView(
            filePath: '/tmp/sample.pdf',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final first = await tester.startGesture(topLeft + const Offset(20, 10));
    final second = await tester.startGesture(topLeft + const Offset(100, 60));
    await tester.pump();

    expect(instanceCalls.any((c) => c.method == 'cancelAnnotationSelection'), isTrue);

    await first.up();
    await second.up();
  });

  testWidgets('9 個 Key(nav_zone_\$index) 皆存在，點擊觸發對應 onZoneAction', (tester) async {
    final capturedActions = <ZoneAction>[];
    final calls = await _pumpPdfReaderView(
      tester,
      PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        navZoneActions: const [
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
        ],
        onZoneAction: capturedActions.add,
      ),
    );
    calls.clear();

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

  testWidgets('showNavZoneDebugOverlay=true 時，格子顯示對應動作文字標籤', (tester) async {
    await _pumpPdfReaderView(
      tester,
      PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        navZoneActions: const [
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
        ],
        showNavZoneDebugOverlay: true,
      ),
    );

    expect(find.text('上一頁'), findsWidgets);
    expect(find.text('選單'), findsWidgets);
    expect(find.text('下一頁'), findsWidgets);
  });

  testWidgets('build() 不再註冊 onHorizontalDragEnd（ADR 0010，滑動翻頁已移除）',
      (tester) async {
    await _pumpPdfReaderView(
      tester,
      const PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final detector = tester.widget<GestureDetector>(find.byType(GestureDetector));
    expect(detector.onHorizontalDragEnd, isNull);
    expect(detector.onTapUp, isNotNull);
    expect(detector.onLongPressStart, isNotNull);
  });
}

void _noop() {}
void _noopError(String message) {}
