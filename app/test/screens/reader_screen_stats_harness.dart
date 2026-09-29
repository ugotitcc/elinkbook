import 'package:clock/clock.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/library/library_repository.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/search/search_repository.dart';
import 'package:elinkbook/stats/reading_stats_repository.dart';
import 'package:elinkbook/stats/reading_stats_tracker.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/fake_inappwebview_platform.dart';
import '../support/fake_reader_prefs_manager.dart';

/// 三個 ReaderScreen 統計測試檔共用的常數與工具（epic-9-stats Issue 4）。
const String kStatsTestBookId = 'stats-book';
const String kStatsTestBookTitle = '統計測試書';

/// 在測試檔的 `main()` 開頭呼叫：註冊 `reader_screen_test.dart` 既有的環境設定
/// （假 WebView 平台、略過檔案系統的書籍快取、全螢幕 channel、pdfrx 初始化）。
void registerReaderStatsTestEnvironment() {
  late Future<String?> Function(String, String) originalCacheBookForServing;

  setUpAll(() {
    InAppWebViewPlatform.instance = FakeInAppWebViewPlatform();
    originalCacheBookForServing = cacheBookForServing;
    cacheBookForServing =
        (filePath, instanceId) async => '/fake/cache/dir/current.epub';
  });

  tearDownAll(() {
    cacheBookForServing = originalCacheBookForServing;
  });

  setUp(() {
    pdfrxInitialize();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/fullscreen'),
      (call) async => null,
    );
  });

  // 生命週期狀態掛在全域 binding 上，不會隨測試重置：每個測試結束時還原為前景，
  // 避免上一個測試停在 paused，讓下一個測試的「進入背景」變成空操作。
  tearDown(() {
    _stepLifecycle(TestWidgetsFlutterBinding.instance, AppLifecycleState.resumed);
  });
}

/// 依 Flutter 允許的相鄰狀態逐步轉換（resumed ↔ inactive ↔ hidden ↔ paused），
/// 不能直接由 paused 跳到 resumed（`AppLifecycleListener` 會斷言失敗；
/// 有 PDF 測試留下的監聽時尤其明顯）。
void _stepLifecycle(WidgetsBinding binding, AppLifecycleState target) {
  const order = [
    AppLifecycleState.resumed,
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  var index = order.indexOf(binding.lifecycleState ?? AppLifecycleState.resumed);
  final targetIndex = order.indexOf(target);
  while (index != targetIndex) {
    index += targetIndex > index ? 1 : -1;
    binding.handleAppLifecycleStateChanged(order[index]);
  }
}

/// 模擬 App 進入背景（依序經過 inactive、hidden，最後 paused）。
void moveAppToBackground(WidgetTester tester) =>
    _stepLifecycle(tester.binding, AppLifecycleState.paused);

/// 模擬 App 回到前景（依序經過 hidden、inactive，最後 resumed）。
void moveAppToForeground(WidgetTester tester) =>
    _stepLifecycle(tester.binding, AppLifecycleState.resumed);

MaterialApp _app(Widget home) => MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: home,
    );

/// 開啟閱讀器。[markRendered] 為 true 時（預設）呼叫底層 View 的
/// `onPageRendered`，讓畫面離開載入中狀態（並取消 30 秒開書逾時計時器，
/// 否則之後 `pump` 超過 30 秒會被判定為開書逾時）。
Future<void> pumpStatsReader(
  WidgetTester tester, {
  String filePath = 'test/fixtures/sample.epub',
  String? bookTitle = kStatsTestBookTitle,
  ReadingStatsRepository? readingStatsRepository,
  ReadingStatsTracker? readingStatsTracker,
  SearchRepository? searchRepository,
  LibraryRepository? libraryRepository,
  GlobalKey<State<ReaderScreen>>? readerKey,
  bool markRendered = true,
}) async {
  await tester.pumpWidget(
    _app(
      ReaderScreen(
        key: readerKey,
        filePath: filePath,
        bookId: kStatsTestBookId,
        bookTitle: bookTitle,
        prefsManager: FakeReaderPrefsManager(),
        isFixedLayout: filePath.endsWith('.epub') ? false : null,
        readingStatsRepository: readingStatsRepository,
        readingStatsTracker: readingStatsTracker,
        searchRepository: searchRepository,
        libraryRepository: libraryRepository,
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(() => Future.delayed(Duration.zero));
  await tester.pump();
  if (!markRendered) return;
  if (filePath.endsWith('.pdf')) {
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
  } else {
    tester
        .widget<FoliateReaderView>(find.byType(FoliateReaderView))
        .onPageRendered();
  }
  await tester.pump();
}

/// 換掉整棵樹讓 ReaderScreen dispose（觸發退出結算）。
Future<void> disposeStatsReader(WidgetTester tester) async {
  await tester.pumpWidget(_app(const SizedBox.shrink()));
  await tester.pump();
}

/// 模擬 Foliate 回報第 [n] 個位置（onLocatorChanged）。
void reportLocator(WidgetTester tester, int n) {
  tester
      .widget<FoliateReaderView>(find.byType(FoliateReaderView))
      .onLocatorChanged
      ?.call(
        EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/$n)","index":0,"fraction":0.1}',
          progression: 0.1,
          locationIndex: n,
          locationTotal: 100,
        ),
      );
}

/// 目前（fake 時鐘下）的本地日期字串，與 tracker 寫入的 `YYYY-MM-DD` 一致。
String statsToday() {
  // 與 ReadingStatsTracker 一致：一律轉成本地日期後再格式化。
  final now = clock.now().toLocal();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year.toString().padLeft(4, '0')}-$month-$day';
}
