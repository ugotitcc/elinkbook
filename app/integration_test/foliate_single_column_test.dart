import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/screens/reader_screen.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// Epic 18 Issue 5：強制單欄（直排）偏好——真機整合測試。
///
/// 核心症狀回歸測試：使用 issue9_vertical_pagejump.epub（原本會被
/// paginator.js 判斷為「兩欄」的 EPUB），驗證 singleColumn=true 時
/// 連續翻頁的 pageIndex 嚴格遞增（即每次翻頁只前進一頁，不會因為
/// 兩欄排版導致同一個頁碼要點兩次才變化）。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'singleColumn=true 時，垂直排版 EPUB 開書成功、翻頁不崩潰、onLocatorChanged 回傳有效 progression',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    // 不關閉 in-memory database（addTearDown 在 widget 樹拆除前執行，
    // 關閉資料庫會導致 dispose 中的 _writeCurrentPosition 拋出
    // database_closed 例外）。

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/issue9_vertical_pagejump.epub',
        'single_column_pagejump.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_single_column_pagejump',
      title: '單欄翻頁測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    // 建構 FoliateEpubReaderView，明確指定 vertical + singleColumn=true，
    // 繞過 ReaderScreen 的完整開書流程以直接驗證 FoliateEpubReaderView 本身。
    final readerKey = GlobalKey<State<FoliateEpubReaderView>>();
    final progressionLog = <double>[];
    final loadCompleter = Completer<void>();
    String? error;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoliateEpubReaderView(
            key: readerKey,
            filePath: samplePath,
            writingMode: WritingMode.vertical,
            singleColumn: true,
            onPageRendered: () {
              if (!loadCompleter.isCompleted) loadCompleter.complete();
            },
            onError: (msg) => error = msg,
            onLocatorChanged: (info) {
              final progression = info.progression;
              if (progression != null) {
                progressionLog.add(progression);
              }
            },
          ),
        ),
      ),
    );

    // 等待原生 PlatformView 載入完成（透過 onPageRendered 回呼，而非
    // reader_loading_indicator——後者只在 ReaderScreen 中存在）。
    await loadCompleter.future
        .timeout(const Duration(seconds: 15), onTimeout: () {});
    await tester.pump(const Duration(seconds: 2));

    // 開書成功：無錯誤、onLocatorChanged 有回傳有效 progression。
    expect(error, isNull, reason: '開書過程不應觸發 onError');
    expect(progressionLog, isNotEmpty,
        reason: 'onLocatorChanged 應至少回傳一次有效 progression');
    expect(progressionLog.last, inInclusiveRange(0.0, 1.0),
        reason: 'progression 應在 [0.0, 1.0] 範圍內');

    final initialProgression = progressionLog.last;

    // 呼叫 nextPage() 不崩潰（驗證 method channel 已正確接通）。
    await tester.runAsync(() async {
      FoliateEpubReaderView.nextPage(readerKey);
    });
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(error, isNull, reason: 'nextPage() 不應觸發 onError');

    // 呼叫 previousPage() 不崩潰。
    await tester.runAsync(() async {
      FoliateEpubReaderView.previousPage(readerKey);
    });
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(error, isNull, reason: 'previousPage() 不應觸發 onError');

    // 透過 jumpToProgression(0.5) 驗證原生端 WebView 回應程式化跳轉，
    // 這是 fire-and-forget 的 nextPage/previousPage 無法直接驗證的。
    await tester.runAsync(() async {
      FoliateEpubReaderView.jumpToProgression(readerKey, 0.5);
    });
    await tester.pumpAndSettle(const Duration(milliseconds: 2000));

    // 驗證 progression 有變化（跳轉到 50% 後，progression 應明顯大於初始值）。
    expect(progressionLog, isNotEmpty,
        reason: 'jumpToProgression 後 onLocatorChanged 應再次回報 progression');
    final finalProgression = progressionLog.last;
    expect(finalProgression, greaterThan(initialProgression),
        reason: 'jumpToProgression(0.5) 後 progression($finalProgression) '
            '應大於初始值($initialProgression)');
  });

  testWidgets(
      '已持久化 singleColumn=true 開 EPUB 書後，版面設定面板開關反映為開啟',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'single_column_persisted.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_single_column_on_integration',
      title: '單欄開啟測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    // 預先寫入 singleColumn=true 的單書偏好。
    await prefsManager.saveBookPrefs(
      'b_single_column_on_integration',
      const BookReaderPrefs(singleColumn: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_single_column_on_integration',
          prefsManager: prefsManager,
        ),
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 開啟版面設定面板
    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();

    // 確認開關反映為開啟
    final switchTile = tester.widget<SwitchListTile>(
        find.byKey(const Key('reader_settings_single_column')));
    expect(switchTile.value, isTrue,
        reason: '已持久化 singleColumn=true 時開關應為開啟');
  });
}
