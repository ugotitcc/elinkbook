import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
import 'package:elinkbook/reader/pdf_page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:flutter_test/flutter_test.dart';

/// 33 個欄位全部填滿的 [BookReaderPrefs]（Issue 10「整列重建全欄位保留守衛」）。
///
/// 每個值都刻意取「與各面板預設值不同」的選項（例如 publisherStyles 預設
/// true 這裡是 false、columnMode 預設 auto 這裡是 double），這樣「漏帶後被
/// 重設成預設」也會被抓到，不會因為剛好等於預設值而漏判。
///
/// 數值也要能被 ReaderSettingsSheet 的滑桿換算無損來回：fontSize 1.5
/// （×16＝24，再 ÷16 回 1.5）、paragraphSpacing 1.2（×10＝12，再 ÷10 回 1.2）。
///
/// 新增 [BookReaderPrefs] 欄位時必須同步補進這裡，否則 book_reader_prefs_test
/// 的「種子自檢」會失敗。
const fullBookReaderPrefsSeed = BookReaderPrefs(
  fontFamily: 'SourceHanSerifTC',
  fontSize: 1.5,
  fontWeight: 1.25,
  lineHeight: 1.8,
  paragraphSpacing: 1.2,
  letterSpacing: 0.05,
  pageMargins: 20,
  marginTop: 40,
  marginBottom: 20,
  marginLeft: 28,
  marginRight: 28,
  textAlign: EpubTextAlign.justify,
  publisherStyles: false,
  writingModeOverride: WritingMode.vertical,
  pageTurnModeOverride: PageTurnMode.paginated,
  screenOrientationOverride: ScreenOrientationSetting.lock90,
  pdfFitMode: PdfFitMode.fitWidth,
  pdfContrast: 20,
  pdfBrightness: -10,
  pdfBoldStrength: 0.5,
  pdfCropMode: PdfCropMode.manual,
  pdfCropRect: PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
  dualPageMode: DualPageMode.always,
  dualPageCoverAlone: false,
  dualPageDirection: DualPageDirection.ltr,
  pdfPageTurnAnimation: PdfPageTurnAnimation.none,
  pdfPageTurnMode: PdfPageTurnMode.scroll,
  showHeader: true,
  showFooter: true,
  columnMode: ColumnMode.double,
  columnSize: 800,
  fullscreen: true,
  textConversionOverride: TextConversionMode.toTraditional,
);

/// 逐欄位比對 [actual] 與 [expected]，只有 [except] 內的欄位（`toMap()` 的
/// 欄位名，snake_case）允許不同；其他欄位只要有一個不同就失敗，並在訊息列出
/// 欄位名與前後值。
///
/// 用 `toMap()` 比對而不是整物件 `==`：整物件不相等時看不出是哪個欄位被丟。
void expectPrefsPreserved(
  BookReaderPrefs? actual,
  BookReaderPrefs expected, {
  Set<String> except = const {},
}) {
  // actual 接受 nullable：呼叫端多半是 onChanged 的捕捉變數，Dart 不會因為
  // expect(x, isNotNull) 而收窄型別，統一在這裡檢查比較不易漏。
  expect(actual, isNotNull, reason: 'onChanged／儲存庫沒有收到任何 prefs');
  final actualMap = actual!.toMap('b');
  final expectedMap = expected.toMap('b');
  // 防假陽性：except 寫錯欄位名會讓比對默默放行。
  expect(
    expectedMap.keys,
    containsAll(except),
    reason: 'except 內有不存在於 toMap() 的欄位名',
  );
  final diffs = <String>[
    for (final key in expectedMap.keys)
      if (!except.contains(key) && actualMap[key] != expectedMap[key])
        '$key：預期 ${expectedMap[key]}，實際 ${actualMap[key]}',
  ];
  expect(
    diffs,
    isEmpty,
    reason: '下列欄位被改動或清空（整列重建漏帶欄位）：\n${diffs.join('\n')}',
  );
}
