import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/tts_audio_handler.dart';
import 'package:elinkbook/reader/tts_audio_handler_startup.dart';
import 'package:elinkbook/reader/tts_controller.dart';
import 'package:elinkbook/reader/tts_segment_cfi.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_inappwebview_platform.dart';
import '../support/fake_tts_audio_player.dart';
import '../support/fake_tts_provider.dart';

// epic-61 Issue 2（F1）：handler 晚到注入。holder 在背景完成前是 pending，
// ReaderScreen 監聽 holder：handler 晚到時補 attachController；降級晚到時
// 補顯示提示一次。記錄呼叫的 handler 子類別驗證 attach 時機與次數。
class _RecordingTtsAudioHandler extends TtsAudioHandler {
  int attachCount = 0;
  final attachedTitles = <String>[];

  @override
  void attachController(TtsController controller, {required String bookTitle}) {
    attachCount++;
    attachedTitles.add(bookTitle);
    super.attachController(controller, bookTitle: bookTitle);
  }
}

const _snackbarKey = Key('reader_tts_degraded_snackbar');
const _ttsButtonKey = Key('reader_chrome_tts_button');

Widget _app({
  required FakeReaderPrefsManager prefs,
  required TtsAudioHandlerHolder? ttsAudio,
  required String bookId,
  String? bookTitle,
}) {
  return MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
    home: ReaderScreen(
      filePath: 'test/fixtures/sample.epub',
      bookId: bookId,
      bookTitle: bookTitle,
      prefsManager: prefs,
      isFixedLayout: false,
      ttsProvider: FakeTtsProvider(),
      ttsAudio: ttsAudio,
    ),
  );
}

/// 讓指定順位的 FoliateReaderView 完成渲染回呼（比照既有接線測試流程）。
Future<void> _resolveLayout(WidgetTester tester, int index) async {
  final foliateView =
      tester.widget<FoliateReaderView>(find.byType(FoliateReaderView).at(index));
  foliateView.onPageRendered();
  foliateView.onLayoutResolved?.call(
    const EpubLayoutInfo(
      isFixedLayout: false,
      writingMode: WritingMode.horizontal,
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// 點開指定順位的朗讀按鈕，觸發該畫面建立 TtsController。
Future<void> _openTts(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(_ttsButtonKey).at(index));
  await tester.pump();
}

void main() {
  late FakeReaderPrefsManager prefs;
  late Future<String?> Function(String, String) originalCacheBookForServing;

  setUpAll(() {
    InAppWebViewPlatform.instance = FakeInAppWebViewPlatform();
    originalCacheBookForServing = cacheBookForServing;
    // 比照 reader_screen_test.dart：繞過 Dart 端檔案系統檢查，確保
    // FoliateReaderView 的 _cacheBook() 在測試環境中能順利完成。
    cacheBookForServing = (filePath, instanceId) async {
      return '/fake/cache/dir/current.epub';
    };
  });

  tearDownAll(() {
    cacheBookForServing = originalCacheBookForServing;
  });

  setUp(() {
    prefs = FakeReaderPrefsManager();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('elinkbook/fullscreen'),
      (call) async => null,
    );
    // EPUB 開書會附加原生 ReaderView，離開時經 volume_key 通知分離。
    messenger.setMockMethodCallHandler(
      const MethodChannel('elinkbook/volume_key'),
      (call) async => null,
    );
  });

  group('handler 晚到注入', () {
    testWidgets('controller 已建立、handler 晚到 → 補 attach 一次，書名正確',
        (tester) async {
      final completer = Completer<TtsAudioHandler>();
      final recording = _RecordingTtsAudioHandler();
      final holder =
          startTtsAudioHandlerInBackground(() => completer.future);

      await tester.pumpWidget(
        _app(prefs: prefs, ttsAudio: holder, bookId: 'b_late', bookTitle: '晚到書'),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await _resolveLayout(tester, 0);
      await _openTts(tester, 0);
      expect(recording.attachCount, 0);

      // handler 晚到。
      completer.complete(recording);
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await tester.pump();

      expect(recording.attachCount, 1);
      expect(recording.attachedTitles, ['晚到書']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('handler 先到、後建 controller → 行為與現況相同，只 attach 一次',
        (tester) async {
      final recording = _RecordingTtsAudioHandler();
      final holder = TtsAudioHandlerHolder.ready(recording);

      await tester.pumpWidget(
        _app(prefs: prefs, ttsAudio: holder, bookId: 'b_early', bookTitle: '先到書'),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await _resolveLayout(tester, 0);
      await _openTts(tester, 0);

      expect(recording.attachCount, 1);
      expect(recording.attachedTitles, ['先到書']);
      expect(recording.mediaItem.value?.title, '先到書');
      expect(tester.takeException(), isNull);
    });

    testWidgets('dispose 後 holder 才通知 → 不例外、不 attach', (tester) async {
      final completer = Completer<TtsAudioHandler>();
      final recording = _RecordingTtsAudioHandler();
      final holder =
          startTtsAudioHandlerInBackground(() => completer.future);

      await tester.pumpWidget(
        _app(prefs: prefs, ttsAudio: holder, bookId: 'b_gone', bookTitle: '離開書'),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await _resolveLayout(tester, 0);
      await _openTts(tester, 0);

      // 離開閱讀器。
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);

      // holder 才完成：已卸載的畫面不可再被 attach，也不可拋例外。
      completer.complete(recording);
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await tester.pump();

      expect(recording.attachCount, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('降級晚到（閱讀器已開啟後才失敗）', () {
    testWidgets('立即顯示提示一次；之後重進不重複', (tester) async {
      final completer = Completer<TtsAudioHandler>();
      final holder =
          startTtsAudioHandlerInBackground(() => completer.future);

      await tester.pumpWidget(
        _app(prefs: prefs, ttsAudio: holder, bookId: 'b_late_fail'),
      );
      await tester.pump();
      expect(find.byKey(_snackbarKey), findsNothing);

      // 閱讀器開著時 init 失敗。
      completer.completeError(StateError('綁定逾時'));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await tester.pump();

      expect(find.byKey(_snackbarKey), findsOneWidget);

      // 離開再重進：同一個 holder 已提示過，不重複。
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _app(prefs: prefs, ttsAudio: holder, bookId: 'b_late_fail'),
      );
      await tester.pump();

      expect(find.byKey(_snackbarKey), findsNothing);
    });

    testWidgets('通知後立即排程 frame，閒置畫面不必等外部重繪提示才出現（審查 I-1）',
        (tester) async {
      final completer = Completer<TtsAudioHandler>();
      final holder =
          startTtsAudioHandlerInBackground(() => completer.future);

      await tester.pumpWidget(
        _app(prefs: prefs, ttsAudio: holder, bookId: 'b_late_fail_frame'),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      // 先把畫面沖到閒置：沒有待處理的 frame，等同電子紙上靜止閱讀的情況。
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: '前置條件：畫面已閒置，否則下面的斷言沒有鑑別力');

      completer.completeError(StateError('綁定逾時'));
      // 只讓背景 Future 完成，不手動 pump——模擬真機上沒有外部觸發重繪。
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));

      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'post-frame 回呼不會自己要求 frame；必須主動排程，否則提示要等下一次重繪');
    });

    testWidgets('晚到成功時不顯示提示', (tester) async {
      final completer = Completer<TtsAudioHandler>();
      final holder =
          startTtsAudioHandlerInBackground(() => completer.future);

      await tester.pumpWidget(
        _app(prefs: prefs, ttsAudio: holder, bookId: 'b_late_ok'),
      );
      await tester.pump();

      completer.complete(TtsAudioHandler());
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await tester.pump();

      expect(find.byKey(_snackbarKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('兩個 ReaderScreen 並存（閱讀器→單書搜尋→回閱讀器）', () {
    testWidgets('先關後建立者：不會把先前畫面的綁定拆掉', (tester) async {
      final recording = _RecordingTtsAudioHandler();
      final holder = TtsAudioHandlerHolder.ready(recording);
      Widget column({required bool withSecond}) {
        return MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                key: const ValueKey('wrap_first'),
                child: ReaderScreen(
                  filePath: 'test/fixtures/sample.epub',
                  bookId: 'b_first',
                  bookTitle: '第一本書',
                  prefsManager: prefs,
                  isFixedLayout: false,
                  ttsProvider: FakeTtsProvider(),
                  ttsAudio: holder,
                ),
              ),
              if (withSecond)
                Expanded(
                  key: const ValueKey('wrap_second'),
                  child: ReaderScreen(
                    filePath: 'test/fixtures/sample.epub',
                    bookId: 'b_second',
                    bookTitle: '第二本書',
                    prefsManager: prefs,
                    isFixedLayout: false,
                    ttsProvider: FakeTtsProvider(),
                    ttsAudio: holder,
                  ),
                ),
            ],
          ),
        );
      }

      // 先建立者開書、建 controller → 綁定第一本書。
      await tester.pumpWidget(column(withSecond: false));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await _resolveLayout(tester, 0);
      await _openTts(tester, 0);
      expect(recording.mediaItem.value?.title, '第一本書');

      // 後建立者開啟（尚未建 controller、不碰 TTS），再先關掉。
      await tester.pumpWidget(column(withSecond: true));
      await tester.pump();
      await tester.pumpWidget(column(withSecond: false));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(recording.mediaItem.value?.title, '第一本書');
    });

    testWidgets('先關先建立者：解綁自己的綁定；最終狀態與存活畫面一致',
        (tester) async {
      final recording = _RecordingTtsAudioHandler();
      final holder = TtsAudioHandlerHolder.ready(recording);
      Widget column({required bool withFirst}) {
        return MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (withFirst)
                Expanded(
                  key: const ValueKey('wrap_first'),
                  child: ReaderScreen(
                    filePath: 'test/fixtures/sample.epub',
                    bookId: 'b_first',
                    bookTitle: '第一本書',
                    prefsManager: prefs,
                    isFixedLayout: false,
                    ttsProvider: FakeTtsProvider(),
                    ttsAudio: holder,
                  ),
                ),
              Expanded(
                key: const ValueKey('wrap_second'),
                child: ReaderScreen(
                  filePath: 'test/fixtures/sample.epub',
                  bookId: 'b_second',
                  bookTitle: '第二本書',
                  prefsManager: prefs,
                  isFixedLayout: false,
                  ttsProvider: FakeTtsProvider(),
                  ttsAudio: holder,
                ),
              ),
            ],
          ),
        );
      }

      await tester.pumpWidget(column(withFirst: true));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      // 兩個畫面都建 controller：後建者搶到綁定（單一實例語意不變）。
      await _resolveLayout(tester, 0);
      await _resolveLayout(tester, 1);
      await _openTts(tester, 0);
      await _openTts(tester, 1);
      expect(recording.mediaItem.value?.title, '第二本書');

      // 先關先建立者：handler 當下綁的不是它，不可解綁存活畫面。
      await tester.pumpWidget(column(withFirst: false));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(recording.mediaItem.value?.title, '第二本書');

      // 再關後建立者：綁定清空。
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(recording.mediaItem.value, isNull);
    });

    testWidgets('降級提示在兩個畫面並存時只顯示一次', (tester) async {
      final holder = TtsAudioHandlerHolder.degraded();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ReaderScreen(
                  filePath: 'test/fixtures/sample.epub',
                  bookId: 'b_notice_first',
                  prefsManager: prefs,
                  isFixedLayout: false,
                  ttsProvider: FakeTtsProvider(),
                  ttsAudio: holder,
                ),
              ),
              Expanded(
                child: ReaderScreen(
                  filePath: 'test/fixtures/sample.epub',
                  bookId: 'b_notice_second',
                  prefsManager: prefs,
                  isFixedLayout: false,
                  ttsProvider: FakeTtsProvider(),
                  ttsAudio: holder,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      // 兩個 Scaffold 共用同一個 ScaffoldMessenger，同一則 SnackBar 會在每個
      // Scaffold 各畫一份，所以這裡用 findsWidgets，不以數量判斷「只提示一次」。
      expect(find.byKey(_snackbarKey), findsWidgets);
      expect(holder.consumeDegradedNotice(), isFalse,
          reason: '提示已被其中一個畫面消耗，另一個畫面不可再拿到');

      // ScaffoldMessenger 會把多則 SnackBar 排隊、一次只顯示一則；若兩個畫面都
      // consume 到 true，第一則消失後第二則會接著出現，所以要等過兩個顯示週期。
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(_snackbarKey), findsNothing,
          reason: '只能有一個畫面拿到提示，不可有第二則排隊後出現');
    });
  });

  // 注意：flutter_test 環境下 FoliateReaderView.loadTtsSegments() 恆回傳空清單，
  // ReaderScreen 內的 TtsController 無法進入 playing，所以這裡只在 handler 層級驗證
  // 「已在播放的 controller 被 attach 時，playbackState 會同步為 playing」。
  // 晚到 attach 走 ReaderScreen 的路徑，由上面的「補 attach 一次」案例守住。
  group('attach 時的播放狀態同步（handler 層級）', () {
    test('controller 已在播放時 attach → playbackState.playing 為 true',
        () async {
      const segments = [
        TtsSegmentCfi(segmentId: '0', cfi: 'epubcfi(/6/4!/1:0)', text: '第一句。'),
        TtsSegmentCfi(segmentId: '1', cfi: 'epubcfi(/6/4!/1:5)', text: '第二句。'),
      ];
      final controller = TtsController(
        provider: FakeTtsProvider(),
        player: FakeTtsAudioPlayer(),
        loadSegments: () async => segments,
      );
      await controller.play();
      expect(controller.status, TtsPlaybackStatus.playing);

      final handler = TtsAudioHandler();
      handler.attachController(controller, bookTitle: '播放中');

      expect(handler.playbackState.value.playing, isTrue);
    });
  });
}
