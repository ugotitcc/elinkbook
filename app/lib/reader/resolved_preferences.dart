import 'app_font.dart';
import 'dual_page_direction.dart';
import 'dual_page_mode.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'pdf_crop_mode.dart';
import 'pdf_crop_rect.dart';
import 'pdf_fit_mode.dart';
import 'screen_orientation_setting.dart';
import 'writing_mode.dart';

/// 「實際套用到畫面」的最終生效值，由 [ReaderPrefsManager.resolve] 產生。
/// 與 [BookReaderPrefs]（使用者是否覆寫了哪些欄位，供設定面板顯示）刻意
/// 分離，見 docs/superpowers/plans/2026-07-12-refactor-reader-prefs-manager.md。
///
/// **欄位是否 non-nullable 的判斷依據**：只有現行架構已有明確、安全預設值
/// 的欄位才宣告 non-nullable（`pageTurnMode`／`screenOrientation`／
/// `pdfFitMode`／`pdfContrast`／`pdfBrightness`／`pdfBoldStrength`／
/// `pdfCropMode`）。EPUB 字型/排版 8 個欄位與 `writingMode`／`pdfCropRect`
/// 維持 nullable——現行 `EpubReaderView`／`PdfReaderView` 對這些欄位是
/// null 時整個 Method Channel key 省略、交由 Readium 內部預設值或書本
/// CSS 決定，本類別不得發明一個目前不存在的預設值（見審查意見 C1，
/// `tmp/refactor-reader-prefs/reviews/review-refactor-reader-prefs-plan.md`）。
class ResolvedPreferences {
  final WritingMode? writingMode;
  final AppFont? fontFamily;
  final double? fontSize;
  final double? fontWeight;
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? pageMargins;
  final EpubTextAlign? textAlign;
  final bool? publisherStyles;

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

  const ResolvedPreferences({
    this.writingMode,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
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
  });
}
