import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/book_format.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import '../support/fake_reader_feature_dependencies.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_reader_surface.dart';
import '../support/pump_until_pdf_ready.dart';

/// ReaderScreen 與「閱讀面」的接線測試（epic-54 Issue 23）：經
/// `ReaderFeatureDependencies.readerSurfaceFactory` 注入 [FakeReaderSurface]，
/// 驗證 ReaderScreen 下了哪些指令；View 本身仍是真實掛載的，只是不會收到指令。
void main() {
  setUp(() {
    pdfrxInitialize();
    // ReaderScreen 初始化時會呼叫 elinkbook/fullscreen（非 awaited）；
    // 理由同 reader_screen_test.dart 的 setUp，全域註冊避免競態洩漏。
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('elinkbook/fullscreen'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('elinkbook/volume_key'),
      (call) async => null,
    );
  });

  Future<GlobalKey<State<ReaderScreen>>> pumpPdfReader(
    WidgetTester tester,
    FakeReaderSurface surface, {
    ReaderJumpTarget? initialJumpTarget,
  }) async {
    final key = GlobalKey<State<ReaderScreen>>();
    BookFormat? requestedFormat;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_surface',
          initialJumpTarget: initialJumpTarget,
          dependencies: fakeReaderFeatureDependencies(
            prefsManager: FakeReaderPrefsManager(),
            readerSurfaceFactory: (format) {
              requestedFormat = format;
              return surface;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await pumpUntilPdfReady(
      tester,
      condition: () =>
          find.byKey(const Key('reader_loading_indicator')).evaluate().isEmpty,
    );
    expect(requestedFormat, BookFormat.pdf, reason: '工廠應收到依副檔名偵測出的格式');
    return key;
  }

  testWidgets('PDF View 以注入 surface 的 viewKey 掛載', (tester) async {
    final surface = FakeReaderSurface.pdf();
    await pumpPdfReader(tester, surface);

    final view = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(view.key, surface.pdf!.viewKey);
  });

  testWidgets('熱區翻頁：下一頁 → 換頁後中止拖曳（順序逐字沿用）', (tester) async {
    final surface = FakeReaderSurface.pdf();
    final key = await pumpPdfReader(tester, surface);
    surface.calls.clear();

    ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
    await tester.pump();

    expect(surface.calls, ['nextPage', 'pdf.cancelActiveSelectionDrag']);
  });

  testWidgets('熱區翻頁：上一頁 → 換頁後中止拖曳（順序逐字沿用）', (tester) async {
    final surface = FakeReaderSurface.pdf();
    final key = await pumpPdfReader(tester, surface);
    surface.calls.clear();

    ReaderScreen.triggerZoneAction(key, ZoneAction.previousPage);
    await tester.pump();

    expect(surface.calls, ['previousPage', 'pdf.cancelActiveSelectionDrag']);
  });

  testWidgets('開書帶跳轉目標：只疊暫態高亮、不導覽（shouldNavigate: false）', (tester) async {
    final surface = FakeReaderSurface.pdf(showsTransientHighlight: true);
    await pumpPdfReader(
      tester,
      surface,
      initialJumpTarget: const ReaderJumpTarget(
        pdfPageIndex: 0,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
      ),
    );

    expect(surface.calls, contains('showTransientHighlight'));
    expect(surface.calls, isNot(contains('jumpTo')));
  });
}
