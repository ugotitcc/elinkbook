import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import '../support/fake_book_reader_prefs_repository.dart';

void main() {
  group('resolve()（純同步，不需要資料庫/SharedPreferences）', () {
    late ReaderPrefsManagerImpl manager;

    setUp(() {
      manager = ReaderPrefsManagerImpl(
        FakeBookReaderPrefsRepository(),
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
    });

    test('單書覆寫為 null 時，正確退回全域預設（非硬編碼初始值，證明真的有讀 globalPrefs）',
        () {
      final loaded = LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs(
          pageTurnMode: PageTurnMode.scroll,
          screenOrientation: ScreenOrientationSetting.lock270,
        ),
      );
      final resolved = manager.resolve(loaded);

      expect(resolved.pageTurnMode, PageTurnMode.scroll);
      expect(resolved.screenOrientation, ScreenOrientationSetting.lock270);
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
      expect(resolved.textAlign, isNull);
      expect(resolved.publisherStyles, isNull);
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
      manager =
          ReaderPrefsManagerImpl(BookReaderPrefsRepository(libraryRepository.database));
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

    test('saveGlobalPrefs 寫入後，load 讀回相同的全域預設值', () async {
      const globalPrefs = GlobalReaderPrefs(
        pageTurnMode: PageTurnMode.scroll,
        screenOrientation: ScreenOrientationSetting.lock90,
      );
      await manager.saveGlobalPrefs(globalPrefs);
      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs, globalPrefs);
    });

    test('已儲存的全域預設字串無法對應到任何列舉值時，安全回退為初始值', () async {
      SharedPreferences.setMockInitialValues({
        'global_reader_page_turn_mode': 'not_a_real_enum_value',
        'global_reader_screen_orientation': 'not_a_real_enum_value',
      });
      final loaded = await manager.load('b1');
      expect(loaded.globalPrefs, const GlobalReaderPrefs.initial());
    });
  });
}
