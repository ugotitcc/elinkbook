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
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import '../test/support/fake_reader_feature_dependencies.dart';
import '../test/support/pump_localized_widget.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// Epic 5 Issue 5：頁首/頁尾顯示切換——真機整合測試。
/// 現行語意（epic-38-reader-chrome-tts-redesign，見 `reader_screen.dart`
/// 文件註解）：`showHeader`／`showFooter` 偏好只控制工具列收合
/// （`_chromeVisible == false`）時螢幕邊角是否仍保留常駐頁首／頁尾文字；
/// 工具列可見時，底部頁尾（EPUB 的 `_buildFoliateEpubFooter`、PDF 的
/// `ReaderFooter`）恆顯示，與 `showFooter` 無關（epic-54 Issue 18 判定，
/// 見 epic.md「Issue 18 實作完成與真機驗證結果」(3)）。
///
/// 純 flutter test 環境下 EpubReaderView._channel 恆為 null（AndroidView
/// 未真正建立），無法觸發 onPageRendered/onLayoutResolved 等原生回呼，
/// 因此上述端到端行為必須在此檔案以真機驗證。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '已持久化 showHeader=true 開 EPUB 書後，收合工具列後頁首文字顯示章節名稱'
      '（reader_foliate_header_text），頁尾正常顯示',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    addTearDown(() => libraryRepository.close());

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'reader_header_toggle_epub.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 必須先插入書籍，否則 prefs 寫入會因 FOREIGN KEY 約束失敗
    await libraryRepository.insertBook(Book(
      id: 'b_header_toggle_integration',
      title: '預設測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    // 角落頁首文字只在 showHeader=true 且工具列收合時顯示（全域預設為
    // false，見 GlobalReaderDefaults），故此處明確持久化 showHeader=true。
    await prefsManager.saveBookPrefs(
      'b_header_toggle_integration',
      const BookReaderPrefs(showHeader: true),
    );

    final key = GlobalKey<State<ReaderScreen>>();
    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        key: key,
        filePath: samplePath,
        bookId: 'b_header_toggle_integration',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    // 等待原生 PlatformView 載入完成（loading indicator 消失）。
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 原生端完成渲染後，Dart 端需要一次額外 pump 以處理回呼佇列（如
    // onLayoutResolved、onCharacterCountReady 等 microtask）。
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    // 預設 showFooter=true → 頁尾正常顯示（工具列可見時）。
    expect(find.byKey(const Key('reader_footer')), findsOneWidget,
        reason: '預設 showFooter=true 時頁尾應顯示');
    // 角落頁首文字只在工具列收合時顯示（reader_screen.dart：showHeader 且
    // !_chromeVisible），先收合再驗證章節名稱。
    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();
    // 已持久化 showHeader=true → 頁首應顯示章節名稱文字。
    expect(find.byKey(const Key('reader_foliate_header_text')), findsOneWidget,
        reason: 'showHeader=true 時頁首應顯示 reader_foliate_header_text');
  });

  testWidgets(
      '已持久化 showFooter=false 開 EPUB 書後，工具列可見時底部頁尾仍顯示；'
      '收合工具列後角落進度文字不顯示，頁首文字仍正常顯示章節名稱',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    addTearDown(() => libraryRepository.close());

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'reader_footer_off_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 必須先插入書籍，否則 prefs 寫入會因 FOREIGN KEY 約束失敗
    await libraryRepository.insertBook(Book(
      id: 'b_footer_off_integration',
      title: '頁尾關閉測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await prefsManager.saveBookPrefs(
      'b_footer_off_integration',
      const BookReaderPrefs(showFooter: false, showHeader: true),
    );

    final key = GlobalKey<State<ReaderScreen>>();
    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        key: key,
        filePath: samplePath,
        bookId: 'b_footer_off_integration',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    // 現行語意（epic-54 Issue 18 判定）：工具列可見時底部頁尾恆顯示，
    // 與 showFooter 無關。先輪詢等頁尾出現（位置資訊就緒，與對照組前置條件
    // 一致），避免慢裝置上固定等待不足造成偶發失敗，也讓後面「收合後角落文字
    // 不顯示」不會因 displayTotalPages 尚為 0 而空過。
    final footerDeadline = DateTime.now().add(const Duration(seconds: 15));
    while (find.byKey(const Key('reader_footer')).evaluate().isEmpty) {
      if (DateTime.now().isAfter(footerDeadline)) {
        fail('等待逾時：工具列底部頁尾未出現');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('reader_footer')), findsOneWidget,
        reason: 'showFooter=false 但工具列可見時，底部頁尾仍應顯示');
    // 角落頁首文字只在工具列收合時顯示，先收合再驗證（showHeader 已明確持久化為 true；全域預設其實是 false）。
    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();
    // showFooter=false → 收合後角落進度文字不顯示。
    expect(find.byKey(const Key('reader_foliate_progress_text')), findsNothing,
        reason: 'showFooter=false 時收合工具列，角落進度文字不應顯示');
    // showHeader 明確持久化為 true（不受 showFooter=false 影響），頁首應顯示章節名稱文字。
    expect(find.byKey(const Key('reader_foliate_header_text')), findsOneWidget,
        reason: 'showHeader=true 時頁首應為 reader_foliate_header_text');
  });

  testWidgets(
      '已持久化 showFooter=true 開 EPUB 書後，收合工具列後角落進度文字顯示'
      '（showFooter=false 案例的對照組）',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    addTearDown(() => libraryRepository.close());

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'reader_footer_on_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 必須先插入書籍，否則 prefs 寫入會因 FOREIGN KEY 約束失敗
    await libraryRepository.insertBook(Book(
      id: 'b_footer_on_integration',
      title: '頁尾開啟測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await prefsManager.saveBookPrefs(
      'b_footer_on_integration',
      const BookReaderPrefs(showFooter: true),
    );

    final key = GlobalKey<State<ReaderScreen>>();
    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        key: key,
        filePath: samplePath,
        bookId: 'b_footer_on_integration',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    // 先等工具列底部頁尾出現（位置資訊就緒），再收合，避免角落文字因
    // displayTotalPages 尚為 0 而缺席造成誤判。
    final footerDeadline = DateTime.now().add(const Duration(seconds: 15));
    while (find.byKey(const Key('reader_footer')).evaluate().isEmpty) {
      if (DateTime.now().isAfter(footerDeadline)) {
        fail('等待逾時：工具列底部頁尾未出現');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();
    // showFooter=true → 收合後角落進度文字應顯示（對照組：證明前一案例的
    // findsNothing 不是因為根本沒位置資料）。
    expect(find.byKey(const Key('reader_foliate_progress_text')), findsOneWidget,
        reason: 'showFooter=true 時收合工具列，角落進度文字應顯示');
  });

  testWidgets(
      '已持久化 showFooter=false 開 PDF 書後，工具列可見時底部頁尾仍顯示'
      '（Issue 17 審查 M-2 缺口：PDF 頁尾現行語意此前無測試覆蓋）',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    addTearDown(() => libraryRepository.close());

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'reader_footer_off_pdf.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 必須先插入書籍，否則 prefs 寫入會因 FOREIGN KEY 約束失敗
    await libraryRepository.insertBook(Book(
      id: 'b_footer_off_pdf',
      title: 'PDF 頁尾關閉測試書',
      format: BookFileFormat.pdf,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await prefsManager.saveBookPrefs(
      'b_footer_off_pdf',
      const BookReaderPrefs(showFooter: false),
    );

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b_footer_off_pdf',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    // 現行語意：PDF 的 ReaderFooter 只在 _chromeVisible 且非裁切編輯模式時
    // 出現，不看 showFooter（工具列預設可見）。
    expect(find.byKey(const Key('reader_footer')), findsOneWidget,
        reason: 'PDF：showFooter=false 但工具列可見時，底部頁尾仍應顯示');
  });
}
