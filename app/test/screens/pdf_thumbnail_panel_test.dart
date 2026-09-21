import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/pdf_thumbnail_panel.dart';
import 'package:elinkbook/l10n/app_localizations.dart';

/// 合成 [count] 張 2×2 像素的真實 `ui.Image`，供測試用假 `renderThumbnail`
/// callback 回傳——避免依賴真實 PDFium 渲染耗時，同時仍是真正的
/// `dart:ui` Image（可用 `debugDisposed` 驗證釋放時機，比純 Dart 假物件
/// 更貼近實際整合情境）。
Future<List<ui.Image>> _createTestImages(WidgetTester tester, int count) async {
  final images = await tester.runAsync(() async {
    final result = <ui.Image>[];
    for (var i = 0; i < count; i++) {
      final completer = Completer<ui.Image>();
      final pixels = Uint8List(2 * 2 * 4);
      ui.decodeImageFromPixels(pixels, 2, 2, ui.PixelFormat.rgba8888, completer.complete);
      result.add(await completer.future);
    }
    return result;
  });
  return images!;
}

void main() {
  testWidgets('totalPages 為 0 時顯示空狀態，不建構 GridView', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PdfThumbnailPanel(
            totalPages: 0,
            renderThumbnail: (_) async => null,
            onPageSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('pdf_thumbnail_panel_empty')), findsOneWidget);
    expect(find.byKey(const Key('pdf_thumbnail_panel_grid')), findsNothing);
  });

  testWidgets('totalPages 遠大於可視範圍時，初次建構只觸發少量縮圖載入，不會一次渲染全書',
      (tester) async {
    final images = await _createTestImages(tester, 50);
    final requested = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PdfThumbnailPanel(
            totalPages: 50,
            renderThumbnail: (index) async {
              requested.add(index);
              return images[index];
            },
            onPageSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(requested.length, lessThan(30),
        reason: '不應一次性渲染全書 50 頁縮圖，只應渲染可視附近範圍');
    expect(requested, isNot(contains(49)), reason: '清單底部（尚未捲動到）不應被提前渲染');
  });

  testWidgets('renderThumbnail 完成後，對應格子顯示縮圖影像取代載入指示器', (tester) async {
    final images = await _createTestImages(tester, 3);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PdfThumbnailPanel(
            totalPages: 3,
            renderThumbnail: (index) async => images[index],
            onPageSelected: (_) {},
          ),
        ),
      ),
    );
    // 尚未完成非同步載入前，顯示載入指示器。
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pump();
    await tester.pump();

    expect(find.byType(RawImage), findsNWidgets(3));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('點擊縮圖觸發 onPageSelected 並傳入正確頁碼索引', (tester) async {
    final images = await _createTestImages(tester, 5);
    int? selected;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PdfThumbnailPanel(
            totalPages: 5,
            renderThumbnail: (index) async => images[index],
            onPageSelected: (index) => selected = index,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('pdf_thumbnail_tile_2')));
    expect(selected, 2);
  });

  testWidgets('捲動觸發夠多不同頁縮圖載入後，快取上限之外的舊縮圖會被 dispose', (tester) async {
    final images = await _createTestImages(tester, 40);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PdfThumbnailPanel(
            totalPages: 40,
            renderThumbnail: (index) async => images[index],
            onPageSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // 捲動至清單底部，觸發足夠多不同頁的縮圖載入（超過快取上限 24 張）。
    for (var i = 0; i < 10; i++) {
      await tester.drag(
        find.byKey(const Key('pdf_thumbnail_panel_grid')),
        const Offset(0, -2000),
      );
      await tester.pump();
      await tester.pump();
    }

    expect(images[0].debugDisposed, isTrue, reason: '最早載入、已捲出畫面外的縮圖應被淘汰釋放');
  });

  testWidgets('面板從 widget tree 移除時，快取中的縮圖全部釋放', (tester) async {
    final images = await _createTestImages(tester, 5);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PdfThumbnailPanel(
            totalPages: 5,
            renderThumbnail: (index) async => images[index],
            onPageSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,home: Scaffold(body: SizedBox.shrink())));

    for (final image in images) {
      expect(image.debugDisposed, isTrue);
    }
  });

  testWidgets('面板在縮圖仍在渲染中就被 Unmount，稍後才完成的影像仍會被 dispose，不洩漏',
      (tester) async {
    final completer = Completer<ui.Image?>();
    final images = await _createTestImages(tester, 1);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PdfThumbnailPanel(
            totalPages: 1,
            renderThumbnail: (_) => completer.future,
            onPageSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    // 縮圖仍在渲染中（completer 尚未完成）時就把面板從 widget tree 移除。
    await tester.pumpWidget(const MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,home: Scaffold(body: SizedBox.shrink())));

    // 面板已 unmount 之後，非同步渲染才真正完成——這是 Critical 1 審查
    // 修正要保護的情境：遲來的 image 不會再被放進快取，必須在 `_load`
    // 的 `!mounted` 分支主動 dispose，否則原生記憶體洩漏。
    completer.complete(images[0]);
    await tester.pump();
    await tester.pump();

    expect(images[0].debugDisposed, isTrue,
        reason: '面板已 unmount，遲來的縮圖影像不應洩漏，須被 dispose()');
  });
}
