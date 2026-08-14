import 'column_mode.dart';
import 'dual_page_direction.dart';
import 'dual_page_mode.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'pdf_crop_mode.dart';
import 'pdf_crop_rect.dart';
import 'pdf_fit_mode.dart';
import 'pdf_page_turn_animation.dart';
import 'screen_orientation_setting.dart';
import 'writing_mode.dart';
import 'zone_action.dart';

/// 「實際套用到畫面」的最終生效值，由 [ReaderPrefsManager.resolve] 產生。
/// 與 [BookReaderPrefs]（使用者是否覆寫了哪些欄位，供設定面板顯示）刻意
/// 分離，見 docs/superpowers/plans/2026-07-12-refactor-reader-prefs-manager.md。
///
/// **欄位是否 non-nullable 的判斷依據**：只有現行架構已有明確、安全預設值
/// 的欄位才宣告 non-nullable（`pageTurnMode`／`screenOrientation`／
/// `pdfFitMode`／`pdfContrast`／`pdfBrightness`／`pdfBoldStrength`／
/// `pdfCropMode`／`navZoneActions`／`showNavZoneDebugOverlay`）。EPUB
/// 字型/排版 8 個欄位與 `writingMode`／`pdfCropRect` 維持 nullable
/// ——現行 `EpubReaderView`／`PdfReaderView` 對這些欄位是
/// null 時整個 Method Channel key 省略、交由 Readium 內部預設值或書本
/// CSS 決定，本類別不得發明一個目前不存在的預設值（見審查意見 C1，
/// `tmp/refactor-reader-prefs/reviews/review-refactor-reader-prefs-plan.md`）。
class ResolvedPreferences {
  final WritingMode? writingMode;
  final String? fontFamily;
  final double? fontSize;
  final double? fontWeight;
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? letterSpacing;
  final double? pageMargins;
  final double? marginTop;
  final double? marginBottom;
  final double? marginLeft;
  final double? marginRight;
  final EpubTextAlign? textAlign;
  final bool? publisherStyles;

  /// 流式 EPUB 分欄模式（epic-18-reader-device-qa Issue 6）：auto/single/double。
  /// null = auto（預設），由 foliate-js paginator.js 依 [columnSize] 決定欄數。
  final ColumnMode columnMode;

  /// 欄位大小閾值（epic-18-reader-device-qa Issue 6），360~1440px，
  /// 僅 [columnMode] == auto 時有效。預設 720.0。
  final double columnSize;

  final PageTurnMode pageTurnMode;
  final ScreenOrientationSetting screenOrientation;

  final PdfFitMode pdfFitMode;
  final double pdfContrast;
  final double pdfBrightness;
  final double pdfBoldStrength;
  final PdfCropMode pdfCropMode;
  final PdfCropRect? pdfCropRect; // pdfCropMode == none 時為 null，既有語意

  final DualPageMode dualPageMode;
  final bool dualPageCoverAlone;
  final DualPageDirection dualPageDirection;

  /// PDF 換頁動畫（epic-24-pdf-engine-rebuild Issue 11）：恆非 null，
  /// resolve() 內 book.pdfPageTurnAnimation ?? PdfPageTurnAnimation.slide
  /// （預設維持現行 200ms 滑動動畫）。
  final PdfPageTurnAnimation pdfPageTurnAnimation;

  final bool showHeader;
  final bool showFooter;

  /// 長度固定 9，由 [ReaderPrefsManagerImpl.resolve] 呼叫
  /// `resolveZoneActions()` 算出（見 epic-7-interaction spec.md）。
  final List<ZoneAction> navZoneActions;
  final bool showNavZoneDebugOverlay;

  /// 全域音量鍵翻頁開關（epic-14-system-settings Issue 4）：恆非 null，
  /// resolve() 內直接透傳 global.volumeKeyEnabled（無單書覆寫層，FR-36
  /// 本身即為全域總開關語意）。
  final bool volumeKeyEnabled;

  /// 全螢幕模式（epic-19-shelf-reading-enhance Issue 1）：恆非 null，
  /// resolve() 內 book.fullscreen ?? global.fullscreen（預設關閉，雙層解析）。
  final bool fullscreen;

  /// Console Log 攔截總開關（epic-28-reader-settings-enhancements
  /// Issue 2）：恆非 null，resolve() 內直接透傳
  /// global.consoleLogEnabled（無單書覆寫層，epic-28 design.md 決策）。
  final bool consoleLogEnabled;

  const ResolvedPreferences({
    this.writingMode,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.letterSpacing,
    this.pageMargins,
    this.marginTop,
    this.marginBottom,
    this.marginLeft,
    this.marginRight,
    this.textAlign,
    this.publisherStyles,
    this.columnMode = ColumnMode.auto,
    this.columnSize = 720.0,
    required this.pageTurnMode,
    required this.screenOrientation,
    required this.pdfFitMode,
    required this.pdfContrast,
    required this.pdfBrightness,
    required this.pdfBoldStrength,
    required this.pdfCropMode,
    this.pdfCropRect,
    required this.dualPageMode,
    required this.dualPageCoverAlone,
    required this.dualPageDirection,
    this.pdfPageTurnAnimation = PdfPageTurnAnimation.slide,
    required this.showHeader,
    required this.showFooter,
    required this.navZoneActions,
    required this.showNavZoneDebugOverlay,
    this.volumeKeyEnabled = true,
    this.fullscreen = false,
    this.consoleLogEnabled = false,
  });
}
