import 'app_font.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'pdf_crop_mode.dart';
import 'pdf_crop_rect.dart';
import 'pdf_fit_mode.dart';
import 'screen_orientation_setting.dart';
import 'writing_mode.dart';

/// 單一書籍的版面偏好設定（FR-09／FR-10／FR-11），對應 `book_reader_prefs`
/// 表的一列（見 docs/epics/epic-4-pdf-enhance/spec.md「資料模型」）。所有
/// 欄位皆為 nullable：`null` 代表未覆寫，由呼叫端依各欄位語意決定回退值
/// （書本內建樣式、Readium 預設，或——僅限 [pageTurnModeOverride]／
/// [screenOrientationOverride]——全域預設值，見 `GlobalReaderDefaults`）。
/// `pdf` 前綴的 6 個欄位為 PDF 專屬，皆為單書持久化、無全域預設層（見
/// epic-4 design.md 決策 #2／#8）。
class BookReaderPrefs {
  final AppFont? fontFamily;
  final double? fontSize;
  final double? fontWeight; // Readium 倍率語意（1.0 = normal），非 CSS 300-900 原始值
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? pageMargins; // 單一數值，四邊同步變動，見 ADR 0005
  final EpubTextAlign? textAlign;
  final bool? publisherStyles; // 對應 Readium publisherStyles；true=使用書本內建 CSS
  final WritingMode? writingModeOverride; // null=採用書籍排版（自動偵測）
  final PageTurnMode? pageTurnModeOverride; // null=使用全域預設
  final ScreenOrientationSetting? screenOrientationOverride; // null=使用全域預設

  final PdfFitMode? pdfFitMode; // null=pageFit（預設）
  final double? pdfContrast; // -100..100，null=0（無調整）
  final double? pdfBrightness; // -100..100，null=0（無調整）
  final double? pdfBoldStrength; // 0..1，null=0（無加粗）
  final PdfCropMode? pdfCropMode; // null=none（不裁切）
  final PdfCropRect? pdfCropRect; // pdfCropMode != none 時才有意義

  const BookReaderPrefs({
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
    this.writingModeOverride,
    this.pageTurnModeOverride,
    this.screenOrientationOverride,
    this.pdfFitMode,
    this.pdfContrast,
    this.pdfBrightness,
    this.pdfBoldStrength,
    this.pdfCropMode,
    this.pdfCropRect,
  });

  /// 無任何覆寫，等同資料庫無對應列時的狀態。
  static const empty = BookReaderPrefs();

  Map<String, Object?> toMap(String bookId) {
    return {
      'book_id': bookId,
      'font_family': fontFamily?.name,
      'font_size': fontSize,
      'font_weight': fontWeight,
      'line_height': lineHeight,
      'paragraph_spacing': paragraphSpacing,
      'page_margins': pageMargins,
      'text_align': textAlign?.name,
      'publisher_styles':
          publisherStyles == null ? null : (publisherStyles! ? 1 : 0),
      'writing_mode_override': writingModeOverride?.name,
      'page_turn_mode_override': pageTurnModeOverride?.name,
      'screen_orientation_override': screenOrientationOverride?.name,
      'pdf_fit_mode': pdfFitMode?.name,
      'pdf_contrast': pdfContrast,
      'pdf_brightness': pdfBrightness,
      'pdf_bold_strength': pdfBoldStrength,
      'pdf_crop_mode': pdfCropMode?.name,
      'pdf_crop_rect': pdfCropRect?.toJson(),
    };
  }

  factory BookReaderPrefs.fromMap(Map<String, Object?> map) {
    return BookReaderPrefs(
      fontFamily: map['font_family'] == null
          ? null
          : AppFont.values.byName(map['font_family'] as String),
      // SQLite 對無小數部分的 REAL 欄位可能讀回 int（見
      // Book.fromMap 的 progress 欄位既有處理方式），故用 num? 轉換，
      // 不可直接 `as double?`（會拋出 type cast 例外）。
      fontSize: (map['font_size'] as num?)?.toDouble(),
      fontWeight: (map['font_weight'] as num?)?.toDouble(),
      lineHeight: (map['line_height'] as num?)?.toDouble(),
      paragraphSpacing: (map['paragraph_spacing'] as num?)?.toDouble(),
      pageMargins: (map['page_margins'] as num?)?.toDouble(),
      textAlign: map['text_align'] == null
          ? null
          : EpubTextAlign.values.byName(map['text_align'] as String),
      publisherStyles: map['publisher_styles'] == null
          ? null
          : (map['publisher_styles'] as int) == 1,
      writingModeOverride: map['writing_mode_override'] == null
          ? null
          : WritingMode.values.byName(map['writing_mode_override'] as String),
      pageTurnModeOverride: map['page_turn_mode_override'] == null
          ? null
          : PageTurnMode.values
              .byName(map['page_turn_mode_override'] as String),
      screenOrientationOverride: map['screen_orientation_override'] == null
          ? null
          : ScreenOrientationSetting.values
              .byName(map['screen_orientation_override'] as String),
      pdfFitMode: map['pdf_fit_mode'] == null
          ? null
          : PdfFitMode.values.byName(map['pdf_fit_mode'] as String),
      pdfContrast: (map['pdf_contrast'] as num?)?.toDouble(),
      pdfBrightness: (map['pdf_brightness'] as num?)?.toDouble(),
      pdfBoldStrength: (map['pdf_bold_strength'] as num?)?.toDouble(),
      pdfCropMode: map['pdf_crop_mode'] == null
          ? null
          : PdfCropMode.values.byName(map['pdf_crop_mode'] as String),
      pdfCropRect: map['pdf_crop_rect'] == null
          ? null
          : PdfCropRect.fromJson(map['pdf_crop_rect'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookReaderPrefs &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.lineHeight == lineHeight &&
      other.paragraphSpacing == paragraphSpacing &&
      other.pageMargins == pageMargins &&
      other.textAlign == textAlign &&
      other.publisherStyles == publisherStyles &&
      other.writingModeOverride == writingModeOverride &&
      other.pageTurnModeOverride == pageTurnModeOverride &&
      other.screenOrientationOverride == screenOrientationOverride &&
      other.pdfFitMode == pdfFitMode &&
      other.pdfContrast == pdfContrast &&
      other.pdfBrightness == pdfBrightness &&
      other.pdfBoldStrength == pdfBoldStrength &&
      other.pdfCropMode == pdfCropMode &&
      other.pdfCropRect == pdfCropRect;

  @override
  int get hashCode => Object.hash(
        fontFamily,
        fontSize,
        fontWeight,
        lineHeight,
        paragraphSpacing,
        pageMargins,
        textAlign,
        publisherStyles,
        writingModeOverride,
        pageTurnModeOverride,
        screenOrientationOverride,
        pdfFitMode,
        pdfContrast,
        pdfBrightness,
        pdfBoldStrength,
        pdfCropMode,
        pdfCropRect,
      );

  /// 只更新明確傳入的欄位，其餘欄位沿用目前值（`newValue ?? this.value`
  /// 語意，不支援「明確清成 null」——需要清空欄位的情境（例如
  /// `ReaderSettingsSheet` 的排版方向三態選擇器）請繼續用既有的整列
  /// 建構方式，不要用這個方法，見 epic-4 plan-issue-5.md Global
  /// Constraints「copyWith 語意」的說明。
  BookReaderPrefs copyWith({
    AppFont? fontFamily,
    double? fontSize,
    double? fontWeight,
    double? lineHeight,
    double? paragraphSpacing,
    double? pageMargins,
    EpubTextAlign? textAlign,
    bool? publisherStyles,
    WritingMode? writingModeOverride,
    PageTurnMode? pageTurnModeOverride,
    ScreenOrientationSetting? screenOrientationOverride,
    PdfFitMode? pdfFitMode,
    double? pdfContrast,
    double? pdfBrightness,
    double? pdfBoldStrength,
    PdfCropMode? pdfCropMode,
    PdfCropRect? pdfCropRect,
  }) {
    return BookReaderPrefs(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      pageMargins: pageMargins ?? this.pageMargins,
      textAlign: textAlign ?? this.textAlign,
      publisherStyles: publisherStyles ?? this.publisherStyles,
      writingModeOverride: writingModeOverride ?? this.writingModeOverride,
      pageTurnModeOverride: pageTurnModeOverride ?? this.pageTurnModeOverride,
      screenOrientationOverride:
          screenOrientationOverride ?? this.screenOrientationOverride,
      pdfFitMode: pdfFitMode ?? this.pdfFitMode,
      pdfContrast: pdfContrast ?? this.pdfContrast,
      pdfBrightness: pdfBrightness ?? this.pdfBrightness,
      pdfBoldStrength: pdfBoldStrength ?? this.pdfBoldStrength,
      pdfCropMode: pdfCropMode ?? this.pdfCropMode,
      pdfCropRect: pdfCropRect ?? this.pdfCropRect,
    );
  }
}
