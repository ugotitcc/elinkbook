import 'package:shared_preferences/shared_preferences.dart';

import 'book_reader_prefs.dart';
import 'book_reader_prefs_repository.dart';
import 'dual_page_direction.dart';
import 'dual_page_mode.dart';
import 'global_reader_prefs.dart';
import 'page_turn_mode.dart';
import 'pdf_crop_mode.dart';
import 'pdf_fit_mode.dart';
import 'reader_prefs_manager.dart';
import 'resolved_preferences.dart';
import 'screen_orientation_setting.dart';
import 'writing_mode.dart';

/// [ReaderPrefsManager] 的正式實作。直接內建全域預設值的 SharedPreferences
/// 讀寫邏輯（吸收原 `GlobalReaderDefaults` 的職責，鍵名沿用不變以保留既有
/// 使用者資料），不把它當成注入依賴——這樣 `global_reader_defaults.dart`
/// 才能在完成遷移後被真正刪除，不會卡在「還有人依賴它」的狀態。
class ReaderPrefsManagerImpl implements ReaderPrefsManager {
  final BookReaderPrefsRepository _sqliteRepository;

  const ReaderPrefsManagerImpl(this._sqliteRepository);

  static const _pageTurnModeKey = 'global_reader_page_turn_mode';
  static const _screenOrientationKey = 'global_reader_screen_orientation';

  @override
  Future<LoadedPrefs> load(String bookId) async {
    final results = await Future.wait([
      _sqliteRepository.load(bookId),
      _loadGlobalPrefs(),
    ]);
    return LoadedPrefs(
      bookPrefs: results[0] as BookReaderPrefs,
      globalPrefs: results[1] as GlobalReaderPrefs,
    );
  }

  Future<GlobalReaderPrefs> _loadGlobalPrefs() async {
    final sp = await SharedPreferences.getInstance();
    return GlobalReaderPrefs(
      pageTurnMode: _readEnum(sp, _pageTurnModeKey, PageTurnMode.values) ??
          PageTurnMode.paginated,
      screenOrientation: _readEnum(
            sp,
            _screenOrientationKey,
            ScreenOrientationSetting.values,
          ) ??
          ScreenOrientationSetting.auto,
    );
  }

  T? _readEnum<T extends Enum>(
    SharedPreferences sp,
    String key,
    List<T> values,
  ) {
    final raw = sp.getString(key);
    if (raw == null) return null;
    try {
      return values.byName(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveBookPrefs(String bookId, BookReaderPrefs prefs) =>
      _sqliteRepository.save(bookId, prefs);

  @override
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_pageTurnModeKey, prefs.pageTurnMode.name);
    await sp.setString(_screenOrientationKey, prefs.screenOrientation.name);
  }

  @override
  ResolvedPreferences resolve(
    LoadedPrefs loaded, {
    WritingMode? autoDetectedWritingMode,
  }) {
    final book = loaded.bookPrefs;
    final global = loaded.globalPrefs;
    return ResolvedPreferences(
      writingMode: book.writingModeOverride ?? autoDetectedWritingMode,
      fontFamily: book.fontFamily,
      fontSize: book.fontSize,
      fontWeight: book.fontWeight,
      lineHeight: book.lineHeight,
      paragraphSpacing: book.paragraphSpacing,
      pageMargins: book.pageMargins,
      textAlign: book.textAlign,
      publisherStyles: book.publisherStyles,
      pageTurnMode: book.pageTurnModeOverride ?? global.pageTurnMode,
      screenOrientation:
          book.screenOrientationOverride ?? global.screenOrientation,
      pdfFitMode: book.pdfFitMode ?? PdfFitMode.pageFit,
      pdfContrast: book.pdfContrast ?? 0,
      pdfBrightness: book.pdfBrightness ?? 0,
      pdfBoldStrength: book.pdfBoldStrength ?? 0,
      pdfCropMode: book.pdfCropMode ?? PdfCropMode.none,
      pdfCropRect: book.pdfCropRect,
      dualPageMode: book.dualPageMode ?? DualPageMode.auto,
      dualPageCoverAlone: book.dualPageCoverAlone ?? true,
      dualPageDirection: book.dualPageDirection ?? DualPageDirection.ltr,
    );
  }
}
