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
/// 核心症狀回歸測試：使用 sample_long_chinese_vertical.epub（足夠長的
/// 繁體中文直排 EPUB），驗證 singleColumn=true 時連續翻頁的
/// pageIndex 嚴格遞增（即每次翻頁只前進一頁，不會因為兩欄排版導致
/// 同一個頁碼要點兩次才變化）。
///
/// foliate-js 的 SectionProgress 以 content size / sizePerLoc(1500)
/// 計算 pageIndex，因此 EPUB 內容需足夠長（>= 9000 bytes XHTML）
/// 才能產生多個 pageIndex 值供遞增驗證。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'singleColumn=true 時，使用長篇直排 EPUB 連續翻頁 5 次，pageIndex 嚴格遞增',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    // 不關閉 in-memory database（addTearDown 在 widget 樹拆除前執行，
    // 關閉資料庫會導致 dispose 中的 _writeCurrentPosition 拋出
    // database_closed 例外）。

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_long_chinese_vertical.epub',
        'single_column_long.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_single_column_long',
      title: '長篇單欄翻頁測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    // 建構 FoliateEpubReaderView，明確指定 vertical + singleColumn=true，
    // 繞過 ReaderScreen 的完整開書流程以直接驗證 FoliateEpubReaderView 本身
    // 的翻頁行為。使用 onPageRendered 等待原生 PlatformView 載入完成
    // （reader_loading_indicator 只在 ReaderScreen 中存在）。
    final readerKey = GlobalKey<State<FoliateEpubReaderView>>();
    final pageIndexLog = <int>[];
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
              final pageIndex = info.pageIndex;
              if (pageIndex != null) {
                pageIndexLog.add(pageIndex);
              }
            },
          ),
        ),
      ),
    );

    // 等待原生 PlatformView 載入完成。
    await loadCompleter.future
        .timeout(const Duration(seconds: 15), onTimeout: () {});
    await tester.pump(const Duration(seconds: 2));

    expect(error, isNull, reason: '開書過程不應觸發 onError');
    expect(pageIndexLog, isNotEmpty,
        reason: 'onLocatorChanged 應至少回傳一次有效 pageIndex');

    // 清空初始載入的數據，確保後續只記錄翻頁結果。
    pageIndexLog.clear();

    // 連續翻頁 5 次，透過 FoliateEpubReaderView 的強型別 static helper
    // （比照 ReaderScreen 實際使用模式）。nextPage() 呼叫原生端
    // view.next()，觸發 paginator.js 的 relocate 事件，經 Kotlin bridge
    // 回呼 Dart 端 onLocatorChanged，因此可觀察 pageIndex 變化。
    //
    // 重要：使用 tester.runAsync + Future.delayed 而非 pumpAndSettle，
    // 因為 pumpAndSettle 只處理 Flutter framework 幀，無法等到原生
    // WebView 的 relocate 事件經 Kotlin bridge 非同步回呼 Dart 端。
    // 3 秒延遲足夠 WebView 完成 scroll + paginator 計算 + Kotlin
    // mainHandler.post 切回主執行緒觸發 channel.invokeMethod。
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        FoliateEpubReaderView.nextPage(readerKey);
        await Future.delayed(const Duration(milliseconds: 3000));
      });
    }

    // 核心驗證：pageIndex 嚴格遞增。
    // 若 main.js:120-124 的 singleColumn 分支被移除（bug 未修復），
    // 部分直排 EPUB 會被 paginator.js 判斷為「兩欄」，導致同一個
    // 頁碼要翻兩次才變化——此時連續 5 次 nextPage() 會產生重複的
    // pageIndex 值，此斷言會失敗。
    //
    // 此 EPUB 的 chapter1.xhtml 約 9000 bytes，以 sizePerLoc=1500
    // 計算可產生約 6 個 pageIndex（0~5），足夠 5 次 nextPage() 都
    // 產生遞增的 pageIndex 值。
    //
    // foliate-js 的 relocate 事件會對同一個 pageIndex 觸發多次
    // （ paginator.js 動畫開始與結束各觸發一次），因此需要先去除
    // 連續重複值，再驗證嚴格遞增。
    expect(pageIndexLog, isNotEmpty, reason: '翻頁後應至少有一筆 pageIndex');
    final deduped = <int>[];
    for (final v in pageIndexLog) {
      if (deduped.isEmpty || deduped.last != v) deduped.add(v);
    }
    expect(deduped.length, greaterThanOrEqualTo(2),
        reason: '去除連續重複後至少需要 2 個不同 pageIndex 來驗證遞增');
    for (var i = 1; i < deduped.length; i++) {
      expect(deduped[i], greaterThan(deduped[i - 1]),
          reason: 'deduped[$i](${deduped[i]}) 應大於 deduped[${i - 1}](${deduped[i - 1]})，'
              '表示每次翻頁只前進一頁，不會因為兩欄排版導致同一頁碼重複');
    }
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
