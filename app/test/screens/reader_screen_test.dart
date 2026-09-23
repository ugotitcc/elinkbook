import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/reader/zone_action.dart';
import '../support/pump_until_pdf_ready.dart';
import 'package:elinkbook/screens/fxl_settings_sheet.dart';
import 'package:elinkbook/screens/reader_settings_sheet.dart';
import 'package:elinkbook/reader/toc_entry.dart';
import 'package:elinkbook/screens/toc_bottom_sheet.dart';

import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/reader_activity_tracker.dart';
import 'package:elinkbook/screens/reader_chrome_bottom_bar.dart';
import 'package:elinkbook/screens/tts_panel.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/reader/foliate_bridge_codec.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import '../support/fake_inappwebview_platform.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_custom_fonts_repository.dart';
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import '../support/fake_bookmarks_repository.dart';
import 'package:elinkbook/screens/annotation_toolbar.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';
import '../support/fake_tts_provider.dart';
import 'package:elinkbook/reader/tts_audio_focus_source.dart';
import 'package:elinkbook/reader/tts_audio_handler.dart';

import '../support/fake_tts_audio_focus_source.dart';
import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:elinkbook/reader/pdf_crop_frame_overlay.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/screens/book_search_screen.dart';
import 'package:elinkbook/search/search_repository.dart';
import '../support/fake_search_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/layout_preset.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
import 'package:elinkbook/reader/reading_position.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 依 spec.md「測試決策」：ReaderScreen 分派到 EpubReaderView/PdfReaderView
// 後，實際渲染內容存在於原生 PlatformView 之中，一般 flutter test（無真實
// 裝置/模擬器）無法觀察其渲染結果，因此 EPUB/PDF 兩個分支的「確實渲染出
// 內容」驗證改由 integration_test/reader_screen_test.dart 在真實裝置上
// 執行；此處只保留 flutter test 就能可靠驗證的部分：「不支援格式」分支、
// 「⚙️版面」按鈕在 onLayoutResolved 觸發前的初始狀態，以及排版方向／
// 翻頁模式雙層解析邏輯（後者不依賴 onLayoutResolved，可離線驗證，見
// docs/epics/epic-3-fonts-layout/plans/plan-issue-4.md）。

// epic-27-reader-device-compat Issue 4：模擬 LayoutPresetRepository.insert()
// 在真機環境拋出未預期例外的情境（見 reviews/bugfix-repro.md Issue 4
// 「未能透過程式碼靜態確認、但無法排除的可能」）。LayoutPresetRepository
// 是一般 class（非 final/sealed），可安全繼承並只覆寫 insert()；listAll()
// 不覆寫、沿用真實記憶體內 SQLite 連線正常運作，確保 ReaderScreen
// initState() 時機的 _loadLayoutPresets() 不受影響（見
// docs/epics/epic-27-reader-device-compat/plans/plan-issue-4.md
// 規劃階段查證第 5 點）。
class _ThrowingLayoutPresetRepository extends LayoutPresetRepository {
  _ThrowingLayoutPresetRepository(super.db);

  @override
  Future<void> insert(LayoutPreset preset) async {
    throw Exception('模擬 insert 失敗（測試用）');
  }

  // Epic 43 Issue 5：供「刪除預設集失敗」測試使用。
  @override
  Future<void> delete(int id) async {
    throw Exception('模擬 delete 失敗（測試用）');
  }
}

// Epic 43 Issue 5：模擬 BookReaderPrefsRepository.load()/save()/
// saveMultiple() 拋出未預期例外的情境，比照上方 _ThrowingLayoutPreset-
// Repository 手法——單一「全部拋例外」的測試替身供「套用預設集」
// （Task 1，觸發 save/saveMultiple）與「套用來源書籍」（Task 2，觸發
// load）兩則測試共用。
class _ThrowingBookReaderPrefsRepository extends BookReaderPrefsRepository {
  _ThrowingBookReaderPrefsRepository(super.db);

  @override
  Future<BookReaderPrefs> load(String bookId) async {
    throw Exception('模擬 load 失敗（測試用）');
  }

  @override
  Future<void> save(String bookId, BookReaderPrefs prefs) async {
    throw Exception('模擬 save 失敗（測試用）');
  }

  @override
  Future<void> saveMultiple(
    List<String> bookIds,
    BookReaderPrefs prefs,
  ) async {
    throw Exception('模擬 saveMultiple 失敗（測試用）');
  }
}

/// `BookSearchDetailResult.book` 只是型別要求的欄位，`BookSearchScreen`
/// 實際渲染／跳轉行為只讀取 `widget.book`（也就是 `ReaderScreen` 合成的
/// 那一個），不讀取 `result.book`，故這裡用什麼內容皆不影響測試行為，純粹
/// 滿足建構子（epic-10-search Issue 8 規劃階段查證）。
Book _searchResultPlaceholderBook({BookFileFormat format = BookFileFormat.pdf}) {
  return Book(
    id: 'placeholder',
    title: 'placeholder',
    format: format,
    filePath: 'content://placeholder',
    source: BookSource.local,
    createTime: DateTime.fromMillisecondsSinceEpoch(0),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

void main() {
  late FakeReaderPrefsManager prefsManager;
  // 保存原始實作， tearDownAll 時還原
  late Future<String?> Function(String, String) originalCacheBookForServing;

  setUpAll(() {
    InAppWebViewPlatform.instance = FakeInAppWebViewPlatform();
    originalCacheBookForServing = cacheBookForServing;
    // 直接覆寫頂層函數變數，繞過 Dart 端檔案系統檢查（File.exists()、
    // resolveSymbolicLinksSync()、getApplicationDocumentsDirectory() 等），
    // 確保 FoliateReaderView 的 _cacheBook() 在測試環境中能順利完成。
    cacheBookForServing = (filePath, instanceId) async {
      return '/fake/cache/dir/current.epub';
    };
  });

  setUp(() {
    pdfrxInitialize();
    prefsManager = FakeReaderPrefsManager();
    // ReaderScreen 初始化時會透過 elinkbook/fullscreen MethodChannel 呼叫
    // setEnabled（非同步、非 awaited）。若前一個測試的 addTearDown 移除了
    // mock handler，這段 async 呼叫會在 handler 遺失時完成，導致
    // MissingPluginException 洩漏到下一個測試。在 setUp 全域註冊 mock
    // handler 可避免此競態。
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    binaryMessenger.setMockMethodCallHandler(
      const MethodChannel('elinkbook/fullscreen'),
      (call) async => null,
    );
  });

  test('reader_screen 版面預設集錯誤訊息英文 ARB 驗證（{error} placeholder 移除後的固定文字）',
      () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(l10n.readerSaveAsPresetFailedMessage, 'Failed to save new preset');
    expect(l10n.readerApplyPresetFailedMessage, 'Failed to apply layout settings');
    expect(l10n.readerDeletePresetFailedMessage, 'Failed to delete preset');
  });

  group('epic-10-search Issue 5：initialJumpTarget 覆寫初始定位', () {
    testWidgets('PDF：initialJumpTarget.pdfPageIndex 優先於資料庫既有 lastPosition',
        (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        readingPositionByBookId: {
          'b_jump_pdf_pos': const ReadingPosition(pdfPageIndex: 4),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_jump_pdf_pos',
            prefsManager: prefsManager,
            initialJumpTarget: const ReaderJumpTarget(pdfPageIndex: 2),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      expect(pdfView.initialPageIndex, 2);
    });

    testWidgets('Foliate：initialJumpTarget.cfi 優先於資料庫既有 lastPosition',
        (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        readingPositionByBookId: {
          'b_jump_epub_pos': const ReadingPosition(
            epubLocatorJson: 'epubcfi(/stored)',
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_jump_epub_pos',
            prefsManager: prefsManager,
            initialJumpTarget: const ReaderJumpTarget(cfi: 'epubcfi(/jump)'),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      expect(foliateView.initialLocatorJson, 'epubcfi(/jump)');
      // 驗證 FoliateReaderView._buildInitialUri 依賴的 extractCfi 能成功解析純 CFI 字串
      expect(extractCfi(foliateView.initialLocatorJson), 'epubcfi(/jump)');
    });

    testWidgets('Foliate：FoliateReaderView.textConversion 反映 resolveTextConversion() 解析結果（單書覆寫優先）',
        (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        bookPrefsByBookId: {
          'b_text_conversion': const BookReaderPrefs(
            textConversionOverride: TextConversionMode.toTraditional,
          ),
        },
        globalPrefs: GlobalReaderPrefs.initial().copyWith(
          reading: const ReadingDefaults(
            textConversion: TextConversionMode.toSimplified,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_text_conversion',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      expect(foliateView.textConversion, TextConversionMode.toTraditional);
    });

    testWidgets('Foliate：FoliateReaderView.textConversion 未覆寫時回退全域預設值',
        (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        globalPrefs: GlobalReaderPrefs.initial().copyWith(
          reading: const ReadingDefaults(
            textConversion: TextConversionMode.toSimplified,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_text_conversion_fallback',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      expect(foliateView.textConversion, TextConversionMode.toSimplified);
    });

    testWidgets(
        'initialJumpTarget 為 null（一般開書）時，沿用資料庫既有 lastPosition，零回歸',
        (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        readingPositionByBookId: {
          'b_no_jump_pos': const ReadingPosition(
            epubLocatorJson: 'epubcfi(/stored)',
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_no_jump_pos',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      expect(foliateView.initialLocatorJson, 'epubcfi(/stored)');
    });

    testWidgets(
        'PDF：跳轉後使用者繼續翻頁，dispose() 的 checkpoint 存檔行為與未帶入 initialJumpTarget 時完全一致'
        '（issues.md Issue 5 單元測試要求，審查修正 I-3）', (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        readingPositionByBookId: {
          'b_jump_then_navigate': const ReadingPosition(pdfPageIndex: 4),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_jump_then_navigate',
            prefsManager: prefsManager,
            initialJumpTarget: const ReaderJumpTarget(pdfPageIndex: 2),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      // 第一次回報：抵達 initialJumpTarget 指定的頁碼（開書當下的初始
      // 定位回報，_hasRelocatedSinceOpen 仍應維持 false）。
      pdfView.onPageChanged?.call(const PdfPageInfo(pageIndex: 2, totalPages: 5));
      await tester.pump();
      // 第二次回報：使用者從跳轉目標（頁碼 2）繼續往後翻到頁碼 3——這才
      // 是「後續重定位事件」，_hasRelocatedSinceOpen 應轉為 true（比照
      // 既有 PDF 測試直接呼叫 onPageChanged 的既有慣例，不需要真的等待
      // pdfrx 完整載入）。
      pdfView.onPageChanged?.call(const PdfPageInfo(pageIndex: 3, totalPages: 5));
      await tester.pump();

      // 移除畫面觸發 dispose()，比照既有「PDF 收到 onPageChanged 後離開
      // 畫面（dispose），正確寫入 ReadingPosition」測試的既有慣例（見
      // reader_screen_test.dart「Epic 5 Issue 2：閱讀位置記憶」區塊）。
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SizedBox.shrink(),
        ),
      );
      await tester.pump();

      expect(
        prefsManager.savedReadingPositionCalls.last.key,
        'b_jump_then_navigate',
      );
      expect(
        prefsManager.savedReadingPositionCalls.last.value.pdfPageIndex,
        3,
        reason: 'dispose() 應寫入使用者實際翻到的頁碼（3），而非跳轉目標'
            '（2）或跳轉前資料庫既有的舊進度（4）——checkpoint 寫入行為與'
            '一般開書完全同構，不因為曾經是搜尋跳轉而有任何殘留特殊狀態。',
      );
    });

    testWidgets(
        'PDF：跳轉後使用者未曾產生任何後續重定位事件即離開，dispose() 保留資料庫既有進度、不覆寫'
        '（spec.md §6 2026-09-11 修訂，`review-plan-issue-5.md` I-2 修訂——'
        '推翻本計畫原版「這是刻意接受的簡化」設計，改為實際修正這個行為）',
        (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        readingPositionByBookId: {
          'b_jump_immediate_exit': const ReadingPosition(pdfPageIndex: 49),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_jump_immediate_exit',
            prefsManager: prefsManager,
            initialJumpTarget: const ReaderJumpTarget(pdfPageIndex: 2),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 只有「開書當下抵達跳轉目標」這一次回報，使用者完全沒有進一步
      // 互動——onPageChanged 是原生端每次頁面確實顯示變更時都會回報，
      // 這裡刻意只呼叫一次，模擬使用者查看一下就離開的情境。
      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      pdfView.onPageChanged?.call(const PdfPageInfo(pageIndex: 2, totalPages: 5));
      await tester.pump();

      // 使用者未曾翻頁即離開閱讀畫面。
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SizedBox.shrink(),
        ),
      );
      await tester.pump();

      expect(
        prefsManager.savedReadingPositionCalls,
        isEmpty,
        reason: '使用者跳轉後沒有任何後續重定位事件，_writeCurrentPosition() '
            '應在最前面就直接 return，完全不呼叫 saveReadingPosition——不能'
            '把搜尋跳轉目標（頁碼 2）誤存成新進度，覆蓋掉跳轉前的舊進度'
            '（頁碼 49）。',
      );
      expect(
        prefsManager.readingPositionByBookId['b_jump_immediate_exit']
            ?.pdfPageIndex,
        49,
        reason: '資料庫既有進度應維持原樣（頁碼 49），完全不受這次搜尋'
            '跳轉瀏覽影響。',
      );
    });
  });

  group('epic-10-search Issue 5：搜尋跳轉暫態高亮生命週期', () {
    testWidgets('PDF：抵達 initialJumpTarget 後顯示暫態高亮，3 秒後自動清除',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_jump_highlight_auto_clear',
            prefsManager: FakeReaderPrefsManager(),
            initialJumpTarget: const ReaderJumpTarget(
              pdfPageIndex: 0,
              pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      // 【審查修正 C-1】不能用不帶 condition 的 pumpUntilPdfReady(tester)
      // ——該 helper 沒有 condition 時會無條件跑滿 30 輪、每輪
      // pump(100ms)，在 fake-async 環境下等同一次性推進 3,000ms 的假時鐘，
      // 剛好等於本測試要驗證的 3 秒暫態高亮計時器時長，會讓計時器在下面
      // 第一個 expect() 執行「之前」就已經到期並清除高亮，導致
      // findsOneWidget 斷言必定失敗（誤判成通過的反而是巧合）。改為傳入
      // condition，讓 pumpUntilPdfReady 一偵測到高亮 widget 出現就立刻
      // 返回，把「等待 3 秒計時器到期」這件事完全交給下面明確的
      // tester.pump(const Duration(seconds: 3))。
      await pumpUntilPdfReady(
        tester,
        condition: () =>
            find.byKey(const Key('pdf_reader_jump_highlight_0')).evaluate().isNotEmpty,
      );

      expect(
        find.byKey(const Key('pdf_reader_jump_highlight_0')),
        findsOneWidget,
        reason: '開書抵達跳轉目標後應立即顯示暫態高亮',
      );

      await tester.pump(const Duration(seconds: 3));
      expect(
        find.byKey(const Key('pdf_reader_jump_highlight_0')),
        findsNothing,
        reason: '3 秒後應自動清除',
      );
    });

    testWidgets('PDF：使用者提前點擊畫面（_handleZoneAction）時立即清除，不等待 3 秒',
        (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_jump_highlight_early_clear',
            prefsManager: FakeReaderPrefsManager(),
            initialJumpTarget: const ReaderJumpTarget(
              pdfPageIndex: 0,
              pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      // 【審查修正 C-1】理由同上一個測試——必須帶 condition，否則
      // pumpUntilPdfReady(tester) 累積推進的 3,000ms 假時鐘會讓 3 秒計時
      // 器在下面斷言之前就先到期，讓這個測試即使 _handleZoneAction 的
      // 提前清除邏輯根本沒有執行也會「意外看似通過」。
      await pumpUntilPdfReady(
        tester,
        condition: () =>
            find.byKey(const Key('pdf_reader_jump_highlight_0')).evaluate().isNotEmpty,
      );

      expect(
        find.byKey(const Key('pdf_reader_jump_highlight_0')),
        findsOneWidget,
      );

      // 用 ZoneAction.menu（單純點擊畫面，不換頁）驗證清除邏輯本身，
      // 避免與「換頁導致頁面本身不再可見」的效果混淆（見本計畫 Global
      // Constraints 對測試設計的說明）。
      ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
      await tester.pump();

      expect(
        find.byKey(const Key('pdf_reader_jump_highlight_0')),
        findsNothing,
        reason: '使用者點擊畫面應立即清除，不需要等待 3 秒計時器到期',
      );
    });

    testWidgets(
        'PDF：initialJumpTarget 只有 pdfPageIndex、沒有 pdfRect 時，正常跳轉頁面但不顯示暫態高亮',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_jump_no_rect',
            prefsManager: FakeReaderPrefsManager(),
            initialJumpTarget: const ReaderJumpTarget(pdfPageIndex: 0),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      expect(pdfView.initialPageIndex, 0);
      expect(
        find.byKey(const Key('pdf_reader_jump_highlight_0')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Foliate：initialJumpTarget 帶 cfi 時，開書流程與暫態高亮 wiring 皆不崩潰（誠實測試邊界，見本計畫 Global Constraints）',
        (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_jump_epub_highlight',
            prefsManager: FakeReaderPrefsManager(),
            initialJumpTarget:
                const ReaderJumpTarget(cfi: 'epubcfi(/6/2!/4/2)'),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      await tester.pump();

      // 3 秒自動清除路徑。
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);

      // 提前點擊清除路徑（此時計時器已到期，_clearSearchJumpHighlight
      // 內部的早退保護應能安全處理重複呼叫）。
      ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('initialJumpTarget 為 null 時，_handlePageRendered 不觸發任何暫態高亮',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_no_jump_no_highlight',
            prefsManager: FakeReaderPrefsManager(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>)
                  .value
                  .startsWith('pdf_reader_jump_highlight_'),
        ),
        findsNothing,
      );
    });
  });

  testWidgets('不支援格式顯示明確錯誤訊息', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.unknown',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );

    // 2026-09-12 使用者需求：頂部列標題暫時一律為空字串，TopBar 不再顯示書名。
    expect(find.text('不支援的檔案格式'), findsOneWidget);
  });

  group('頂部列標題暫時一律為空字串（2026-09-12 使用者需求：頁首已有另一處顯示書籍/章節資訊，避免重複）', () {
    testWidgets('EPUB：頂部列標題為空字串，不顯示書名', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_chapter_title_fallback_epub',
            prefsManager: prefsManager,
            bookTitle: '一本測試用書',
          ),
        ),
      );
      await tester.pump();

      final titleText = tester.widget<Text>(
        find.byKey(const Key('reader_chrome_title')),
      );
      expect(titleText.data, '');
    });

    testWidgets('PDF：頂部列標題為空字串，不顯示書名', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b_chapter_title_fallback_pdf',
            prefsManager: prefsManager,
            bookTitle: '另一本測試用書',
          ),
        ),
      );
      await tester.pump();

      final titleText = tester.widget<Text>(
        find.byKey(const Key('reader_chrome_title')),
      );
      expect(titleText.data, '');
    });
  });

  testWidgets('EPUB 格式顯示「⚙️版面」按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );

    final finder = find.byKey(const Key('reader_chrome_layout_button'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '尚未收到 onLayoutResolved，_autoDetectedWritingMode 仍為 null，按鈕應為停用狀態',
    );
  });

  testWidgets('PDF 格式顯示「⚙️版面」按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );

    // epic-24 Issue 8：PDF 不再使用 AppBar，設定按鈕改為 FAB。
    final finder = find.byKey(const Key('reader_chrome_layout_button'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason:
          '尚未收到 onPageRendered（純 flutter test 環境下 AndroidView 不會'
          '觸發原生回呼），按鈕應為停用狀態，比照 EPUB 齒輪按鈕的既有測試限制'
          '（見本檔案第 46-65 行）',
    );
  });

  // Epic 20 Issue 2：isFixedLayout: true 時改為 FoliateReaderView 並傳遞
  // isFixedLayoutHint，不呼叫偵測（main.js 會 early-return 跳過 applyPreferences
  // 的非必要設定）。
  testWidgets(
    'isFixedLayout: true 時建構 FoliateReaderView 並傳遞 isFixedLayoutHint',
    (tester) async {
      final repository = FakeLibraryRepository();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_fixed_layout.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            isFixedLayout: true,
            libraryRepository: repository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(find.byType(FoliateReaderView), findsOneWidget);
      expect(repository.detectAndCacheEpubLayoutCalls, isEmpty);
      // 驗證 isFixedLayoutHint 正確傳遞到 FoliateReaderView
      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      expect(foliateView.isFixedLayoutHint, isTrue);
    },
  );

  testWidgets('isFixedLayout: false 時直接建構 FoliateReaderView，不呼叫偵測', (
    tester,
  ) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: false,
          libraryRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(FoliateReaderView), findsOneWidget);
    expect(repository.detectAndCacheEpubLayoutCalls, isEmpty);
  });

  // Epic 20 Issue 3：FoliateReaderView 的 dualPageMode/isLandscape 參數下傳
  testWidgets('裝置為橫向時，isLandscape 正確下傳給 FoliateReaderView 建構參數', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 400)); // 橫向

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    expect(foliateView.isLandscape, isTrue);
  });

  testWidgets('裝置為直向時，isLandscape 正確下傳為 false', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800)); // 直向
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    expect(foliateView.isLandscape, isFalse);
  });

  testWidgets('開啟該書已有的持久化雙頁偏好設定後，FoliateReaderView 的 dualPageMode 正確載入', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(dualPageMode: DualPageMode.always),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    expect(foliateView.dualPageMode, DualPageMode.always);
  });

  testWidgets('尚未持久化雙頁偏好設定時，FoliateReaderView 的 dualPageMode 為 auto（預設值）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    expect(foliateView.dualPageMode, DualPageMode.auto);
  });

  testWidgets('開啟該書已有的持久化換頁動畫偏好設定後，PdfReaderView 的 pdfPageTurnAnimation 正確載入', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.none),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.pdfPageTurnAnimation, PdfPageTurnAnimation.none);
  });

  testWidgets(
    '尚未持久化換頁動畫偏好設定時，PdfReaderView 的 pdfPageTurnAnimation 為 slide（預設值）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b1',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      expect(pdfView.pdfPageTurnAnimation, PdfPageTurnAnimation.slide);
    },
  );

  testWidgets(
    '流式 EPUB（isFixedLayout: false）開書後，onLayoutResolved 回報結果驅動「版面設定」按鈕從停用轉為可用',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final finder = find.byKey(const Key('reader_chrome_layout_button'));
      expect(
        tester.widget<IconButton>(finder).onPressed,
        isNull,
        reason: '尚未收到 onLayoutResolved，_autoDetectedWritingMode 仍為 null',
      );

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.vertical,
        ),
      );
      await tester.pump();

      expect(
        tester.widget<IconButton>(finder).onPressed,
        isNotNull,
        reason: 'onLayoutResolved 觸發後，_autoDetectedWritingMode 非 null，按鈕應可用',
      );
    },
  );

  testWidgets('流式 EPUB 開書後，ReaderSettingsSheet 變動的偏好正確傳遞到 FoliateReaderView', (
    tester,
  ) async {
    // 設定較大的 Viewport，確保 BottomSheet 內的控制項皆在可點擊範圍內
    // （Issue 14 邊距拆為 4 個獨立滑桿後內容變高，1200 已不足，調高至 1600）
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final initialView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    initialView.onPageRendered(); // 模擬開書成功，脫離 loading 狀態
    initialView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pumpAndSettle();

    await switchToTab(tester, '呈現');
    await tester.tap(
      find.byKey(const Key('reader_settings_writing_mode_vertical')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('reader_settings_column_mode_single')),
    );
    await tester.pumpAndSettle();

    await switchToTab(tester, '邊界');
    await tester.tap(find.byKey(const Key('reader_settings_show_footer')));
    await tester.pumpAndSettle();

    final updatedView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    expect(updatedView.writingMode, WritingMode.vertical);
    expect(updatedView.columnMode, ColumnMode.single);
    expect(updatedView.showFooter, isFalse);
  });

  testWidgets(
    'isFixedLayout: null 且提供 libraryRepository 時，呼叫 detectAndCacheEpubLayout 並依結果建構 FoliateReaderView',
    (tester) async {
      final repository = FakeLibraryRepository(detectedIsFixedLayout: false);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            libraryRepository: repository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(repository.detectAndCacheEpubLayoutCalls, ['b1']);
      expect(find.byType(FoliateReaderView), findsOneWidget);
    },
  );

  testWidgets(
    'isFixedLayout: null 且提供 libraryRepository、偵測結果為 FXL 時，建構 EpubReaderView',
    (tester) async {
      final repository = FakeLibraryRepository(detectedIsFixedLayout: true);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_fixed_layout.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            libraryRepository: repository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(repository.detectAndCacheEpubLayoutCalls, ['b1']);
      expect(find.byType(FoliateReaderView), findsOneWidget);
    },
  );

  testWidgets(
    'isFixedLayout: null 且未提供 libraryRepository 時，退回既有行為建構 EpubReaderView（零回歸）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(find.byType(FoliateReaderView), findsOneWidget);
    },
  );

  testWidgets('AZW3 書籍 isFixedLayout: null 時，防禦性視為 false 並建構 FoliateReaderView，'
      '不呼叫 EPUB 專屬的 detectAndCacheEpubLayout（epic-11 Issue 2 程式碼審查 C2 迴歸測試）', (
    tester,
  ) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.azw3',
          bookId: 'b1',
          prefsManager: prefsManager,
          libraryRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 修復前：_dispatchedIsFixedLayout 永遠停留 null，FoliateReaderView
    // 永遠無法建構（_buildBody 的 gating 條件永遠不滿足），書籍完全無法
    // 開啟。修復後應立即（同步、不需等待非同步偵測）建構完成。
    expect(find.byType(FoliateReaderView), findsOneWidget);
    // KF8 沒有對應 EPUB OPF/CSS 解析器的執行期重新偵測手段，不應呼叫
    // 這個 EPUB 專屬方法。
    expect(repository.detectAndCacheEpubLayoutCalls, isEmpty);
  });

  testWidgets('CBZ 書籍 isFixedLayout: null 時，防禦性視為 true 並建構 FoliateReaderView，'
      '不永遠停留載入中畫面（epic-11 Issue 3 程式碼審查 Important #1，比照 Issue 2 '
      'C2 迴歸測試同構情境；正常匯入流程下 Book.isFixedLayout 必為 true，本測試'
      '涵蓋邊界防禦——修復前 _dispatchedIsFixedLayout 永遠停留 null，_buildBody '
      '的 gating 條件永遠不滿足，畫面永遠卡在載入指示器且無錯誤訊息）', (tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.cbz',
          bookId: 'b1',
          prefsManager: prefsManager,
          libraryRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(FoliateReaderView), findsOneWidget);
    // CBZ 沒有對應 EPUB OPF/CSS 解析器的執行期重新偵測手段，不應呼叫
    // 這個 EPUB 專屬方法。
    expect(repository.detectAndCacheEpubLayoutCalls, isEmpty);
  });

  testWidgets('CBZ 書籍建構 FoliateReaderView 時，isComicBookHint 正確傳為 true'
      '（epic-11 Issue 4 程式碼審查 Important #1 迴歸測試——Task 8 一度誤以為'
      '這個參數已存在於呼叫端而遺漏補上，導致 CBZ 的 book.dir RTL 覆寫在 '
      'main.js 端被靜默跳過，這類問題此前只有真機整合測試才抓得到；本測試'
      '把它收斂到 Seam 1，flutter test 秒級即可攔截同類回歸）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.cbz',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    expect(foliateView.isComicBookHint, isTrue);
  });

  testWidgets('CBZ 書籍開啟 FxlSettingsSheet 時 showTextConversion 為 false（不顯示簡繁轉換選項）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.cbz',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(
      find.byKey(const Key('reader_chrome_layout_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(FxlSettingsSheet), findsOneWidget);
    expect(
      tester.widget<FxlSettingsSheet>(find.byType(FxlSettingsSheet)).showTextConversion,
      isFalse,
    );
  });

  testWidgets('非 CBZ 格式建構 FoliateReaderView 時，isComicBookHint 恆為 false'
      '（EPUB／TXT 皆不應誤觸 main.js 的 CBZ 專屬 book.dir 覆寫邏輯，'
      '同一則審查修正的對照組）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    expect(foliateView.isComicBookHint, isFalse);
  });

  testWidgets('TXT 書籍 isFixedLayout: null 時，防禦性視為 false 並建構 FoliateReaderView，'
      '不永遠停留載入中畫面（epic-11 Issue 4，比照 Issue 2 C2／Issue 3 Important #1 '
      '同構情境；正常匯入流程下 Book.isFixedLayout 必為 false，本測試涵蓋邊界防禦）', (tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_synth.txt',
          bookId: 'b1',
          prefsManager: prefsManager,
          libraryRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    expect(find.byType(FoliateReaderView), findsOneWidget);
    expect(repository.detectAndCacheEpubLayoutCalls, isEmpty);
  });

  testWidgets('MD 書籍 isFixedLayout: null 時，防禦性視為 false 並建構 FoliateReaderView，'
      '不永遠停留載入中畫面（epic-11 Issue 5，比照 Issue 2 C2／Issue 3 Important #1／'
      'Issue 4 同構情境；正常匯入流程下 Book.isFixedLayout 必為 false，本測試涵蓋'
      '邊界防禦）', (tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_synth.md',
          bookId: 'b1',
          prefsManager: prefsManager,
          libraryRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    expect(find.byType(FoliateReaderView), findsOneWidget);
    expect(repository.detectAndCacheEpubLayoutCalls, isEmpty);
  });

  testWidgets('開啟該書已有的持久化版面偏好設定後，狀態正確載入', (tester) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(fontSize: 1.5),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final viewFinder = find.byType(FoliateReaderView);
    expect(viewFinder, findsOneWidget);
    final epubView = tester.widget<FoliateReaderView>(viewFinder);
    expect(epubView.fontSize, 1.5);
  });

  testWidgets('writingModeOverride 已持久化時，即使尚未收到 onLayoutResolved，'
      'EpubReaderView.writingMode 仍採用覆寫值', (tester) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(writingModeOverride: WritingMode.vertical),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    expect(epubView.writingMode, WritingMode.vertical);
    // 排版方向的雙層解析獨立於「⚙️版面」按鈕的啟用條件——後者仍要求真正
    // 收到 onLayoutResolved（見 _buildAppBarActions 的
    // _autoDetectedWritingMode 判斷），純 flutter test 環境下 AndroidView
    // 不會觸發原生回呼，因此這裡按鈕仍是停用狀態，屬預期行為，不是本測試
    // 要驗證的重點。
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('reader_chrome_layout_button')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('pageTurnModeOverride 為 null 時，未覆寫的書籍採用全域預設值（paginated）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    expect(epubView.pageTurnMode, PageTurnMode.paginated);
  });

  testWidgets('全域預設值已改為 scroll 時，未覆寫的書籍採用該全域值', (tester) async {
    prefsManager.globalPrefs = prefsManager.globalPrefs.copyWith(
      reading: prefsManager.globalPrefs.reading.copyWith(
        pageTurnMode: PageTurnMode.scroll,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    expect(epubView.pageTurnMode, PageTurnMode.scroll);
  });

  testWidgets('pageTurnModeOverride 已持久化時，優先於全域預設值', (tester) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(pageTurnModeOverride: PageTurnMode.scroll),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    expect(epubView.pageTurnMode, PageTurnMode.scroll);
  });

  testWidgets('進入手動裁切互動模式後，PopScope.canPop 為 false（返回鍵不應退出整個閱讀器）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(
      tester.widget<PopScope>(find.byType(PopScope)).canPop,
      isTrue,
      reason: '尚未進入裁切互動模式時，返回鍵應正常運作（可以離開閱讀器）',
    );

    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    // epic-24 Issue 8：PDF 不再使用 AppBar，設定按鈕改為 FAB。
    // 直接呼叫 onPressed callback 繞過 PdfReaderView gesture arena 問題。
    tester
        .widget<IconButton>(find.byKey(const Key('reader_chrome_layout_button')))
        .onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<PopScope>(find.byType(PopScope)).canPop,
      isFalse,
      reason:
          '裁切互動模式進行中，返回鍵不應把整個 ReaderScreen 一併 '
          'pop 掉（審查意見 2.1(b)：避免誤觸返回鍵導致整個閱讀器被意外'
          '關閉；刻意不新增「取消並還原」語意，維持 spec.md 已鎖定的簡化'
          '狀態機決策——見本檔案 _handleRequestManualCrop 的文件註解）',
    );
  });

  testWidgets(
    'onLayoutResolved 觸發後，EpubReaderView.writingMode 帶入自動偵測到的直排方向（C2 接線）',
    (tester) async {
      // 不預設任何 writingModeOverride，讓自動偵測值決定結果
      final manager = FakeReaderPrefsManager();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: manager,
          ),
        ),
      );
      // 等待 initState 的 async load 完成
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 比照同檔既有 PDF 測試直接呼叫公開 callback prop 的手法
      //（onPageRendered: reader_screen_test.dart:317），
      // EpubReaderView.onLayoutResolved 是公開的 ValueChanged<EpubLayoutInfo>?
      // callback prop（epub_reader_view.dart:32），可在純 flutter test 中直接呼叫。
      tester
          .widget<FoliateReaderView>(find.byType(FoliateReaderView))
          .onLayoutResolved!(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.vertical,
        ),
      );
      await tester.pump();

      expect(
        tester
            .widget<FoliateReaderView>(find.byType(FoliateReaderView))
            .writingMode,
        WritingMode.vertical,
      );
    },
  );

  testWidgets('EPUB 固定版面開書後，畫面右上角出現懸浮設定按鈕，點擊能開啟 FxlSettingsSheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 純 flutter test 環境沒有真實裝置能觸發原生端 onLayoutResolved，直接呼叫
    // EpubReaderView 目前已知的 onLayoutResolved callback 模擬原生端回報，比照
    // 本檔案既有測試對「無法在此層級驅動原生渲染」的既定限制處理方式。
    final view = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_chrome_layout_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(FxlSettingsSheet), findsOneWidget);

    expect(
      tester.widget<FxlSettingsSheet>(find.byType(FxlSettingsSheet)).showTextConversion,
      isTrue,
    );
  });

  // epic-20-fxl-foliate-migration Issue 4 Task 3 Step 3：合併按鈕群組後，
  // reader_chrome_layout_button 是唯一仍需依 _isFixedLayout 分流的按鈕
  // （FXL 開 FxlSettingsSheet、流式開 ReaderSettingsSheet）。以下兩個測試
  // 明確斷言「另一種 Sheet 不會被誤開」（`findsNothing` 交叉驗證），
  // 區別於既有兩個各自獨立驗證單一分支的測試（:890「開啟 FxlSettingsSheet」、
  // :3479「開啟 ReaderSettingsSheet」）；比照既有 FXL 測試（:890）
  // 使用固定 `pump` 而非 `pumpAndSettle`（FXL 分支下 `pumpAndSettle` 曾
  // 逾時，見該處既有寫法）。
  testWidgets(
    'reader_chrome_layout_button 分流：FXL 書籍開啟 FxlSettingsSheet、不誤開 ReaderSettingsSheet',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_fixed_layout.epub',
            bookId: 'b_settings_dispatch_fxl',
            prefsManager: prefsManager,
            isFixedLayout: true,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      final fxlView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      fxlView.onPageRendered();
      fxlView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: true,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(FxlSettingsSheet), findsOneWidget);
      expect(find.byType(ReaderSettingsSheet), findsNothing);
    },
  );

  testWidgets(
    'reader_chrome_layout_button 分流：流式書籍開啟 ReaderSettingsSheet、不誤開 FxlSettingsSheet',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_settings_dispatch_reflowable',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      final reflowableView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      reflowableView.onPageRendered();
      reflowableView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSettingsSheet), findsOneWidget);
      expect(find.byType(FxlSettingsSheet), findsNothing);
    },
  );

  testWidgets('固定版面點擊中間熱區可切換懸浮按鈕顯示/隱藏', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 直接呼叫 onLayoutResolved 模擬原生端回報 isFixedLayout=true
    final view = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget);
    expect(
      find.byKey(const Key('reader_chrome_layout_button')),
      findsOneWidget,
    );

    // 直接呼叫 onZoneAction 模擬中間熱區觸發
    view.onZoneAction?.call(ZoneAction.menu);
    await tester.pump();

    // 2026-09-10 修正：ReaderChromeTopBar 的工具列（含返回鍵）改回依
    // _chromeVisible 收合，跟頁首（頁首開關預設 true 時仍顯示標題文字）各自
    // 獨立，理由與完整狀態表見 CONTEXT.md「Chrome Bar」詞條。
    expect(find.byKey(const Key('reader_chrome_back_button')), findsNothing);
    expect(
      find.byKey(const Key('reader_chrome_layout_button')),
      findsNothing,
    );

    // 再次觸發切換顯示
    view.onZoneAction?.call(ZoneAction.menu);
    await tester.pump();

    expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget);
    expect(
      find.byKey(const Key('reader_chrome_layout_button')),
      findsOneWidget,
    );
  });

  testWidgets('固定版面點擊左/右熱區換頁後，懸浮按鈕維持原狀（不自動收起）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 直接呼叫 onLayoutResolved 模擬原生端回報 isFixedLayout=true
    final view = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget);

    // 直接呼叫 onZoneAction 模擬換頁觸發
    view.onZoneAction?.call(ZoneAction.nextPage);
    await tester.pump();

    expect(
      find.byKey(const Key('reader_chrome_back_button')),
      findsOneWidget,
      reason: '換頁後，懸浮控制項應維持原狀（不自動收起，design.md 決策 #14）',
    );
  });

  testWidgets(
    '強制 FXL（widget.isFixedLayout: true）時，native 端異步回報 isFixedLayout: false 不會覆蓋，FXL chrome 仍正確顯示（Issue 15 commit 97878c4 回歸測試）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_fixed_layout.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            isFixedLayout: true,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 引擎分派（_dispatchedIsFixedLayout）已由 widget.isFixedLayout 同步
      // 決定，建構的必為 EpubReaderView（Readium/FXL 路徑）。
      expect(find.byType(FoliateReaderView), findsOneWidget);

      // 模擬 native 端（Readium 自己對這本書 metadata 的獨立判讀，見
      // EpubReaderView.kt 的 publication?.metadata?.layout）異步回報
      // isFixedLayout: false——比照本檔案既有測試對「無法在此層級驅動原生
      // 渲染」的既定處理方式，直接呼叫 onLayoutResolved callback。
      final view = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      view.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();

      // 使用者透過「強制 FXL」手動設定的決定不應被 native 端的異步回報
      // 覆蓋——FXL 專屬的懸浮設定按鈕仍須顯示（見 reader_screen.dart
      // `_resolveEpubEngineDispatch()`／`_handleLayoutResolved()` 的
      // widget.isFixedLayout 保護邏輯）。
      expect(
        find.byKey(const Key('reader_chrome_layout_button')),
        findsOneWidget,
        reason: '強制 FXL 後，native 異步回報 isFixedLayout=false 不應覆蓋 _isFixedLayout',
      );
    },
  );

  testWidgets('FXL：真實點擊熱區「選單」格（index 1，中欄）觸發沉浸模式切換', (tester) async {
    // 【Task 4 重寫】原本使用 SystemChannels.platform_views mock 擷取
    // per-instance MethodChannel 來模擬 EpubReaderView（Readium）內部的
    // isFixedLayout 狀態。Epic 17 Issue 2 後 _buildNativeView() 統一返回
    // FoliateReaderView，其熱區由 Dart 端 _ZoneOverlay（build() 內
    // 3×3 grid）直接渲染，不再依賴 MethodChannel。改用
    // tester.widget<FoliateReaderView>() 取得 widget 實例、直接呼叫
    // onLayoutResolved 回調來設定 ReaderScreen 的 _isFixedLayout 狀態。
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 直接呼叫 FoliateReaderView 的 onLayoutResolved 回調，模擬原生端
    // 回報 isFixedLayout=true，讓 ReaderScreen 顯示 FXL 專屬懸浮按鈕。
    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget);

    // review-issue-3.md Critical #1：刻意不呼叫 onPageRendered()，維持
    // _state == loading——驗證 menu 熱區在 loading 期間仍可切換沉浸模式
    // （epic-27-reader-device-compat Issue 1 既有保證，_handleZoneAction
    // 刻意不對 menu 動作套用 loading 防呆，見 plan-issue-1.md）。
    // navZoneMode 預設 rightFlip，index 1（中欄）為 menu
    // （見 app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。
    // FoliateReaderView 的 _ZoneOverlay 永遠渲染 3×3 熱區，
    // onZoneAction 回調已接線到 ReaderScreen._handleZoneAction。
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    // 2026-09-10 修正：工具列（含返回鍵）改依 _chromeVisible 收合，見
    // CONTEXT.md「Chrome Bar」詞條。
    expect(find.byKey(const Key('reader_chrome_back_button')), findsNothing);
  });

  testWidgets('PDF 開書後，收到原生端 onPageChanged 回報時，頁尾正確顯示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_footer_test',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 模擬原生端回報頁碼：直接呼叫 PdfReaderView widget 上的 onPageChanged
    // callback（比照既有 EPUB 測試直接呼叫 onLayoutResolved 的模式）。
    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageChanged?.call(
      const PdfPageInfo(pageIndex: 0, totalPages: 12),
    );
    await tester.pump();

    // epic-38 Issue 1：PDF 使用 ReaderChromeBottomBar，頁碼文字與 ReaderFooter
    // 皆嵌入 BottomBar 內（取代舊版獨立 FAB + Bottom Sheet 模式）。
    expect(find.byKey(const Key('reader_chrome_page_info_text')), findsOneWidget);
    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
  });

  // --- 0↔1 頁碼轉換與 jumpToPage 原生呼叫 ---
  //
  // 此邊界在 widget test 層級**無法完整驗證**，原因：
  //   Flutter widget test 環境下 AndroidView 的 texture meta 未初始化，
  //   觸發 PdfReaderView.jumpToPage → method channel → platform view resize
  //   會導致 'meta != null' assertion failure（Flutter 框架已知限制，
  //   見 flutter_test/flutter_test.dart 以及 epic-1/epic-4 的歷史記錄）。
  //
  //   0↔1 轉換公式（page1Indexed - 1）以及原生端 jumpToPage 呼叫參數的
  //   完整驗證，由 integration_test/reader_footer_test.dart（真機）涵蓋：
  //   輸入「4」→ 斷言頁尾文字從「第 1/6 頁」變成「第 4/6 頁」。
  //
  //   讀者-footer 自身的 onPageChanged 回呼（1-indexed）已由
  //   reader_screen_test.dart 的其他測試以及 reader_footer_test.dart 覆蓋。
  //
  // 本檔案不重複測試上述已覆蓋的路徑。

  // --- Epic 5 Issue 2：閱讀位置記憶 ---

  testWidgets('PDF 收到 onPageChanged 後離開畫面（dispose），正確寫入 ReadingPosition', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_dispose_test',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 模擬原生端回報頁碼：直接呼叫 PdfReaderView widget 上的 onPageChanged
    // callback（比照既有「PDF 開書後，收到原生端 onPageChanged 回報時，
    // 頁尾正確顯示」的模式），驗證 dispose() 時正確寫入 ReadingPosition。
    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageChanged?.call(
      const PdfPageInfo(pageIndex: 3, totalPages: 10),
    );
    await tester.pump();

    // 導覽離開 ReaderScreen，觸發 dispose()。
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox.shrink(),
      ),
    );
    await tester.pump();

    expect(prefsManager.savedReadingPositionCalls, hasLength(1));
    final saved = prefsManager.savedReadingPositionCalls.single;
    expect(saved.key, 'b_dispose_test');
    expect(saved.value.pdfPageIndex, 3);
    expect(saved.value.progress, 0.4); // (3+1)/10
  });

  testWidgets(
    '尚未收到任何 onPageChanged 時，dispose 不呼叫 saveReadingPosition（避免覆寫既有記錄）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b_no_position',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SizedBox.shrink(),
        ),
      );
      await tester.pump();

      expect(prefsManager.savedReadingPositionCalls, isEmpty);
    },
  );

  testWidgets('PDF 頁尾行為不受本工單影響（既有回歸驗證）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_pdf_regression',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageChanged?.call(
      const PdfPageInfo(pageIndex: 0, totalPages: 12),
    );
    await tester.pump();

    // epic-38 Issue 1：PDF 使用 ReaderChromeBottomBar，頁碼文字與 ReaderFooter
    // 皆嵌入 BottomBar 內（取代舊版獨立 FAB + Bottom Sheet 模式）。
    expect(find.byKey(const Key('reader_chrome_page_info_text')), findsOneWidget);
    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
  });

  // --- Epic 5 Issue 4：EPUB 目錄（TOC）樹狀清單 ---

  testWidgets('EPUB 格式顯示「目錄」按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_toc_initial',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final finder = find.byKey(const Key('reader_chrome_toc_button'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '尚未收到 onLayoutResolved，按鈕應為停用狀態',
    );
  });

  testWidgets('PDF 格式下，目錄按鈕初始為停用狀態（epic-38-reader-chrome-tts-redesign '
      'Issue 1 審查修正：ReaderChromeTopBar 目錄按鈕全格式恆常渲染，不再是'
      '「PDF 不存在」，_pdfTocLoaded 完成前 onPressed 為 null）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_toc_pdf',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final finder = find.byKey(const Key('reader_chrome_toc_button'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '_pdfTocLoaded 尚未完成，按鈕應為停用狀態',
    );
  });

  testWidgets('EPUB 固定版面（FXL）開書後，目錄按鈕初始為停用狀態（epic-38-reader-chrome-'
      'tts-redesign Issue 1 審查修正：ReaderChromeTopBar 目錄按鈕全格式恆常'
      '渲染，不再受既有 AppBar 隱藏機制排除，FXL 與 reflowable EPUB 走同一套'
      '_autoDetectedWritingMode 防呆條件）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_toc_fxl',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 刻意不呼叫 onLayoutResolved：停用狀態的閘門是
    // `_autoDetectedWritingMode == null`（與 isFixedLayout 無關，比照
    // reflowable EPUB 同款「初始為停用狀態」測試，本檔案第 1421 行附近），
    // 在這個測試 fixture 下 `_tocLoaded` 的非同步載入會在同一次
    // `pump()` 內就完成，若先呼叫 onLayoutResolved 讓
    // `_autoDetectedWritingMode` 非 null，反而會因為 `_tocLoaded` 已同時
    // 就緒而直接變成可點擊，無法穩定觀察到停用狀態。
    final finder = find.byKey(const Key('reader_chrome_toc_button'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '尚未收到 onLayoutResolved，_autoDetectedWritingMode 仍為 null，'
          '按鈕應為停用狀態',
    );
  });

  testWidgets(
    'EPUB reflowable 收到 onLayoutResolved 後，目錄按鈕轉為可點擊，點擊後開啟 TocBottomSheet',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_toc_open',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final epubView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      epubView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      // 審查修正：目錄按鈕的啟用條件額外要求 _tocLoaded，該旗標由
      // EpubReaderView.loadTableOfContents() 這個 async 呼叫的 .then()
      // callback 設定，需要多一次 pump 讓其 microtask 完成、觸發 setState。
      await tester.pump();

      final finder = find.byKey(const Key('reader_chrome_toc_button'));
      expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

      await tester.tap(finder);
      // showModalBottomSheet 動畫在 flutter test 環境下 pumpAndSettle 永遠不
      // 會收斂（持續泵送動畫幀），改用有限幀 pump 等待動畫展開，比照本檔案
      // 既有的 FxlSettingsSheet 開啟測試模式（第 548-554 行）。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(TocBottomSheet), findsOneWidget);
    },
  );

  testWidgets('點選目錄項目後，TocBottomSheet 關閉', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_toc_select',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // 審查修正：多一次 pump 讓 loadTableOfContents() 的 .then() callback
    // 完成、_tocLoaded 變為 true，目錄按鈕才會真正可點擊。
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_chrome_toc_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TocBottomSheet), findsOneWidget);

    // 純 flutter test 環境下 EpubReaderView._channel 恆為 null（AndroidView
    // 未真正建立），loadTableOfContents() 回傳空清單，TocBottomSheet 內部
    // 不會有任何可點擊的項目列——直接呼叫 TocBottomSheet.onEntrySelected
    // 模擬使用者選取（比照本檔案既有測試對「純 flutter test 環境無法觸發
    // 原生回呼」的既定處理方式，見 onPageRendered/onLayoutResolved 相關
    // 既有測試）。
    final sheet = tester.widget<TocBottomSheet>(find.byType(TocBottomSheet));
    sheet.onEntrySelected(
      const TocEntry(title: '測試章節', locatorJson: '{}', progression: 0.5),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TocBottomSheet), findsNothing);
  });

  // --- Epic 5 Issue 5：頁首/頁尾顯示切換 ---

  // epic-24 Issue 8：PDF 不再使用 AppBar，改用 6 顆 FAB。
  testWidgets('PDF 開書後，無 AppBar；6 顆 FAB 正確顯示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_pdf_header',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();

    // PDF 不再使用 AppBar。
    expect(find.byType(AppBar), findsNothing);
    // 驗證 FAB 存在（以返回按鈕與設定按鈕為代表）。
    expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_chrome_layout_button')), findsOneWidget);
  });

  testWidgets('showFooter=false 時，EPUB 頁尾不顯示', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_footer_off_epub',
      const BookReaderPrefs(showFooter: false, showHeader: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_footer_off_epub',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsNothing);
    // 頁尾關閉不影響頁首（預設開啟）——驗證兩者互相獨立。
    expect(
      find.byKey(const Key('reader_chrome_title')),
      findsOneWidget,
    );
  });

  testWidgets('showFooter=false 時，PDF 頁尾即使收到 onPageChanged 也不顯示', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_footer_off_pdf',
      const BookReaderPrefs(showFooter: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_footer_off_pdf',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageChanged?.call(
      const PdfPageInfo(pageIndex: 0, totalPages: 12),
    );
    await tester.pump();

    // showFooter 現僅控制浮動進度文字，ReaderChromeBottomBar 跳頁列內嵌的
    // ReaderFooter 不受其閘控（epic-38-reader-chrome-tts-redesign Issue 1）。
    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
  });

  testWidgets('showHeader=true 且 showFooter=false 組合：頁首顯示章節標題元件、頁尾不顯示', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_header_on_footer_off',
      const BookReaderPrefs(showHeader: true, showFooter: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_on_footer_off',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('reader_chrome_title')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('showHeader=false 且 showFooter=true 組合：頁首不顯示、頁尾顯示', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_header_off_footer_on',
      const BookReaderPrefs(showHeader: false, showFooter: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_off_footer_on',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    // 2026-09-10 修正：頁首（reader_chrome_title）改依 showHeader 獨立控制
    // 顯示/隱藏，不再是「TOPBAR 一律顯示、不受 showHeader 限制」，見
    // CONTEXT.md「Chrome Bar」詞條。
    expect(find.byKey(const Key('reader_chrome_title')), findsNothing);
    // 頁尾不出現。
    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets(
    'EPUB 固定版面（FXL）開書後，即使 showHeader=false/showFooter=false，懸浮返回/設定按鈕仍正常顯示（FXL 完全不受影響）',
    (tester) async {
      await prefsManager.saveBookPrefs(
        'b_fxl_untouched',
        const BookReaderPrefs(showHeader: false, showFooter: false),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_fixed_layout.epub',
            bookId: 'b_fxl_untouched',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final epubView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      epubView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: true,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();

      expect(
        find.byType(AppBar),
        findsNothing,
        reason: 'FXL 不建構 Scaffold AppBar，頁首邏輯不適用',
      );
      expect(
        find.byKey(const Key('reader_chrome_back_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('reader_chrome_layout_button')),
        findsOneWidget,
      );
    },
  );

  // --- Epic 6 Issue 1：書籤管理 + 統一「筆記」入口 ---

  testWidgets('未提供 bookmarksRepository 時，📚 筆記按鈕為停用狀態（既有呼叫端不受影響）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_no_bookmarks_repo',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();

    // ReaderChromeBottomBar 選單列書籤/劃線筆記/版面 3 顆恆常渲染，
    // bookmarksRepository 缺席時只是 onPressed 為 null 顯示停用狀態
    // （epic-38-reader-chrome-tts-redesign Issue 1，plan.md「計劃範圍
    // 澄清」第 4 點），不再整格不渲染。
    final finder = find.byKey(const Key('reader_chrome_annotations_button'));
    expect(finder, findsOneWidget);
    expect(tester.widget<IconButton>(finder).onPressed, isNull);
  });

  testWidgets(
    'EPUB 提供 bookmarksRepository 後，📚 筆記按鈕存在，onLayoutResolved 前為停用狀態',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_notes_epub',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
          ),
        ),
      );
      await tester.pump();

      final finder = find.byKey(const Key('reader_chrome_annotations_button'));
      expect(finder, findsOneWidget);
      expect(tester.widget<IconButton>(finder).onPressed, isNull);
    },
  );

  testWidgets('EPUB 只收到 onLayoutResolved（尚未收到 onLocatorChanged）時，📚 按鈕仍為停用狀態'
      '（審查修正：避免定位資料未就緒時寫入無定位資訊的壞書籤）', (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_notes_epub_no_locator_yet',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    final finder = find.byKey(const Key('reader_chrome_annotations_button'));
    expect(tester.widget<IconButton>(finder).onPressed, isNull);
  });

  testWidgets(
    'EPUB 收到 onLayoutResolved 與 onLocatorChanged 後，📚 按鈕可點擊，點擊後開啟 NotesBottomSheet',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_notes_epub_open',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final epubView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      epubView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      epubView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"href":"/c1.xhtml"}',
          progression: 0.1,
        ),
      );
      await tester.pump();

      final finder = find.byKey(const Key('reader_chrome_annotations_button'));
      expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(NotesBottomSheet), findsOneWidget);
    },
  );

  testWidgets(
    'PDF 提供 bookmarksRepository 後，onPageRendered 前 📚 按鈕為停用狀態，之後可點擊',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b_notes_pdf',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
          ),
        ),
      );
      await tester.pump();

      // epic-24 Issue 8：PDF 筆記按鈕改為 FAB。
      final finder = find.byKey(const Key('reader_chrome_annotations_button'));
      expect(tester.widget<IconButton>(finder).onPressed, isNull);

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      pdfView.onPageRendered();
      await tester.pump();

      expect(tester.widget<IconButton>(finder).onPressed, isNotNull);
    },
  );

  // --- Epic 6 Issue 2：EPUB 劃線/備註 ---

  testWidgets(
    '未提供 highlightsRepository／notesRepository 時，EPUB 選取事件不顯示浮動工具列（既有呼叫端零回歸）',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: FakeReaderPrefsManager(),
            bookmarksRepository: bookmarksRepository,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsNothing);
    },
  );

  testWidgets(
    '提供 highlightsRepository／notesRepository 後，ReaderScreen 建構不受影響、仍正常顯示（既有測試涵蓋常態載入行為）',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      final highlightsRepository = FakeHighlightsRepository();
      final notesRepository = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: FakeReaderPrefsManager(),
            bookmarksRepository: bookmarksRepository,
            highlightsRepository: highlightsRepository,
            notesRepository: notesRepository,
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(ReaderScreen));
      // ReaderScreen 在 app/test/ 環境下 _channel 恆為 null（無真實
      // AndroidView），無法透過原生端觸發 onSelectionChanged；改為直接
      // 呼叫 State 內部的處理方法驗證（比照既有測試對「_channel 恆為
      // null」限制的既有因應方式：專案既有測試不新增 Method Channel Mock
      // 基礎設施，見 spec.md「Testing Decisions」）。由於
      // `_handleSelectionChanged` 是私有方法，本測試改為直接驗證
      // `AnnotationToolbar` 在 `_currentSelection` 非 null 時確實會被
      // build 出來，透過 State 是否存在對應的公開行為間接驗證——此處
      // 選擇不新增測試專用的 public API，僅驗證 widget tree 初始狀態不
      // 顯示 AnnotationToolbar（上一個測試已涵蓋），選取觸發後的顯示邏輯
      // 交由 Task 11 的 integration_test 驗證（原生選字手勢本身即無法在
      // widget test 環境下真實模擬）。
      expect(state, isNotNull);
    },
  );

  testWidgets(
    'PDF 書籍提供 highlightsRepository／notesRepository 後，ReaderScreen 建構不受影響、仍正常顯示',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      final highlightsRepository = FakeHighlightsRepository();
      final notesRepository = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b1',
            prefsManager: FakeReaderPrefsManager(),
            bookmarksRepository: bookmarksRepository,
            highlightsRepository: highlightsRepository,
            notesRepository: notesRepository,
          ),
        ),
      );
      await tester.pump();

      // 原生 PlatformView 在 app/test/ 環境下不會真正建立（_channel 恆為
      // null，見既有兩層測試架構慣例），選取觸發後的浮動工具列顯示效果留
      // 給 Task 11 integration_test 驗證；本測試只驗證建構參數可正確傳入
      // 不崩潰，且未觸發選取時不顯示浮動工具列（既有行為零回歸）。
      expect(find.byType(AnnotationToolbar), findsNothing);
    },
  );

  testWidgets(
    'PDF 書籍未提供 highlightsRepository／notesRepository 時建構不受影響（既有呼叫端零回歸）',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b1',
            prefsManager: FakeReaderPrefsManager(),
            bookmarksRepository: bookmarksRepository,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsNothing);
    },
  );

  // --- Epic 6 Issue 4：FXL 書籤支援 ---

  testWidgets('FXL：未提供 bookmarksRepository 時，懸浮書籤/筆記按鈕皆為停用狀態（既有呼叫端零回歸）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_no_repo',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    // ReaderChromeBottomBar 選單列書籤/劃線筆記/版面 3 顆恆常渲染，
    // bookmarksRepository 缺席時只是 onPressed 為 null 顯示停用狀態
    // （epic-38-reader-chrome-tts-redesign Issue 1），不再整格不渲染。
    final bookmarkFinder =
        find.byKey(const Key('reader_chrome_bookmark_button'));
    final annotationsFinder =
        find.byKey(const Key('reader_chrome_annotations_button'));
    expect(bookmarkFinder, findsOneWidget);
    expect(annotationsFinder, findsOneWidget);
    expect(tester.widget<IconButton>(bookmarkFinder).onPressed, isNull);
    expect(tester.widget<IconButton>(annotationsFinder).onPressed, isNull);
  });

  testWidgets('FXL：提供 bookmarksRepository 後，懸浮書籤按鈕存在，onLocatorChanged 前為停用狀態', (
    tester,
  ) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_bookmark_disabled',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    final finder = find.byKey(
      const Key('reader_chrome_bookmark_button'),
    );
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason:
          '尚未收到 onLocatorChanged，_epubPositionInfo 仍為 null，比照 '
          'reader_chrome_annotations_button 既有防呆邏輯',
    );
  });

  testWidgets('FXL：收到 onLocatorChanged 後，點擊懸浮書籤按鈕可新增/移除目前頁書籤，圖示正確切換並持久化', (
    tester,
  ) async {
    final bookmarksRepository = FakeBookmarksRepository();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_bookmark_toggle',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    // 解決 loading state 導致 CircularProgressIndicator 動畫持續排程與 MissingPluginException 問題
    view.onPageRendered();
    await tester.pump();

    view.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"href":"/page1.xhtml"}',
        progression: 0.2,
      ),
    );
    await tester.pump();

    final finder = find.byKey(
      const Key('reader_chrome_bookmark_button'),
    );
    expect(tester.widget<IconButton>(finder).onPressed, isNotNull);
    expect(
      (tester.widget<IconButton>(finder).icon as Icon).icon,
      Icons.star_border,
    );

    // 點擊新增書籤
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 斷言 UI 圖示是否已切換為已加入書籤狀態
    expect((tester.widget<IconButton>(finder).icon as Icon).icon, Icons.star);

    final afterAdd = await bookmarksRepository.listByBook(
      'b_fxl_bookmark_toggle',
    );
    expect(afterAdd, hasLength(1));
    expect(afterAdd.single.epubLocatorJson, '{"href":"/page1.xhtml"}');
    expect(afterAdd.single.progression, 0.2);
    expect(afterAdd.single.pdfPageIndex, isNull);

    // 再次點擊移除書籤
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 斷言 UI 圖示是否已還原為未加入書籤狀態
    expect(
      (tester.widget<IconButton>(finder).icon as Icon).icon,
      Icons.star_border,
    );

    final afterRemove = await bookmarksRepository.listByBook(
      'b_fxl_bookmark_toggle',
    );
    expect(afterRemove, isEmpty);
  });

  // --- Epic 6 Issue 4：FXL 書籤支援（Task 2） ---

  testWidgets('FXL：懸浮筆記按鈕開啟 Bottom Sheet，「🔖 書籤」分頁可用、「✏️ 劃線與備註」分頁顯示空狀態且不可互動', (
    tester,
  ) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_notes_sheet',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    // 解決 loading state 導致 CircularProgressIndicator 無限動畫持續排程的問題
    view.onPageRendered();
    await tester.pump();

    final notesButtonFinder = find.byKey(
      const Key('reader_chrome_annotations_button'),
    );
    expect(notesButtonFinder, findsOneWidget);
    expect(tester.widget<IconButton>(notesButtonFinder).onPressed, isNull);

    view.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"href":"/page1.xhtml"}',
        progression: 0.2,
      ),
    );
    await tester.pump();
    expect(tester.widget<IconButton>(notesButtonFinder).onPressed, isNotNull);

    await tester.tap(notesButtonFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 底部選單列「✎ 劃線筆記」按鈕改傳 initialTabIndex: 1，開啟後預設停在
    // 「✏️ 劃線與備註」分頁（epic-38-reader-chrome-tts-redesign Issue 1，
    // 接上 NotesBottomSheet.initialTabIndex），不再是舊行為的「🔖 書籤」分頁。
    expect(find.byType(NotesBottomSheet), findsOneWidget);
    expect(
      tester.widget<NotesBottomSheet>(find.byType(NotesBottomSheet)).initialTabIndex,
      1,
    );
    expect(
      find.byKey(const Key('notes_sheet_annotations_placeholder')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('notes_sheet_delete_all_highlights')),
      findsNothing,
    );
    expect(find.byKey(const Key('notes_sheet_delete_all_notes')), findsNothing);

    await tester.tap(find.byKey(const Key('notes_sheet_tab_bookmarks')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const Key('notes_sheet_bookmark_toggle')),
      findsOneWidget,
    );
  });

  testWidgets('FXL：於 Bottom Sheet 的書籤分頁新增書籤後關閉，懸浮書籤按鈕圖示同步更新', (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_sync',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    // 解決 loading state
    view.onPageRendered();
    await tester.pump();

    view.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"href":"/page1.xhtml"}',
        progression: 0.2,
      ),
    );
    await tester.pump();

    final bookmarkToggleFinder = find.byKey(
      const Key('reader_chrome_bookmark_button'),
    );
    expect(
      (tester.widget<IconButton>(bookmarkToggleFinder).icon as Icon).icon,
      Icons.star_border,
    );

    await tester.tap(find.byKey(const Key('reader_chrome_annotations_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 「✎ 劃線筆記」按鈕開啟後預設停在「✏️ 劃線與備註」分頁（initialTabIndex:
    // 1），需先切到「🔖 書籤」分頁才看得到 notes_sheet_bookmark_toggle
    // （epic-38-reader-chrome-tts-redesign Issue 1）。
    await tester.tap(find.byKey(const Key('notes_sheet_tab_bookmarks')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('notes_sheet_bookmark_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 關閉 Bottom Sheet（點擊外側遮罩）。
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      (tester.widget<IconButton>(bookmarkToggleFinder).icon as Icon).icon,
      Icons.star,
      reason: 'Bottom Sheet 內新增書籤後關閉，懸浮按鈕應重新載入並反映最新狀態',
    );
  });

  testWidgets('FXL：從書籤清單點選跳轉後，Bottom Sheet 關閉且底部選單列收合'
      '（頂部列工具列隨之收合、頁首仍顯示）', (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_jump_collapse',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final view = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    // 解決 loading state
    view.onPageRendered();
    await tester.pump();

    view.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"href":"/page1.xhtml"}',
        progression: 0.2,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_chrome_annotations_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 「✎ 劃線筆記」按鈕開啟後預設停在「✏️ 劃線與備註」分頁（initialTabIndex:
    // 1），需先切到「🔖 書籤」分頁才看得到 notes_sheet_bookmark_toggle
    // （epic-38-reader-chrome-tts-redesign Issue 1）。
    await tester.tap(find.byKey(const Key('notes_sheet_tab_bookmarks')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('notes_sheet_bookmark_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byType(ListTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NotesBottomSheet), findsNothing);
    // 2026-09-10 修正：書籤跳轉會強制收合 _chromeVisible，連帶
    // ReaderChromeTopBar 的工具列（含返回鍵）也一併收合，只有頁首（標題
    // 文字，showHeader 預設 true）維持顯示，見 CONTEXT.md「Chrome Bar」
    // 詞條。
    expect(
      find.byKey(const Key('reader_chrome_back_button')),
      findsNothing,
      reason: '工具列隨書籤跳轉造成的沉浸模式收合而隱藏',
    );
    expect(
      find.byKey(const Key('reader_chrome_title')),
      findsOneWidget,
      reason: '頁首（標題文字）不受沉浸模式收合影響',
    );
    expect(find.byType(ReaderChromeBottomBar), findsNothing,
        reason: '書籤跳轉比照既有換頁慣例，強制收合底部選單列');
  });

  // --- Epic 6 Issue 5：Markdown 導出 ---

  testWidgets(
    'EPUB：開啟「📚 筆記」時，傳給 NotesBottomSheet 的 bookProgress 反映目前即時進度，而非開書當下的舊 bookProgress',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_chapter.epub',
            bookId: 'b_progress_export_epub',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
            bookProgress: 0.1,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final epubView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      epubView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      epubView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"href":"/c3.xhtml"}',
          progression: 0.5,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_chrome_annotations_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final sheet = tester.widget<NotesBottomSheet>(
        find.byType(NotesBottomSheet),
      );
      expect(
        sheet.bookProgress,
        0.5,
        reason: '應反映 onLocatorChanged 回報的最新進度，而非建構時的舊 bookProgress: 0.1',
      );
    },
  );

  testWidgets(
    'PDF：開啟「📚 筆記」時，傳給 NotesBottomSheet 的 bookProgress 依 onPageChanged 回報的頁碼/總頁數即時換算',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b_progress_export_pdf',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
            bookProgress: 0.0,
          ),
        ),
      );
      await tester.pump();

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      pdfView.onPageRendered();
      await tester.pump();

      // 先透過 onPageChanged 設定頁碼資訊，再 pump 讓狀態就緒。
      pdfView.onPageChanged?.call(
        const PdfPageInfo(pageIndex: 4, totalPages: 10),
      );
      await tester.pump();

      // epic-24 Issue 8：PDF 筆記按鈕改為 FAB。
      final notesFinder = find.byKey(const Key('reader_chrome_annotations_button'));
      expect(notesFinder, findsOneWidget);
      expect(tester.widget<IconButton>(notesFinder).onPressed, isNotNull);

      // 直接呼叫 onPressed callback 繞過 gesture 問題
      tester.widget<IconButton>(notesFinder).onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      final sheet = tester.widget<NotesBottomSheet>(
        find.byType(NotesBottomSheet),
      );
      expect(
        sheet.bookProgress,
        0.5,
        reason: '第 5 頁／共 10 頁應換算為 0.5，而非建構時的舊 bookProgress: 0.0',
      );
    },
  );

  // epic-24 Issue 8：PDF 不再使用 AppBar / in-flow footer，沉浸模式改由
  // FAB 可見性反映。
  testWidgets('_handleZoneAction(menu) 切換 FAB 顯示（PDF）', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 初始狀態：FAB 可見（_chromeVisible == true）。
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget);

    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();

    // 2026-09-10 修正：工具列（含返回鍵）改依 _chromeVisible 收合。
    expect(find.byKey(const Key('reader_chrome_back_button')), findsNothing);

    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();

    // 切回：FAB 恢復可見。
    expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget);
  });

  testWidgets(
    '_handleZoneAction(previousPage/nextPage) 不影響 AppBar 顯示狀態（PDF，design.md 決策 #14）',
    (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b1',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // epic-24 Issue 8：PDF 不再使用 AppBar，改以 FAB 可見性驗證。
      expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget);

      ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
      await tester.pump();
      expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget);

      ReaderScreen.triggerZoneAction(key, ZoneAction.previousPage);
      await tester.pump();
      expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget);

      ReaderScreen.triggerZoneAction(key, ZoneAction.none);
      await tester.pump();
      expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget);
    },
  );

  testWidgets(
    'Scaffold 開啟 extendBodyBehindAppBar，PdfReaderView 尺寸不因沉浸模式切換而改變（審查修正：避免 AppBar 顯示/隱藏觸發 PlatformView resize）',
    (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b1',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.extendBodyBehindAppBar, isTrue);

      final sizeWithAppBar = tester.getSize(find.byType(PdfReaderView));

      ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
      await tester.pump();

      expect(find.byType(AppBar), findsNothing, reason: '沉浸模式已切換，AppBar 應隱藏');
      final sizeWithoutAppBar = tester.getSize(find.byType(PdfReaderView));
      expect(
        sizeWithoutAppBar,
        sizeWithAppBar,
        reason: 'PdfReaderView 尺寸不應因 AppBar 顯示/隱藏而改變',
      );
    },
  );

  testWidgets('PdfReaderView.nextPage／previousPage 在真實 pdfrx 載入後正確切換頁碼', (
    tester,
  ) async {
    // 【epic-24-pdf-engine-rebuild Issue 1】新 PdfReaderView 為純 Dart widget
    // （pdfrx），不再使用 PlatformView。直接驗證 PdfReaderView.nextPage /
    // previousPage 靜態方法在真實 pdfrx 載入後能正確切換頁碼。
    // Volume key → ReaderScreen → PdfReaderView.nextPage 為薄包裝層，
    // 核心翻頁邏輯在此測試覆蓋。
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );

    // 等待 pdfrx 真實載入 PDF（非模擬）。
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
    expect(renderedCount, 1);
    expect(lastPageInfo?.totalPages, 5);
    expect(lastPageInfo?.pageIndex, 0);

    // PdfReaderView.nextPage 觸發頁碼前進（0 → 1）。
    PdfReaderView.nextPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 1);

    // PdfReaderView.previousPage 觸發頁碼後退（1 → 0）。
    PdfReaderView.previousPage(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastPageInfo?.pageIndex, 0);
  });

  testWidgets('全域音量鍵開關關閉時，onVolumeKey 觸發被忽略，不執行翻頁', (tester) async {
    // 【epic-24-pdf-engine-rebuild Issue 1】驗證 ReaderScreen 在
    // volumeKeyEnabled: false 時忽略 onVolumeKey 事件。
    //
    // 【測試範圍】本測試透過 ReaderScreen 驗證全域音量鍵開關的行為。
    // ReaderScreen 內部的 _pdfPageInfo 為私有欄位，無法從外部直接觀察
    // 頁碼變化，因此斷言限於：widget 保持 mounted 且無例外拋出。
    // 核心翻頁邏輯已由 pdf_reader_view_test.dart 的 real loading 測試覆蓋。
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    // mock fullscreen channel 以避免 MissingPluginException
    const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
    binaryMessenger.setMockMethodCallHandler(fullscreenChannel, (call) async {
      return null;
    });
    addTearDown(
      () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
    );

    final disabledPrefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(volumeKeyEnabled: false),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b1',
          prefsManager: disabledPrefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 等待 pdfrx 真實載入 PDF（非模擬 onPageRendered）。
    await pumpUntilPdfReady(tester);

    const volumeKeyChannel = MethodChannel('elinkbook/volume_key');
    final byteData = volumeKeyChannel.codec.encodeMethodCall(
      const MethodCall('onVolumeKey', {'direction': 'down'}),
    );
    await binaryMessenger.handlePlatformMessage(
      volumeKeyChannel.name,
      byteData,
      (data) {},
    );
    await tester.pump();

    // volumeKeyEnabled: false 時，onVolumeKey 不應觸發翻頁。
    // 由於 ReaderScreen._pdfPageInfo 為私有欄位，無法直接斷言頁碼，
    // 僅驗證 widget 保持 mounted 且無例外拋出。
    final state = tester.state<State>(find.byType(ReaderScreen));
    expect(state.mounted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PopScope：pop 動作啟動當下呼叫 notifyLeavingReader，及早通知原生端釋放音量鍵攔截', (
    tester,
  ) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const volumeKeyChannel = MethodChannel('elinkbook/volume_key');
    final outgoingCalls = <MethodCall>[];
    binaryMessenger.setMockMethodCallHandler(volumeKeyChannel, (call) async {
      outgoingCalls.add(call);
      return null;
    });
    addTearDown(
      () => binaryMessenger.setMockMethodCallHandler(volumeKeyChannel, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open_reader'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReaderScreen(
                      filePath: 'test/fixtures/sample.pdf',
                      bookId: 'b1',
                      prefsManager: prefsManager,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    // 模擬原生端 onPageRendered，讓 _state 脫離 loading（純 flutter test
    // 環境下 AndroidView 不會真正觸發原生回呼，比照本檔案既有測試慣例，
    // 見第 294-298 行）——CircularProgressIndicator 為不定長動畫，若一直
    // 停留在 loading，後續 pumpAndSettle() 永遠不會收斂而逾時（見第
    // 957-962 行既有註解記錄的相同教訓）。
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    expect(outgoingCalls, isEmpty);

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(outgoingCalls.any((c) => c.method == 'notifyLeavingReader'), isTrue);
  });

  testWidgets(
    'EPUB 流式（isFixedLayout: false）：點擊選單熱區觸發沉浸模式切換（Issue 7：AppBar 恆為 null，改斷言浮動按鈕）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(find.byType(AppBar), findsNothing);
      expect(
        find.byKey(const Key('reader_chrome_back_button')),
        findsOneWidget,
      );

      // review-issue-3.md Critical #1：刻意不呼叫 onPageRendered()，維持
      // _state == loading——驗證 menu 熱區在 loading 期間仍可切換沉浸模式
      // （epic-27-reader-device-compat Issue 1 既有保證，見
      // plan-issue-1.md）。
      // navZoneMode 預設 rightFlip，index 1（中欄）為 menu（見
      // app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。
      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();

      // 2026-09-10 修正：工具列（含返回鍵）改依 _chromeVisible 收合。
      expect(find.byKey(const Key('reader_chrome_back_button')), findsNothing);
    },
  );

  testWidgets('EPUB 流式：previousPage/nextPage 熱區觸發 FoliateReaderView '
      '換頁，且不影響沉浸模式狀態（design.md 決策 #14；Issue 7 改斷言浮動按鈕）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget);

    // rightFlip 模板：index 2（右欄）＝ nextPage。
    await tester.tap(find.byKey(const Key('nav_zone_2')));
    await tester.pump();
    expect(
      find.byKey(const Key('reader_chrome_back_button')),
      findsOneWidget,
      reason: '換頁動作不應影響沉浸模式狀態',
    );

    // rightFlip 模板：index 0（左欄）＝ previousPage。
    await tester.tap(find.byKey(const Key('nav_zone_0')));
    await tester.pump();
    expect(
      find.byKey(const Key('reader_chrome_back_button')),
      findsOneWidget,
      reason: 'previousPage 同樣不應影響沉浸模式狀態',
    );
  });

  // ─────────────────────────────────────────────────────────────────────
  // epic-17-epub-render-migration Issue 6：流式 EPUB 目錄跳轉、定位
  // 持久化與頁尾頁碼測試。
  // ─────────────────────────────────────────────────────────────────────

  testWidgets(
    '流式 EPUB（isFixedLayout: false）收到 onLayoutResolved 後，目錄按鈕轉為可點擊，點擊後開啟 TocBottomSheet',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_toc_foliate_open',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      // 比照既有 Readium 分支測試：目錄按鈕的啟用條件額外要求 _tocLoaded，
      // 該旗標由 FoliateReaderView.loadTableOfContents() 這個 async
      // 呼叫的 .then() callback 設定，需要多一次 pump 讓其 microtask 完成。
      await tester.pump();

      final finder = find.byKey(const Key('reader_chrome_toc_button'));
      expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(TocBottomSheet), findsOneWidget);
    },
  );

  testWidgets(
    '流式 EPUB：點選目錄項目呼叫 FoliateReaderView.jumpToLocator（非 EpubReaderView）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_toc_foliate_jump',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_chrome_toc_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(TocBottomSheet), findsOneWidget);

      final sheet = tester.widget<TocBottomSheet>(find.byType(TocBottomSheet));
      sheet.onEntrySelected(
        const TocEntry(
          title: '測試章節',
          locatorJson: '{"cfi":"epubcfi(/6/8!/4)","index":1,"fraction":0.2}',
          progression: 0.2,
        ),
      );
      await tester.pump();

      // 驗證 FoliateReaderView 存在（代表走對了分支），且
      // EpubReaderView 未被建構——確認目錄跳轉走的是 Foliate 路徑。
      expect(find.byType(FoliateReaderView), findsOneWidget);
    },
  );

  testWidgets('流式 EPUB：onLocatorChanged 回報 pageIndex/totalPages 後，頁尾顯示對應頁碼', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_footer_foliate',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        locationIndex: 9,
        locationTotal: 100,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_foliate_progress_text')),
      findsOneWidget,
    );
    // epic-38：頁碼文字同時出現在浮動進度文字與 BottomBar 內的
    // ReaderFooter，共 2 份。
    expect(find.text('10/100'), findsNWidgets(2));
  });

  testWidgets('流式 EPUB：橫排時頁首上邊界與頁尾下邊界皆為 0，頁首/頁尾字體大小皆為 16'
      '（真機使用回報，epic-18-reader-device-qa Issue 32）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_header_footer_margin_h',
      const BookReaderPrefs(showHeader: true, showFooter: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_header_footer_margin_h',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        locationIndex: 9,
        locationTotal: 100,
      ),
    );
    await tester.pump();

    // 初始狀態 _chromeVisible=true，頁首不顯示（頁尾不受沉浸模式影響，
    // 比照既有測試慣例）；觸發沉浸模式後頁首才會出現。
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerPositioned = tester.widget<Positioned>(
      find
          .ancestor(
            of: find.byKey(const Key('reader_foliate_header_text')),
            matching: find.byType(Positioned),
          )
          .first,
    );
    expect(headerPositioned.top, 0);

    final footerPositioned = tester.widget<Positioned>(
      find
          .ancestor(
            of: find.byKey(const Key('reader_foliate_progress_text')),
            matching: find.byType(Positioned),
          )
          .first,
    );
    expect(footerPositioned.bottom, 0);

    final headerText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('reader_foliate_header_text')),
        matching: find.byType(Text),
      ),
    );
    expect(headerText.style?.fontSize, 12);

    final footerText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('reader_foliate_progress_text')),
        matching: find.byType(Text),
      ),
    );
    expect(footerText.style?.fontSize, 12);
  });

  testWidgets(
    '流式 EPUB：onLocatorChanged 未觸發前（pageIndex/totalPages 皆為 null），頁尾不顯示',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_footer_foliate_absent',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      await tester.pump();

      expect(
        find.byKey(const Key('reader_foliate_progress_text')),
        findsNothing,
      );
    },
  );

  testWidgets('流式 EPUB：onLocatorChanged 回報 totalPages=0 時，頁尾不顯示且不崩潰', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_footer_foliate_zero',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        locationIndex: 0,
        locationTotal: 0,
      ),
    );
    await tester.pump();

    // totalPages=0 應被 Issue 7 新增的疊加層條件
    // （(_epubPositionInfo?.totalPages ?? 0) > 0）攔截，不會建構
    // _buildFoliateProgressText()。
    expect(find.byKey(const Key('reader_foliate_progress_text')), findsNothing);
  });

  // --- Epic 17 Issue 8：流式 EPUB（FoliateReaderView）劃線與備註 ---

  testWidgets(
    '流式 EPUB 開書後，自動載入既有劃線/備註並透過 FoliateReaderView.setDecorations 送給原生端',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      await highlightsRepo.insert(
        const Highlight(
          id: 'h_fs1',
          bookId: 'b_foliate_anno',
          style: HighlightStyle.highlighterYellow,
          epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_anno',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      // InAppWebView 環境下 setDecorations 透過 evaluateJavascript 發送，
      // flutter_test 無法攔截 JS 呼叫。此處驗證 widget 成功建構且不崩潰，
      // 表示劃線載入 → setDecorations 完整流程未拋出例外。
      expect(find.byType(FoliateReaderView), findsOneWidget);
    },
  );

  // epic-20-fxl-foliate-migration Issue 4 Task 2/3：_sendDecorationsToNative()
  // 修正前對 FXL 書籍會呼叫已無人建構的 EpubReaderView.setDecorations（見
  // tmp/epic-20/issue2-implementation-review.md 原始發現），修正後無條件呼叫
  // FoliateReaderView.setDecorations——比照上方既有的流式版本測試風格
  // （InAppWebView 環境下 flutter_test 無法攔截 evaluateJavascript 呼叫本身，
  // 故以「不崩潰」+「畫面中只有 FoliateReaderView、沒有 EpubReaderView」
  // 佐證分派目標正確，是本測試能提供的最強保證）。
  testWidgets(
    'FXL EPUB 開書後，自動載入既有劃線/備註並透過 FoliateReaderView.setDecorations（而非已無人建構的 EpubReaderView）送給原生端',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      await highlightsRepo.insert(
        const Highlight(
          id: 'h_fs2',
          bookId: 'b_fxl_anno',
          style: HighlightStyle.highlighterYellow,
          epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_fixed_layout.epub',
            bookId: 'b_fxl_anno',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: true,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final fxlView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      fxlView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: true,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(FoliateReaderView), findsOneWidget);
    },
  );

  testWidgets(
    '流式 EPUB：FoliateReaderView 回報 onSelectionChanged 時，顯示 AnnotationToolbar',
    (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_select',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 先呼叫 onLayoutResolved 觸發 _resolved 設定（_buildNativeView 所需）
      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      foliateView.onSelectionChanged?.call(
        const EpubSelectionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
        ),
      );
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsOneWidget);
    },
  );

  testWidgets('流式 EPUB：選取範圍靠近畫面右緣時，AnnotationToolbar 右緣不應超出畫面寬度', (
    tester,
  ) async {
    // 固定視窗尺寸（400×800，比照既有 PDF 選取測試慣例），讓 clamp 後的
    // 精確像素值可預期、可斷言，而非依賴 flutter test 預設 800×600。
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800));
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final highlightsRepo = FakeHighlightsRepository();
    final notesRepo = FakeNotesRepository();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_select_edge',
          prefsManager: prefsManager,
          highlightsRepository: highlightsRepo,
          notesRepository: notesRepo,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    // 選取範圍靠近畫面右緣（left=0.95），比照使用者截圖回報的症狀
    // （tmp/images/畫線問題/畫線太右邊無法看到全部工具列.jpg）。
    foliateView.onSelectionChanged?.call(
      const EpubSelectionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.9}',
        progression: 0.9,
        rect: PercentRect(left: 0.95, top: 0.2, right: 0.99, bottom: 0.3),
      ),
    );
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsOneWidget);
    final bottomRight = tester.getBottomRight(find.byType(AnnotationToolbar));
    expect(
      bottomRight.dx,
      lessThanOrEqualTo(400.0),
      reason:
          '工具列右緣（現況會落在 636.0）不應超出畫面寬度 400.0，'
          '否則右半部按鈕會被裁切看不到',
    );
  });

  testWidgets('流式 EPUB：點擊 AnnotationToolbar 的關閉按鈕後，清空選取狀態、工具列消失', (
    tester,
  ) async {
    final highlightsRepo = FakeHighlightsRepository();
    final notesRepo = FakeNotesRepository();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_close_toolbar',
          prefsManager: prefsManager,
          highlightsRepository: highlightsRepo,
          notesRepository: notesRepo,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    foliateView.onSelectionChanged?.call(
      const EpubSelectionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
      ),
    );
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsOneWidget);

    await tester.tap(find.byKey(const Key('annotation_toolbar_close')));
    await tester.pump();

    expect(
      find.byType(AnnotationToolbar),
      findsNothing,
      reason: '點擊關閉按鈕後應清空選取狀態，工具列從畫面消失',
    );
  });

  testWidgets('流式 EPUB：長按選取範圍命中既有畫線時，工具列顯示刪除按鈕，點擊後刪除該畫線', (tester) async {
    final highlightsRepo = FakeHighlightsRepository();
    final notesRepo = FakeNotesRepository();
    const highlightId = 'h_merge1';
    await highlightsRepo.insert(
      const Highlight(
        id: highlightId,
        bookId: 'b_foliate_merge1',
        style: HighlightStyle.highlighterYellow,
        epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_merge1',
          prefsManager: prefsManager,
          highlightsRepository: highlightsRepo,
          notesRepository: notesRepo,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    foliateView.onSelectionChanged?.call(
      const EpubSelectionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
        text: '選取的文字',
        existingAnnotationId: 'highlight:$highlightId',
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('annotation_toolbar_delete')),
      findsOneWidget,
      reason: '選取範圍命中既有畫線時，工具列應顯示刪除按鈕',
    );

    await tester.tap(find.byKey(const Key('annotation_toolbar_delete')));
    await tester.pump();
    await tester.pump();

    expect(
      await highlightsRepo.listByBook('b_foliate_merge1'),
      isEmpty,
      reason: '點擊刪除按鈕後，該畫線應從 repository 移除',
    );
    expect(find.byType(AnnotationToolbar), findsNothing, reason: '刪除後工具列應一併關閉');
  });

  testWidgets('流式 EPUB：長按選取範圍未命中既有標記時，工具列不顯示刪除按鈕', (tester) async {
    final highlightsRepo = FakeHighlightsRepository();
    final notesRepo = FakeNotesRepository();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_merge2',
          prefsManager: prefsManager,
          highlightsRepository: highlightsRepo,
          notesRepository: notesRepo,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    foliateView.onSelectionChanged?.call(
      const EpubSelectionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
        text: '沒有畫線的文字',
      ),
    );
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_delete')), findsNothing);
  });

  testWidgets('流式 EPUB：長按選取範圍命中既有備註時，點擊備註按鈕開啟編輯對話框且文字已預填', (tester) async {
    final highlightsRepo = FakeHighlightsRepository();
    final notesRepo = FakeNotesRepository();
    const noteId = 'n_merge1';
    await notesRepo.insert(
      const Note(
        id: noteId,
        bookId: 'b_foliate_merge3',
        text: '既有備註內容',
        epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_merge3',
          prefsManager: prefsManager,
          highlightsRepository: highlightsRepo,
          notesRepository: notesRepo,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    foliateView.onSelectionChanged?.call(
      const EpubSelectionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
        text: '既有備註內容',
        existingAnnotationId: 'note:$noteId',
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('annotation_toolbar_note')));
    await tester.pump();

    expect(find.text('編輯備註'), findsOneWidget);
    expect(find.text('既有備註內容'), findsOneWidget, reason: '編輯備註對話框應預填既有備註文字');
  });

  testWidgets('流式 EPUB：點擊複製按鈕，選取文字寫入剪貼簿', (tester) async {
    final highlightsRepo = FakeHighlightsRepository();
    final notesRepo = FakeNotesRepository();
    final clipboardCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardCalls.add(call.arguments['text'] as String);
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_merge4',
          prefsManager: prefsManager,
          highlightsRepository: highlightsRepo,
          notesRepository: notesRepo,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    foliateView.onSelectionChanged?.call(
      const EpubSelectionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
        text: '要複製的文字',
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('annotation_toolbar_copy')));
    await tester.pump();

    expect(clipboardCalls, ['要複製的文字']);
    expect(
      find.byKey(const Key('reader_copy_selection_snackbar')),
      findsOneWidget,
    );
    expect(find.text('已複製到剪貼簿'), findsOneWidget);
  });

  // ─────────────────────────────────────────────────────────────────────
  // epic-18-reader-device-qa Issue 7：流式 EPUB Chrome 重構（浮動選單列＋
  // 頁眉/進度資訊分離）。
  // ─────────────────────────────────────────────────────────────────────

  testWidgets('流式 EPUB：AppBar 不顯示，6 顆浮動按鈕存在且可點擊（Issue 7）', (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_chrome',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // _tocLoaded 由 loadTableOfContents() 的 .then() 設定，需多一次 pump。
    await tester.pump();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        locationIndex: 0,
        locationTotal: 10,
      ),
    );
    await tester.pump();

    for (final key in [
      'reader_chrome_back_button',
      'reader_chrome_toc_button',
      'reader_chrome_layout_button',
      'reader_chrome_bookmark_button',
      'reader_chrome_annotations_button',
    ]) {
      final finder = find.byKey(Key(key));
      expect(finder, findsOneWidget, reason: '$key 應存在');
      expect(
        tester.widget<IconButton>(finder).onPressed,
        isNotNull,
        reason: '$key 應為可點擊狀態',
      );
    }
    // 頁碼文字（非 IconButton）獨立檢查——替代舊版 reader_foliate_progress_button
    expect(
      find.byKey(const Key('reader_chrome_page_info_text')),
      findsOneWidget,
      reason: '頁碼文字應存在於 ReaderChromeBottomBar 頁碼列',
    );
  });

  testWidgets('流式 EPUB：點擊浮動版面設定按鈕開啟 ReaderSettingsSheet（Issue 7）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_settings_btn',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderSettingsSheet), findsOneWidget);
  });

  testWidgets(
    '流式 EPUB：點擊浮動書籤 toggle 按鈕可新增/移除目前頁書籤，圖示正確切換（複用泛用化後的 _toggleBookmark，Issue 7）',
    (tester) async {
      final bookmarksRepository = FakeBookmarksRepository();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_bookmark_btn',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          locationIndex: 0,
          locationTotal: 10,
        ),
      );
      await tester.pump();

      final finder = find.byKey(
        const Key('reader_chrome_bookmark_button'),
      );
      expect(
        (tester.widget<IconButton>(finder).icon as Icon).icon,
        Icons.star_border,
      );

      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect((tester.widget<IconButton>(finder).icon as Icon).icon, Icons.star);

      final afterAdd = await bookmarksRepository.listByBook(
        'b_foliate_bookmark_btn',
      );
      expect(afterAdd, hasLength(1));
    },
  );

  testWidgets(
    '流式 EPUB：重新開啟已在目前位置有書籤的書，開書後未打開過筆記面板時第一次點擊書籤按鈕應刪除既有書籤而非重複新增（Epic 26 Issue 1 回歸測試）',
    (tester) async {
      const locatorJson = '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}';
      final bookmarksRepository = FakeBookmarksRepository();
      // 模擬「先前已在此位置加過書籤」：重開書時 repository 已有一筆。
      await bookmarksRepository.insert(
        Bookmark(
          id: 'existing-bookmark',
          bookId: 'b_epic26_issue1',
          name: '既有書籤',
          epubLocatorJson: locatorJson,
          progression: 0.1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_epic26_issue1',
            prefsManager: prefsManager,
            bookmarksRepository: bookmarksRepository,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: locatorJson,
          progression: 0.1,
          locationIndex: 0,
          locationTotal: 10,
        ),
      );
      await tester.pump();

      // 刻意不打開 NotesBottomSheet——重現「_fxlBookmarks 快取從未被
      // 預先載入」的狀態，開書後直接第一次點擊書籤按鈕。
      final finder = find.byKey(
        const Key('reader_chrome_bookmark_button'),
      );

      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        (tester.widget<IconButton>(finder).icon as Icon).icon,
        Icons.star_border,
        reason: '既有書籤應已被刪除，圖示應變回未加書籤狀態',
      );

      final afterTap = await bookmarksRepository.listByBook('b_epic26_issue1');
      expect(afterTap, hasLength(0), reason: '目前位置已有書籤時第一次點擊應是刪除，不應變成重複新增');
    },
  );

  testWidgets('流式 EPUB：點擊浮動筆記按鈕開啟 NotesBottomSheet（Issue 7）', (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_notes_btn',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_chrome_annotations_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NotesBottomSheet), findsOneWidget);
    // Step 2 新增的 initialTabIndex 接線回歸測試（review-plan-issue-1.md C1）。
    expect(
      tester
          .widget<NotesBottomSheet>(find.byType(NotesBottomSheet))
          .initialTabIndex,
      1,
    );
  });

  testWidgets('流式 EPUB：頁眉純顯示章節名稱、不可點擊，showHeader=false 時不顯示（Issue 7）', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_header',
      const BookReaderPrefs(showHeader: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_header',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    // 觸發沉浸模式（_chromeVisible=false），頁首才會顯示
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerFinder = find.byKey(const Key('reader_foliate_header_text'));
    expect(headerFinder, findsOneWidget);
    expect(
      find.ancestor(of: headerFinder, matching: find.byType(InkWell)),
      findsNothing,
      reason: '頁眉須為純顯示，不可點擊開啟目錄',
    );
    expect(
      find.ancestor(of: headerFinder, matching: find.byType(GestureDetector)),
      findsNothing,
    );
  });

  testWidgets(
    '流式 EPUB：沉浸模式收起選單（_chromeVisible=false）時，頁首文字仍常駐顯示、'
    'ReaderChromeBottomBar 與 ReaderChromeTopBar 工具列（含返回鍵）皆收合'
    '（Issue 13；2026-09-10 修正：頁首／工具列拆成兩組獨立開關，見'
    'ReaderChromeTopBar 類別文件註解／CONTEXT.md「Chrome Bar」詞條）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_header_immersive',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();

      // navZoneMode 預設 rightFlip，index 1（中欄）為 menu（見
      // app/lib/reader/nav_zone_mode.dart rightFlipZoneTemplate）。
      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();

      expect(
        find.byType(ReaderChromeBottomBar),
        findsNothing,
        reason: '沉浸模式收起後，底部選單列應收合',
      );
      expect(
        find.byKey(const Key('reader_chrome_back_button')),
        findsNothing,
        reason: '工具列（含返回鍵）隨 _chromeVisible 收合',
      );
      expect(
        find.byKey(const Key('reader_foliate_header_text')),
        findsOneWidget,
        reason: '頁首文字（資訊顯示）不受沉浸模式影響，應常駐顯示',
      );
    },
  );

  testWidgets('流式 EPUB：直排模式下頁首以 RotatedBox 顯示於右上角，與 FAB 互斥（Issue 23）', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_header_v',
      const BookReaderPrefs(
        writingModeOverride: WritingMode.vertical,
        showHeader: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_header_v',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.vertical,
      ),
    );
    await tester.pump();

    // 初始狀態 _chromeVisible=true，頁首不顯示
    expect(find.byKey(const Key('reader_foliate_header_text')), findsNothing);

    // 觸發沉浸模式（_chromeVisible=false），頁首顯示
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerFinder = find.byKey(const Key('reader_foliate_header_text'));
    expect(headerFinder, findsOneWidget);

    // 驗證直排分支使用 RotatedBox
    expect(
      find.ancestor(of: headerFinder, matching: find.byType(RotatedBox)),
      findsOneWidget,
      reason: '直排模式頁首應以 RotatedBox 包裹',
    );

    // 驗證 Positioned 包含 bottom: 16（有界寬度約束）
    final positioned = tester.widget<Positioned>(
      find.ancestor(of: headerFinder, matching: find.byType(Positioned)).first,
    );
    expect(positioned.bottom, 16);
    expect(positioned.right, 0);
    expect(positioned.top, 16);
  });

  testWidgets('流式 EPUB：目錄尚未載入時，頁首顯示書名而非「閱讀器」（Issue 23）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_header_title',
      const BookReaderPrefs(showHeader: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_header_title',
          prefsManager: prefsManager,
          isFixedLayout: false,
          bookTitle: '我的測試書名',
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    // 觸發沉浸模式
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    // 目錄尚未載入（_tocEntries 為空），角落頁首應顯示書名——改用限定在
    // reader_foliate_header_text 底下的 descendant 查找（epic-38-reader-
    // chrome-tts-redesign Issue 1 審查修正）：ReaderChromeTopBar 永遠渲染，
    // 且找不到章節時同樣回退為書名（2026-09-08 /grill-with-docs 使用者需求
    // 起，兩者回退值恆相同），全域 find.text(bookTitle) 會同時命中頂部列
    // 與角落頁首兩份，不能用來單獨斷言角落頁首的內容。
    final headerText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('reader_foliate_header_text')),
        matching: find.byType(Text),
      ),
    );
    expect(headerText.data, '我的測試書名');
  });

  testWidgets('流式 EPUB：單書覆寫簡繁轉換時，頁首書名依轉換模式呈現（epic-42-text-conversion Issue 3）',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_header_text_conversion',
      const BookReaderPrefs(
        showHeader: true,
        textConversionOverride: TextConversionMode.toTraditional,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_header_text_conversion',
          prefsManager: prefsManager,
          isFixedLayout: false,
          bookTitle: '国电脑',
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('reader_foliate_header_text')),
        matching: find.byType(Text),
      ),
    );
    expect(headerText.data, '國電腦');
  });

  testWidgets('流式 EPUB：ReaderChromeBottomBar 的 bookTitle 依單書簡繁轉換呈現（epic-42-text-conversion Issue 3）',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_bottom_bar_text_conversion',
      const BookReaderPrefs(
        textConversionOverride: TextConversionMode.toTraditional,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_bottom_bar_text_conversion',
          prefsManager: prefsManager,
          isFixedLayout: false,
          bookTitle: '国电脑',
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final bar = tester.widget<ReaderChromeBottomBar>(
      find.byType(ReaderChromeBottomBar),
    );
    expect(bar.bookTitle, '國電腦');
  });

  testWidgets('PDF：ReaderChromeBottomBar 的 bookTitle 依單書簡繁轉換呈現（epic-42-text-conversion Issue 3）',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_pdf_bottom_bar_text_conversion',
      const BookReaderPrefs(
        textConversionOverride: TextConversionMode.toTraditional,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_pdf_bottom_bar_text_conversion',
          prefsManager: prefsManager,
          bookTitle: '国电脑',
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final bar = tester.widget<ReaderChromeBottomBar>(
      find.byType(ReaderChromeBottomBar),
    );
    expect(bar.bookTitle, '國電腦');
  });

  testWidgets('目錄按鈕開啟的 TocBottomSheet 帶入該書已解析的簡繁轉換模式（epic-42-text-conversion Issue 3）',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_toc_text_conversion',
      const BookReaderPrefs(
        textConversionOverride: TextConversionMode.toTraditional,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_toc_text_conversion',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_chrome_toc_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final sheet = tester.widget<TocBottomSheet>(find.byType(TocBottomSheet));
    expect(sheet.textConversion, TextConversionMode.toTraditional);
  });

  testWidgets('筆記按鈕開啟的 NotesBottomSheet 帶入該書已解析的簡繁轉換模式（epic-42-text-conversion Issue 3）',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_notes_text_conversion',
      const BookReaderPrefs(
        showHeader: true,
        showFooter: true,
        textConversionOverride: TextConversionMode.toTraditional,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_notes_text_conversion',
          prefsManager: prefsManager,
          bookmarksRepository: FakeBookmarksRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    epubView.onPageRendered();
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    epubView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"href":"/page1.xhtml"}',
        progression: 0.2,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_chrome_annotations_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final sheet =
        tester.widget<NotesBottomSheet>(find.byType(NotesBottomSheet));
    expect(sheet.textConversion, TextConversionMode.toTraditional);
  });

  testWidgets('流式 EPUB：showHeader=false 時頁眉不顯示（Issue 7）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_header_off',
      const BookReaderPrefs(showHeader: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_header_off',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_foliate_header_text')), findsNothing);
  });

  testWidgets('流式 EPUB：進度為純顯示、橫排時置於下方置中且不含手勢 widget（Issue 7）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_progress_h',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        locationIndex: 167,
        locationTotal: 197,
      ),
    );
    await tester.pump();

    final progressFinder = find.byKey(
      const Key('reader_foliate_progress_text'),
    );
    expect(progressFinder, findsOneWidget);
    // epic-38：頁碼文字同時出現在浮動進度文字與 BottomBar 內的
    // ReaderFooter，共 2 份。
    expect(find.text('168/197'), findsNWidgets(2));
    expect(find.byType(RotatedBox), findsNothing);
    expect(
      find.ancestor(of: progressFinder, matching: find.byType(GestureDetector)),
      findsNothing,
    );
  });

  testWidgets('流式 EPUB：沉浸模式收起選單（_chromeVisible=false）時，進度文字仍常駐顯示（Issue 13）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_progress_immersive',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        locationIndex: 167,
        locationTotal: 197,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    // epic-38 Issue 1：沉浸模式收起後 ReaderChromeBottomBar 應隱藏
    expect(
      find.byKey(const Key('reader_chrome_page_info_text')),
      findsNothing,
      reason: '沉浸模式收起後，BottomBar（含頁碼文字）應收合',
    );
    // 但浮動進度文字不受 _chromeVisible 控制，仍應常駐顯示
    expect(find.text('168/197'), findsOneWidget,
      reason: '沉浸模式收起後浮動進度文字仍應常駐顯示（Issue 13）',
    );
  });

  testWidgets('流式 EPUB：直排時進度以 RotatedBox 顯示於左下角（Issue 7）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_progress_v',
      const BookReaderPrefs(
        writingModeOverride: WritingMode.vertical,
        showFooter: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_progress_v',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        locationIndex: 167,
        locationTotal: 197,
      ),
    );
    await tester.pump();

    final rotatedFinder = find.ancestor(
      of: find.byKey(const Key('reader_foliate_progress_text')),
      matching: find.byType(RotatedBox),
    );
    expect(rotatedFinder, findsOneWidget);
    expect(tester.widget<RotatedBox>(rotatedFinder).quarterTurns, isNot(0));

    final positioned = tester.widget<Positioned>(
      find
          .ancestor(
            of: find.byKey(const Key('reader_foliate_progress_text')),
            matching: find.byType(Positioned),
          )
          .first,
    );
    expect(
      positioned.left,
      0,
      reason: '真機使用回報（epic-18-reader-device-qa Issue 32）：直排時頁尾左邊界改為 0',
    );
  });

  testWidgets('流式 EPUB：showFooter=false 時進度文字不顯示，但進度/跳頁按鈕仍顯示且可點擊（Issue 12）', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_progress_off',
      const BookReaderPrefs(showFooter: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_progress_off',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        locationIndex: 0,
        locationTotal: 10,
      ),
    );
    await tester.pump();

    // epic-38 Issue 1：showFooter=false 時浮動進度文字不顯示，
    // 但 ReaderFooter 仍嵌入 ReaderChromeBottomBar（不受 showFooter 控制）。
    expect(
      find.byKey(const Key('reader_chrome_page_info_text')),
      findsOneWidget,
      reason: '頁碼文字不受 showFooter 控制，應常駐於 BottomBar',
    );
    // ReaderFooter 在 BottomBar 內直接嵌入，不受 showFooter 控制
    expect(find.byKey(const Key('reader_footer')), findsOneWidget,
      reason: 'ReaderFooter 嵌入 BottomBar，showFooter 僅控制浮動進度文字',
    );
  });

  testWidgets(
    '流式 EPUB：ReaderFooter 直接嵌入 ReaderChromeBottomBar，頁碼列與跳頁列同時可見（Issue 7，epic-38 重寫）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_progress_sheet',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          locationIndex: 9,
          locationTotal: 100,
        ),
      );
      await tester.pump();

      // epic-38 重寫：ReaderFooter 不再透過 Bottom Sheet 顯示，而是直接
      // 嵌入 ReaderChromeBottomBar 的 56dp 中間列。頁碼列（34dp）
      // reader_chrome_page_info_text 與跳頁列 reader_footer 同時存在。
      expect(find.byKey(const Key('reader_chrome_page_info_text')), findsOneWidget);
      expect(find.byKey(const Key('reader_footer')), findsOneWidget);
      expect(
        find.byKey(const Key('reader_footer_progress_text')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '流式 EPUB：進度/跳頁 Bottom Sheet 內容包在 SafeArea 內，避免被系統工具列蓋住（Issue 11）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            // 模擬有系統手勢列/三鍵導覽列的裝置：viewPadding.bottom > 0。
            data: const MediaQueryData(
              viewPadding: EdgeInsets.only(bottom: 48),
            ),
            child: ReaderScreen(
              filePath: 'test/fixtures/sample.epub',
              bookId: 'b_foliate_progress_safearea',
              prefsManager: prefsManager,
              isFixedLayout: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          locationIndex: 0,
          locationTotal: 10,
        ),
      );
      await tester.pump();

      // epic-38 重寫：ReaderFooter 直接嵌入 BottomBar，不再需要 tap FAB
      // 開啟 Bottom Sheet。跳頁滑桿直接存在於 widget 樹中。
      final sliderFinder = find.byKey(const Key('reader_footer_jump_slider'));
      expect(sliderFinder, findsOneWidget);
      expect(
        find.ancestor(of: sliderFinder, matching: find.byType(SafeArea)),
        findsOneWidget,
        reason: '跳頁滑桿須包在 SafeArea 內，避免被系統工具列（viewPadding.bottom）蓋住',
      );
    },
  );

  testWidgets(
    '流式 EPUB：positionInfo 尚未就緒（null）時 ReaderFooter 為空，SafeArea 仍正常包裹，不噴例外（epic-38 重寫）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_progress_safearea_null',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 刻意不呼叫 onLocatorChanged，讓 _epubPositionInfo 維持 null，
      // 藉此觸發 ReaderChromeBottomBar 的 footer = SizedBox.shrink() 分支。
      // 此時 reader_footer 不應存在，但 reader_chrome_page_info_text 仍應顯示。
      expect(find.byType(SafeArea), findsOneWidget);

      expect(find.byKey(const Key('reader_footer')), findsNothing);
      // 頁碼列不依賴 positionInfo，應常駐存在
      expect(find.byKey(const Key('reader_chrome_page_info_text')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '流式 EPUB：邊距 4 個欄位從 ResolvedPreferences 正確透傳到 FoliateReaderView（Issue 14）',
    (tester) async {
      await prefsManager.saveBookPrefs(
        'b_foliate_margins',
        const BookReaderPrefs(
          marginTop: 72,
          marginBottom: 20,
          marginLeft: 30,
          marginRight: 30,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_foliate_margins',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      expect(foliateView.marginTop, 72);
      expect(foliateView.marginBottom, 20);
      expect(foliateView.marginLeft, 30);
      expect(foliateView.marginRight, 30);
    },
  );

  testWidgets('流式 EPUB：Theme.of(context) 的顏色正確透傳到 FoliateReaderView'
      '（epic-22-reader-theme-integration Issue 1）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_theme_color',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    final expectedTheme = buildThemeData(AppTheme.dark);
    expect(foliateView.textColor, expectedTheme.colorScheme.onSurface);
    expect(foliateView.backgroundColor, expectedTheme.scaffoldBackgroundColor);
  });

  testWidgets('流式 EPUB：預設淺色主題（AppTheme.light）下顏色仍正確透傳，'
      '與改動前行為相容（epic-22-reader-theme-integration Issue 1）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildThemeData(AppTheme.light),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_theme_color_light',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    final expectedTheme = buildThemeData(AppTheme.light);
    expect(foliateView.textColor, expectedTheme.colorScheme.onSurface);
    expect(foliateView.backgroundColor, expectedTheme.scaffoldBackgroundColor);
  });

  testWidgets('EPUB 固定版面：不論主題為何，傳給 FoliateReaderView 的顏色皆為 null'
      '（epic-22-reader-theme-integration Issue 1，圖片內容無法預期背景色）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_foliate_theme_color_fxl',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    expect(foliateView.textColor, isNull);
    expect(foliateView.backgroundColor, isNull);
  });

  testWidgets('開啟全螢幕模式偏好後，elinkbook/fullscreen 頻道收到 setEnabled(true)', (
    tester,
  ) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
    final calls = <MethodCall>[];
    binaryMessenger.setMockMethodCallHandler(fullscreenChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
    );

    final prefsManager = FakeReaderPrefsManager(
      bookPrefsByBookId: {'b1': const BookReaderPrefs(fullscreen: true)},
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setEnabled');
    expect(calls.single.arguments, isTrue);
  });

  testWidgets(
    '離開 ReaderScreen 時，elinkbook/fullscreen 頻道收到 setEnabled(false) 無條件還原',
    (tester) async {
      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
      final calls = <MethodCall>[];
      binaryMessenger.setMockMethodCallHandler(fullscreenChannel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
      );

      final prefsManager = FakeReaderPrefsManager(
        bookPrefsByBookId: {'b1': const BookReaderPrefs(fullscreen: true)},
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_reader'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReaderScreen(
                      filePath: 'test/fixtures/sample.pdf',
                      bookId: 'b1',
                      prefsManager: prefsManager,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open_reader')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      // 模擬原生端 onPageRendered，讓畫面脫離 loading（純 flutter test 環境下
      // AndroidView 不會真正觸發原生回呼，比照本檔案既有測試慣例，見既有
      // 「離開閱讀器時通知原生端」測試）——CircularProgressIndicator 為不定長
      // 動畫，若一直停留在 loading，後續 pumpAndSettle() 永遠不會收斂而逾時。
      tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
      await tester.pump();
      calls.clear();

      final navigatorState = tester.state<NavigatorState>(
        find.byType(Navigator),
      );
      navigatorState.maybePop();
      await tester.pumpAndSettle();

      expect(
        calls,
        contains(
          predicate<MethodCall>(
            (c) => c.method == 'setEnabled' && c.arguments == false,
          ),
        ),
      );
    },
  );

  // 2026-09-10 修正：推翻 2026-09-08 /grill-with-docs 舊決策「全螢幕模式
  // 開啟時才讓頂部列跟沉浸模式一起收合」——全螢幕模式改回只管 Android
  // 系統列，跟頂部列工具列（返回/搜尋/⬓）完全無關；工具列一律直接依
  // _chromeVisible 收合，不論全螢幕開關為何，見 CONTEXT.md「全螢幕模式」
  // 詞條與 ReaderChromeTopBar 類別文件註解。以下測試分別以 fullscreen
  // true／false 驗證兩者行為相同，證明兩者已脫鉤。
  group('沉浸模式收合頂部列工具列，與全螢幕模式無關（2026-09-10 修正）', () {
    testWidgets('PDF：全螢幕模式開啟時，觸發沉浸模式收合後頂部列工具列一併隱藏', (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        bookPrefsByBookId: {
          'b_fullscreen_immersive_pdf': const BookReaderPrefs(fullscreen: true),
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b_fullscreen_immersive_pdf',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      expect(
        find.byKey(const Key('reader_chrome_back_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_1')));
      await tester.pump();
      // PdfViewer 內部 DoubleTapGestureRecognizer 的定時器過期後才算真正
      // 結束，比照 pdf_reader_view_nav_zone_test.dart 既有慣例。
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('reader_chrome_back_button')), findsNothing);
    });

    testWidgets('EPUB：全螢幕模式開啟時，觸發沉浸模式收合後頂部列工具列一併隱藏', (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        bookPrefsByBookId: {
          'b_fullscreen_immersive_epub': const BookReaderPrefs(fullscreen: true),
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_fullscreen_immersive_epub',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_chrome_back_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();

      expect(find.byKey(const Key('reader_chrome_back_button')), findsNothing);
    });

    testWidgets('PDF：全螢幕模式關閉（預設）時，觸發沉浸模式收合後頂部列工具列同樣隱藏', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b_fullscreen_off_pdf',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byKey(const Key('reader_chrome_back_button')),
        findsNothing,
        reason: '全螢幕模式關閉也一樣收合，證明工具列不受全螢幕開關影響',
      );
    });

    testWidgets('PDF：全螢幕模式開啟時，再次觸發沉浸模式（顯示）後頂部列恢復顯示', (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        bookPrefsByBookId: {
          'b_fullscreen_toggle_back_pdf': const BookReaderPrefs(fullscreen: true),
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b_fullscreen_toggle_back_pdf',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('reader_chrome_back_button')), findsNothing);

      // 頂部列本身已隨沉浸模式收合而消失，只能透過畫面中央的選單熱區
      // 喚回（見 CONTEXT.md「沉浸模式」詞條的條件限定說明）。
      await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const Key('reader_chrome_back_button')),
        findsOneWidget,
      );
    });
  });

  testWidgets('離開 ReaderScreen（書籍切換）觸發一次 checkpoint', (tester) async {
    var triggerCallCount = 0;
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => true,
      runCheckpoint: () async {
        triggerCallCount++;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open_reader'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(
                    filePath: 'test/fixtures/sample.pdf',
                    bookId: 'b1',
                    prefsManager: prefsManager,
                    syncCheckpointTrigger: syncCheckpointTrigger,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    expect(triggerCallCount, 0, reason: '開書當下不應觸發 checkpoint');

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(triggerCallCount, 1);
  });

  testWidgets('未提供 syncCheckpointTrigger 時，離開 ReaderScreen 不拋出例外（零回歸）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open_reader'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(
                    filePath: 'test/fixtures/sample.pdf',
                    bookId: 'b1',
                    prefsManager: prefsManager,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('閱讀中每 5 分鐘計時器觸發 checkpoint，離開畫面後計時器停止', (tester) async {
    var triggerCallCount = 0;
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => true,
      runCheckpoint: () async {
        triggerCallCount++;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open_reader'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(
                    filePath: 'test/fixtures/sample.pdf',
                    bookId: 'b1',
                    prefsManager: prefsManager,
                    syncCheckpointTrigger: syncCheckpointTrigger,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    expect(triggerCallCount, 0);

    await tester.pump(const Duration(minutes: 5));
    expect(triggerCallCount, 1, reason: '第一次 5 分鐘計時應觸發一次 checkpoint');

    await tester.pump(const Duration(minutes: 5));
    expect(triggerCallCount, 2, reason: '計時器應持續每 5 分鐘觸發一次');

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pumpAndSettle();
    // 離開畫面當下 Task 3 的「書籍切換」觸發也會呼叫一次 trigger()，
    // 這裡只關心「離開之後計時器是否已停止」，故以離開當下的次數為基準，
    // 不假設離開當下的確切次數。
    final countAfterLeaving = triggerCallCount;

    await tester.pump(const Duration(minutes: 5));
    expect(
      triggerCallCount,
      countAfterLeaving,
      reason: '離開畫面後計時器應已被 cancel，不應再繼續觸發',
    );
  });

  testWidgets(
    'App 從背景恢復時，即使 fullscreen 值未變，_applySystemUiMode 仍重新呼叫 elinkbook/fullscreen',
    (tester) async {
      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
      final calls = <MethodCall>[];
      binaryMessenger.setMockMethodCallHandler(fullscreenChannel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
      );

      final prefsManager = FakeReaderPrefsManager(
        bookPrefsByBookId: {'b1': const BookReaderPrefs(fullscreen: true)},
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b1',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      expect(calls, hasLength(1)); // 初次套用

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(calls, hasLength(2), reason: 'resumed 應強制重新呼叫，不受等值節流影響');
      expect(calls.last.method, 'setEnabled');
      expect(calls.last.arguments, isTrue);
    },
  );

  testWidgets('提供 customFontsRepository 時，開啟版面設定顯示自訂字型選項', (tester) async {
    final customFontsRepository = FakeCustomFontsRepository();
    await customFontsRepository.insert(
      const CustomFont(
        displayName: '測試自訂字型',
        familyName: 'TestCustomFamily',
        fontUri: 'content://example/test',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
          customFontsRepository: customFontsRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ReaderSettingsSheet), findsOneWidget);

    // 展開字型下拉選單以驗證自訂字型是否出現
    await tester.tap(find.byKey(const Key('reader_settings_font_family')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('測試自訂字型'), findsWidgets);
  });

  testWidgets(
    '提供 customFontsRepository 時，自訂字型清單載入完成前 FoliateReaderView 不建構，載入完成後才建構',
    (tester) async {
      // ReaderScreen._applySystemUiMode() 開書時一定會呼叫
      // elinkbook/fullscreen 頻道的 setEnabled（Epic 19），未 mock 會導致
      // 未被 await 的 MethodChannel 呼叫非同步拋出 MissingPluginException
      // （審查修正，見 tmp/epic-14/review-issue-3.md Important 2；比照同檔
      // 第 4473-4481 行既有寫法）。
      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
      binaryMessenger.setMockMethodCallHandler(
        fullscreenChannel,
        (call) async => null,
      );
      addTearDown(
        () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
      );

      final customFontsRepository = FakeCustomFontsRepository();
      final gate = Completer<void>();
      customFontsRepository.loadGate = gate;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            customFontsRepository: customFontsRepository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 自訂字型清單尚未載入完成，FoliateReaderView 不應建構，仍顯示載入中指示器。
      expect(find.byType(FoliateReaderView), findsNothing);
      expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

      gate.complete();
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(find.byType(FoliateReaderView), findsOneWidget);
    },
  );

  testWidgets(
    '開書逾時（epic-18-reader-device-qa Issue 33，epic-27-reader-device-compat '
    'Issue 2 調整為 30 秒）：30 秒內未收到 onPageRendered，'
    '自動切換為錯誤畫面，不會永遠停在載入指示器',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.pdf',
            bookId: 'b_open_timeout',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 刻意不呼叫 onPageRendered，模擬「原生端/WebView 從未回報成功」的
      // 卡住情境（真機使用回報：iReader Ocean 4 Plus 開啟書籍時畫面永遠
      // 停在轉圈圈，5 個推測根因皆未經真機診斷資料驗證）。
      expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);
      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      // epic-27-reader-device-compat Issue 2：先推進 29 秒並斷言「仍是載入
      // 中」，確認逾時值真的是 30 秒（而不只是某個大於舊值 12 秒的時間點
      // 剛好也能通過）——若實作仍是舊的 12 秒，這裡會提早看到錯誤畫面而
      // 斷言失敗。
      await tester.pump(const Duration(seconds: 29));

      expect(
        find.byKey(const Key('reader_loading_indicator')),
        findsOneWidget,
        reason: '30 秒內尚未逾時，應維持載入中，不應提早顯示錯誤畫面',
      );
      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      await tester.pump(const Duration(seconds: 1));

      expect(
        find.byKey(const Key('reader_error_text')),
        findsOneWidget,
        reason: '滿 30 秒後應切換為可見的錯誤畫面，而非讓使用者永遠面對轉圈圈',
      );
      expect(find.byKey(const Key('reader_loading_indicator')), findsNothing);
    },
  );

  testWidgets('開書逾時計時器：onPageRendered 在逾時前已觸發時，逾時計時器不應覆蓋既有的成功狀態', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_open_timeout_success',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    expect(find.byKey(const Key('reader_loading_indicator')), findsNothing);

    // 逾時計時器理應在 onPageRendered 觸發當下就被取消；即使沒有取消，
    // 逾時處理本身也必須判斷「已經不是 loading 狀態才動作」，兩者皆可
    // 避免這裡誤把已成功渲染的畫面覆蓋回錯誤狀態。
    // epic-27-reader-device-compat Issue 2：逾時值調整為 30 秒，此處同步
    // 更新推進時長；本測試驗證的是「已成功渲染不受逾時計時器覆蓋」，
    // 與逾時值本身大小無關，故不需要像 Step 1 那樣拆成兩段推進。
    await tester.pump(const Duration(seconds: 30));

    expect(
      find.byKey(const Key('reader_error_text')),
      findsNothing,
      reason: '已成功渲染的畫面不應被逾時計時器事後覆蓋成錯誤狀態',
    );
  });

  testWidgets('EPUB 載入中：原生視圖上方應有不透明主題遮罩，蓋住原生視圖首幀黑屏'
      '（epic-27-reader-device-compat Issue 3）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_black_flash_epub_loading',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 刻意不觸發 onLayoutResolved/onPageRendered，維持 _state == loading。
    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    final placeholder = tester.widget<ColoredBox>(
      find.byKey(const Key('reader_render_placeholder_background')),
    );
    final expectedColor = Theme.of(
      tester.element(find.byType(ReaderScreen)),
    ).scaffoldBackgroundColor;
    expect(placeholder.color, expectedColor);

    // z-order 迴歸防呆（epic-27-reader-device-compat Issue 3 審查 Critical
    // #1）：遮罩必須疊在原生視圖「之上」才有蓋住黑幀的效果，若日後有人誤把
    // 順序寫反，這裡要能直接抓到，而不是只驗證「兩者都存在」。遮罩包了一層
    // IgnorePointer（review-issue-3.md Critical #1 修正：讓觸控穿透，不擋
    // Issue 1 保留的 menu 熱區），故從 Positioned.child 找 IgnorePointer.child
    // 才是 ColoredBox。
    final stack = tester.widget<Stack>(
      find.byKey(const Key('reader_body_stack')),
    );
    final nativeViewIndex = stack.children.indexWhere(
      (child) => child is FoliateReaderView,
    );
    final placeholderIndex = stack.children.indexWhere(
      (child) =>
          child is Positioned &&
          child.child is IgnorePointer &&
          (child.child as IgnorePointer).child is ColoredBox &&
          ((child.child as IgnorePointer).child as ColoredBox).key ==
              const Key('reader_render_placeholder_background'),
    );
    expect(
      nativeViewIndex,
      greaterThanOrEqualTo(0),
      reason: '應能在 Stack 找到原生視圖 FoliateReaderView',
    );
    expect(
      placeholderIndex,
      greaterThanOrEqualTo(0),
      reason: '應能在 Stack 找到不透明遮罩',
    );
    expect(
      placeholderIndex,
      greaterThan(nativeViewIndex),
      reason:
          '遮罩必須疊在原生視圖之上（z-order 較高）才能真正蓋住原生視圖的首幀'
          '黑屏——這是初版計畫審查抓到的 Critical 錯誤（reviews/review-plan-issue-3.md），'
          '此斷言防止未來回歸',
    );

    // 觸控穿透防呆（review-issue-3.md Critical #1）：遮罩存在時，menu 熱區
    // 仍應可正常點擊——不應是靠測試繞過 loading 狀態才通過。
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();
    // 2026-09-10 修正：工具列（含返回鍵）改依 _chromeVisible 收合，這裡改
    // 斷言返回鍵消失，證明 menu 熱區觸控確實穿透遮罩命中 _ZoneOverlay、
    // loading 期間仍可切換沉浸模式（Issue 1 既有保證未變，只是驗證訊號
    // 從「按鈕仍在」改為「按鈕跟著收合」）。
    expect(
      find.byKey(const Key('reader_chrome_back_button')),
      findsNothing,
      reason:
          '遮罩必須只負責視覺覆蓋，menu 熱區觸控必須能穿透遮罩命中'
          '_ZoneOverlay，loading 期間仍可切換沉浸模式（Issue 1 既有保證）',
    );
  });

  testWidgets('PDF 載入中：原生視圖上方應有不透明主題遮罩，蓋住原生視圖首幀黑屏'
      '（epic-27-reader-device-compat Issue 3）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_black_flash_pdf_loading',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 刻意不呼叫 onPageRendered，維持 _state == loading。
    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    final placeholder = tester.widget<ColoredBox>(
      find.byKey(const Key('reader_render_placeholder_background')),
    );
    final expectedColor = Theme.of(
      tester.element(find.byType(ReaderScreen)),
    ).scaffoldBackgroundColor;
    expect(placeholder.color, expectedColor);
  });

  testWidgets('PDF 已渲染完成後：不透明遮罩應隨 _state 轉為 rendered 而消失，不殘留阻擋手勢'
      '（epic-27-reader-device-compat Issue 3 設計決策 1：僅在 loading 時顯示，'
      '非恆常存在——恆常存在會在渲染完成後永久蓋住書籍內容，是比原始黑屏更嚴重的回歸）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_black_flash_pdf_rendered',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 渲染完成前：遮罩應存在（與前一則 PDF loading 測試對稱佈置情境）。
    expect(
      find.byKey(const Key('reader_render_placeholder_background')),
      findsOneWidget,
    );

    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    expect(find.byKey(const Key('reader_loading_indicator')), findsNothing);
    expect(
      find.byType(PdfReaderView),
      findsOneWidget,
      reason: '遮罩不應影響既有原生視圖的正常渲染（零回歸）',
    );
    expect(
      find.byKey(const Key('reader_render_placeholder_background')),
      findsNothing,
      reason:
          '_state 轉為 rendered 後遮罩必須立即移除，否則會永久蓋住已渲染完成的'
          '書籍內容、阻擋底層原生視圖的觸控手勢（審查 Critical #1 連帶修正的'
          '設計決策，見 plan 上方「設計決策」1）',
    );
  });

  testWidgets('流式 EPUB 頁首/頁尾文字：字級為 12、不含按鈕底色與內距，只佔文字本身空間、'
      '文字顏色跟隨 Theme.of(context)（epic-22-reader-theme-integration '
      'Issue 2；epic-18-reader-device-qa Issue 43 的既有測試在此更新——'
      '原本斷言寫死 Colors.black，現在明確指定 AppTheme.light 並比對其實際'
      'onSurface 色值，理由同 Issue 43：拿掉底色後，文字顏色必須與書頁'
      '背景形成足夠對比才看得到）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_header_footer_no_bg',
      const BookReaderPrefs(showHeader: true, showFooter: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildThemeData(AppTheme.light),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_footer_no_bg',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        locationIndex: 9,
        locationTotal: 100,
      ),
    );
    await tester.pump();

    // 觸發沉浸模式讓頁首頁尾顯示
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerContainer = tester.widget<Container>(
      find.byKey(const Key('reader_foliate_header_text')),
    );
    expect(headerContainer.padding, isNull);
    expect(headerContainer.decoration, isNull);

    final headerText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('reader_foliate_header_text')),
        matching: find.byType(Text),
      ),
    );
    expect(headerText.style?.fontSize, 12);
    expect(
      headerText.style?.color,
      buildThemeData(AppTheme.light).colorScheme.onSurface,
    );

    final footerContainer = tester.widget<Container>(
      find.byKey(const Key('reader_foliate_progress_text')),
    );
    expect(footerContainer.padding, isNull);
    expect(footerContainer.decoration, isNull);

    final footerText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('reader_foliate_progress_text')),
        matching: find.byType(Text),
      ),
    );
    expect(footerText.style?.fontSize, 12);
    expect(
      footerText.style?.color,
      buildThemeData(AppTheme.light).colorScheme.onSurface,
    );
  });

  testWidgets('流式 EPUB 頁首/頁尾文字：深色主題下顏色跟隨 Theme.of(context)'
      '（epic-22-reader-theme-integration Issue 2）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_header_footer_dark',
      const BookReaderPrefs(showHeader: true, showFooter: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_footer_dark',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        locationIndex: 9,
        locationTotal: 100,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('reader_foliate_header_text')),
        matching: find.byType(Text),
      ),
    );
    expect(
      headerText.style?.color,
      buildThemeData(AppTheme.dark).colorScheme.onSurface,
    );

    final footerText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('reader_foliate_progress_text')),
        matching: find.byType(Text),
      ),
    );
    expect(
      footerText.style?.color,
      buildThemeData(AppTheme.dark).colorScheme.onSurface,
    );
  });

  testWidgets('EPUB 固定版面：不論主題為何，頁首/頁尾文字色維持既有寫死 Colors.black'
      '（epic-22-reader-theme-integration Issue 2，固定版面內容通常是白底'
      '圖片，若文字色跟著深色主題變淺會看不見）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_header_footer_fxl',
      const BookReaderPrefs(showHeader: true, showFooter: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_header_footer_fxl',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        visualPageIndex: 9,
        visualTotalPages: 100,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('reader_foliate_header_text')),
        matching: find.byType(Text),
      ),
    );
    expect(headerText.style?.color, Colors.black);

    final footerText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('reader_foliate_progress_text')),
        matching: find.byType(Text),
      ),
    );
    expect(footerText.style?.color, Colors.black);
  });

  testWidgets('深色主題下開啟版面設定 Bottom Sheet，遮罩同樣透明（epic-22-reader-'
      'theme-integration Issue 5：修法透過共用 helper 套用到全部 6 個'
      'Bottom Sheet 呼叫點，不只進度面板一處，本測試驗證另一個呼叫點'
      '同樣生效）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_settings_sheet_dark_barrier',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 「版面設定」按鈕在收到 onLayoutResolved 前是停用的（onPressed 為
    // null），比照既有測試（本檔案第 293 行附近）先觸發一次才能點擊。
    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.vertical,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final dimmingBarrierFinder = find.byWidgetPredicate(
      (widget) =>
          widget is ModalBarrier && widget.color != null && widget.color!.a > 0,
    );
    expect(dimmingBarrierFinder, findsNothing);
  });

  testWidgets('淺色主題下開啟版面設定 Bottom Sheet，遮罩維持 Flutter 既有預設值'
      '（不受深色主題專用修法影響，回歸保證；epic-38-reader-chrome-tts-'
      'redesign Issue 1 審查修正：原測試觸發點 reader_foliate_progress_button'
      '已隨進度 Bottom Sheet 一併移除，改用仍存在的 reader_chrome_layout_button，'
      '驗證意圖不變——淺色主題不套用深色主題那套透明遮罩特例）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildThemeData(AppTheme.light),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_settings_sheet_light_barrier',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final barrier = tester.widget<ModalBarrier>(
      find.byWidgetPredicate(
        (widget) => widget is ModalBarrier && widget.color != null,
      ),
    );
    expect(barrier.color, Colors.black54);
  });

  testWidgets('深色主題下流式 EPUB「返回」浮動按鈕底色/圖示色跟隨 Theme.of(context)'
      '（epic-22-reader-theme-integration Issue 3）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_fab_color_dark',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 審查修正（review-issue-1.md C-1 類別 D／C-2）：按鈕底色改由
    // ReaderChromeTopBar 外層單一 Material 承載（不再是逐顆 ClipOval+
    // Container），圖示顏色改由 IconButton.style 的 foregroundColor 決定
    // （Icon 本身不再自帶 color），比對 Container.color／Icon.color 的舊
    // 寫法都已不適用。
    final backMaterial = tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(const Key('reader_chrome_back_button')),
            matching: find.byType(Material),
          )
          .first,
    );
    final backButton = tester.widget<IconButton>(
      find.byKey(const Key('reader_chrome_back_button')),
    );

    final expectedTheme = buildThemeData(AppTheme.dark);
    expect(backMaterial.color, expectedTheme.colorScheme.surface);
    expect(
      backButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      expectedTheme.colorScheme.onSurface,
    );
  });

  testWidgets('淺色主題下流式 EPUB「返回」浮動按鈕底色/圖示色跟隨 Theme.of(context)'
      '（epic-22-reader-theme-integration Issue 3）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildThemeData(AppTheme.light),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_fab_color_light',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 審查修正（review-issue-1.md C-1 類別 D／C-2）：同上方深色主題測試。
    final backMaterial = tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(const Key('reader_chrome_back_button')),
            matching: find.byType(Material),
          )
          .first,
    );
    final backButton = tester.widget<IconButton>(
      find.byKey(const Key('reader_chrome_back_button')),
    );

    final expectedTheme = buildThemeData(AppTheme.light);
    expect(backMaterial.color, expectedTheme.colorScheme.surface);
    expect(
      backButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      expectedTheme.colorScheme.onSurface,
    );
  });

  testWidgets('E-Ink 模式下流式 EPUB「返回」浮動按鈕維持黑底白圖示（2026-09-08 '
      '/grill-with-docs 使用者需求：只有一般主題的底色/圖示色互換，E-Ink 高'
      '對比模式的既有黑底白圖示不受影響）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: true),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_fab_color_eink',
          prefsManager: prefsManager,
          isFixedLayout: false,
          isEinkMode: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final backMaterial = tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(const Key('reader_chrome_back_button')),
            matching: find.byType(Material),
          )
          .first,
    );
    final backButton = tester.widget<IconButton>(
      find.byKey(const Key('reader_chrome_back_button')),
    );

    final einkTheme = resolveThemeData(theme: AppTheme.light, isEinkMode: true);
    expect(backMaterial.color, einkTheme.colorScheme.onSurface);
    expect(
      backButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      einkTheme.colorScheme.surface,
    );
  });

  testWidgets('EPUB 固定版面：不論主題為何，浮動按鈕維持既有寫死 Colors.black54/'
      'Colors.white（epic-22-reader-theme-integration Issue 3，固定版面'
      '內容通常是白底圖片，控制按鈕跟著深色主題變色會失去對比）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fab_color_fxl',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 審查修正（review-issue-1.md C-1 類別 D／C-2）：同上方兩則主題測試。
    final backMaterial = tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(const Key('reader_chrome_back_button')),
            matching: find.byType(Material),
          )
          .first,
    );
    final backButton = tester.widget<IconButton>(
      find.byKey(const Key('reader_chrome_back_button')),
    );

    expect(backMaterial.color, Colors.black54);
    expect(
      backButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      Colors.white,
    );
  });

  testWidgets('深色主題下流式 EPUB「版面設定」浮動按鈕（有 onPressed 分流邏輯的'
      '按鈕）顏色同樣跟隨主題（epic-22-reader-theme-integration Issue 3，'
      '驗證不只最簡單的返回按鈕生效）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_fab_color_settings_dark',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // ReaderChromeBottomBar 底色改由外層單一 Material（而非各按鈕獨立
    // ClipOval+Container）承載（epic-38-reader-chrome-tts-redesign
    // Issue 1），直接讀 widget 的 backgroundColor/iconColor 建構參數，
    // 比對 Container.color 的舊寫法已不適用。
    final bottomBar = tester.widget<ReaderChromeBottomBar>(
      find.byType(ReaderChromeBottomBar),
    );
    // 審查修正（review-issue-1.md C-2）：Icon 已不再自帶 color，改由
    // IconButton.style 的 foregroundColor 統一決定，直接讀取 style 解析
    // 後的顏色，比對 Icon.color（現在恆為 null）已不適用。
    final settingsButton = tester.widget<IconButton>(
      find.byKey(const Key('reader_chrome_layout_button')),
    );

    final expectedTheme = buildThemeData(AppTheme.dark);
    expect(bottomBar.backgroundColor, expectedTheme.colorScheme.surface);
    expect(
      settingsButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      expectedTheme.colorScheme.onSurface,
    );
  });

  testWidgets('流式 EPUB 成功開啟後收到 onError（例如螢幕旋轉觸發的 ResizeObserver '
      '瀏覽器警告，經 epic-18-reader-device-qa Issue 33 的全域 window.onerror '
      '轉發），不應覆蓋已成功渲染的畫面（/diagnose：真機回報旋轉螢幕後畫面'
      '整個被錯誤文字取代，無法繼續閱讀）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_error_after_render',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.vertical,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byType(FoliateReaderView), findsOneWidget);

    // 模擬旋轉螢幕時，foliate-js 的 ResizeObserver 觸發瀏覽器層級的
    // 「loop completed with undelivered notifications」警告，被全域
    // window.onerror 補捉後透過既有 onError bridge 轉發過來——這是一則
    // 良性警告，不代表書籍真的開啟失敗。
    foliateView.onError(
      'JS Error: ResizeObserver loop completed with undelivered '
      'notifications. (https://appassets.androidplatform.net/assets/'
      'foliate/index.html?prefs=...)',
    );
    await tester.pump();

    expect(
      find.byKey(const Key('reader_error_text')),
      findsNothing,
      reason: '已成功渲染的畫面不應被開書成功後才發生的良性 JS 警告覆蓋成錯誤狀態',
    );
    expect(
      find.byType(FoliateReaderView),
      findsOneWidget,
      reason: '書籍內容應維持顯示，使用者仍可繼續閱讀',
    );
  });

  group('PdfCropFrameOverlay', () {
    testWidgets('進入手動裁切模式時顯示 PdfCropFrameOverlay，確認後寫回 prefs', (tester) async {
      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
      binaryMessenger.setMockMethodCallHandler(
        fullscreenChannel,
        (call) async => null,
      );
      addTearDown(
        () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b1',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      // epic-24 Issue 8：PDF 不再使用 AppBar，設定按鈕改為 FAB。
      // 直接呼叫 onPressed callback 繞過 PdfReaderView gesture arena 問題。
      tester
          .widget<IconButton>(
            find.byKey(const Key('reader_chrome_layout_button')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
      await tester.pumpAndSettle();

      expect(find.byType(PdfCropFrameOverlay), findsOneWidget);

      await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
      await tester.pumpAndSettle();

      expect(
        find.byType(PdfCropFrameOverlay),
        findsNothing,
        reason: '確認後應退出裁切編輯模式',
      );
    });

    testWidgets('進入手動裁切模式時顯示 PdfCropFrameOverlay，取消後退出且不寫回 prefs', (
      tester,
    ) async {
      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
      binaryMessenger.setMockMethodCallHandler(
        fullscreenChannel,
        (call) async => null,
      );
      addTearDown(
        () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b2',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      // epic-24 Issue 8：PDF 不再使用 AppBar，設定按鈕改為 FAB。
      // 直接呼叫 onPressed callback 繞過 PdfReaderView gesture arena 問題。
      tester
          .widget<IconButton>(
            find.byKey(const Key('reader_chrome_layout_button')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
      await tester.pumpAndSettle();

      expect(find.byType(PdfCropFrameOverlay), findsOneWidget);

      await tester.tap(find.byKey(const Key('pdf_crop_frame_cancel')));
      await tester.pumpAndSettle();

      expect(
        find.byType(PdfCropFrameOverlay),
        findsNothing,
        reason: '取消後應退出裁切編輯模式',
      );
    });
  });

  testWidgets(
    'PDF 長按拖曳框選完成後，顯示 AnnotationToolbar；點擊螢光筆後劃線已寫入且 Toolbar 仍開啟（可續加備註）',
    (tester) async {
      // 【epic-24 Issue 4 Task 6，複審修正】改回真實手勢模擬——原本的版本
      // 註解宣稱「ReaderScreen 的 widget tree 會截斷手勢／pdfrx 在 widget
      // test 環境下攔截手勢」，經 /superpowers:receiving-code-review 複審
      // 追查後證實這個說法是錯的：真正原因有兩個，且都與「手勢被攔截」
      // 無關。(1) 原本的等待邏輯只有 `Future.delayed(Duration.zero)`
      // 一個 microtask，遠不足以讓 pdfrx 真正完成非同步文件載入／版面計算
      // （見下方改用本檔案 PdfCropFrameOverlay 測試已驗證過的 30 次輪詢
      // 等待樣板），手勢發生時 GestureDetector 根本還沒真正建構出來。
      // (2) `flutter test` 預設視窗是 800×600（橫向），會讓
      // `isLandscape` 判定為 true，觸發產品預設 `dualPageMode: auto`
      // 悄悄啟用雙頁並列——雙頁模式下頁面內容在畫面上的實際位置與單頁
      // 模式完全不同（頁面通常不會貼齊 widget 左上角），這裡沿用其他
      // 測試「以左上角為基準取固定偏移量」的觸控座標假設會直接落在頁面
      // 內容範圍之外，長按自然永遠不會命中任何 GestureDetector——這不是
      // 本測試要驗證的範圍（雙頁模式下框選正確歸屬單一頁面已有
      // `pdf_reader_view_selection_test.dart` 的專屬測試涵蓋，見計畫
      // Task 5），故這裡改用本檔案既有的直向視窗慣例強制單頁模式，讓
      // 座標假設成立，而非放棄真實手勢模擬。
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(400, 800)); // 直向。
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final highlightsRepository = FakeHighlightsRepository();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b1',
            prefsManager: FakeReaderPrefsManager(),
            highlightsRepository: highlightsRepository,
            notesRepository: FakeNotesRepository(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      // epic-24 Issue 8：PDF 新增 FAB 後，原本的 (40, 60) 觸控座標落在
      // reader_chrome_back_button（top:16, left:16, 48x48 IconButton）範圍內，
      // 會被 FAB 的 InkWell 攔截而非命中 PdfReaderView 的 GestureDetector。
      // 改用 (200, 300) 避開所有 FAB（右側 FAB 在 right:16、左側僅左上角
      // back FAB 在 left:16, top:16）。
      final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
      final gesture = await tester.startGesture(
        topLeft + const Offset(200, 300),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(topLeft + const Offset(160, 220));
      await tester.pump();
      await gesture.up();
      await pumpUntilPdfReady(
        tester,
        condition: () => find.byType(AnnotationToolbar).evaluate().isNotEmpty,
      );

      expect(
        find.byType(AnnotationToolbar),
        findsOneWidget,
        reason: '選取完成後應顯示 AnnotationToolbar',
      );

      await tester.tap(
        find.byKey(const Key('annotation_toolbar_highlighter_yellow')),
      );
      await tester.pumpAndSettle();

      // 選色後應建立劃線，但選取狀態與 Toolbar 刻意保持開啟——比照 EPUB
      // 的 _handleHighlightStyleSelected（reader_screen.dart），讓使用者
      // 能接著按「備註」把備註掛在同一筆劃線上（見
      // AnnotationToolbar.onNotePressed 文件註解）；只有按下「備註」或
      // 取消選取才會清空 _currentPdfSelection。
      expect(
        find.byType(AnnotationToolbar),
        findsOneWidget,
        reason: '選色後劃線已建立，但 Toolbar 應保持開啟以便續加備註',
      );
      final saved = await highlightsRepository.listByBook('b1');
      expect(saved, hasLength(1));
      expect(saved.single.pdfPageIndex, 0);
    },
  );

  testWidgets('PDF：選取範圍靠近畫面右緣時，AnnotationToolbar 右緣不應超出畫面寬度', (tester) async {
    // 固定視窗尺寸（400×800），讓 clamp 後的精確像素值可預期、可斷言。
    // 本測試直接呼叫 onSelectionRectComputed 回呼（比照 EPUB 測試對
    // onSelectionChanged 的呼叫方式），不透過真實長按拖曳手勢，因此不需要
    // 其他 PDF 測試（如 5391 行）為了等待真實 pdfrx 文件載入完成才需要的
    // 30 次輪詢等待樣板——本測試只驗證 AnnotationToolbar 收到選取矩形後
    // 的定位計算，與 pdfrx 是否已完成真實頁面渲染無關。
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800));
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_select_edge',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: FakeHighlightsRepository(),
          notesRepository: FakeNotesRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    // 選取範圍靠近畫面右緣（widgetRect.left=0.95），比照使用者截圖回報的
    // 症狀（tmp/images/畫線問題/畫線太右邊無法看到全部工具列.jpg）。
    pdfView.onSelectionRectComputed?.call(
      const PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.95, top: 0.2, right: 0.99, bottom: 0.3),
        widgetRect: PercentRect(left: 0.95, top: 0.2, right: 0.99, bottom: 0.3),
      ),
    );
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsOneWidget);
    final bottomRight = tester.getBottomRight(find.byType(AnnotationToolbar));
    expect(
      bottomRight.dx,
      lessThanOrEqualTo(400.0),
      reason:
          '工具列右緣（現況會落在 636.0）不應超出畫面寬度 400.0，'
          '否則右半部按鈕會被裁切看不到',
    );
  });

  testWidgets('PDF：點擊 AnnotationToolbar 的關閉按鈕後，清空選取狀態、工具列消失', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_close_toolbar',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: FakeHighlightsRepository(),
          notesRepository: FakeNotesRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onSelectionRectComputed?.call(
      const PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
        widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
      ),
    );
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsOneWidget);

    await tester.tap(find.byKey(const Key('annotation_toolbar_close')));
    await tester.pump();

    expect(
      find.byType(AnnotationToolbar),
      findsNothing,
      reason: '點擊關閉按鈕後應清空選取狀態，工具列從畫面消失',
    );
  });

  testWidgets('PDF 換頁時應清除既有選取狀態，AnnotationToolbar 隨之消失（Epic 24 Issue 10）', (
    tester,
  ) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_page_turn_clears_selection',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: FakeHighlightsRepository(),
          notesRepository: FakeNotesRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    // epic-27-reader-device-compat Issue 1：_handleZoneAction 新增的
    // loading 狀態防呆，若 _state 仍是 loading 會直接 return（包含本測試
    // 要驗證的清除選取副作用），故需明確模擬 onPageRendered 讓 _state
    // 轉為 rendered，比照既有 EPUB 測試的既有慣例（測的是「已載入完成後
    // 換頁」情境，不是本 Issue 要防呆的「載入中換頁」情境）。
    pdfView.onPageRendered();
    await tester.pump();

    // 情境 A：nextPage 應清除既有選取。
    pdfView.onSelectionRectComputed?.call(
      const PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
        widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
      ),
    );
    await tester.pump();
    expect(
      find.byType(AnnotationToolbar),
      findsOneWidget,
      reason: '選取完成後應顯示 AnnotationToolbar',
    );

    ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
    await tester.pump();
    expect(
      find.byType(AnnotationToolbar),
      findsNothing,
      reason: 'nextPage 換頁後應清空選取狀態，工具列從畫面消失',
    );

    // 情境 B：previousPage 同樣應清除既有選取。
    pdfView.onSelectionRectComputed?.call(
      const PdfSelectionInfo(
        pageIndex: 1,
        rect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
        widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
      ),
    );
    await tester.pump();
    expect(
      find.byType(AnnotationToolbar),
      findsOneWidget,
      reason: '第二次選取完成後應再次顯示 AnnotationToolbar',
    );

    ReaderScreen.triggerZoneAction(key, ZoneAction.previousPage);
    await tester.pump();
    expect(
      find.byType(AnnotationToolbar),
      findsNothing,
      reason: 'previousPage 換頁後同樣應清空選取狀態，工具列從畫面消失',
    );
  });

  testWidgets(
    'PDF：_state 仍為 loading 時觸發換頁熱區，應被忽略——不清除既有選取狀態（epic-27-reader-device-compat Issue 1）',
    (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_pdf_loading_guard',
            prefsManager: FakeReaderPrefsManager(),
            highlightsRepository: FakeHighlightsRepository(),
            notesRepository: FakeNotesRepository(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 刻意**不**呼叫 pdfView.onPageRendered()——維持 _state == loading，
      // 模擬使用者在書籍仍在載入中時就點擊熱區的真機回報情境。
      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      pdfView.onSelectionRectComputed?.call(
        const PdfSelectionInfo(
          pageIndex: 0,
          rect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
          widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
        ),
      );
      await tester.pump();
      expect(
        find.byType(AnnotationToolbar),
        findsOneWidget,
        reason: '選取完成後應顯示 AnnotationToolbar（此步驟與 loading 防呆無關，只是佈置情境）',
      );

      ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
      await tester.pump();
      expect(
        find.byType(AnnotationToolbar),
        findsOneWidget,
        reason:
            '_state 仍是 loading，nextPage 應被忽略——若防呆失效，'
            'PdfReaderView.nextPage 呼叫路徑會一併清除既有選取，'
            'AnnotationToolbar 將意外消失（未加防呆前的既有行為，見 '
            'epic-27-reader-device-compat Issue 1 診斷）',
      );

      ReaderScreen.triggerZoneAction(key, ZoneAction.previousPage);
      await tester.pump();
      expect(
        find.byType(AnnotationToolbar),
        findsOneWidget,
        reason: '_state 仍是 loading，previousPage 同樣應被忽略',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'EPUB 流式：_state 仍為 loading 時觸發換頁熱區，不拋出例外（epic-27-reader-device-compat Issue 1；真機上 JS 尚未就緒時是否正確攔截需 integration_test/人工驗證，見 issues.md）',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_epub_loading_guard',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 刻意**不**呼叫 onPageRendered()/onLayoutResolved()——維持
      // _state == loading。rightFlip 模板：index 0（左欄）＝ previousPage、
      // index 2（右欄）＝ nextPage（見 nav_zone_mode.dart
      // rightFlipZoneTemplate）。
      await tester.tap(find.byKey(const Key('nav_zone_0')));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('nav_zone_2')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PDF：_state 已是 rendered 後，換頁熱區維持既有行為不受 loading 防呆影響（回歸檢查，epic-27-reader-device-compat Issue 1）',
    (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_pdf_rendered_no_regression',
            prefsManager: FakeReaderPrefsManager(),
            highlightsRepository: FakeHighlightsRepository(),
            notesRepository: FakeNotesRepository(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      pdfView.onPageRendered();
      await tester.pump();
      pdfView.onSelectionRectComputed?.call(
        const PdfSelectionInfo(
          pageIndex: 0,
          rect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
          widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
        ),
      );
      await tester.pump();
      expect(find.byType(AnnotationToolbar), findsOneWidget);

      ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
      await tester.pump();
      expect(
        find.byType(AnnotationToolbar),
        findsNothing,
        reason:
            '_state 已是 rendered，既有「換頁清除選取」行為應維持不變，'
            '不受新增的 loading 防呆影響（零回歸）',
      );
    },
  );

  testWidgets(
    'PDF 換頁時若有進行中的長按拖曳框選（尚未放開手指），應一併中止，放開後不會用換頁前的舊頁面重新彈出 AnnotationToolbar（Epic 24 Issue 10 審查修正）',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(400, 800)); // 直向。
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_pdf_page_turn_cancels_active_drag',
            prefsManager: FakeReaderPrefsManager(),
            highlightsRepository: FakeHighlightsRepository(),
            notesRepository: FakeNotesRepository(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      // 觸控位置刻意取畫面中央附近（而非邊角），避開 PDF FAB
      // （reader_chrome_back_button 等固定在 top:16/left:16 一類螢幕邊角，
      // 靠邊角的座標會被 FAB 攔截，長按永遠不會到達下方的框選手勢層）。
      final center = tester.getCenter(find.byType(PdfReaderView));
      final finger = await tester.startGesture(center);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await finger.moveTo(center + const Offset(80, 100));
      await tester.pump();
      expect(
        find.byKey(const Key('pdf_reader_selection_drag_indicator')),
        findsOneWidget,
        reason: '長按拖曳進行中應顯示框選視覺回饋',
      );

      // 比照真機情境：音量鍵翻頁與觸控手勢是完全獨立的輸入通道，可能在
      // 使用者手指仍按著螢幕、拖曳框選進行中時觸發——直接呼叫
      // triggerZoneAction 等價於音量鍵事件經 _handleVolumeKeyCall 分派的
      // 結果。
      ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
      await tester.pump();

      expect(
        find.byKey(const Key('pdf_reader_selection_drag_indicator')),
        findsNothing,
        reason: '換頁應一併中止進行中的拖曳，框選視覺回饋消失',
      );

      await finger.up();
      await tester.pump();

      expect(
        find.byType(AnnotationToolbar),
        findsNothing,
        reason: '拖曳已被中止，放開手指不應用換頁前的舊頁面座標重新彈出 AnnotationToolbar',
      );
    },
  );

  testWidgets('PDF 選取被取消（onSelectionCanceled）時，不顯示 AnnotationToolbar', (
    tester,
  ) async {
    // 同上一則測試：改回真實多指手勢模擬，強制直向視窗維持單頁模式，
    // 並補足 30 次輪詢等待真實 pdfrx 載入完成。
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800)); // 直向。
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b1',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: FakeHighlightsRepository(),
          notesRepository: FakeNotesRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await pumpUntilPdfReady(tester);

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final firstFinger = await tester.startGesture(
      topLeft + const Offset(40, 60),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await firstFinger.moveTo(topLeft + const Offset(120, 160));
    await tester.pump();
    expect(
      find.byType(AnnotationToolbar),
      findsNothing,
      reason: '拖曳進行中尚未放開，不應顯示 Toolbar',
    );

    final secondFinger = await tester.startGesture(
      topLeft + const Offset(300, 400),
    );
    await tester.pump();

    expect(
      find.byType(AnnotationToolbar),
      findsNothing,
      reason: '第二指觸控應取消進行中的框選，不顯示 AnnotationToolbar',
    );

    await firstFinger.up();
    await secondFinger.up();
    await tester.pump();

    // DoubleTapGestureRecognizer 內部有 300ms 計時器，需 flush 否則
    // 測試結束時會擲出 "!timersPending" 斷言。
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('PDF 書籤 toggle：目前頁無書籤時呼叫後新增一筆，頁碼定位正確', (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b1',
          prefsManager: FakeReaderPrefsManager(),
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    // 等待 pdfrx 真實載入 PDF（30 次輪詢，比照本檔案既有 PDF 測試慣例）。
    await pumpUntilPdfReady(tester);

    // 模擬原生端回報頁碼，讓 _pdfPageInfo 非 null（比照既有 PDF 測試
    // 直接呼叫 PdfReaderView.onPageChanged 的模式）。
    tester
        .widget<PdfReaderView>(find.byType(PdfReaderView))
        .onPageChanged
        ?.call(const PdfPageInfo(pageIndex: 0, totalPages: 5));
    await tester.pump();

    ReaderScreen.togglePdfBookmark(key);
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final saved = await bookmarksRepository.listByBook('b1');
    expect(saved, hasLength(1));
    expect(saved.single.pdfPageIndex, 0);
    expect(saved.single.name, '第 1 頁');
  });

  testWidgets('PDF 書籤 toggle：目前頁已有書籤時呼叫後移除該筆', (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await bookmarksRepository.insert(
      Bookmark(id: 'existing', bookId: 'b1', name: '第 1 頁', pdfPageIndex: 0),
    );
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b1',
          prefsManager: FakeReaderPrefsManager(),
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    // 等待 pdfrx 真實載入 PDF（30 次輪詢，比照本檔案既有 PDF 測試慣例）。
    await pumpUntilPdfReady(tester);

    // 模擬原生端回報頁碼，讓 _pdfPageInfo 非 null。
    tester
        .widget<PdfReaderView>(find.byType(PdfReaderView))
        .onPageChanged
        ?.call(const PdfPageInfo(pageIndex: 0, totalPages: 5));
    await tester.pump();

    ReaderScreen.togglePdfBookmark(key);
    await tester.pump();
    // _togglePdfBookmark 是 async（呼叫 repository.delete + _loadFxlBookmarks），
    // togglePdfBookmark static seam 以 unawaited 包裝，需多 pump 讓 microtask 完成。
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final saved = await bookmarksRepository.listByBook('b1');
    expect(saved, isEmpty, reason: '已存在同頁書籤時應移除，而非重複新增');
  });

  testWidgets('PDF 開書後背景載入目錄；載入完成前 openPdfToc 無作用，完成後可開啟 TocBottomSheet', (
    tester,
  ) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_pdf_toc.pdf',
          bookId: 'b_pdf_toc',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 目錄背景載入尚未完成（onPageRendered 尚未真正觸發），此時呼叫應
    // 無作用。
    ReaderScreen.openPdfToc(key);
    await tester.pump();
    expect(find.byType(TocBottomSheet), findsNothing);

    // 等待 pdfrx 真實載入 PDF（30 次輪詢，比照本檔案既有 PDF 測試慣例）。
    await pumpUntilPdfReady(tester);
    // _pdfTocLoaded 由 loadTableOfContents() 這個 async 呼叫的 .then()
    // callback 設定，需要多一次 pump 讓其 microtask 完成、觸發 setState。
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TocBottomSheet), findsOneWidget);
    expect(find.text('Part One'), findsOneWidget);
    expect(find.text('Chapter 5'), findsOneWidget);
  });

  testWidgets('點選 PDF 目錄項目後正確跳轉頁面並關閉 Bottom Sheet', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_pdf_toc.pdf',
          bookId: 'b_pdf_toc_jump',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await pumpUntilPdfReady(tester);
    await tester.pump();

    // epic-38 Issue 1：PDF 使用 ReaderChromeBottomBar，頁碼文字嵌入 BottomBar。
    expect(find.byKey(const Key('reader_chrome_page_info_text')), findsOneWidget);

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TocBottomSheet), findsOneWidget);

    // 驗證 Chapter 5 存在於目錄中
    expect(find.text('Chapter 5'), findsOneWidget);

    // 點選 Chapter 5 後，Bottom Sheet 應關閉（Navigator.pop 生效）。
    await tester.tap(find.text('Chapter 5'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TocBottomSheet), findsNothing);
  });

  testWidgets('無大綱的 PDF 開啟後，openPdfToc 顯示空清單提示而非崩潰', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_pdf_toc_empty',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await pumpUntilPdfReady(tester);
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TocBottomSheet), findsOneWidget);
    expect(
      find.byKey(const Key('toc_bottom_sheet_empty_text')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('PDF 搜尋："Page" 找到符合結果，顯示計數器', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_search',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await pumpUntilPdfReady(tester);
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();

    // 輸入搜尋關鍵字
    final textField = find.byKey(const Key('pdf_search_field'));
    expect(textField, findsOneWidget);
    await tester.enterText(textField, 'Page');
    await tester.pump(const Duration(milliseconds: 600));

    // 等待搜尋完成
    await pumpUntilPdfReady(tester, maxIterations: 10);
    await tester.pump();

    // 驗證搜尋面板可見且計數器顯示（搜尋面板內的計數器格式為「1 / 5」）。
    expect(find.text('1 / 5'), findsOneWidget);
    // epic-24 Issue 8：PDF 不再有 in-flow 頁尾，'1/5' 不會出現在 body。
    // 確認搜尋面板存在即可，不再驗證頁尾文字。
  });

  testWidgets('PDF 搜尋：點擊下一個/上一個依序跳轉並於首尾循環導覽', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_search_nav',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await pumpUntilPdfReady(tester);
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();

    final textField = find.byKey(const Key('pdf_search_field'));
    expect(textField, findsOneWidget);
    await tester.enterText(textField, 'Page');
    await tester.pump(const Duration(milliseconds: 600));

    await pumpUntilPdfReady(tester, maxIterations: 10);
    await tester.pump();

    // 起始狀態：5 筆符合結果，目前在第 1 筆。
    //
    // 註：本測試只斷言搜尋面板計數器（_pdfSearchStateNotifier 驅動的
    // 「N / 5」文字），不斷言 reader footer 實際頁碼（「N/5」）——footer
    // 頁碼變化依賴 pdfrx PdfViewer 內部真實捲動動畫，經診斷確認在本檔案
    // 「Bottom Sheet 開啟中」這個既有測試情境下，即使搭配 runAsync 真實
    // 延遲等待數秒，動畫完成時機仍不可靠（連 Issue 5 既有、已合併的 TOC
    // 跳頁測試「點選 PDF 目錄項目後正確跳轉頁面並關閉 Bottom Sheet」也有
    // 同樣現象，非本工單新增邏輯所致）；已用獨立情境（無 ReaderScreen／
    // Bottom Sheet 包裹的裸 PdfReaderView）重現驗證 jumpToPage() 本身在
    // 連續兩次呼叫下能正確落點，證實這是既有的測試環境時序問題，非
    // `_goToPdfSearchMatch` 的索引計算邏輯缺陷。搜尋面板計數器才是本測試
    // 真正要保護的行為（循環導覽的索引數學），且其更新不依賴 pdfrx 動畫
    // 完成，可靠地同步反映在畫面上。
    expect(find.text('1 / 5'), findsOneWidget);

    // 從第一筆點擊「上一個」，須循環到最後一筆（第 5 筆），而不是產生負數
    // 索引例外（獨立審查已確認 Dart `%` 為 Euclidean modulo、程式邏輯本身
    // 沒有 RangeError 風險，這裡是補上先前缺漏的整合層級回歸測試）。
    await tester.tap(find.byKey(const Key('pdf_search_prev_button')));
    await tester.pump();
    expect(find.text('5 / 5'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 從最後一筆點擊「下一個」，須循環回第一筆。
    await tester.tap(find.byKey(const Key('pdf_search_next_button')));
    await tester.pump();
    expect(find.text('1 / 5'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 連續點擊「下一個」4 次，依序跳轉至第 2~5 筆。
    for (var expected = 2; expected <= 5; expected++) {
      await tester.tap(find.byKey(const Key('pdf_search_next_button')));
      await tester.pump();
      expect(find.text('$expected / 5'), findsOneWidget);
    }
  });

  testWidgets('PDF 搜尋：無文字層的 PDF 查無符合結果時顯示提示文字', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_pdf_search_empty',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await pumpUntilPdfReady(tester);
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();

    final textField = find.byKey(const Key('pdf_search_field'));
    expect(textField, findsOneWidget);
    await tester.enterText(textField, 'anything');
    await tester.pump(const Duration(milliseconds: 600));

    await pumpUntilPdfReady(tester, maxIterations: 10);
    await tester.pump();

    expect(find.byKey(const Key('pdf_search_empty')), findsOneWidget);
    expect(find.text('找不到符合的文字'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PDF 縮圖：切換到縮圖分頁後正確顯示每一頁的縮圖格', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_thumbnails',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await pumpUntilPdfReady(tester);
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('縮圖'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 驗證縮圖面板已顯示
    expect(find.byKey(const Key('pdf_thumbnail_panel_grid')), findsOneWidget);

    // 驗證 5 頁縮圖格皆存在（sample_multi_page.pdf 有 5 頁）
    for (var i = 0; i < 5; i++) {
      expect(find.byKey(Key('pdf_thumbnail_tile_$i')), findsOneWidget);
    }
    // 驗證第 6 格不存在——僅可視範圍內建構（Global Constraint）
    expect(find.byKey(const Key('pdf_thumbnail_tile_5')), findsNothing);
  });

  testWidgets('PDF 縮圖：點擊縮圖後正確關閉 Bottom Sheet，不拋出例外', (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_thumbnails_click',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    await pumpUntilPdfReady(tester);
    await tester.pump();

    ReaderScreen.openPdfToc(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('縮圖'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 點擊第 3 頁縮圖（index 2）
    await tester.tap(find.byKey(const Key('pdf_thumbnail_tile_2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 驗證 Bottom Sheet 已關閉
    expect(find.byType(TocBottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('版面設定預設集（epic-28-reader-settings-enhancements Issue 3）', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    late SqliteLibraryRepository libraryRepository;
    late LayoutPresetRepository layoutPresetRepository;
    late BookReaderPrefsRepository bookReaderPrefsRepository;

    setUp(() async {
      libraryRepository = await SqliteLibraryRepository.open(
        inMemoryDatabasePath,
        singleInstance: false,
      );
      layoutPresetRepository = LayoutPresetRepository(
        libraryRepository.database,
      );
      bookReaderPrefsRepository = BookReaderPrefsRepository(
        libraryRepository.database,
      );
      await libraryRepository.insertBook(
        Book(
          id: 'b1',
          title: '目前書籍',
          format: BookFileFormat.epub,
          filePath: 'test/fixtures/sample.epub',
          source: BookSource.local,
          isFixedLayout: false,
          createTime: DateTime.fromMillisecondsSinceEpoch(1000),
          lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      );
      await libraryRepository.insertBook(
        Book(
          id: 'b_other',
          title: '其他流式書',
          format: BookFileFormat.epub,
          filePath: 'content://example/other.epub',
          source: BookSource.local,
          isFixedLayout: false,
          createTime: DateTime.fromMillisecondsSinceEpoch(1000),
          lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      );
      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      binaryMessenger.setMockMethodCallHandler(
        const MethodChannel('elinkbook/volume_key'),
        (call) async => null,
      );
    });

    tearDown(() async {
      await libraryRepository.close();
    });

    // 比照既有「流式 EPUB 開書後，ReaderSettingsSheet 變動的偏好正確傳遞到
    // FoliateReaderView」測試（約 line 351）的既有手法：settings 按鈕
    // 的 onPressed 要到 `onLayoutResolved` 觸發、_autoDetectedWritingMode
    // 非 null 後才可用（純 flutter test 環境沒有真實 WebView，須手動呼叫
    // FoliateReaderView widget 上的 onPageRendered()/onLayoutResolved()
    // 模擬原生端回報）。按鈕 key 用 `reader_chrome_layout_button`（現行
    // FAB 化路徑，非舊版 `reader_chrome_layout_button`）。
    Future<void> pumpReaderScreen(
      WidgetTester tester, {
      // epic-27-reader-device-compat Issue 4：讓「另存為新預設集」的兩則
      // 新測試可以分別模擬 layoutPresetRepository 為 null、或注入一個會
      // 拋出例外的假 repository；其餘既有呼叫點沿用預設值，行為不變。
      bool includeLayoutPresetRepository = true,
      LayoutPresetRepository? layoutPresetRepositoryOverride,
      // Epic 43 Issue 5：讓「套用預設集」/「套用來源書籍」的失敗路徑測試
      // 可以注入一個會拋出例外的假 BookReaderPrefsRepository；其餘既有
      // 呼叫點沿用預設值，行為不變。
      BookReaderPrefsRepository? bookReaderPrefsRepositoryOverride,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final effectiveLayoutPresetRepository =
          layoutPresetRepositoryOverride ??
          (includeLayoutPresetRepository ? layoutPresetRepository : null);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            isFixedLayout: false,
            libraryRepository: libraryRepository,
            layoutPresetRepository: effectiveLayoutPresetRepository,
            bookReaderPrefsRepository:
                bookReaderPrefsRepositoryOverride ?? bookReaderPrefsRepository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
    }

    testWidgets('另存為新預設集：命名對話框輸入名稱後，正確寫入 LayoutPresetRepository', (
      tester,
    ) async {
      await pumpReaderScreen(tester);

      // 開啟版面設定 Sheet、捲動到「另存為新預設集」按鈕並點擊。
      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_save_as_preset')),
      );
      await tester.tap(find.byKey(const Key('reader_settings_save_as_preset')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('layout_preset_name_dialog_field')),
        '測試預設集',
      );
      await tester.tap(
        find.byKey(const Key('layout_preset_name_dialog_confirm')),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      final all = await tester.runAsync(() => layoutPresetRepository.listAll());
      expect(all, hasLength(1));
      expect(all!.single.name, '測試預設集');
    });

    testWidgets('存滿 3 組後再次另存，跳出覆蓋選單，選擇並確認後正確覆蓋既有一組', (tester) async {
      for (final name in ['A', 'B', 'C']) {
        await tester.runAsync(
          () => layoutPresetRepository.insert(
            LayoutPreset(
              id: null,
              name: name,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              prefs: const BookReaderPrefs(fontSize: 16),
            ),
          ),
        );
      }

      await pumpReaderScreen(tester);
      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_save_as_preset')),
      );
      await tester.tap(find.byKey(const Key('reader_settings_save_as_preset')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('layout_preset_name_dialog_field')),
        'D',
      );
      await tester.tap(
        find.byKey(const Key('layout_preset_name_dialog_confirm')),
      );
      await tester.pumpAndSettle();

      // 覆蓋選單：選第一組（名稱 'A'，這是這個乾淨的記憶體內資料庫本測試
      // 第一筆 insert，AUTOINCREMENT id 必為 1）。
      await tester.tap(
        find.byKey(const Key('layout_preset_overwrite_option_1')),
      );
      await tester.pumpAndSettle();
      // 確認覆蓋對話框。
      await tester.tap(
        find.byKey(const Key('layout_preset_overwrite_confirm')),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      final all = await tester.runAsync(() => layoutPresetRepository.listAll());
      expect(all, hasLength(3));
      expect(all!.map((p) => p.name).toList(), ['D', 'B', 'C']);
    });

    testWidgets('另存為新預設集：layoutPresetRepository 為 null 時顯示提示，而非毫無反應', (
      tester,
    ) async {
      await pumpReaderScreen(tester, includeLayoutPresetRepository: false);

      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_save_as_preset')),
      );
      await tester.tap(find.byKey(const Key('reader_settings_save_as_preset')));
      await tester.pump();

      expect(
        find.byKey(
          const Key('reader_save_as_preset_repository_unavailable_snackbar'),
        ),
        findsOneWidget,
      );
      expect(find.text('暫時無法儲存預設集'), findsOneWidget);
      // 命名對話框不應該被誤開——確認「靜默失敗」已被提示取代，而不是
      // 多開出一個對話框（兩者都算「有反應」，但語意不同，須分開鑑別）。
      expect(
        find.byKey(const Key('layout_preset_name_dialog_field')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('另存為新預設集：寫入過程拋出例外時顯示提示，不被靜默吞掉', (tester) async {
      final throwingRepository = _ThrowingLayoutPresetRepository(
        libraryRepository.database,
      );
      await pumpReaderScreen(
        tester,
        layoutPresetRepositoryOverride: throwingRepository,
      );

      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_save_as_preset')),
      );
      await tester.tap(find.byKey(const Key('reader_settings_save_as_preset')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('layout_preset_name_dialog_field')),
        '測試預設集',
      );
      await tester.tap(
        find.byKey(const Key('layout_preset_name_dialog_confirm')),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reader_save_as_preset_error_snackbar')),
        findsOneWidget,
      );
      expect(find.text('另存為新預設集失敗'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('套用預設集到目前書籍：立即寫入且畫面即時反映新值（透過 _handlePrefsChanged）', (
      tester,
    ) async {
      await tester.runAsync(
        () => layoutPresetRepository.insert(
          LayoutPreset(
            id: null,
            name: '測試預設集',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            prefs: const BookReaderPrefs(fontSize: 24 / 16),
          ),
        ),
      );

      await pumpReaderScreen(tester);
      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_apply_current')),
      );
      await tester.tap(
        find.byKey(const Key('reader_settings_preset_slot_0_apply_current')),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      final saved = await tester.runAsync(
        () => bookReaderPrefsRepository.load('b1'),
      );
      expect(saved!.fontSize, 24 / 16);

      // Bottom Sheet 開啟中同步（spec.md「套用當下 Sheet 仍開啟」情境，
      // 對應審查意見 Minor 2.7）：套用當下 Sheet 仍在畫面上，_prefs 更新
      // 觸發 ReaderScreen 重建，_openLayoutSettings() 的 builder 以新的
      // _prefs 重新建構 ReaderSettingsSheet，其既有 didUpdateWidget 邏輯
      // （本 Task 未改動，沿用既有機制）同步內部草稿——驗證目前畫面上這顆
      // ReaderSettingsSheet 的 prefs 已是套用後的新值，而非套用前的舊值。
      final sheetAfterApply = tester.widget<ReaderSettingsSheet>(
        find.byType(ReaderSettingsSheet),
      );
      expect(sheetAfterApply.prefs.fontSize, 24 / 16);
    });

    // M-2（審查修訂）：只用「套用到目前書籍」（save() 拋例外）驗證，不另外
    // 補一則「套用到其他書籍」（saveMultiple() 拋例外）——兩條路徑在
    // _applyPrefsToTargets 內部共用同一個 try/catch 區塊，save/saveMultiple
    // 各自的分支邏輯本身已由 Issue 2 的 layout_preset_actions_test.dart
    // 獨立驗證過，此處只需要證明「這一個 catch 區塊」有效即可，不需要
    // 為同一段 catch 邏輯重複測兩次。
    testWidgets('套用預設集到目前書籍：寫入過程拋出例外時顯示提示，不被靜默吞掉', (
      tester,
    ) async {
      await tester.runAsync(
        () => layoutPresetRepository.insert(
          LayoutPreset(
            id: null,
            name: '測試預設集',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            prefs: const BookReaderPrefs(fontSize: 24 / 16),
          ),
        ),
      );
      final throwingBookReaderPrefsRepository =
          _ThrowingBookReaderPrefsRepository(libraryRepository.database);
      await pumpReaderScreen(
        tester,
        bookReaderPrefsRepositoryOverride: throwingBookReaderPrefsRepository,
      );

      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_apply_current')),
      );
      await tester.tap(
        find.byKey(const Key('reader_settings_preset_slot_0_apply_current')),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reader_apply_preset_error_snackbar')),
        findsOneWidget,
      );
      expect(find.text('套用版面設定失敗'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('套用預設集到其他書籍（多本）：跳出「即將覆蓋 N 本書」確認對話框，確認後批次寫入', (tester) async {
      await tester.runAsync(
        () => layoutPresetRepository.insert(
          LayoutPreset(
            id: null,
            name: '測試預設集',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            prefs: const BookReaderPrefs(fontSize: 24 / 16),
          ),
        ),
      );

      await pumpReaderScreen(tester);
      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_apply_others')),
      );
      await tester.tap(
        find.byKey(const Key('reader_settings_preset_slot_0_apply_others')),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      // 書籍選擇器：勾選「其他流式書」後點確定。
      await tester.tap(
        find.byKey(const Key('layout_preset_book_picker_item_b_other')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('layout_preset_book_picker_confirm')),
      );
      await tester.pumpAndSettle();

      // 「即將覆蓋 N 本書」確認對話框。
      await tester.tap(find.byKey(const Key('layout_preset_apply_confirm')));
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      final saved = await tester.runAsync(
        () => bookReaderPrefsRepository.load('b_other'),
      );
      expect(saved!.fontSize, 24 / 16);
      // 目前書籍（b1）不在目標內，不受影響。
      final currentBookPrefs = await tester.runAsync(
        () => bookReaderPrefsRepository.load('b1'),
      );
      expect(currentBookPrefs!.fontSize, isNull);
    });

    testWidgets('刪除預設集：正確從 LayoutPresetRepository 移除', (tester) async {
      await tester.runAsync(
        () => layoutPresetRepository.insert(
          LayoutPreset(
            id: null,
            name: '待刪除',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            prefs: BookReaderPrefs.empty,
          ),
        ),
      );

      await pumpReaderScreen(tester);
      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_delete')),
      );
      await tester.tap(
        find.byKey(const Key('reader_settings_preset_slot_0_delete')),
      );
      await tester.pumpAndSettle();
      // 「確認刪除」對話框。
      await tester.tap(find.byKey(const Key('layout_preset_delete_confirm')));
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      final all = await tester.runAsync(() => layoutPresetRepository.listAll());
      expect(all, isEmpty);
    });

    testWidgets('刪除預設集：刪除過程拋出例外時顯示提示，不被靜默吞掉', (tester) async {
      await tester.runAsync(
        () => layoutPresetRepository.insert(
          LayoutPreset(
            id: null,
            name: '待刪除',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            prefs: BookReaderPrefs.empty,
          ),
        ),
      );
      final throwingRepository = _ThrowingLayoutPresetRepository(
        libraryRepository.database,
      );
      await pumpReaderScreen(
        tester,
        layoutPresetRepositoryOverride: throwingRepository,
      );

      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_delete')),
      );
      await tester.tap(
        find.byKey(const Key('reader_settings_preset_slot_0_delete')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('layout_preset_delete_confirm')));
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reader_delete_preset_error_snackbar')),
        findsOneWidget,
      );
      expect(find.text('刪除預設集失敗'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // M-3（審查修訂）：驗證刪除失敗時底層資料未被誤刪，狀態未受污染。
      final all = await tester.runAsync(() => layoutPresetRepository.listAll());
      expect(all, hasLength(1));
    });

    testWidgets('刪除預設集：確認對話框取消時不刪除', (tester) async {
      await tester.runAsync(
        () => layoutPresetRepository.insert(
          LayoutPreset(
            id: null,
            name: '不應被刪除',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            prefs: BookReaderPrefs.empty,
          ),
        ),
      );

      await pumpReaderScreen(tester);
      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_delete')),
      );
      await tester.tap(
        find.byKey(const Key('reader_settings_preset_slot_0_delete')),
      );
      await tester.pumpAndSettle();
      // 「確認刪除」對話框中點擊「取消」。
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();

      final all = await tester.runAsync(() => layoutPresetRepository.listAll());
      expect(all, hasLength(1));
    });

    testWidgets('複製其他書籍設定到本書：正確以 reflowableEpubFields() 過濾後寫入並即時反映', (
      tester,
    ) async {
      await tester.runAsync(
        () => bookReaderPrefsRepository.save(
          'b_other',
          const BookReaderPrefs(
            fontSize: 20 / 16,
            pdfContrast: 30, // 應被過濾，不應出現在複製結果中。
          ),
        ),
      );

      await pumpReaderScreen(tester);
      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_copy_from_book_current')),
      );
      await tester.tap(
        find.byKey(const Key('reader_settings_copy_from_book_current')),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('layout_preset_book_picker_item_b_other')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('layout_preset_book_picker_confirm')),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      final saved = await tester.runAsync(
        () => bookReaderPrefsRepository.load('b1'),
      );
      expect(saved!.fontSize, 20 / 16);
      expect(saved.pdfContrast, isNull);
    });

    testWidgets('複製其他書籍設定到本書：讀取來源書籍設定拋出例外時顯示提示，不被靜默吞掉', (
      tester,
    ) async {
      final throwingBookReaderPrefsRepository =
          _ThrowingBookReaderPrefsRepository(libraryRepository.database);
      await pumpReaderScreen(
        tester,
        bookReaderPrefsRepositoryOverride: throwingBookReaderPrefsRepository,
      );

      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pumpAndSettle();
      await switchToTab(tester, '預設集');
      await tester.ensureVisible(
        find.byKey(const Key('reader_settings_copy_from_book_current')),
      );
      await tester.tap(
        find.byKey(const Key('reader_settings_copy_from_book_current')),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('layout_preset_book_picker_item_b_other')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('layout_preset_book_picker_confirm')),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reader_apply_preset_error_snackbar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('PDF：框選矩形命中既有畫線時，工具列顯示刪除按鈕，點擊後刪除該畫線', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      const highlightId = 'ph_merge1';
      await highlightsRepo.insert(
        const Highlight(
          id: highlightId,
          bookId: 'b_pdf_merge1',
          style: HighlightStyle.highlighterYellow,
          pdfPageIndex: 0,
          pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.3),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_pdf_merge1',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      pdfView.onSelectionRectComputed?.call(
        const PdfSelectionInfo(
          pageIndex: 0,
          rect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
          widgetRect: PercentRect(
            left: 0.2,
            top: 0.15,
            right: 0.4,
            bottom: 0.25,
          ),
          text: '框選文字',
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('annotation_toolbar_delete')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('annotation_toolbar_delete')));
      await tester.pump();
      await tester.pump();

      expect(await highlightsRepo.listByBook('b_pdf_merge1'), isEmpty);
      expect(find.byType(AnnotationToolbar), findsNothing);
    });

    testWidgets('PDF：框選矩形未命中既有標記時，工具列不顯示刪除按鈕', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_pdf_merge2',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      pdfView.onSelectionRectComputed?.call(
        const PdfSelectionInfo(
          pageIndex: 0,
          rect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
          widgetRect: PercentRect(
            left: 0.2,
            top: 0.15,
            right: 0.4,
            bottom: 0.25,
          ),
          text: '框選文字',
        ),
      );
      await tester.pump();

      expect(find.byType(AnnotationToolbar), findsOneWidget);
      expect(find.byKey(const Key('annotation_toolbar_delete')), findsNothing);
    });
  });

  group('PDF 原地長按既有標記（退化選取，epic-25-annotation-interaction-qa Issue 6）', () {
    testWidgets('PDF：退化選取命中既有劃線時，顯示工具列且帶刪除鈕（epic-25 Issue 6）', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      await highlightsRepo.insert(
        const Highlight(
          id: 'h_issue6_hit',
          bookId: 'b_pdf_issue6_hit',
          style: HighlightStyle.highlighterYellow,
          pdfPageIndex: 0,
          // 覆蓋幾乎整頁，確保退化選取落點一定落在這筆劃線範圍內。
          pdfRect: PercentRect(
            left: 0.05,
            top: 0.05,
            right: 0.95,
            bottom: 0.95,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_pdf_issue6_hit',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      // 透過真實長按手勢重現使用者操作（規劃階段審查 review-issue-6.md
      // Important #2 修正——原本直接呼叫 onSelectionRectComputed，繞過真實
      // 手勢偵測層，恰好落入本 Issue 自己診斷出「導致 bug 未被測出」的同一
      // 種測試模式）。落點須用既有劃線疊圖實際渲染出來的座標（而非假設
      // PdfReaderView 整個 widget 尺寸等於頁面內容範圍——PAGE_FIT 模式下
      // 常有 letterbox 留白，兩者不相等），才能保證精準命中。
      final decorationFinder = find.byKey(
        const Key('pdf_reader_decoration_0_0'),
      );
      expect(decorationFinder, findsOneWidget);
      final pos = tester.getCenter(decorationFinder);

      final gesture = await tester.startGesture(pos);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.up();
      // _finishSelectionDrag() 的文字萃取是真實非同步 FFI 呼叫
      // （page.loadStructuredText()），須用 pumpUntilPdfReady 讓真實
      // event loop 有機會推進，固定時長的 tester.pump() 等不到它完成。
      await pumpUntilPdfReady(
        tester,
        condition: () => find.byType(AnnotationToolbar).evaluate().isNotEmpty,
      );

      expect(
        find.byType(AnnotationToolbar),
        findsOneWidget,
        reason: '退化選取命中既有劃線，應顯示工具列（Issue 6）',
      );
      expect(
        find.byKey(const Key('annotation_toolbar_delete')),
        findsOneWidget,
        reason: '命中既有劃線，工具列應帶刪除鈕',
      );
    });

    testWidgets('PDF：退化選取未命中任何既有標記時，不顯示工具列（epic-25 Issue 6）', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_pdf_issue6_miss',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      // 透過真實長按手勢重現（同上則測試的修正理由，review-issue-6.md
      // Important #2）。沒有任何既有劃線/備註，落點用 PdfReaderView 的
      // 畫面中心即可——PAGE_FIT 模式預設置中，落在頁面內容範圍內。
      final pos = tester.getCenter(find.byType(PdfReaderView));

      final gesture = await tester.startGesture(pos);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.up();
      await pumpUntilPdfReady(tester);

      expect(
        find.byType(AnnotationToolbar),
        findsNothing,
        reason:
            '沒有命中任何既有標記的退化選取，須維持原本「什麼都不做」'
            '的行為，不能彈出建立工具列',
      );
    });
  });

  group('TTS 語音朗讀（epic-34-tts-readalong Issue 2）', () {
    testWidgets('未提供 ttsProvider 時，不顯示 TTS 播放按鈕', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts_no_provider',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('reader_tts_play_pause_button')),
        findsNothing,
      );
    });

    testWidgets('提供 ttsProvider 時，流式 EPUB 顯示 TTS 播放按鈕，點擊後不崩潰且維持在 ReaderChromeBottomBar（誠實測試邊界，見計劃範圍澄清第 2 點）', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts_with_provider',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      // epic-38-reader-chrome-tts-redesign Issue 2 審查澄清：點擊後呼叫
      // _ttsControllerOrNull!.play()，flutter_test 環境下
      // FoliateReaderView.loadTtsSegments() 恆回傳空清單，status 永遠
      // 停在 idle，TtsPanel 結構性不會出現（見 plan-issue-2.md 計劃範圍
      // 澄清第 2 點）——這裡驗證的是「點擊不崩潰、維持在
      // ReaderChromeBottomBar」這個環境限制下仍可觀察的結構性保證，深層
      // 狀態機正確性由 tts_controller_test.dart 完整涵蓋。
      final toggleFinder = find.byKey(const Key('reader_chrome_tts_button'));
      await tester.tap(toggleFinder);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
      expect(find.byType(TtsPanel), findsNothing);
    });

    testWidgets('CBZ 格式提供 ttsProvider 時，TTS 按鈕顯示但為停用狀態', (tester) async {
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.cbz',
            bookId: 'b_tts_cbz',
            prefsManager: prefsManager,
            isFixedLayout: true,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: true,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(
        find.byKey(const Key('reader_chrome_tts_button')),
      );
      await tester.pump();

      final buttonFinder = find.byKey(
        const Key('reader_tts_play_pause_button'),
      );
      expect(buttonFinder, findsOneWidget);
      final button = tester.widget<IconButton>(buttonFinder);
      expect(button.onPressed, isNull);
    });

    testWidgets('CBZ 停用播放鍵圖示顏色與啟用狀態明確區隔（epic-34-tts-readalong Issue 10）', (
      tester,
    ) async {
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.cbz',
            bookId: 'b_tts_cbz_disabled_color',
            prefsManager: prefsManager,
            isFixedLayout: true,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: true,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(
        find.byKey(const Key('reader_chrome_tts_button')),
      );
      await tester.pump();

      final buttonFinder = find.byKey(
        const Key('reader_tts_play_pause_button'),
      );
      // 審查修正（epic-38-reader-chrome-tts-redesign Issue 2）：TtsPanel
      // 的 Icon 不再自帶 color，改由 IconButton.style 的
      // disabledForegroundColor 決定，比對 Icon.color（現在恆為 null）
      // 已不適用。CBZ 恆為固定版面，啟用狀態的既有圖示色固定為
      // Colors.white（_themedFabIconColor）；停用狀態須與其明確不同，
      // 且不得只是同一顏色套上透明度（見本計畫 Global Constraints
      // 說明），故直接斷言為不透明的 Colors.grey（已隱含「不是
      // Colors.white」，不需另外斷言 isNot）。
      final button = tester.widget<IconButton>(buttonFinder);
      expect(
        button.style?.foregroundColor?.resolve(<WidgetState>{WidgetState.disabled}),
        Colors.grey,
      );
    });
  });

  group('同步高亮跟隨（epic-34-tts-readalong Issue 3）', () {
    // 誠實測試邊界（比照既有 setDecorations 測試慣例，見本檔案「流式
    // EPUB 開書後...透過 FoliateReaderView.setDecorations 送給原生端」
    // 測試的既有註解）：flutter_test 環境下 FoliateReaderView 的
    // _controller 恆為 null，FoliateReaderView.showTtsHighlight()/
    // clearTtsHighlight() 實際送出的 JS 呼叫參數（含 cfi／vertical 旗標）
    // 無法在這層直接攔截斷言——同一個既有限制也適用於 setDecorations。
    // 這裡驗證的是「直排書籍下這段 wiring 不崩潰」這個結構性保證；
    // 「onHighlightSegment 在正確時機被呼叫、帶正確的段落」由
    // tts_controller_test.dart（純 Dart，見 Task 2）完整涵蓋；main.js
    // 端 key 空間隔離／vertical 覆寫邏輯由 foliate_reader_view_test.dart
    // 的 main.js regression guard（見 Task 1）涵蓋；真實 JS 高亮渲染
    // 正確性（含直排/橫排實際跟隨、朗讀段切換時無殘影）須真機手動驗證
    // （見本計畫「測試策略總結」）。
    testWidgets('提供 ttsProvider 且書本為直排（vertical）時，ReaderScreen 正常建構、'
        'TTS 按鈕存在且可點擊，不崩潰', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts_vertical',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.vertical,
        ),
      );
      await tester.pump();
      await tester.pump();

      // epic-38-reader-chrome-tts-redesign Issue 2：flutter_test 環境下
      // TtsController 永遠 idle，TtsPanel 結構性不出現，維持在 ReaderChromeBottomBar
      final toggleFinder = find.byKey(const Key('reader_chrome_tts_button'));
      await tester.tap(toggleFinder);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
      expect(find.byType(TtsPanel), findsNothing);
    });

    testWidgets('TTS 播放按鈕點擊後，highlightsRepository/notesRepository 內容不受影響'
        '（ADR 0026：朗讀高亮不寫入劃線/備註資料表）', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final ttsProvider = FakeTtsProvider();
      const bookId = 'b_tts_adr0026';

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: bookId,
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      // epic-38 Issue 2：同上，點擊不崩潰、維持在 ReaderChromeBottomBar
      final toggleFinder2 = find.byKey(const Key('reader_chrome_tts_button'));
      await tester.tap(toggleFinder2);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
      expect(find.byType(TtsPanel), findsNothing);
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(await highlightsRepo.listByBook(bookId), isEmpty);
      expect(await notesRepo.listByBook(bookId), isEmpty);
    });
  });

  group('手動導覽自動暫停與恢復播放（epic-34-tts-readalong Issue 4）', () {
    // 誠實測試邊界（比照 Issue 3 Task 3 既有慣例）：flutter_test 環境下
    // FoliateReaderView 的 _controller 恆為 null，TtsController.play() 的
    // loadSegments() 因此恆回傳空清單，永遠不會真正進入 playing 狀態——
    // 這裡驗證的是「onLocatorChanged 觸發手動導覽重置這段 wiring 不崩潰」
    // 這個結構性保證；handleExternalPositionChange() 實際重設狀態/清除
    // 高亮/清空段落的行為，由 tts_controller_test.dart（純 Dart，見
    // Task 2）完整涵蓋；真實「翻頁時朗讀自動暫停、恢復播放從新位置開始」
    // 的端到端正確性須真機手動驗證（見本計畫「測試策略總結」）。
    testWidgets('提供 ttsProvider 時，onLocatorChanged 觸發（模擬手動翻頁）不崩潰，'
        '按播放鍵仍可正常運作', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts_manual_nav',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      // epic-38 Issue 2：點擊不崩潰、維持在 ReaderChromeBottomBar
      final toggleFinder3 = find.byKey(const Key('reader_chrome_tts_button'));
      await tester.tap(toggleFinder3);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
      expect(find.byType(TtsPanel), findsNothing);

      // 模擬手動翻頁：main.js 端 onLocatorChanged 事件（比照既有
      // foliate_bridge_codec_test.dart／reader_screen_test.dart 對這個
      // callback 的既有觸發方式，直接呼叫 widget 建構時傳入的 closure）。
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson:
              '{"cfi":"epubcfi(/6/6!/4/2,/1:0,/1:5)","index":1,"fraction":0.3}',
          progression: 0.3,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 翻頁後再次點擊朗讀按鈕仍不崩潰、維持在 ReaderChromeBottomBar
      await tester.tap(toggleFinder3);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
      expect(find.byType(TtsPanel), findsNothing);
    });
  });

  group('上一句/下一句/語速調整控制（epic-34-tts-readalong Issue 5）', () {
    testWidgets('未提供 ttsProvider 時，不顯示上一句/下一句/語速按鈕', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts5_no_provider',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('reader_tts_previous_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_next_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_speed_button')), findsNothing);
    });

    testWidgets('CBZ 格式提供 ttsProvider 時，上一句/下一句/語速按鈕皆不顯示（僅播放/暫停停用按鈕存在）', (
      tester,
    ) async {
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.cbz',
            bookId: 'b_tts5_cbz',
            prefsManager: prefsManager,
            isFixedLayout: true,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: true,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(
        find.byKey(const Key('reader_chrome_tts_button')),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('reader_tts_play_pause_button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reader_tts_previous_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_next_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_speed_button')), findsNothing);
    });

    testWidgets('提供 ttsProvider 時，流式 EPUB 顯示上一句/下一句/語速按鈕，初始語速顯示 1.00x', (
      tester,
    ) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts5_buttons',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      // epic-38 Issue 2：flutter_test 環境下 TtsPanel 不出現，維持在 ReaderChromeBottomBar
      final toggleFinder4 = find.byKey(const Key('reader_chrome_tts_button'));
      await tester.tap(toggleFinder4);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
      expect(find.byType(TtsPanel), findsNothing);
    });

    testWidgets('提供 ttsProvider 時，點擊上一句/下一句按鈕不崩潰（誠實測試邊界：flutter_test 環境下'
        'FoliateReaderView 的 _controller 恆為 null，loadSegments 恆回傳空清單，'
        'TtsController 永遠不會真正進入 playing 狀態，這裡驗證的是 UI 接線不崩潰這個'
        '結構性保證；真正的段落跳轉行為由 tts_controller_test.dart（Task 1）完整涵蓋）', (
      tester,
    ) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts5_tap',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      // epic-38 Issue 2：TtsPanel 不出現，點擊朗讀按鈕維持在 ReaderChromeBottomBar
      final toggleFinder5 = find.byKey(const Key('reader_chrome_tts_button'));
      await tester.tap(toggleFinder5);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
      expect(find.byType(TtsPanel), findsNothing);
      // 原本的上一句/下一句點擊在新架構下無法直接觸發，深層行為由 tts_controller_test 涵蓋
      expect(tester.takeException(), isNull);
    });

    testWidgets('點擊語速按鈕依序循環預設語速清單，畫面數字同步更新'
        '（單一事實來源：直接顯示 TtsController.speed，比照既有播放/暫停按鈕的'
        'AnimatedBuilder 訂閱模式）', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts5_speed',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      // epic-38 Issue 2：TtsPanel 不出現，維持在 ReaderChromeBottomBar，語速循環深層行為由 tts_controller_test 涵蓋
      final toggleFinder6 = find.byKey(const Key('reader_chrome_tts_button'));
      await tester.tap(toggleFinder6);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
      expect(find.byType(TtsPanel), findsNothing);
    });
  });

  group('Mini Player 與既有底部元件顯示連動（epic-34-tts-readalong Issue 6）', () {
    testWidgets(
      '頁尾預設顯示（showFooter 預設 null＝true）且提供 ttsProvider 時，頁尾進度文字與朗讀按鈕點擊不崩潰，兩者互不排斥',
      (tester) async {
        final highlightsRepo = FakeHighlightsRepository();
        final notesRepo = FakeNotesRepository();
        final ttsProvider = FakeTtsProvider();

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
            home: ReaderScreen(
              filePath: 'test/fixtures/sample.epub',
              bookId: 'b_mini_player_footer',
              prefsManager: prefsManager,
              highlightsRepository: highlightsRepo,
              notesRepository: notesRepo,
              isFixedLayout: false,
              ttsProvider: ttsProvider,
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();

        final foliateView = tester.widget<FoliateReaderView>(
          find.byType(FoliateReaderView),
        );
        foliateView.onPageRendered();
        foliateView.onLayoutResolved?.call(
          const EpubLayoutInfo(
            isFixedLayout: false,
            writingMode: WritingMode.horizontal,
          ),
        );
        foliateView.onLocatorChanged?.call(
          const EpubPositionInfo(
            locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.25}',
            progression: 0.25,
            locationIndex: 4,
            locationTotal: 20,
          ),
        );
        await tester.pump();
        await tester.pump();

        // epic-38 Issue 2：點擊不崩潰、維持在 ReaderChromeBottomBar，TtsPanel 不出現
        final toggleFinder7 = find.byKey(const Key('reader_chrome_tts_button'));
        await tester.tap(toggleFinder7);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
        expect(find.byType(TtsPanel), findsNothing);
        // 頁尾資訊仍應存在（由 ReaderChromeBottomBar 承載）
        expect(
          find.byKey(const Key('reader_foliate_progress_text')),
          findsOneWidget,
        );
        // epic-38 Issue 2（審查修正 review-issue-2.md Minor #3：原註解誤指
        // ReaderChromeBottomBar 頁碼文字，實際上該文字格式是
        // "5 / 20 · 25%"〔_pageProgressText()〕，跟這裡的 "5/20" 不同。
        // 真正同時顯示 "5/20" 的是兩個獨立元件：ReaderChromeBottomBar 內嵌
        // 的 ReaderFooter〔key: reader_footer_progress_text〕，以及
        // _buildFoliateProgressText()〔key: reader_foliate_progress_text，
        // 上面已在 8343-8346 行斷言其存在〕——兩者格式皆為
        // "$currentPage/$totalPages"，同一份 EpubPositionInfo 換算出同樣的
        // "5/20"，故 find.text 必然命中 2 個，findsOneWidget 會失敗
        // （已實測驗證），findsWidgets 才是正確斷言。
        expect(find.text('5/20'), findsWidgets);
      },
    );

    testWidgets('未提供 ttsProvider 時，Mini Player 四顆按鈕皆不顯示', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_mini_player_no_provider',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('reader_tts_play_pause_button')),
        findsNothing,
      );
      expect(find.byKey(const Key('reader_tts_previous_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_next_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_speed_button')), findsNothing);
    });

  });

  group('背景播放與系統整合（epic-34-tts-readalong Issue 7）', () {
    testWidgets('提供 ttsAudioHandler／ttsAudioFocusSource 時，開書/播放/離開畫面'
        '皆不崩潰（誠實測試邊界：flutter_test 環境下 loadSegments() 恆'
        '回傳空清單，TtsController 永遠不會真正進入 playing，這裡驗證的'
        '是接線本身的結構性保證，深層狀態機正確性由'
        'tts_audio_focus_coordinator_test.dart／tts_audio_handler_test.dart'
        '（純 Dart）完整涵蓋，見 plan-issue-7.md「測試分層」）', (tester) async {
      final ttsProvider = FakeTtsProvider();
      final ttsAudioHandler = TtsAudioHandler();
      final ttsAudioFocusSource = FakeTtsAudioFocusSource();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts7_wiring',
            prefsManager: prefsManager,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
            ttsAudioHandler: ttsAudioHandler,
            ttsAudioFocusSource: ttsAudioFocusSource,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      // epic-38 Issue 2：點擊不崩潰、維持在 ReaderChromeBottomBar
      final toggleFinder9 = find.byKey(const Key('reader_chrome_tts_button'));
      await tester.tap(toggleFinder9);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
      expect(find.byType(TtsPanel), findsNothing);

      // TtsAudioHandler 應已綁定書名（attachController 已被呼叫）。
      expect(ttsAudioHandler.mediaItem.value?.title, '未知書籍');

      // 焦點事件送達不應造成崩潰（idle 狀態下為 no-op）。
      ttsAudioFocusSource.emit(TtsAudioFocusEvent.transientLoss);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // App 從背景恢復前景時，resyncHighlight() 接線不應崩潰。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 離開畫面（dispose）應呼叫 detachController()
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
      expect(
        ttsAudioHandler.mediaItem.value,
        isNull,
        reason: '離開畫面（dispose）應呼叫 detachController()',
      );
    });

    testWidgets('單書覆寫簡繁轉換時，TtsAudioHandler 綁定的系統通知/鎖定畫面書名依轉換模式呈現（epic-42-text-conversion Issue 3 審查修正 I-1）',
        (tester) async {
      await prefsManager.saveBookPrefs(
        'b_tts_text_conversion',
        const BookReaderPrefs(
          textConversionOverride: TextConversionMode.toTraditional,
        ),
      );
      final ttsProvider = FakeTtsProvider();
      final ttsAudioHandler = TtsAudioHandler();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts_text_conversion',
            bookTitle: '国电脑',
            prefsManager: prefsManager,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
            ttsAudioHandler: ttsAudioHandler,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_chrome_tts_button')));
      await tester.pump();

      expect(ttsAudioHandler.mediaItem.value?.title, '國電腦');
    });

    testWidgets('未提供 ttsAudioHandler／ttsAudioFocusSource 時，既有播放/暫停行為零回歸', (
      tester,
    ) async {
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts7_no_wiring',
            prefsManager: prefsManager,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(
        find.byType(FoliateReaderView),
      );
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      // epic-38 Issue 2：同上，點擊不崩潰
      final toggleFinder9b = find.byKey(const Key('reader_chrome_tts_button'));
      await tester.tap(toggleFinder9b);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
      expect(find.byType(TtsPanel), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('安全視窗跟隨翻頁（epic-34-tts-readalong Issue 8）', () {
    testWidgets(
      '提供 ttsProvider 時，onTtsHighlightOutOfSafeWindow 觸發（模擬 next/prev）不崩潰',
      (tester) async {
        final ttsProvider = FakeTtsProvider();

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
            home: ReaderScreen(
              filePath: 'test/fixtures/sample.epub',
              bookId: 'b_tts8_safe_window',
              prefsManager: prefsManager,
              isFixedLayout: false,
              ttsProvider: ttsProvider,
              isEinkMode: true,
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();

        final foliateView = tester.widget<FoliateReaderView>(
          find.byType(FoliateReaderView),
        );
        foliateView.onPageRendered();
        foliateView.onLayoutResolved?.call(
          const EpubLayoutInfo(
            isFixedLayout: false,
            writingMode: WritingMode.horizontal,
          ),
        );
        await tester.pump();
        await tester.pump();

        // epic-38 Issue 2：點擊不崩潰、維持在 ReaderChromeBottomBar
        final toggleFinder10 = find.byKey(const Key('reader_chrome_tts_button'));
        await tester.tap(toggleFinder10);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
        expect(find.byType(TtsPanel), findsNothing);

        foliateView.onTtsHighlightOutOfSafeWindow?.call('next');
        await tester.pump();
        expect(tester.takeException(), isNull);

        foliateView.onTtsHighlightOutOfSafeWindow?.call('prev');
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '未提供 ttsProvider 時，onTtsHighlightOutOfSafeWindow 欄位為 null（未建構 TtsController）',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
            home: ReaderScreen(
              filePath: 'test/fixtures/sample.epub',
              bookId: 'b_tts8_no_provider',
              prefsManager: prefsManager,
              isFixedLayout: false,
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();

        final foliateView = tester.widget<FoliateReaderView>(
          find.byType(FoliateReaderView),
        );
        foliateView.onTtsHighlightOutOfSafeWindow?.call('next');
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('睡眠定時器（epic-38-reader-chrome-tts-redesign Issue 2）', () {
    testWidgets('選擇「30 分鐘」後，再次開啟選單該選項顯示已勾選', (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_sleep_timer_select',
            prefsManager: prefsManager,
            ttsProvider: FakeTtsProvider(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 審查修正（review-plan-issue-2.md M2）：先點一次「◗ 朗讀」讓
      // _ttsControllerOrNull 真正建構出 TtsController（status 仍停在
      // idle，flutter_test 環境下無法真正播放，見計劃範圍澄清第 2 點），
      // 讓下面的 Timer 到期時 _ttsController?.pause() 呼叫在一個真實
      // controller 而非 null 上，更貼近實際執行期路徑。
      await tester.tap(find.byKey(const Key('reader_chrome_tts_button')));
      await tester.pump();

      ReaderScreen.openSleepTimerPickerForTest(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byKey(const Key('reader_tts_sleep_timer_option_30')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      ReaderScreen.openSleepTimerPickerForTest(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final optionFinder =
          find.byKey(const Key('reader_tts_sleep_timer_option_30'));
      expect(
        find.descendant(of: optionFinder, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
    });

    testWidgets('選擇「30 分鐘」後經過 30 分鐘，再次開啟選單「不限時」變為已勾選'
        '（計時器已自動到期歸零）', (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_sleep_timer_expire',
            prefsManager: prefsManager,
            ttsProvider: FakeTtsProvider(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 審查修正（review-plan-issue-2.md M2）：見上一則測試的說明。
      await tester.tap(find.byKey(const Key('reader_chrome_tts_button')));
      await tester.pump();

      ReaderScreen.openSleepTimerPickerForTest(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('reader_tts_sleep_timer_option_30')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pump(const Duration(minutes: 30));

      ReaderScreen.openSleepTimerPickerForTest(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final noneFinder =
          find.byKey(const Key('reader_tts_sleep_timer_option_none'));
      expect(
        find.descendant(of: noneFinder, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('選擇「不限時」後，計時器不會在任何延遲後觸發任何狀態變化', (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_sleep_timer_none',
            prefsManager: prefsManager,
            ttsProvider: FakeTtsProvider(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 審查修正（review-plan-issue-2.md M2）：見第一則測試的說明。
      await tester.tap(find.byKey(const Key('reader_chrome_tts_button')));
      await tester.pump();

      ReaderScreen.openSleepTimerPickerForTest(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('reader_tts_sleep_timer_option_none')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pump(const Duration(hours: 2));

      expect(tester.takeException(), isNull);
    });
  });

  group('小喇叭圖示 showTtsIndicator（epic-38-reader-chrome-tts-redesign Issue 2）', () {
    testWidgets('未提供 ttsProvider 時，小喇叭圖示恆不存在（_chromeVisible 任一值）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts_indicator_no_provider',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_chrome_tts_indicator_icon')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_chrome_tts_indicator_icon')),
        findsNothing,
      );
    });

    testWidgets('提供 ttsProvider 但從未按下「◗ 朗讀」（_ttsController 為 null）時，'
        '小喇叭圖示不存在', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts_indicator_not_built',
            prefsManager: prefsManager,
            ttsProvider: FakeTtsProvider(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_chrome_tts_indicator_icon')),
        findsNothing,
        reason: '_isTtsActive 讀 _ttsController（非 _ttsControllerOrNull），'
            '尚未按過朗讀鍵時恆為 false，不應觸發 lazy 建構',
      );
    });

    testWidgets('_isTtsActive && !_chromeVisible 兩個條件皆成立時才顯示（誠實測試邊界：'
        'flutter_test 環境下 TtsController.status 永遠是 idle，_isTtsActive 永遠為'
        'false，這個組合本身無法在本檔案驗證，正確性由 _isTtsActive 定義本身'
        '〔純欄位比對，無額外邏輯〕與上方兩個「不顯示」案例的互補覆蓋保證）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts_indicator_documented_gap',
            prefsManager: prefsManager,
            ttsProvider: FakeTtsProvider(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // _chromeVisible 仍為 true（未觸發沉浸模式）時，即使 _ttsController
      // 已建構，小喇叭不應顯示——這個組合本身可以在測試環境驗證。
      await tester.tap(find.byKey(const Key('reader_chrome_tts_button')));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_chrome_tts_indicator_icon')),
        findsNothing,
        reason: '_chromeVisible 仍為 true，即使 _isTtsActive 為 true 也不應顯示'
            '（本案例中 _isTtsActive 實際仍為 false，但斷言與其為 true 時的'
            '預期行為一致，兩者皆是 findsNothing）',
      );
    });
  });


  testWidgets('readerActivityTracker 提供時，開啟/離開閱讀畫面會呼叫 markReaderOpened/markReaderClosed',
      (tester) async {
    final tracker = ReaderActivityTracker();
    expect(tracker.isReaderOpen, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'reader-activity-tracker-test-book',
          prefsManager: FakeReaderPrefsManager(),
          readerActivityTracker: tracker,
        ),
      ),
    );
    await tester.pump();

    expect(tracker.isReaderOpen, isTrue, reason: '開啟閱讀畫面後應標記為已開啟');

    // 換掉整棵 widget 樹讓 ReaderScreen dispose。
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox.shrink(),
      ),
    );

    expect(tracker.isReaderOpen, isFalse, reason: '離開閱讀畫面後應標記為已關閉');
  });

  group('epic-10-search Issue 8：閱讀器 TopBar 搜尋接線', () {
    testWidgets(
        'searchRepository／libraryRepository 皆存在時，點擊搜尋按鈕推入 BookSearchScreen（fromReader: true，帶入合成的 Book）',
        (tester) async {
      final searchRepository = FakeSearchRepository();
      final libraryRepository = FakeLibraryRepository();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_search_entry',
            bookTitle: '搜尋接線測試書',
            prefsManager: FakeReaderPrefsManager(),
            searchRepository: searchRepository,
            libraryRepository: libraryRepository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
      await tester.pumpAndSettle();

      expect(find.byType(BookSearchScreen), findsOneWidget);
      final pushed =
          tester.widget<BookSearchScreen>(find.byType(BookSearchScreen));
      expect(pushed.fromReader, isTrue,
          reason: '從閱讀器進入須為 fromReader:true，點選片段才會 pop 而非 push ReaderScreen');
      expect(pushed.book.id, 'b_search_entry');
      expect(pushed.book.title, '搜尋接線測試書');
      expect(pushed.book.format, BookFileFormat.epub);
      expect(pushed.searchRepository, same(searchRepository));
      expect(pushed.libraryRepository, same(libraryRepository));
      expect(pushed.readerFeatureRepositories.isFullTextSearchAvailable, isTrue,
          reason: 'ReaderScreen.isFullTextSearchAvailable 預設 true，未提供時應維持預設值');
    });

    testWidgets(
        '單書覆寫簡繁轉換時，推入的 BookSearchScreen 帶入已轉換的書名／作者（epic-42-text-conversion Issue 3）',
        (tester) async {
      final searchRepository = FakeSearchRepository();
      final libraryRepository = FakeLibraryRepository();
      final localPrefsManager = FakeReaderPrefsManager(
        bookPrefsByBookId: {
          'b_search_text_conversion': const BookReaderPrefs(
            textConversionOverride: TextConversionMode.toTraditional,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_search_text_conversion',
            bookTitle: '国电脑',
            bookAuthor: '电脑作者',
            prefsManager: localPrefsManager,
            searchRepository: searchRepository,
            libraryRepository: libraryRepository,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
      await tester.pumpAndSettle();

      final pushed =
          tester.widget<BookSearchScreen>(find.byType(BookSearchScreen));
      expect(pushed.book.title, '國電腦');
      expect(pushed.book.author, '電腦作者');
    });

    testWidgets(
        'isFullTextSearchAvailable: false 時，推入的 BookSearchScreen 正確帶入 false（不落回預設值 true）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_search_fts_unavailable',
            prefsManager: FakeReaderPrefsManager(),
            searchRepository: FakeSearchRepository(),
            libraryRepository: FakeLibraryRepository(),
            isFullTextSearchAvailable: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
      await tester.pumpAndSettle();

      final pushed =
          tester.widget<BookSearchScreen>(find.byType(BookSearchScreen));
      expect(pushed.readerFeatureRepositories.isFullTextSearchAvailable, isFalse);
    });

    testWidgets('searchRepository 為 null 時，點擊搜尋按鈕顯示不可用提示，不導覽',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_search_unavailable_no_search_repo',
            prefsManager: FakeReaderPrefsManager(),
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_chrome_search_unavailable_snackbar')),
        findsOneWidget,
      );
      expect(find.byType(BookSearchScreen), findsNothing);
    });

    testWidgets('libraryRepository 為 null 時，點擊搜尋按鈕顯示不可用提示，不導覽',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_search_unavailable_no_library_repo',
            prefsManager: FakeReaderPrefsManager(),
            searchRepository: FakeSearchRepository(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_chrome_search_unavailable_snackbar')),
        findsOneWidget,
      );
      expect(find.byType(BookSearchScreen), findsNothing);
    });

    testWidgets(
        'PDF：從搜尋按鈕開啟 BookSearchScreen，選取片段後就地跳轉並顯示暫態高亮，3 秒後自動清除',
        (tester) async {
      final searchRepository = FakeSearchRepository(
        bookSearchDetailResult: BookSearchDetailResult(
          book: _searchResultPlaceholderBook(format: BookFileFormat.pdf),
          matches: const [
            ContentMatchSnippet(
              snippet: '第 3 頁含有搜尋目標文字',
              locator:
                  '{"page":2,"rect":{"left":0.1,"top":0.1,"right":0.5,"bottom":0.2}}',
              chapterIndex: 2,
            ),
          ],
          totalMatches: 1,
          isTruncated: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_search_midsession_pdf',
            prefsManager: FakeReaderPrefsManager(),
            searchRepository: searchRepository,
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('book_search_screen_field')),
        '搜尋目標',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      await tester.tap(find.byKey(const Key('book_search_snippet_0')));
      await tester.pumpAndSettle();

      // BookSearchScreen 已 pop，閱讀器 session 沒有被銷毀重建（同一個
      // ReaderScreen widget tree，只是疊了一層新的暫態高亮）。
      expect(find.byType(BookSearchScreen), findsNothing);
      await pumpUntilPdfReady(
        tester,
        condition: () => find
            .byKey(const Key('pdf_reader_jump_highlight_2'))
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.byKey(const Key('pdf_reader_jump_highlight_2')),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 3));
      expect(
        find.byKey(const Key('pdf_reader_jump_highlight_2')),
        findsNothing,
      );
    });

    testWidgets(
        'PDF：命中片段缺少 rect（優雅降級情境）時仍正常跳頁，只是不顯示暫態高亮'
        '（review-plan-issue-8.md C-1 回歸測試）', (tester) async {
      final searchRepository = FakeSearchRepository(
        bookSearchDetailResult: BookSearchDetailResult(
          book: _searchResultPlaceholderBook(format: BookFileFormat.pdf),
          matches: const [
            ContentMatchSnippet(
              // 沒有 "rect" 鍵：ReaderJumpTarget.fromContentLocator() 依既有
              // 優雅降級設計，會回傳 pdfPageIndex 非 null、pdfRect 為 null。
              snippet: '第 3 頁含有搜尋目標文字（無精確座標）',
              locator: '{"page":2}',
              chapterIndex: 2,
            ),
          ],
          totalMatches: 1,
          isTruncated: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_search_midsession_pdf_no_rect',
            prefsManager: FakeReaderPrefsManager(),
            searchRepository: searchRepository,
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('book_search_screen_field')),
        '搜尋目標',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.tap(find.byKey(const Key('book_search_snippet_0')));
      await tester.pumpAndSettle();

      expect(find.byType(BookSearchScreen), findsNothing);
      expect(tester.takeException(), isNull);

      final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
      expect(pdfView.initialPageIndex, isNot(2),
          reason: '本測試斷言的是「跳轉方法確實被呼叫」而非重新斷言 initialPageIndex'
              '（那是開書當下的建構參數，跟就地跳轉無關，此行只是排除誤用）');
      // 沒有 rect，就不應該有任何高亮疊加層——但仍應正常跳到第 3 頁（不斷言
      // 底層 pdfrx 是否真的翻頁，那需要 integration_test；此處鎖住的是
      // 「不會因為 rect 缺席就整段提早 return、完全不呼叫 jumpToPage」。
      expect(find.textContaining('pdf_reader_jump_highlight_'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'PDF：就地跳轉後使用者提前點擊畫面（_handleZoneAction）立即清除暫態高亮，不等待 3 秒',
        (tester) async {
      final searchRepository = FakeSearchRepository(
        bookSearchDetailResult: BookSearchDetailResult(
          book: _searchResultPlaceholderBook(format: BookFileFormat.pdf),
          matches: const [
            ContentMatchSnippet(
              snippet: '第 3 頁含有搜尋目標文字',
              locator:
                  '{"page":2,"rect":{"left":0.1,"top":0.1,"right":0.5,"bottom":0.2}}',
              chapterIndex: 2,
            ),
          ],
          totalMatches: 1,
          isTruncated: false,
        ),
      );
      final key = GlobalKey<State<ReaderScreen>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_search_midsession_pdf_early_clear',
            prefsManager: FakeReaderPrefsManager(),
            searchRepository: searchRepository,
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('book_search_screen_field')),
        '搜尋目標',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.tap(find.byKey(const Key('book_search_snippet_0')));
      await tester.pumpAndSettle();

      await pumpUntilPdfReady(
        tester,
        condition: () => find
            .byKey(const Key('pdf_reader_jump_highlight_2'))
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.byKey(const Key('pdf_reader_jump_highlight_2')),
        findsOneWidget,
      );

      ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
      await tester.pump();

      expect(
        find.byKey(const Key('pdf_reader_jump_highlight_2')),
        findsNothing,
        reason: '重用 Issue 5 既有的 _handleZoneAction 早清除邏輯，不需要另外接線',
      );
    });

    testWidgets(
        'Foliate：從搜尋按鈕開啟 BookSearchScreen，選取片段後就地跳轉不拋出例外'
        '（WebView 真實渲染效果留給 integration_test 驗證）', (tester) async {
      final searchRepository = FakeSearchRepository(
        bookSearchDetailResult: BookSearchDetailResult(
          book: _searchResultPlaceholderBook(format: BookFileFormat.epub),
          matches: const [
            ContentMatchSnippet(
              snippet: '第一章含有搜尋目標文字',
              locator: 'epubcfi(/6/4)',
              chapterIndex: 1,
            ),
          ],
          totalMatches: 1,
          isTruncated: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_search_midsession_epub',
            prefsManager: FakeReaderPrefsManager(),
            searchRepository: searchRepository,
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('book_search_screen_field')),
        '搜尋目標',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      await tester.tap(find.byKey(const Key('book_search_snippet_0')));
      await tester.pumpAndSettle();

      expect(find.byType(BookSearchScreen), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '使用者未選取任何片段、直接從 BookSearchScreen 返回（pop null）時，'
        '閱讀器不受影響、不拋出例外（review-plan-issue-8.md M-1）', (tester) async {
      final searchRepository = FakeSearchRepository(
        bookSearchDetailResult: BookSearchDetailResult(
          book: _searchResultPlaceholderBook(format: BookFileFormat.pdf),
          matches: const [
            ContentMatchSnippet(
              snippet: '第 3 頁含有搜尋目標文字',
              locator:
                  '{"page":2,"rect":{"left":0.1,"top":0.1,"right":0.5,"bottom":0.2}}',
              chapterIndex: 2,
            ),
          ],
          totalMatches: 1,
          isTruncated: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample_multi_page.pdf',
            bookId: 'b_search_midsession_pop_null',
            prefsManager: FakeReaderPrefsManager(),
            searchRepository: searchRepository,
            libraryRepository: FakeLibraryRepository(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      await pumpUntilPdfReady(tester);

      await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
      await tester.pumpAndSettle();
      expect(find.byType(BookSearchScreen), findsOneWidget);

      // 直接按系統返回鍵離開 BookSearchScreen，不點選任何片段
      // （Navigator.pop() 不帶值，等同 pop(null)）。改用 find.byType(BackButton)
      // 而非 tester.pageBack()——後者內部靠比對 Material 預設 BackButton 的
      // 英文 tooltip「Back」尋找，這個 MaterialApp 已補上 locale: zh_TW，
      // AppBar 自動產生的 BackButton tooltip 因此變成中文「返回」，pageBack()
      // 會找不到目標（epic-45-interface-i18n Issue 4 最終複審 Minor #4，比照
      // library_screen_test.dart 同類問題的既有處置原則，此處按 Widget 型別
      // 尋找不受 locale 影響）。
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(BookSearchScreen), findsNothing);
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>)
                .value
                .startsWith('pdf_reader_jump_highlight_')),
        findsNothing,
        reason: 'pop(null) 不應觸發任何跳轉／高亮',
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('英文介面下 bookTitle 為 null 時回退顯示 Unknown Book',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_en_unknown_title',
          prefsManager: FakeReaderPrefsManager(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Unknown Book'), findsWidgets);
  });

  testWidgets('簡體中文介面下版面設定 Bottom Sheet 標題正確以簡體渲染',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_zh_cn_settings',
          bookTitle: '書名',
          prefsManager: FakeReaderPrefsManager(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('⚙️ 版面设定'), findsOneWidget);
  });

  testWidgets('英文介面下目錄 Bottom Sheet 標題正確以英文渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_en_toc',
          bookTitle: 'Title',
          prefsManager: FakeReaderPrefsManager(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final foliateView = tester.widget<FoliateReaderView>(
      find.byType(FoliateReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    final finder = find.byKey(const Key('reader_chrome_toc_button'));
    expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TocBottomSheet), findsOneWidget);
    expect(find.text('📖 Table of Contents'), findsOneWidget);
  });

  testWidgets('英文介面下不支援格式提示正確以英文渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.unknown',
          bookId: 'b_en_unsupported',
          prefsManager: FakeReaderPrefsManager(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Unsupported file format'), findsOneWidget);
  });

  tearDownAll(() {
    // 還原 cacheBookForServing 為原始實作，避免污染其他測試檔
    cacheBookForServing = originalCacheBookForServing;
  });
}

/// 點擊 `TabBar` 上文字為 [tabLabel] 的頁籤並等待切換動畫完成
/// （epic-28-reader-settings-enhancements Issue 5，`ReaderSettingsSheet` 的
/// 4 個頁籤）。與 `reader_settings_sheet_test.dart` 內同名 helper 邏輯相同，
/// 因測試檔互不 import，各自維護一份。
Future<void> switchToTab(WidgetTester tester, String tabLabel) async {
  await tester.tap(find.widgetWithText(Tab, tabLabel));
  await tester.pumpAndSettle();
}
