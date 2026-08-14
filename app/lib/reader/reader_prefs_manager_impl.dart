import 'package:shared_preferences/shared_preferences.dart';

import 'book_reader_prefs.dart';
import 'book_reader_prefs_repository.dart';
import 'column_mode.dart';
import 'dual_page_direction.dart';
import 'dual_page_mode.dart';
import 'global_reader_prefs.dart';
import 'nav_zone_mode.dart';
import 'page_turn_mode.dart';
import 'pdf_crop_mode.dart';
import 'pdf_fit_mode.dart';
import 'pdf_page_turn_animation.dart';
import 'reader_prefs_manager.dart';
import 'reading_position.dart';
import 'epub_character_count_repository.dart';
import 'reading_position_repository.dart';
import 'resolved_preferences.dart';
import 'screen_orientation_setting.dart';
import 'writing_mode.dart';
import 'zone_action.dart';

/// [ReaderPrefsManager] 的正式實作。直接內建全域預設值的 SharedPreferences
/// 讀寫邏輯（吸收原 `GlobalReaderDefaults` 的職責，鍵名沿用不變以保留既有
/// 使用者資料），不把它當成注入依賴——這樣 `global_reader_defaults.dart`
/// 才能在完成遷移後被真正刪除，不會卡在「還有人依賴它」的狀態。
class ReaderPrefsManagerImpl implements ReaderPrefsManager {
  final BookReaderPrefsRepository _sqliteRepository;
  final ReadingPositionRepository _positionRepository;
  final EpubCharacterCountRepository? _characterCountRepository;

  const ReaderPrefsManagerImpl(
    this._sqliteRepository,
    this._positionRepository, [
    this._characterCountRepository,
  ]);

  static const _pageTurnModeKey = 'global_reader_page_turn_mode';
  static const _screenOrientationKey = 'global_reader_screen_orientation';
  static const _navZoneModeKey = 'global_reader_nav_zone_mode';
  static const _navZoneCustomActionsKey =
      'global_reader_nav_zone_custom_actions';
  static const _navZoneDebugOverlayKey =
      'global_reader_nav_zone_debug_overlay';
  static const _volumeKeyEnabledKey = 'global_reader_volume_key_enabled';
  static const _fullscreenKey = 'global_reader_fullscreen';
  static const _openLastBookOnLaunchKey = 'global_reader_open_last_book_on_launch';
  static const _consoleLogEnabledKey = 'global_reader_console_log_enabled';

  @override
  Future<LoadedPrefs> load(String bookId) async {
    final results = await Future.wait([
      _sqliteRepository.load(bookId),
      loadGlobalPrefs(),
      _positionRepository.load(bookId),
      _characterCountRepository?.load(bookId) ?? Future.value(null),
    ]);
    return LoadedPrefs(
      bookPrefs: results[0] as BookReaderPrefs,
      globalPrefs: results[1] as GlobalReaderPrefs,
      readingPosition: results[2] as ReadingPosition,
      totalCharacterCount: results[3] as int?,
    );
  }

  /// 單獨載入全域偏好，不需要 bookId——供不依附特定書籍的設定畫面（例如
  /// `NavZoneSettingsScreen`，epic-7-interaction Issue 3）使用；`load(bookId)`
  /// 內部也呼叫這裡，兩者保證讀到一致的值。
  @override
  Future<GlobalReaderPrefs> loadGlobalPrefs() async {
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
      navZoneMode: _readEnum(sp, _navZoneModeKey, NavZoneMode.values) ??
          NavZoneMode.rightFlip,
      navZoneCustomActions:
          _decodeZoneActions(sp.getString(_navZoneCustomActionsKey)),
      showNavZoneDebugOverlay: sp.getBool(_navZoneDebugOverlayKey) ?? false,
      volumeKeyEnabled: sp.getBool(_volumeKeyEnabledKey) ?? true,
      fullscreen: sp.getBool(_fullscreenKey) ?? false,
      openLastBookOnLaunch: sp.getBool(_openLastBookOnLaunchKey) ?? true,
      consoleLogEnabled: sp.getBool(_consoleLogEnabledKey) ?? false,
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

  /// `navZoneCustomActions` 缺席、長度不為 9、或含有無法辨識的 [ZoneAction]
  /// 名稱時，一律回退為 [rightFlipZoneTemplate]——不可回退全 `none`，會
  /// 違反自訂模式「至少 1 格 menu」的驗證規則（spec.md「資料模型」審查
  /// 修正）。只捕捉 `ArgumentError`——`EnumName.byName()` 找不到對應列舉
  /// 值時擲出的例外型別——不使用 `catch (_)` 寬泛捕捉一切，避免意外吞掉
  /// 非預期的系統層級錯誤（審查修正）。
  List<ZoneAction> _decodeZoneActions(String? raw) {
    if (raw == null) return rightFlipZoneTemplate;
    final parts = raw.split(',');
    if (parts.length != 9) return rightFlipZoneTemplate;
    try {
      return parts.map((name) => ZoneAction.values.byName(name)).toList();
    } on ArgumentError catch (_) {
      return rightFlipZoneTemplate;
    }
  }

  String _encodeZoneActions(List<ZoneAction> actions) =>
      actions.map((a) => a.name).join(',');

  @override
  Future<void> saveBookPrefs(String bookId, BookReaderPrefs prefs) =>
      _sqliteRepository.save(bookId, prefs);

  @override
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_pageTurnModeKey, prefs.pageTurnMode.name);
    await sp.setString(_screenOrientationKey, prefs.screenOrientation.name);
    await sp.setString(_navZoneModeKey, prefs.navZoneMode.name);
    await sp.setString(
      _navZoneCustomActionsKey,
      _encodeZoneActions(prefs.navZoneCustomActions),
    );
    await sp.setBool(_navZoneDebugOverlayKey, prefs.showNavZoneDebugOverlay);
    await sp.setBool(_volumeKeyEnabledKey, prefs.volumeKeyEnabled);
    await sp.setBool(_fullscreenKey, prefs.fullscreen);
    await sp.setBool(_openLastBookOnLaunchKey, prefs.openLastBookOnLaunch);
    await sp.setBool(_consoleLogEnabledKey, prefs.consoleLogEnabled);
  }

  @override
  Future<void> saveReadingPosition(String bookId, ReadingPosition position) =>
      _positionRepository.save(bookId, position);

  @override
  Future<void> saveTotalCharacterCount(String bookId, int totalCharacterCount) =>
      _characterCountRepository?.save(bookId, totalCharacterCount) ??
      Future.value();

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
      letterSpacing: book.letterSpacing,
      pageMargins: book.pageMargins,
      marginTop: book.marginTop,
      marginBottom: book.marginBottom,
      marginLeft: book.marginLeft,
      marginRight: book.marginRight,
      textAlign: book.textAlign,
      publisherStyles: book.publisherStyles,
      columnMode: book.columnMode ?? ColumnMode.auto,
      columnSize: book.columnSize ?? 720.0,
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
      dualPageDirection: book.dualPageDirection ?? DualPageDirection.rtl,
      pdfPageTurnAnimation:
          book.pdfPageTurnAnimation ?? PdfPageTurnAnimation.slide,
      showHeader: book.showHeader ?? false,
      showFooter: book.showFooter ?? false,
      navZoneActions:
          resolveZoneActions(global.navZoneMode, global.navZoneCustomActions),
      showNavZoneDebugOverlay: global.showNavZoneDebugOverlay,
      fullscreen: book.fullscreen ?? global.fullscreen,
      volumeKeyEnabled: global.volumeKeyEnabled,
      consoleLogEnabled: global.consoleLogEnabled,
    );
  }
}
