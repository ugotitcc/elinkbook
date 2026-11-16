import 'dart:async';

import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:elinkbook/sync/sync_reading_position.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/fake_inappwebview_platform.dart';
import '../support/fake_reader_feature_dependencies.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_reader_surface.dart';

/// 可在開書後讓 `load` 失敗，模擬重讀雲端位置時資料庫讀取出錯。
class _FlakyPrefs extends FakeReaderPrefsManager {
  bool failLoad = false;

  @override
  Future<LoadedPrefs> load(String bookId) {
    if (failLoad) throw StateError('load failed');
    return super.load(bookId);
  }
}

/// Issue 43：ReaderScreen 開書時並行檢查雲端閱讀位置（PRD FR-19）。
///
/// 以 [FakeReaderSurface] 觀察「畫面下了哪些跳轉指令」（ReaderScreen 只透過
/// `ReaderSurface.jumpTo` 跳轉，見 Issue 23）。
void main() {
  late FakeReaderPrefsManager prefs;
  late FakeReaderSurface surface;
  late List<String> checked;
  late Completer<ReadingPositionChoice?> pending;

  setUpAll(() {
    InAppWebViewPlatform.instance = FakeInAppWebViewPlatform();
  });

  setUp(() {
    pdfrxInitialize();
    // 與 reader_screen_test.dart 相同：ReaderScreen 會呼叫這兩個原生 channel
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('elinkbook/fullscreen'), (call) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('elinkbook/volume_key'), (call) async => null);
    prefs = FakeReaderPrefsManager();
    surface = FakeReaderSurface.pdf();
    checked = [];
    pending = Completer<ReadingPositionChoice?>();
  });

  Future<void> openReader(
    WidgetTester tester, {
    ReaderJumpTarget? jumpTarget,
  }) async {
    final trigger = SyncCheckpointTrigger(
      runCheckpoint: () async => SyncCheckpointResult.synced,
      checkReadingPositionOnOpen: (id) {
        checked.add(id);
        return pending.future;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          initialJumpTarget: jumpTarget,
          dependencies: fakeReaderFeatureDependencies(
            prefsManager: prefs,
            syncCheckpointTrigger: trigger,
            readerSurfaceFactory: (format) => surface,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
  }

  /// 模擬底層 View 渲染完成（引擎就緒，跳轉指令此後才有效）。
  Future<void> finishRendering(WidgetTester tester) async {
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();
  }

  /// 使用者回應對話框；資料庫此時已是雲端位置（由引擎寫入，這裡以 fake 模擬）。
  Future<void> answer(
    WidgetTester tester,
    ReadingPositionChoice? choice, {
    ReadingPosition? cloudPosition,
  }) async {
    if (cloudPosition != null) {
      prefs.readingPositionByBookId['b1'] = cloudPosition;
    }
    pending.complete(choice);
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
  }

  const cloud = ReadingPosition(pdfPageIndex: 7, progress: 0.7);

  testWidgets('開書時以本書 id 檢查一次雲端位置', (tester) async {
    await openReader(tester);
    expect(checked, ['b1']);
  });

  testWidgets('並行：檢查（含對話框）還沒結束，閱讀器已正常顯示、不被阻擋', (tester) async {
    await openReader(tester);
    expect(pending.isCompleted, isFalse);
    expect(find.byType(PdfReaderView), findsOneWidget);
  });

  testWidgets('帶跳轉目標開書（搜尋結果、書籤）：不檢查雲端位置', (tester) async {
    await openReader(
      tester,
      jumpTarget: const ReaderJumpTarget(pdfPageIndex: 2),
    );
    expect(checked, isEmpty);
  });

  testWidgets('閱讀器已渲染完成後選保留雲端：透過 surface 跳到雲端位置', (tester) async {
    await openReader(tester);
    await finishRendering(tester);

    await answer(tester, ReadingPositionChoice.keepCloud, cloudPosition: cloud);

    expect(surface.jumpTargets, hasLength(1));
    expect(surface.jumpTargets.single.pdfPageIndex, 7);
  });

  testWidgets('C-1：閱讀器尚未渲染完成就選保留雲端：先不跳（引擎未就緒會被靜默丟棄），渲染完成後才補跳',
      (tester) async {
    await openReader(tester);

    await answer(tester, ReadingPositionChoice.keepCloud, cloudPosition: cloud);
    expect(surface.jumpTargets, isEmpty, reason: '引擎尚未就緒，此時下跳轉指令會被靜默丟棄');

    await finishRendering(tester);
    expect(surface.jumpTargets, hasLength(1), reason: '渲染完成後必須補跳一次，不可遺失');
    expect(surface.jumpTargets.single.pdfPageIndex, 7);
  });

  testWidgets('選保留本機：不跳轉', (tester) async {
    await openReader(tester);
    await finishRendering(tester);

    await answer(tester, ReadingPositionChoice.keepLocal);

    expect(surface.jumpTargets, isEmpty);
  });

  testWidgets('未決定或無衝突（null）：不跳轉，渲染完成後也不補跳', (tester) async {
    await openReader(tester);
    await answer(tester, null);
    await finishRendering(tester);

    expect(surface.jumpTargets, isEmpty);
  });

  testWidgets('選保留雲端時畫面已被關閉：不拋例外（mounted 防護）', (tester) async {
    await openReader(tester);
    await tester.pumpWidget(const SizedBox());

    await answer(tester, ReadingPositionChoice.keepCloud, cloudPosition: cloud);

    expect(tester.takeException(), isNull);
    expect(surface.jumpTargets, isEmpty);
  });

  testWidgets('M-2：選保留雲端但重讀位置失敗：不拋未處理例外、不跳轉，閱讀器仍可用', (tester) async {
    final flaky = _FlakyPrefs();
    prefs = flaky;
    await openReader(tester);
    await finishRendering(tester);

    flaky.failLoad = true;
    pending.complete(ReadingPositionChoice.keepCloud);
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(surface.jumpTargets, isEmpty);
    expect(find.byType(PdfReaderView), findsOneWidget);
  });

  testWidgets('M-4：未渲染前選保留雲端，補跳只發生一次（不因更新初始位置而重複導覽）', (tester) async {
    await openReader(tester);

    await answer(tester, ReadingPositionChoice.keepCloud, cloudPosition: cloud);
    await finishRendering(tester);
    // 之後再次回報渲染完成（極端情況下可能重複呼叫），也不可再補跳
    await finishRendering(tester);

    expect(surface.jumpTargets, hasLength(1));
  });

  group('M-5：EPUB（Foliate）路徑', () {
    late Future<String?> Function(String, String) originalCache;

    setUpAll(() {
      originalCache = cacheBookForServing;
      cacheBookForServing = (filePath, instanceId) async => '/fake/cache/dir/current.epub';
    });

    tearDownAll(() => cacheBookForServing = originalCache);

    Future<void> openEpub(WidgetTester tester) async {
      surface = FakeReaderSurface.foliate();
      final trigger = SyncCheckpointTrigger(
        runCheckpoint: () async => SyncCheckpointResult.synced,
        checkReadingPositionOnOpen: (id) {
          checked.add(id);
          return pending.future;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            dependencies: fakeReaderFeatureDependencies(
              prefsManager: prefs,
              syncCheckpointTrigger: trigger,
              readerSurfaceFactory: (format) => surface,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
    }

    Future<void> renderEpub(WidgetTester tester) async {
      tester.widget<FoliateReaderView>(find.byType(FoliateReaderView)).onPageRendered();
      await tester.pump();
    }

    const cloudEpub = ReadingPosition(
      epubLocatorJson: '{"cfi":"epubcfi(/6/8!/4/2)","index":3,"fraction":0.42}',
      progress: 0.42,
    );

    testWidgets('已渲染後選保留雲端：以雲端的 CFI 與進度組成跳轉目標', (tester) async {
      await openEpub(tester);
      await renderEpub(tester);

      await answer(tester, ReadingPositionChoice.keepCloud, cloudPosition: cloudEpub);

      expect(surface.jumpTargets, hasLength(1));
      expect(surface.jumpTargets.single.cfi, cloudEpub.epubLocatorJson);
      expect(surface.jumpTargets.single.progression, 0.42);
      expect(surface.jumpTargets.single.pdfPageIndex, isNull);
    });

    testWidgets('未渲染前選保留雲端：渲染完成後才補跳，且只補一次', (tester) async {
      await openEpub(tester);

      await answer(tester, ReadingPositionChoice.keepCloud, cloudPosition: cloudEpub);
      expect(surface.jumpTargets, isEmpty);

      await renderEpub(tester);
      await renderEpub(tester);
      expect(surface.jumpTargets, hasLength(1));
      expect(surface.jumpTargets.single.cfi, cloudEpub.epubLocatorJson);
    });
  });
}
