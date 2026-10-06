// app/integration_test/orientation_repagination_test.dart
import 'dart:io';
import '../test/support/fake_reader_feature_dependencies.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import '../test/support/pump_localized_widget.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時（$timeout）：條件未成立');
    }
    await tester.pump(step);
  }
}

bool _loadingIndicatorGone() =>
    find.byKey(const Key('reader_loading_indicator')).evaluate().isEmpty;

Book _book(String id) => Book(
      id: id,
      title: '旋轉測試書',
      format: BookFileFormat.epub,
      filePath: 'content://example/$id',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SqliteLibraryRepository libraryRepository;
  late ReaderPrefsManager prefsManager;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  testWidgets('模擬自動旋轉：直橫排切換時，畫面能成功重新分頁且無 onError 錯誤', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_orientation_repage.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    await libraryRepository.insertBook(_book('b_repage_1'));

    // 1. 設定初始大小為直排 (Portrait)
    await tester.binding.setSurfaceSize(const Size(600, 1024));

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b_repage_1',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    // 等待載入完畢
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 2. 切換為橫排 (Landscape) 模擬物理旋轉
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    await tester.pumpAndSettle();
    // 給予額外的過渡等待，確保 WebView 重新適應新解析度
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '直排切換為橫排時，應能正常重新分頁，不觸發 onError');

    // 3. 再切回直排 (Portrait)
    await tester.binding.setSurfaceSize(const Size(600, 1024));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '橫排切回直排時，應能正常重新分頁，不觸發 onError');
  });
}
