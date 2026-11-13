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
import 'package:elinkbook/screens/toc_bottom_sheet.dart';
import '../test/support/fake_reader_feature_dependencies.dart';
import '../test/support/pump_localized_widget.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpUntilFooterVisible(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.byKey(const Key('reader_footer')).evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：頁尾未出現（全書字元數計算未完成）');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 等目錄按鈕存在且 `onPressed` 非 null。
///
/// 注意：這**不代表目錄已載入**。`reader_screen.dart` 的 `_onTocTapFor` 在目錄
/// 尚未載入（`_tocLoaded` 為 false）時，會把按鈕指向 `_showTocLoadingHint`
/// （非 null，點了只顯示「目錄載入中」提示），所以按鈕「可點擊」早於「點了會
/// 開面板」。要真的開面板請用 [_openToc]，它會偵測載入提示並重試。
/// （epic-66 Issue 21：BooksPad 上實證 4/4 在此誤判，點到提示、面板未開。）
Future<void> _pumpUntilTocButtonEnabled(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final finder = find.byKey(const Key('reader_chrome_toc_button'));
    if (finder.evaluate().isNotEmpty &&
        tester.widget<IconButton>(finder).onPressed != null) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：目錄按鈕未轉為可點擊狀態（背景目錄抓取未完成）');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 開啟目錄面板：點目錄按鈕，若目錄尚未載入會彈出「載入中」提示而不是面板，
/// 就稍等後再點，直到 [TocBottomSheet] 出現；超過 10 秒仍未出現則明確失敗
/// （不無限等、不吞錯，目錄真的載不出來時要讓測試紅燈）。
///
/// 重試用小步長（300 ms）推進，不依賴 `pumpAndSettle()` 等提示消失（實測
/// `pumpAndSettle()` 結束時提示仍在）。
Future<void> _openToc(WidgetTester tester) async {
  await _pumpUntilTocButtonEnabled(tester);
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    await tester.tap(find.byKey(const Key('reader_chrome_toc_button')));
    await tester.pump(const Duration(milliseconds: 300));
    if (find.byType(TocBottomSheet).evaluate().isNotEmpty) break;
    final hinted = find
        .byKey(const Key('reader_toc_loading_snackbar'))
        .evaluate()
        .isNotEmpty;
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：目錄面板未開啟'
          '（${hinted ? "仍顯示「目錄載入中」提示，目錄一直沒載完" : "也沒有載入提示，原因不明"}）');
    }
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pumpAndSettle();
  expect(find.byType(TocBottomSheet), findsOneWidget);
}

Future<void> _pumpUntilProgressChanged(WidgetTester tester, String oldProgressText) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final textFinder = find.byKey(const Key('reader_footer_progress_text'));
    if (textFinder.evaluate().isNotEmpty) {
      final currentText = tester.widget<Text>(textFinder).data ?? '';
      if (currentText != oldProgressText) {
        return; // 進度已變更，跳出
      }
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：頁尾進度文字未改變，仍為 $oldProgressText');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EPUB 目錄樹狀清單正確渲染巢狀結構，點選項目後畫面確實跳轉至正確章節',
      (tester) async {
    // Windows 桌面預設視窗寬度（>720px）會使 Foliate 自動啟用雙欄／跨章節填滿（paginator.js
    // 在第三章內容短於一跨頁時會載入前一章節第二節補齊前導欄位），導致目前章節判定落在第二節；
    // 依既有測試慣例固定為手機直向視窗（400×800）確保單欄排版。
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await libraryRepository.close();
    });
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'epub_toc_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_epub_toc',
      title: 'EPUB 目錄測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b_epub_toc',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilFooterVisible(tester);

    final initialProgressText =
        (tester.widget<Text>(find.byKey(const Key('reader_footer_progress_text'))))
                .data ??
            '';

    // 開啟目錄，驗證頂層 3 章皆顯示。
    // epic-54 Issue 19 修復後：目前章節改以 spine index 判定，開書在第一章時
    // 第二章必須預設收合（保護「開書預設收合」，本測試曾於 Issue 18 為繞過
    // 已知缺陷而放寬，現已改回）。
    await _openToc(tester);
    expect(find.text('第一章：起始'), findsOneWidget);
    expect(find.text('第二章：發展'), findsOneWidget);
    expect(find.text('第三章：結局'), findsOneWidget);

    // 展開第二章，驗證巢狀子項出現。
    // 注意：展開按鈕的 Key 由 TocBottomSheet 內部產生，實際 Key 字串
    // 取決於 Readium 序列化的 locatorJson 內容。此處改用「找到「第二章：
    // 發展」文字所在的 ListTile，再找同一列的 IconButton」策略，避免
    // Key 字串不匹配導致測試失敗。
    final chapter2Row = find.text('第二章：發展');
    expect(chapter2Row, findsOneWidget);
    final expandButton = find.descendant(
      of: find.ancestor(
        of: chapter2Row,
        matching: find.byType(ListTile),
      ),
      matching: find.byType(IconButton),
    );
    expect(expandButton, findsOneWidget);
    // 開書預設只展開目前章節（第一章）；第二章的子節此時不得出現。
    expect(find.text('第一節'), findsNothing, reason: '開書在第一章，第二章應預設收合');
    expect(find.text('第二節'), findsNothing);
    await tester.tap(expandButton);
    await tester.pump();
    expect(find.text('第一節'), findsOneWidget);
    expect(find.text('第二節'), findsOneWidget);

    // 點選「第三章：結局」，驗證目錄自動關閉、頁尾進度確實反映跳轉結果。
    // FR-08「200ms 內完成跳轉」的時限本身，因 Bottom Sheet 關閉動畫
    // （Material 預設約 250-300ms）與原生跳轉耗時混在同一段
    // pumpAndSettle() 內、無法乾淨拆分自動化量測，已於真機以人工肉眼／
    // 碼表確認跳轉本身（非含 UI 轉場動畫）在觀感上是瞬間完成，此處改以
    // 內容正確性斷言（進度確實改變）驗證跳轉發生。
    await tester.tap(find.text('第三章：結局'));
    await tester.pumpAndSettle();

    expect(find.byType(TocBottomSheet), findsNothing, reason: '點選後應自動關閉目錄');

    // 等待 Native 跳轉並回報最新 progress 到 Dart 端使進度文字改變
    await _pumpUntilProgressChanged(tester, initialProgressText);
    final finalProgressText =
        (tester.widget<Text>(find.byKey(const Key('reader_footer_progress_text'))))
                .data ??
            '';
    expect(finalProgressText, isNot(initialProgressText),
        reason: '跳轉到第三章後頁尾進度應與開書時的起始位置不同');
    // 跳到第三章後再開目錄：目前章節應為第三章，第二章子節不得展開
    // （驗證判定不只在開書當下正確，epic-54 Issue 19）。
    await _openToc(tester);
    expect(find.text('第一節'), findsNothing, reason: '跳到第三章後第二章應維持收合');
    expect(find.text('第二節'), findsNothing);
    // 第三章應被標示為目前章節（TocBottomSheet 以 ListTile.selected 表示）。
    final ch3Tile =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '第三章：結局'));
    expect(ch3Tile.selected, isTrue, reason: '跳轉後第三章應標示為目前章節');

    // 測試自行清理：關閉目錄，避免懸置的 Modal 影響 teardown 或後續案例。
    await tester.tap(find.byKey(const Key('toc_bottom_sheet_close_button')));
    await tester.pumpAndSettle();
    expect(find.byType(TocBottomSheet), findsNothing, reason: '目錄驗證完成後應正常關閉');
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets(
      '桌面寬度（雙欄）：從目錄跳轉後，目前章節就是點選的那一章（epic-66 Issue 20）',
      (tester) async {
    // 1280x800 橫向視窗 → dualPageMode auto 啟用雙欄。雙欄的 relocate range 涵蓋兩欄，
    // foliate 取「range 內最後一個目錄項」，短章節又會被補入前一節內容，
    // 過去跳轉後目錄會標成前一章／章內最後一節。
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await libraryRepository.close();
    });
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'epub_toc_desktop.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    await libraryRepository.insertBook(Book(
      id: 'b_epub_toc_desktop',
      title: 'EPUB 目錄桌面寬度測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));
    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b_epub_toc_desktop',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilFooterVisible(tester);

    // 依序跳第三章、第二章：兩者在雙欄下過去都會標錯。
    for (final target in ['第三章：結局', '第二章：發展']) {
      await _openToc(tester);
      await tester.tap(find.text(target));
      await tester.pumpAndSettle();
      // 等 relocate 回報穩定（雙欄補欄後可能不只回報一次）。
      await tester.pump(const Duration(seconds: 2));

      await _openToc(tester);
      final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, target));
      expect(tile.selected, isTrue, reason: '桌面寬度跳到「$target」後，目錄應標示該章為目前章節');
      if (target == '第三章：結局') {
        expect(find.text('第一節'), findsNothing,
            reason: '跳到第三章後不應展開第二章的子節（代表目前章節沒有落在第二章內）');
        expect(find.text('第二節'), findsNothing);
      } else {
        // 目前章節是第二章本身：子節會展開，但不得把最後一節標成目前位置。
        final sub2 = tester.widget<ListTile>(find.widgetWithText(ListTile, '第二節'));
        expect(sub2.selected, isFalse, reason: '跳到第二章後，目前章節不應是它的最後一節');
      }
      await tester.tap(find.byKey(const Key('toc_bottom_sheet_close_button')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets(
      '桌面寬度（雙欄）一般翻頁：頁首章名與目錄的目前章節以第一欄為準（epic-66 Issue 24）',
      (tester) async {
    // 1280x800 橫向視窗 → 雙欄。雙欄的 relocate range 涵蓋兩欄，過去 foliate 取「range 內
    // 最後一個目錄項」，右欄才出現的下一章標題會讓頁首章名與目錄領先使用者先讀到的那一欄。
    // 規則（人類 2026-11-13，規則 B）：雙欄時把第一欄當成單欄的那一頁，取第一欄範圍內最後一個目錄項。
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await libraryRepository.close();
    });
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_single_spine_flat_toc.epub',
        'epub_toc_dual_page_turn.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    await libraryRepository.insertBook(Book(
      id: 'b_epub_toc_dual_page_turn',
      title: 'EPUB 雙欄翻頁目前章節測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));
    // 頁首章名只在 showHeader 為真且工具列收合時顯示。
    await prefsManager.saveBookPrefs(
      'b_epub_toc_dual_page_turn',
      const BookReaderPrefs(showHeader: true),
    );
    final readerKey = GlobalKey<State<ReaderScreen>>();
    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        key: readerKey,
        filePath: samplePath,
        bookId: 'b_epub_toc_dual_page_turn',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilFooterVisible(tester);

    // 收合工具列，頁首章名才會顯示（不要點螢幕中央熱區）。
    ReaderScreen.triggerZoneAction(readerKey, ZoneAction.menu);
    await tester.pump();

    String headerText() => tester
        .widget<Text>(find.descendant(
          of: find.byKey(const Key('reader_foliate_header_text')),
          matching: find.byType(Text),
        ))
        .data!;

    // 逐頁翻，記錄每頁的頁首章名。雙欄補欄會連續回報兩次，每次翻頁後等位置穩定。
    final headers = <String>[];
    Future<void> turnNext() async {
      ReaderScreen.triggerZoneAction(readerKey, ZoneAction.nextPage);
      await tester.pump(const Duration(seconds: 2));
      headers.add(headerText());
    }

    await turnNext();
    await turnNext();

    // 同一時刻目錄面板的目前章節必須與頁首章名一致（兩者共用同一個判定來源）。
    // 目錄按鈕要工具列顯示才存在，先叫出工具列，驗完再收合。
    ReaderScreen.triggerZoneAction(readerKey, ZoneAction.menu);
    await tester.pump();
    await _openToc(tester);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, headers.last)).selected,
      isTrue,
      reason: '目錄的目前章節應與頁首章名「${headers.last}」一致',
    );
    await tester.tap(find.byKey(const Key('toc_bottom_sheet_close_button')));
    await tester.pumpAndSettle();
    ReaderScreen.triggerZoneAction(readerKey, ZoneAction.menu);
    await tester.pump();

    await turnNext();
    await turnNext();

    // 與版面無關的檢查（所有平台）：頁首章名只會往後走，不會倒退。
    const order = ['第一章', '第二章', '第三章'];
    final indexes = headers.map(order.indexOf).toList();
    expect(indexes.every((i) => i >= 0), isTrue, reason: '頁首章名應是目錄中的章：$headers');
    for (var i = 1; i < indexes.length; i++) {
      expect(indexes[i], greaterThanOrEqualTo(indexes[i - 1]),
          reason: '翻頁後頁首章名不應倒退，實際序列＝$headers');
    }
    // 只有 Windows 1280x800 的分頁位置是固定的，才釘住整串序列：第 2 頁的第一欄仍在第一章、
    // 第二章標題在第二欄，規則 B 應標第一章（舊規則會標成第二章）。其他平台（例如 BooksPad
    // 的實際視窗大小不同、分頁位置不同）的規則驗證由 foliate_touch_harness 的
    // scenario-dual-column-toc-item.mjs（以獨立 DOM 座標當標準答案）負責。
    // 若 Windows 日後字型或版面使分頁位置改變，失敗訊息會列出實際序列，請重新確認後更新。
    if (Platform.isWindows) {
      expect(headers, ['第一章', '第一章', '第二章', '第二章'],
          reason: '雙欄一般翻頁的頁首章名應取第一欄範圍內最後一個目錄項，實際序列＝$headers');
    }
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('單一 spine 內多個目錄錨點：開書與跳轉後「目前章節」皆由 DOM 判定，精確到小節（epic-54 Issue 20）',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await libraryRepository.close();
    });
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_single_spine_multi_anchor.epub',
        'epub_toc_single_spine.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_epub_toc_single_spine',
      title: 'EPUB 單檔多錨點目錄測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b_epub_toc_single_spine',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilFooterVisible(tester);

    bool selected(String title) =>
        tester.widget<ListTile>(find.widgetWithText(ListTile, title)).selected;

    Future<void> closeToc() async {
      await tester.tap(find.byKey(const Key('toc_bottom_sheet_close_button')));
      await tester.pumpAndSettle();
    }

    String progressText() =>
        tester
            .widget<Text>(find.byKey(const Key('reader_footer_progress_text')))
            .data ??
        '';

    // 1) 開書位於第一節（頁面含 h1 與 s1 錨點，s2/s3 在後面）：
    //    不得因全書 progression 偏高而選到第二、三節。
    await _openToc(tester);
    expect(selected('第一節'), isTrue, reason: '開書位於第一節');
    expect(selected('第二節'), isFalse);
    expect(selected('第三節'), isFalse);
    final progressAtOpen = progressText();

    // 2) 跳到第三節。
    await tester.tap(find.widgetWithText(ListTile, '第三節'));
    await tester.pumpAndSettle();
    await _pumpUntilProgressChanged(tester, progressAtOpen);
    await _openToc(tester);
    expect(selected('第三節'), isTrue, reason: '跳到第三節後應標示第三節');
    expect(selected('第一節'), isFalse);
    expect(selected('第二節'), isFalse);
    final progressAtS3 = progressText();

    // 3) 回頭跳到第二節（往回跳，驗證不是只會往後）。
    await tester.tap(find.widgetWithText(ListTile, '第二節'));
    await tester.pumpAndSettle();
    await _pumpUntilProgressChanged(tester, progressAtS3);
    await _openToc(tester);
    expect(selected('第二節'), isTrue, reason: '往回跳到第二節後應標示第二節');
    expect(selected('第一節'), isFalse);
    expect(selected('第三節'), isFalse);

    await closeToc();
    expect(find.byType(TocBottomSheet), findsNothing);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
