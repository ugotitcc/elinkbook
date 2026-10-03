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
import 'pdf_page_turn_mode.dart';
import 'reader_prefs_manager.dart';
import 'reading_position.dart';
import 'reading_position_repository.dart';
import 'resolved_preferences.dart';
import 'screen_orientation_setting.dart';
import 'text_conversion_mode.dart';
import 'writing_mode.dart';
import 'zone_action.dart';

/// [ReaderPrefsManager] 的正式實作。直接內建全域預設值的 SharedPreferences
/// 讀寫邏輯（吸收原 `GlobalReaderDefaults` 的職責，鍵名沿用不變以保留既有
/// 使用者資料），不把它當成注入依賴——這樣 `global_reader_defaults.dart`
/// 才能在完成遷移後被真正刪除，不會卡在「還有人依賴它」的狀態。
class ReaderPrefsManagerImpl implements ReaderPrefsManager {
  final BookReaderPrefsRepository _sqliteRepository;
  final ReadingPositionRepository _positionRepository;

  const ReaderPrefsManagerImpl(
    this._sqliteRepository,
    this._positionRepository,
  );

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
  static const _showHeaderKey = 'global_reader_show_header';
  static const _showFooterKey = 'global_reader_show_footer';
  static const _textConversionKey = 'global_reader_text_conversion';
  static const _ttsVoiceIdKey = 'global_reader_tts_voice_id';
  static const _defaultTtsSpeedKey = 'global_reader_default_tts_speed';

  @override
  Future<LoadedPrefs> load(String bookId) async {
    final results = await Future.wait([
      _sqliteRepository.load(bookId),
      loadGlobalPrefs(),
      _positionRepository.load(bookId),
    ]);
    return LoadedPrefs(
      bookPrefs: results[0] as BookReaderPrefs,
      globalPrefs: results[1] as GlobalReaderPrefs,
      readingPosition: results[2] as ReadingPosition,
    );
  }

  /// 單獨載入全域偏好，不需要 bookId——供不依附特定書籍的設定畫面（例如
  /// `NavZoneSettingsScreen`，epic-7-interaction Issue 3）使用；`load(bookId)`
  /// 內部也呼叫這裡，兩者保證讀到一致的值。
  @override
  Future<GlobalReaderPrefs> loadGlobalPrefs() async {
    final sp = await SharedPreferences.getInstance();
    return GlobalReaderPrefs(
      consoleLogEnabled: sp.getBool(_consoleLogEnabledKey) ?? false,
      navZone: NavZonePrefs(
        navZoneMode: _readEnum(sp, _navZoneModeKey, NavZoneMode.values) ??
            NavZoneMode.rightFlip,
        navZoneCustomActions:
            _decodeZoneActions(sp.getString(_navZoneCustomActionsKey)),
        showNavZoneDebugOverlay: sp.getBool(_navZoneDebugOverlayKey) ?? false,
      ),
      tts: TtsDefaults(
        ttsVoiceId: sp.getString(_ttsVoiceIdKey),
        defaultTtsSpeed: sp.getDouble(_defaultTtsSpeedKey) ?? 1.0,
      ),
      reading: ReadingDefaults(
        pageTurnMode: _readEnum(sp, _pageTurnModeKey, PageTurnMode.values) ??
            PageTurnMode.paginated,
        screenOrientation: _readEnum(
              sp,
              _screenOrientationKey,
              ScreenOrientationSetting.values,
            ) ??
            ScreenOrientationSetting.auto,
        volumeKeyEnabled: sp.getBool(_volumeKeyEnabledKey) ?? true,
        fullscreen: sp.getBool(_fullscreenKey) ?? false,
        openLastBookOnLaunch: sp.getBool(_openLastBookOnLaunchKey) ?? true,
        showHeader: sp.getBool(_showHeaderKey) ?? false,
        showFooter: sp.getBool(_showFooterKey) ?? false,
        textConversion: _readEnum(sp, _textConversionKey, TextConversionMode.values) ??
            TextConversionMode.original,
      ),
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
    await sp.setString(_pageTurnModeKey, prefs.reading.pageTurnMode.name);
    await sp.setString(
      _screenOrientationKey,
      prefs.reading.screenOrientation.name,
    );
    await sp.setString(_navZoneModeKey, prefs.navZone.navZoneMode.name);
    await sp.setString(
      _navZoneCustomActionsKey,
      _encodeZoneActions(prefs.navZone.navZoneCustomActions),
    );
    await sp.setBool(
      _navZoneDebugOverlayKey,
      prefs.navZone.showNavZoneDebugOverlay,
    );
    await sp.setBool(_volumeKeyEnabledKey, prefs.reading.volumeKeyEnabled);
    await sp.setBool(_fullscreenKey, prefs.reading.fullscreen);
    await sp.setBool(
      _openLastBookOnLaunchKey,
      prefs.reading.openLastBookOnLaunch,
    );
    await sp.setBool(_consoleLogEnabledKey, prefs.consoleLogEnabled);
    await sp.setBool(_showHeaderKey, prefs.reading.showHeader);
    await sp.setBool(_showFooterKey, prefs.reading.showFooter);
    await sp.setString(_textConversionKey, prefs.reading.textConversion.name);
    // ttsVoiceId 為 nullable——setString 不接受 null，缺席時須明確 remove()
    // 該鍵，否則舊值會殘留，導致「清空語音選擇」的意圖被忽略。
    if (prefs.tts.ttsVoiceId != null) {
      await sp.setString(_ttsVoiceIdKey, prefs.tts.ttsVoiceId!);
    } else {
      await sp.remove(_ttsVoiceIdKey);
    }
    await sp.setDouble(_defaultTtsSpeedKey, prefs.tts.defaultTtsSpeed);
  }

  @override
  Future<void> saveReadingPosition(String bookId, ReadingPosition position) =>
      _positionRepository.save(bookId, position);

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
      pageTurnMode: book.pageTurnModeOverride ?? global.reading.pageTurnMode,
      screenOrientation:
          book.screenOrientationOverride ?? global.reading.screenOrientation,
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
      pdfPageTurnMode: book.pdfPageTurnMode ?? PdfPageTurnMode.paginated,
      showHeader: book.showHeader ?? global.reading.showHeader,
      showFooter: book.showFooter ?? global.reading.showFooter,
      navZoneActions: resolveZoneActions(
        global.navZone.navZoneMode,
        global.navZone.navZoneCustomActions,
      ),
      showNavZoneDebugOverlay: global.navZone.showNavZoneDebugOverlay,
      fullscreen: book.fullscreen ?? global.reading.fullscreen,
      volumeKeyEnabled: global.reading.volumeKeyEnabled,
      consoleLogEnabled: global.consoleLogEnabled,
    );
  }
}
