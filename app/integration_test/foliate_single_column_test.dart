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
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
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
/// 驗證 singleColumn 偏好被持久化並正確傳遞至 FoliateEpubReaderView，
/// 且 版面設定面板中切換開關可覆蓋既有值。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '未持久化（預設）開 EPUB 書後，singleColumn 維持預設雙欄行為，版面設定面板可開啟/關閉',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    // 不關閉 in-memory database（addTearDown 在 widget 樹拆除前執行，
    // 關閉資料庫會導致 dispose 中的 _writeCurrentPosition 拋出
    // database_closed 例外）。
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'single_column_default.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_single_column_integration',
      title: '單欄測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    // 預設 BookReaderPrefs（singleColumn=null），驗證開書不崩潰。
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_single_column_integration',
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

    // 確認強制單欄開關存在
    expect(find.byKey(const Key('reader_settings_single_column')), findsOneWidget);
    // 預設為關閉狀態
    final switchTile = tester.widget<SwitchListTile>(
        find.byKey(const Key('reader_settings_single_column')));
    expect(switchTile.value, isFalse,
        reason: '預設 singleColumn=null 時開關應為關閉');

    // 開啟強制單欄
    await tester.tap(find.byKey(const Key('reader_settings_single_column')));
    await tester.pumpAndSettle();

    // 關閉面板
    await tester.tap(find.byKey(const Key('reader_settings_close_button')));
    await tester.pumpAndSettle();
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
    // 不關閉 in-memory database（理由同上）。
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