import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/reader/custom_fonts_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:flutter/material.dart';
import '../test/support/fake_reader_feature_dependencies.dart';

const _metadataChannel = MethodChannel('elinkbook/book_metadata');

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('上傳自訂字型並套用於書籍後，真機開書無錯誤（視覺效果人工確認，見 issues.md）',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(repository.close);

    // 比照 pdf_content_uri_metadata_test.dart：透過 createTestContentUri 取得
    // 真正的 content:// URI（FileProvider 自我授權模擬 SAF 選檔結果），
    // 而非直接用本機檔案路徑，才能驗證 ReaderResourceChannel.readCustomFontBytes
    // 的 ContentResolver.openInputStream 真實路徑。
    final fontPath = await _stageAssetAsFile('test/fixtures/sample.ttf', 'custom_font.ttf');
    final fontUri = await _metadataChannel
        .invokeMethod<String>('createTestContentUri', {'path': fontPath});
    expect(fontUri, isNotNull);
    await _metadataChannel
        .invokeMethod<void>('takePersistableUriPermission', {'uri': fontUri});

    final customFontsRepository = CustomFontsRepository(repository.database);
    await customFontsRepository.insert(CustomFont(
      displayName: '測試字型',
      familyName: 'KingHwa_OldSong',
      fontUri: fontUri!,
    ));

    final epubPath = await _stageAssetAsFile('test/fixtures/sample.epub', 'custom_font_test.epub');
    await repository.insertBook(Book(
      id: 'b_custom_font',
      title: '自訂字型測試書',
      format: BookFileFormat.epub,
      filePath: epubPath,
      source: BookSource.local,
      progress: 0,
      groupName: '未分類',
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));
    final prefsRepository = BookReaderPrefsRepository(repository.database);
    await prefsRepository.save(
      'b_custom_font',
      const BookReaderPrefs(fontFamily: 'KingHwa_OldSong'),
    );
    final prefsManager = ReaderPrefsManagerImpl(
      prefsRepository,
      ReadingPositionRepository(repository.database),
    );

    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: epubPath,
        bookId: 'b_custom_font',
        dependencies: fakeReaderFeatureDependencies(
          prefsManager: prefsManager,
          customFontsRepository: customFontsRepository,
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byKey(const Key('reader_loading_indicator')), findsNothing);
  });
}
