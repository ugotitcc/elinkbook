import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/reader/epub_character_count_repository.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import '../support/fake_book_reader_prefs_repository.dart';
import '../support/fake_reading_position_repository.dart';

void main() {
  group('resolve()（純同步，不需要資料庫/SharedPreferences）', () {
    late ReaderPrefsManagerImpl manager;

    setUp(() {
      manager = ReaderPrefsManagerImpl(
        FakeBookReaderPrefsRepository(),
        FakeReadingPositionRepository(),
      );
    });

    test('全部欄位皆未覆寫時，回傳的 non-null 欄位皆為既存安全預設值', () {
      final loaded = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(loaded);

      expect(resolved.writingMode, isNull);
      expect(resolved.fontSize, isNull);
      expect(resolved.pageTurnMode, PageTurnMode.paginated);
      expect(resolved.screenOrientation, ScreenOrientationSetting.auto);
      expect(resolved.pdfFitMode, PdfFitMode.pageFit);
      expect(resolved.pdfContrast, 0);
      expect(resolved.pdfBrightness, 0);
      expect(resolved.pdfBoldStrength, 0);
      expect(resolved.pdfCropMode, PdfCropMode.none);
      expect(resolved.pdfCropRect, isNull);
      expect(resolved.dualPageMode, DualPageMode.auto);
      expect(resolved.dualPageCoverAlone, isTrue);
      expect(resolved.dualPageDirection, DualPageDirection.rtl);
      expect(resolved.showHeader, isFalse);
      expect(resolved.showFooter, isFalse);
      expect(resolved.navZoneActions, rightFlipZoneTemplate);
      expect(resolved.showNavZoneDebugOverlay, isFalse);
      expect(resolved.fullscreen, isFalse);
      expect(resolved.volumeKeyEnabled, isTrue);
    });

    test('單書覆寫存在時，優先套用單書覆寫，忽略全域預設', () {
      final loaded = LoadedPrefs(
        bookPrefs: const BookReaderPrefs(
          pageTurnModeOverride: PageTurnMode.scroll,
          screenOrientationOverride: ScreenOrientationSetting.lock90,
          pdfFitMode: PdfFitMode.fitWidth,
          pdfContrast: 20,
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: false,
          dualPageDirection: DualPageDirection.rtl,
          showHeader: false,
          showFooter: false,
          columnMode: ColumnMode.single,
          columnSize: 600.0,
          fullscreen: true,
        ),
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(loaded);

      expect(resolved.pageTurnMode, PageTurnMode.scroll);
      expect(resolved.screenOrientation, ScreenOrientationSetting.lock90);
      expect(resolved.pdfFitMode, PdfFitMode.fitWidth);
      expect(resolved.pdfContrast, 20);
      expect(resolved.dualPageMode, DualPageMode.always);
      expect(resolved.dualPageCoverAlone, isFalse);
      expect(resolved.dualPageDirection, DualPageDirection.rtl);
      expect(resolved.showHeader, isFalse);
      expect(resolved.showFooter, isFalse);
      expect(resolved.columnMode, ColumnMode.single);
      expect(resolved.columnSize, 600.0);
      expect(resolved.fullscreen, isTrue);
    });

    test('book.fullscreen 為 null 時退回 global.fullscreen（非硬編碼 false，證明雙層解析生效）',
        () {
      final loaded = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs:
            const GlobalReaderPrefs.initial().copyWith(fullscreen: true),
      );
      final resolved = manager.resolve(loaded);
      expect(resolved.fullscreen, isTrue);
    });

    test('book.fullscreen 存在時優先於 global.fullscreen', () {
      final loaded = LoadedPrefs(
        bookPrefs: const BookReaderPrefs(fullscreen: false),
        globalPrefs:
            const GlobalReaderPrefs.initial().copyWith(fullscreen: true),
      );
      final resolved = manager.resolve(loaded);
      expect(resolved.fullscreen, isFalse);
    });

    test('volumeKeyEnabled 直接透傳 global 值，無單書覆寫層', () {
      final loadedEnabled = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      expect(manager.resolve(loadedEnabled).volumeKeyEnabled, isTrue);

      final loadedDisabled = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs.initial()
            .copyWith(volumeKeyEnabled: false),
      );
      expect(manager.resolve(loadedDisabled).volumeKeyEnabled, isFalse);
    });

    test('單書覆寫為 null 時，正確退回全域預設（非硬編碼初始值，證明真的有讀 globalPrefs）',
        () {
      final loaded = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs(
          pageTurnMode: PageTurnMode.scroll,
          screenOrientation: ScreenOrientationSetting.lock270,
          navZoneMode: NavZoneMode.oneHand,
          navZoneCustomActions: rightFlipZoneTemplate,
          showNavZoneDebugOverlay: true,
        ),
      );
      final resolved = manager.resolve(loaded);

      expect(resolved.pageTurnMode, PageTurnMode.scroll);
      expect(resolved.screenOrientation, ScreenOrientationSetting.lock270);
      expect(resolved.navZoneActions, oneHandZoneTemplate);
      expect(resolved.showNavZoneDebugOverlay, isTrue);
    });

    test('navZoneMode 為 custom 時，navZoneActions 直接採用 navZoneCustomActions',
        () {
      const customActions = [
        ZoneAction.none, ZoneAction.none, ZoneAction.menu,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
        ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
      ];
      final loaded = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs(
          pageTurnMode: PageTurnMode.paginated,
          screenOrientation: ScreenOrientationSetting.auto,
          navZoneMode: NavZoneMode.custom,
          navZoneCustomActions: customActions,
          showNavZoneDebugOverlay: false,
        ),
      );
      final resolved = manager.resolve(loaded);

      expect(resolved.navZoneActions, customActions);
    });

    test('autoDetectedWritingMode 在沒有 writingModeOverride 時參與解析', () {
      final loaded = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(
        loaded,
        autoDetectedWritingMode: WritingMode.vertical,
      );
      expect(resolved.writingMode, WritingMode.vertical);
    });

    test('writingModeOverride 存在時優先於 autoDetectedWritingMode', () {
      final loaded = LoadedPrefs(
        bookPrefs: const BookReaderPrefs(
          writingModeOverride: WritingMode.horizontal,
        ),
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(
        loaded,
        autoDetectedWritingMode: WritingMode.vertical,
      );
      expect(resolved.writingMode, WritingMode.horizontal);
    });

    test('EPUB 字型/排版欄位原樣透傳（不套用任何預設值，維持既有 pass-through 語意）',
        () {
      final loaded = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(loaded);

      expect(resolved.fontFamily, isNull);
      expect(resolved.fontSize, isNull);
      expect(resolved.fontWeight, isNull);
      expect(resolved.lineHeight, isNull);
      expect(resolved.paragraphSpacing, isNull);
      expect(resolved.pageMargins, isNull);
      expect(resolved.marginTop, isNull);
      expect(resolved.marginBottom, isNull);
      expect(resolved.marginLeft, isNull);
      expect(resolved.marginRight, isNull);
      expect(resolved.textAlign, isNull);
      expect(resolved.publisherStyles, isNull);
      expect(resolved.columnMode, ColumnMode.auto);
      expect(resolved.columnSize, 720.0);
    });

    test('BookReaderPrefs.fontFamily 字串值正確透傳到 ResolvedPreferences（epic-14 型別由 AppFont 改為 String）',
        () {
      final loaded = LoadedPrefs(
        bookPrefs: const BookReaderPrefs(fontFamily: 'SourceHanSansTC'),
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(loaded);

      expect(resolved.fontFamily, 'SourceHanSansTC');
    });

    test('BookReaderPrefs 的邊距 4 個欄位正確透傳到 ResolvedPreferences', () {
      final loaded = LoadedPrefs(
        bookPrefs: const BookReaderPrefs(
          marginTop: 72,
          marginBottom: 20,
          marginLeft: 30,
          marginRight: 30,
        ),
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(loaded);
      expect(resolved.marginTop, 72);
      expect(resolved.marginBottom, 20);
      expect(resolved.marginLeft, 30);
      expect(resolved.marginRight, 30);
    });

    test('BookReaderPrefs 的 letterSpacing 正確透傳到 ResolvedPreferences', () {
      final loaded = LoadedPrefs(
        bookPrefs: const BookReaderPrefs(letterSpacing: 0.15),
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(loaded);
      expect(resolved.letterSpacing, 0.15);
    });
  });

  group('load()（async，涵蓋原 global_reader_defaults_test.dart 與部分 reader_screen_test.dart 的回歸覆蓋）',
      () {
    late SqliteLibraryRepository libraryRepository;
    late ReaderPrefsManagerImpl manager;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues({});
      libraryRepository =
          await SqliteLibraryRepository.open(inMemoryDatabasePath);
      manager = ReaderPrefsManagerImpl(
        BookReaderPrefsRepository(libraryRepository.database),
        ReadingPositionRepository(libraryRepository.database),
      );
      await libraryRepository.insertBook(Book(
        id: 'b1',
        title: '書名',
        format: BookFileFormat.epub,
        filePath: 'content://example/b1',
        source: BookSource.local,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
    });

    tearDown(() async {
      await libraryRepository.close();
    });

    test('尚未儲存過任何偏好時，load 回傳 BookReaderPrefs.empty + GlobalReaderPrefs.initial()',
        () async {
      final loaded = await manager.load('b1');
      expect(loaded.bookPrefs, BookReaderPrefs.empty);
      expect(loaded.globalPrefs, const GlobalReaderPrefs.initial());
    });

    test('saveBookPrefs 寫入後，load 讀回相同的單書覆寫值', () async {
      const prefs = BookReaderPrefs(pageTurnModeOverride: PageTurnMode.scroll);
      await manager.saveBookPrefs('b1', prefs);
      final loaded = await manager.load('b1');
      expect(loaded.bookPrefs, prefs);
    });

    test('saveGlobalPrefs 寫入後，load 讀回相同的全域預設值（含熱區三欄位）',
        () async {
      const globalPrefs = GlobalReaderPrefs(
        pageTurnMode: PageTurnMode.scroll,
        screenOrientation: ScreenOrientationSetting.lock90,
        navZoneMode: NavZoneMode.custom,
        navZoneCustomActions: [
          ZoneAction.menu, ZoneAction.none, ZoneAction.none,
          ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
          ZoneAction.none, ZoneAction.none, ZoneAction.none,
        ],
        showNavZoneDebugOverlay: true,
      );
      await manager.saveGlobalPrefs(globalPrefs);
      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs, globalPrefs);
    });

    test('loadGlobalPrefs() 回傳與 load(bookId).globalPrefs 一致的值', () async {
      const globalPrefs = GlobalReaderPrefs(
        pageTurnMode: PageTurnMode.scroll,
        screenOrientation: ScreenOrientationSetting.lock90,
        navZoneMode: NavZoneMode.oneHand,
        navZoneCustomActions: rightFlipZoneTemplate,
        showNavZoneDebugOverlay: true,
      );
      await manager.saveGlobalPrefs(globalPrefs);

      final direct = await manager.loadGlobalPrefs();
      final viaLoad = await manager.load('b1');

      expect(direct, globalPrefs);
      expect(direct, viaLoad.globalPrefs);
    });

    test('saveGlobalPrefs 寫入 volumeKeyEnabled／fullscreen 至既有慣例命名的 SharedPreferences key',
        () async {
      const globalPrefs = GlobalReaderPrefs(
        pageTurnMode: PageTurnMode.paginated,
        screenOrientation: ScreenOrientationSetting.auto,
        navZoneMode: NavZoneMode.rightFlip,
        navZoneCustomActions: rightFlipZoneTemplate,
        showNavZoneDebugOverlay: false,
        volumeKeyEnabled: false,
        fullscreen: true,
      );
      await manager.saveGlobalPrefs(globalPrefs);

      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool('global_reader_volume_key_enabled'), isFalse);
      expect(sp.getBool('global_reader_fullscreen'), isTrue);

      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs.volumeKeyEnabled, isFalse);
      expect(loaded.globalPrefs.fullscreen, isTrue);
    });

    test('volumeKeyEnabled／fullscreen 未儲存過（缺鍵）時，安全回退為預設值 true／false',
        () async {
      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs.volumeKeyEnabled, isTrue);
      expect(loaded.globalPrefs.fullscreen, isFalse);
    });

    test('saveGlobalPrefs 寫入 openLastBookOnLaunch 至既有慣例命名的 SharedPreferences key',
        () async {
      const globalPrefs = GlobalReaderPrefs(
        pageTurnMode: PageTurnMode.paginated,
        screenOrientation: ScreenOrientationSetting.auto,
        navZoneMode: NavZoneMode.rightFlip,
        navZoneCustomActions: rightFlipZoneTemplate,
        showNavZoneDebugOverlay: false,
        openLastBookOnLaunch: false,
      );
      await manager.saveGlobalPrefs(globalPrefs);

      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool('global_reader_open_last_book_on_launch'), isFalse);

      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs.openLastBookOnLaunch, isFalse);
    });

    test('openLastBookOnLaunch 未儲存過（缺鍵）時，安全回退為預設值 true', () async {
      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs.openLastBookOnLaunch, isTrue);
    });

    test('navZoneCustomActions 已儲存值為空字串時，安全回退為 rightFlip 模板',
        () async {
      SharedPreferences.setMockInitialValues({
        'global_reader_nav_zone_custom_actions': '',
      });
      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs.navZoneCustomActions, rightFlipZoneTemplate);
    });

    test('navZoneCustomActions 未儲存過（缺鍵）時，安全回退為 rightFlip 模板',
        () async {
      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs.navZoneCustomActions, rightFlipZoneTemplate);
    });

    test('已儲存的全域預設字串無法對應到任何列舉值時，安全回退為初始值', () async {
      SharedPreferences.setMockInitialValues({
        'global_reader_page_turn_mode': 'not_a_real_enum_value',
        'global_reader_screen_orientation': 'not_a_real_enum_value',
      });
      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs, const GlobalReaderPrefs.initial());
    });

    test('尚未儲存過位置時，load 回傳 ReadingPosition() 預設值', () async {
      final loaded = await manager.load('b1');
      expect(loaded.readingPosition, const ReadingPosition());
    });

    test('saveReadingPosition 寫入後，load 讀回相同的位置', () async {
      const position = ReadingPosition(pdfPageIndex: 3, progress: 0.5);
      await manager.saveReadingPosition('b1', position);
      final loaded = await manager.load('b1');
      expect(loaded.readingPosition, position);
    });

    test('EpubCharacterCountRepository 有註冊時，load 回傳 totalCharacterCount，saveTotalCharacterCount 寫入後可讀回',
        () async {
      final managerWithCounting = ReaderPrefsManagerImpl(
        BookReaderPrefsRepository(libraryRepository.database),
        ReadingPositionRepository(libraryRepository.database),
        EpubCharacterCountRepository(libraryRepository.database),
      );

      final beforeSave = await managerWithCounting.load('b1');
      expect(beforeSave.totalCharacterCount, isNull);

      await managerWithCounting.saveTotalCharacterCount('b1', 12345);
      final afterSave = await managerWithCounting.load('b1');
      expect(afterSave.totalCharacterCount, 12345);
    });

    test('未提供 EpubCharacterCountRepository（第 3 個建構參數省略）時，totalCharacterCount 一律為 null 且 saveTotalCharacterCount 安全無操作',
        () async {
      // manager 沿用既有（2 參數）setUp 建立的實例，驗證省略第 3 個建構
      // 參數時仍可安全編譯與執行（見 Global Constraints）。
      await manager.saveTotalCharacterCount('b1', 999); // 不應拋出例外
      final loaded = await manager.load('b1');
      expect(loaded.totalCharacterCount, isNull);
    });
  });
}
