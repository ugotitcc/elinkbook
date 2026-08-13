import 'dart:math' as math;

/// EPUB 模擬分頁估算邏輯（epic-5-toc-pagination Issue 3，spec.md「分頁估算
/// 模組」；精準度優化見 epic-18-reader-device-qa Issue 46）：純 Dart、無
/// I/O，供 `ReaderScreen`／`TocBottomSheet` 依目前生效的版面參數＋全書
/// 字元數快取換算「估計總頁數」／「目前頁碼」，以及頁尾跳頁互動的反向換算
/// （目標頁碼→全書進度比例）。
///
/// 明確聲明：本模組產生的頁碼為模擬估算值，不保證與 foliate-js 實際渲染
/// 逐頁精確對齊（見 spec.md「分頁估算模組」）——`estimateCharsPerScreen()`
/// 用「CJK 全形字元近似正方形字格」的幾何模型換算（字格邊長＝字級 px），
/// 並非逐字量測真實 DOM 版面。
class EpubPageEstimator {
  const EpubPageEstimator._();

  /// 對應「fontSize 倍率 1.0」的基準字級（16px，見 `ReaderSettingsSheet`
  /// 既有慣例：`_toMultiplier(_fontSize, 16.0)`）。
  static const double baseFontSizePx = 16.0;

  /// 依目前生效的版面參數＋實際可視區域尺寸估算「每螢幕可容納字元數」
  /// （Issue 46 精準度優化：改用 CJK 全形字元近似正方形字格的幾何模型，
  /// 並納入真實螢幕尺寸與四邊邊距——舊版公式完全不吃螢幕尺寸這個輸入，
  /// 同一本書在手機與平板上會估出完全相同的頁碼，是既有精準度落差的
  /// 主因之一）。
  ///
  /// [screenWidth]／[screenHeight] 為可視區域邏輯像素尺寸（呼叫端傳入
  /// `MediaQuery.of(context).size`，見 `ReaderScreen._buildEpubFooter()`／
  /// `TocBottomSheet._buildEntryRow()` 呼叫慣例），為必要參數——本函式的
  /// 估算意義完全建立在真實可視尺寸之上，不提供「未知尺寸」的預設語意。
  ///
  /// [marginTop]／[marginBottom]／[marginLeft]／[marginRight] 為原始像素值
  /// （非倍率，與 `main.js` 的 `applyPreferences()` 直接使用的單位一致，
  /// 預設值 32/16/24/24 與 `ReaderSettingsSheet._defaultMarginTop` 等常數
  /// 一致）——取代舊版讀取的 `pageMargins`（單一倍率、四邊同步變動，見
  /// `book_reader_prefs.dart` 欄位註解「僅供 EpubReaderView／FXL 使用」，
  /// `EpubReaderView` 已於 `epic-20-fxl-foliate-migration` 完全移除，
  /// `pageMargins` 對目前唯一的 foliate-js 流式渲染路徑是死欄位、從未真正
  /// 影響過實際版面）。
  ///
  /// [lineHeight] 直接作為 CSS `line-height` 倍率使用（非舊版的「相對 1.5
  /// 正規化倍率」），預設值 1.0 與 `ReaderSettingsSheet._defaultLineHeight`
  /// 一致（舊版預設 1.5 是尚未隨 epic-18 Issue 25/26 產品預設值變動同步更新
  /// 的過期假設）。下限箝制為 0.8，與 `main.js` 實際渲染時套用的
  /// `Math.max(0.8, prefs.lineHeight)`（`main.js:99`，epic-18 Issue 25 新增）
  /// 一致——本函式先前箝制在 0.1，會讓使用者於滑桿選取 0.1~0.7 之間任一值時
  /// 估算出的每螢幕行數系統性偏多，與實際渲染結果脫勾（審查發現，
  /// 2026-08-11）。
  ///
  /// [letterSpacing]（epic-28-reader-settings-enhancements Issue 1）為 em
  /// 單位，對應 `main.js` 的 `letter-spacing: Xem` CSS 覆蓋，`null` 與 `0`
  /// 皆代表不拉開字距。與 `lineHeight`／`paragraphSpacing` 同一類「版面
  /// 密度」變數，一併納入估算公式（審查發現，2026-08-14：Issue 1 原始
  /// 實作漏了這個參數，讓字距調整無法反映在頁碼估算上）。
  static int estimateCharsPerScreen({
    required double screenWidth,
    required double screenHeight,
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? letterSpacing,
    double? marginTop,
    double? marginBottom,
    double? marginLeft,
    double? marginRight,
  }) {
    // fontSize 若顯式傳入 0.0（而非 null），fontSizePx 會是 0，下方
    // charsPerLine 對 Infinity 呼叫 .floor() 會直接拋出 UnsupportedError；
    // 0.1 是避免除以零的下限，與 lineHeight 的既有防護是同一種失效模式
    // （審查發現，2026-08-11：兩者結構相同，此處先前漏了對稱防護）。
    final fontSizeFactor = math.max(0.1, fontSize ?? 1.0);
    final fontSizePx = fontSizeFactor * baseFontSizePx;
    // main.js 實際渲染時對 lineHeight 套用 Math.max(0.8, prefs.lineHeight)
    // （main.js:99，epic-18 Issue 25 新增，防止 CSS line-height 過小造成
    // 文字重疊不可讀）；此處箝制為相同的 0.8 下限，讓估算與實際渲染結果對齊
    // （審查發現，2026-08-11：先前箝制在 0.1，會讓行高 0.1~0.7 這段使用者
    // 可直接選取的區間估算失準）。
    final lineHeightFactor = math.max(0.8, lineHeight ?? 1.0);
    // paragraphSpacingFactor <= -9.0 時，下方 (1 + (paragraphSpacingFactor -
    // 1) * 0.1) 會歸零，adjusted 對 Infinity 呼叫 .round() 同樣會拋出
    // UnsupportedError；0.0 是合理下限（負值段落間距倍率沒有實際意義）。
    final paragraphSpacingFactor = math.max(0.0, paragraphSpacing ?? 1.0);
    // epic-28-reader-settings-enhancements Issue 1 審查發現：新增字距選項後
    // 本函式原本完全沒有納入這個版面密度變數，與 lineHeight／paragraphSpacing
    // 等既有欄位不一致。letterSpacing 為 em 單位（1em = fontSizePx），每字元
    // 的有效寬度 = fontSizePx * (1 + letterSpacingFactor)——沿用「CJK 全形
    // 字元近似正方形字格」模型，字距視為每個字格額外拉開的寬度。下限箝制
    // 為 0.1（與 fontSizeFactor 同一種除以零防呆邏輯），UI 滑桿範圍
    // -0.05~1 本身不會觸及這個下限，純粹是防禦極端輸入。
    final letterSpacingFactor = math.max(0.1, 1 + (letterSpacing ?? 0.0));

    final topPx = marginTop ?? 32.0;
    final bottomPx = marginBottom ?? 16.0;
    final leftPx = marginLeft ?? 24.0;
    final rightPx = marginRight ?? 24.0;

    // 可視內容區域至少保留一個字格的寬高，避免邊距設定超過螢幕尺寸時
    // availableWidth/Height 變成負值。
    final availableWidth =
        math.max(fontSizePx, screenWidth - leftPx - rightPx);
    final availableHeight =
        math.max(fontSizePx, screenHeight - topPx - bottomPx);

    final lineHeightPx = fontSizePx * lineHeightFactor;
    final effectiveCharWidthPx = fontSizePx * letterSpacingFactor;
    final charsPerLine = (availableWidth / effectiveCharWidthPx).floor();
    final linesPerScreen = (availableHeight / lineHeightPx).floor();
    final baseChars = charsPerLine * linesPerScreen;

    // 段落間距對可視面積的實際影響取決於書本本身的段落密度（未知），沿用
    // 既有「低權重整體壓縮」精神，只是套用對象改成幾何算出的 baseChars，
    // 而非舊版的整體 areaFactor（見 Global Constraints）。
    final adjusted =
        (baseChars / (1 + (paragraphSpacingFactor - 1) * 0.1)).round();

    // 防呆下限/上限，避免極端版面設定（例如字體縮到最小、或邊距設定
    // 荒謬）估算出不合理的總頁數。上限自舊版的 2000（`referenceCharsPerScreen
    // * 4`）大幅提高至 20000——舊上限是針對「忽略螢幕尺寸」的舊公式校準，
    // 納入真實螢幕尺寸後，大尺寸平板/桌面在小字級下的合理值本就會遠超過
    // 2000（見本檔案對應測試「screenWidth/Height 加倍」案例）。
    return adjusted.clamp(50, 20000);
  }

  /// 依全書字元數快取與每螢幕可容納字元數換算估計總頁數，至少 1 頁。
  static int estimateTotalPages({
    required int totalCharacterCount,
    required int charsPerScreen,
  }) {
    if (totalCharacterCount <= 0) return 1;
    if (charsPerScreen <= 0) return 1;
    return math.max(1, (totalCharacterCount / charsPerScreen).ceil());
  }

  /// 依 Readium 提供的全書閱讀進度比例（[progression]，來自
  /// `EpubPositionInfo.progression`，可能為 `null`——見 `onLocatorChanged`
  /// 的既有 null 語意）換算目前頁碼，箝制在 `[1, totalPages]` 範圍內。
  static int estimateCurrentPage({
    required double? progression,
    required int totalPages,
  }) {
    if (progression == null) return 1;
    final page = (progression * totalPages).round();
    return page.clamp(1, totalPages);
  }

  /// [estimateCurrentPage] 的反向換算：使用者在頁尾輸入/拖曳指定
  /// [targetPage]（1-indexed）時，換算成供原生端跳轉用的全書進度比例
  /// （頁面區間中點，即 `(targetPage - 0.5) / totalPages`，與
  /// [estimateCurrentPage] 的四捨五入語意互為反函式）。
  static double estimateProgression({
    required int targetPage,
    required int totalPages,
  }) {
    if (totalPages <= 0) return 0.0;
    final progression = (targetPage - 0.5) / totalPages;
    return progression.clamp(0.0, 1.0);
  }
}
