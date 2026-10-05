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
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import '../test/support/fake_reader_feature_dependencies.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 2));
}

Future<void> _pumpUntilTextFound(WidgetTester tester, String textFragment) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.textContaining(textFragment).evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：畫面上未出現包含「$textFragment」的文字');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Epic 7 Issue 7：FR-18 音量鍵翻頁——真機整合測試。
///
/// 【真機人工驗證清單，本測試無法自動涵蓋】
/// `MainActivity.dispatchKeyEvent()` 攔截的是 Android 原生 Activity 層級
/// 的真實硬體音量鍵事件，發生在 Flutter engine 收到任何事件之前——Flutter
/// integration_test 框架的鍵盤事件模擬（`tester.sendKeyEvent` 等）只能合成
/// Flutter 端 `flutter/keyevent` channel 上的事件，不會、也不能觸達原生
/// Activity 的 dispatchKeyEvent()（兩者是完全不同的管線）。因此以下項目
/// 無法由本檔案自動化涵蓋，須由人類於真機/模擬器以下列方式之一驗證：
///   1. 實體/虛擬音量鍵直接按下，或執行 `adb shell input keyevent 24`
///      （VOLUME_UP）／`adb shell input keyevent 25`（VOLUME_DOWN）：
///      確認 ReaderScreen 內正確觸發上一頁/下一頁（PDF／EPUB FXL／EPUB
///      流式三種畫面皆須驗證）。
///   2. 按下返回鍵離開 ReaderScreen 的**當下**（轉場動畫進行中，
///      PlatformView 尚未 dispose()）立即以 adb 音量鍵指令驗證音量鍵已
///      恢復系統音量調整，而非等轉場動畫結束才恢復（驗證
///      notifyLeavingReader 即時釋放機制，design.md 決策 #19 審查修正）。
///   3. 確認音量鍵攔截並消費事件後，系統原生的音量提示 UI（音量條
///      Toast）不會意外跳出（design.md「待驗證風險」段落）。
/// 本檔案自動化的部分改為驗證「Dart 端事件分派管線」：透過模擬全域
/// `elinkbook/volume_key` 頻道送出 `onVolumeKey` MethodCall（比照
/// `epub_stream_nav_zone_test.dart` 對 onZoneTapped 的既有驗證手法），
/// 確認在真機原生渲染下 PDF 真的換頁——這條路徑不涉及硬體按鍵模擬，純粹
/// 驗證 Dart 分派邏輯 → 原生 method channel → 真機渲染結果，是
/// integration_test 可靠涵蓋的範圍；`dispatchKeyEvent()` 本身留給上述人工
/// 驗證清單。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('模擬 onVolumeKey(down/up) 真機正確換頁，且不影響沉浸模式',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_dual_page.pdf', 'volume_key_pageturn.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_volume_key',
      title: '音量鍵翻頁測試書',
      format: BookFileFormat.pdf,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(filePath: samplePath, bookId: 'b_volume_key', dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager)),
      ),
    );
    await _pumpUntilLoaded(tester);

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.textContaining('第 1/'), findsOneWidget, reason: '初始應在第 1 頁');

    const volumeKeyChannel = MethodChannel('elinkbook/volume_key');
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Future<void> simulateVolumeKey(String direction) async {
      final byteData = volumeKeyChannel.codec.encodeMethodCall(
        MethodCall('onVolumeKey', {'direction': direction}),
      );
      await binaryMessenger.handlePlatformMessage(
        volumeKeyChannel.name,
        byteData,
        (data) {},
      );
    }

    await simulateVolumeKey('down');
    await _pumpUntilTextFound(tester, '第 2/');

    expect(find.textContaining('第 2/'), findsOneWidget,
        reason: '模擬 onVolumeKey(down) 後應換到第 2 頁');
    expect(find.byType(AppBar), findsOneWidget, reason: '音量鍵翻頁不應影響沉浸模式');

    await simulateVolumeKey('up');
    await _pumpUntilTextFound(tester, '第 1/');

    expect(find.textContaining('第 1/'), findsOneWidget,
        reason: '模擬 onVolumeKey(up) 後應換回第 1 頁');
  });
}
