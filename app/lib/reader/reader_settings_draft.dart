import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';

/// 「值＋是否已覆寫」成對欄位的值物件。
///
/// [value] 的意義依欄位而異：字級、段距是 UI 刻度（草稿內與儲存倍率換算，
/// 16／10 的倍數）；字重（倍率，UI 的 ×400 在面板）、行距、字距的 [value]
/// 就是儲存值，草稿不換算。
/// 未覆寫時以 [defaultValue] 作為滑桿初始位置，且輸出 [BookReaderPrefs]
/// 時對應欄位會維持 `null`。
class OverridableValue {
  /// 建立一個可覆寫數值欄位。
  ///
  /// 若傳入非 `null` 的 [initial]，則 [value] 為 [initial] 且 [overridden]
  /// 為 `true`；否則 [value] 為 [defaultValue] 且 [overridden] 為 `false`。
  OverridableValue({required this.defaultValue, double? initial})
    : value = initial ?? defaultValue,
      overridden = initial != null;

  /// 未覆寫時的預設 UI 刻度值。
  final double defaultValue;

  /// 目前的 UI 刻度值。
  double value;

  /// 是否已由使用者覆寫（`true` 時輸出不為 `null`）。
  bool overridden;

  /// 設定新值 [v] 並標記為已覆寫。
  void set(double v) {
    value = v;
    overridden = true;
  }

  /// 重設為 [defaultValue] 並取消覆寫標記。
  void reset() {
    value = defaultValue;
    overridden = false;
  }
}

/// 流式閱讀版面設定面板的純 Dart 可變草稿模型。
///
/// 封裝 `ReaderSettingsSheet` 所需的 23 個流式欄位狀態、預設值具現化、
/// 儲存倍率與 UI 刻度之間的雙向換算，以及「恢復書籍預設文字樣式」邏輯。
class ReaderSettingsDraft {
  /// 從持久化的 [BookReaderPrefs] 建立設定草稿。
  ///
  /// 未覆寫的 `OverridableValue` 欄位會以預設值具現化供滑桿顯示，
  /// 並記錄其 `overridden` 狀態；非流式欄位不會進入草稿。
  ReaderSettingsDraft.fromPrefs(BookReaderPrefs prefs)
    : fontFamily = prefs.fontFamily,
      headingFontFamily = prefs.headingFontFamily,
      fontSize = OverridableValue(
        defaultValue: defaultFontSize,
        initial: prefs.fontSize != null
            ? (prefs.fontSize! * 16.0).roundToDouble()
            : null,
      ),
      fontWeight = OverridableValue(
        defaultValue: defaultFontWeight,
        initial: prefs.fontWeight,
      ),
      lineHeight = OverridableValue(
        defaultValue: defaultLineHeight,
        initial: prefs.lineHeight,
      ),
      paragraphSpacing = OverridableValue(
        defaultValue: defaultParagraphSpacing,
        initial: prefs.paragraphSpacing != null
            ? (prefs.paragraphSpacing! * 10.0).roundToDouble()
            : null,
      ),
      firstLineIndent = prefs.firstLineIndent ?? defaultFirstLineIndent,
      firstLineIndentOn = prefs.firstLineIndent != null,
      letterSpacing = OverridableValue(
        defaultValue: defaultLetterSpacing,
        initial: prefs.letterSpacing,
      ),
      marginTop = prefs.marginTop ?? defaultMarginTop,
      marginBottom = prefs.marginBottom ?? defaultMarginBottom,
      marginLeft = prefs.marginLeft ?? defaultMarginLeft,
      marginRight = prefs.marginRight ?? defaultMarginRight,
      textAlign = prefs.textAlign,
      publisherStyles = prefs.publisherStyles ?? true,
      writingModeOverride = prefs.writingModeOverride,
      pageTurnModeOverride = prefs.pageTurnModeOverride,
      screenOrientationOverride = prefs.screenOrientationOverride,
      textConversionOverride = prefs.textConversionOverride,
      showHeader = prefs.showHeader ?? false,
      showFooter = prefs.showFooter ?? false,
      fullscreen = prefs.fullscreen ?? false,
      columnMode = prefs.columnMode ?? ColumnMode.auto,
      columnSize = prefs.columnSize ?? defaultColumnSize;

  /// 尚未有持久化覆寫時，字級滑桿顯示的初始刻度。
  static const double defaultFontSize = 16.0;

  /// 尚未有持久化覆寫時，字重倍率的初始值（UI 顯示為 `1.0 × 400 = 400`）。
  static const double defaultFontWeight = 1.0;

  /// 尚未有持久化覆寫時，行距滑桿顯示的初始值。
  static const double defaultLineHeight = 1.0;

  /// 尚未有持久化覆寫時，段距滑桿顯示的初始刻度。
  static const double defaultParagraphSpacing = 10.0;

  /// 尚未開啟首行縮排時的預設字數。
  static const double defaultFirstLineIndent = 2.0;

  /// 尚未有持久化覆寫時，字距滑桿顯示的初始值。
  static const double defaultLetterSpacing = 0.0;

  /// 尚未設定上邊距時的預設值。
  static const double defaultMarginTop = 32.0;

  /// 尚未設定下邊距時的預設值。
  static const double defaultMarginBottom = 16.0;

  /// 尚未設定左邊距時的預設值。
  static const double defaultMarginLeft = 24.0;

  /// 尚未設定右邊距時的預設值。
  static const double defaultMarginRight = 24.0;

  /// 尚未設定雙欄切換寬度閾值時的預設值。
  static const double defaultColumnSize = 720.0;

  /// 內文字型；`null` 表示跟隨書本。
  String? fontFamily;

  /// 標題字型；`null` 表示跟隨主字型。
  String? headingFontFamily;

  /// 字級（UI 刻度，儲存倍率 ×16）。
  final OverridableValue fontSize;

  /// 字重倍率（預設 1.0；UI 的 ×400 在面板，不在草稿）。
  final OverridableValue fontWeight;

  /// 行距（儲存值，不換算）。
  final OverridableValue lineHeight;

  /// 段距（UI 刻度，儲存倍率 ×10）。
  final OverridableValue paragraphSpacing;

  /// 首行縮排字數；關閉時仍保留數字，重新開啟可沿用。
  double firstLineIndent;

  /// 首行縮排是否開啟（`0` 也算開啟）。
  bool firstLineIndentOn;

  /// 字距（儲存值，不換算）。
  final OverridableValue letterSpacing;

  /// 上邊距。
  double marginTop;

  /// 下邊距。
  double marginBottom;

  /// 左邊距。
  double marginLeft;

  /// 右邊距。
  double marginRight;

  /// 文字對齊；`null` 表示跟隨書本。
  EpubTextAlign? textAlign;

  /// 是否套用出版社樣式（書本 CSS）。
  bool publisherStyles;

  /// 書寫方向覆寫；`null` 表示自動偵測。
  WritingMode? writingModeOverride;

  /// 翻頁模式覆寫；`null` 表示跟隨全域設定。
  PageTurnMode? pageTurnModeOverride;

  /// 螢幕方向覆寫；`null` 表示跟隨全域設定。
  ScreenOrientationSetting? screenOrientationOverride;

  /// 繁簡轉換覆寫；`null` 表示跟隨全域設定。
  TextConversionMode? textConversionOverride;

  /// 是否顯示頁首。
  bool showHeader;

  /// 是否顯示頁尾。
  bool showFooter;

  /// 是否全螢幕。
  bool fullscreen;

  /// 分欄模式。
  ColumnMode columnMode;

  /// 自動分欄的寬度閾值。
  double columnSize;

  static double _toMultiplier(double value, double base) {
    return ((value / base) * 10000).round() / 10000;
  }

  /// 6 個文字樣式欄位（5 個 `OverridableValue` 與首行縮排）是否皆處於未覆寫狀態。
  bool get isBookDefaultTextStyle =>
      !fontSize.overridden &&
      !fontWeight.overridden &&
      !lineHeight.overridden &&
      !paragraphSpacing.overridden &&
      !firstLineIndentOn &&
      !letterSpacing.overridden;

  /// 只將 6 個文字樣式欄位恢復為書籍預設（未覆寫），不動字型、邊距、對齊等其他設定。
  void resetToBookDefault() {
    fontSize.reset();
    fontWeight.reset();
    lineHeight.reset();
    paragraphSpacing.reset();
    firstLineIndentOn = false;
    firstLineIndent = defaultFirstLineIndent;
    letterSpacing.reset();
  }

  /// 將目前草稿轉換為只含 23 個流式欄位的 [BookReaderPrefs]。
  ///
  /// **epic-28-reader-settings-enhancements Issue 4 審查回應**：這裡回傳的
  /// `null`（未覆寫）不只影響本書畫面即時渲染，也會被「另存為新預設集」／
  /// 「複製到其他書籍」原封不動存進 `LayoutPreset`／寫進目標書籍——
  /// `BookReaderPrefsRepository.save()`／`saveMultiple()` 是「整列覆寫」語意
  /// （`INSERT OR REPLACE`，見該檔案 class doc），並非逐欄位合併。因此：
  /// 使用者若存一個只調整過部分欄位的預設集，套用到另一本已有自訂覆寫值的
  /// 書籍時，本欄位若仍是未覆寫狀態，會把目標書籍對應欄位一併清空回該書
  /// 自己的原生樣式，不是只套用預設集裡「有值」的那幾項。這是「整列覆寫」
  /// 既有設計（Epic 28 Issue 3 上線時就如此）與未觸碰欄位正確維持 `null`
  /// 疊加後的預期結果，不是缺陷——比修復前「未觸碰欄位一律凍結成當時滑桿
  /// 顯示的預設數字」更符合直覺，但屬於容易被誤判為回歸的跨 Issue 行為，
  /// 記錄於此供日後排查參考。
  BookReaderPrefs toPrefs() {
    return BookReaderPrefs(
      fontFamily: fontFamily,
      headingFontFamily: headingFontFamily,
      fontSize: fontSize.overridden ? _toMultiplier(fontSize.value, 16.0) : null,
      fontWeight: fontWeight.overridden ? fontWeight.value : null,
      lineHeight: lineHeight.overridden ? lineHeight.value : null,
      paragraphSpacing: paragraphSpacing.overridden
          ? _toMultiplier(paragraphSpacing.value, 10.0)
          : null,
      firstLineIndent: firstLineIndentOn ? firstLineIndent : null,
      letterSpacing: letterSpacing.overridden ? letterSpacing.value : null,
      marginTop: marginTop,
      marginBottom: marginBottom,
      marginLeft: marginLeft,
      marginRight: marginRight,
      textAlign: textAlign,
      publisherStyles: publisherStyles,
      writingModeOverride: writingModeOverride,
      pageTurnModeOverride: pageTurnModeOverride,
      screenOrientationOverride: screenOrientationOverride,
      textConversionOverride: textConversionOverride,
      showHeader: showHeader,
      showFooter: showFooter,
      fullscreen: fullscreen,
      columnMode: columnMode,
      columnSize: columnSize,
    );
  }
}
