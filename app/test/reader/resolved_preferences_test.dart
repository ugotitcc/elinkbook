import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_page_turn_mode.dart';
import 'package:elinkbook/reader/resolved_preferences.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';

void main() {
  test('建構後各欄位保留傳入值，columnMode 預設 auto、columnSize 預設 720.0', () {
    const resolved = ResolvedPreferences(
      writingMode: null,
      fontFamily: null,
      fontSize: null,
      fontWeight: null,
      lineHeight: null,
      paragraphSpacing: null,
      pageMargins: null,
      textAlign: null,
      publisherStyles: null,
      pageTurnMode: PageTurnMode.paginated,
      screenOrientation: ScreenOrientationSetting.auto,
      pdfFitMode: PdfFitMode.pageFit,
      pdfContrast: 0,
      pdfBrightness: 0,
      pdfBoldStrength: 0,
      pdfCropMode: PdfCropMode.none,
      pdfCropRect: null,
      dualPageMode: DualPageMode.auto,
      dualPageCoverAlone: true,
      dualPageDirection: DualPageDirection.ltr,
      showHeader: true,
      showFooter: true,
      navZoneActions: rightFlipZoneTemplate,
      showNavZoneDebugOverlay: false,
    );

    expect(resolved.fontSize, isNull);
    expect(resolved.textAlign, isNull);
    expect(resolved.columnMode, ColumnMode.auto);
    expect(resolved.columnSize, 720.0);
    expect(resolved.pageTurnMode, PageTurnMode.paginated);
    expect(resolved.pdfFitMode, PdfFitMode.pageFit);
    expect(resolved.dualPageMode, DualPageMode.auto);
    expect(resolved.dualPageCoverAlone, isTrue);
    expect(resolved.dualPageDirection, DualPageDirection.ltr);
    expect(resolved.navZoneActions, rightFlipZoneTemplate);
    expect(resolved.showNavZoneDebugOverlay, isFalse);
    expect(resolved.pdfPageTurnMode, PdfPageTurnMode.paginated);
  });

  test('volumeKeyEnabled 未傳入時預設 true', () {
    const resolved = ResolvedPreferences(
      pageTurnMode: PageTurnMode.paginated,
      screenOrientation: ScreenOrientationSetting.auto,
      pdfFitMode: PdfFitMode.pageFit,
      pdfContrast: 0,
      pdfBrightness: 0,
      pdfBoldStrength: 0,
      pdfCropMode: PdfCropMode.none,
      dualPageMode: DualPageMode.auto,
      dualPageCoverAlone: true,
      dualPageDirection: DualPageDirection.ltr,
      showHeader: true,
      showFooter: true,
      navZoneActions: rightFlipZoneTemplate,
      showNavZoneDebugOverlay: false,
    );
    expect(resolved.volumeKeyEnabled, isTrue);
  });
}
