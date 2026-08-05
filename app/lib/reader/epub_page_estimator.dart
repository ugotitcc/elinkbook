import 'dart:math' as math;

/// EPUB 模擬分頁估算邏輯（epic-5-toc-pagination Issue 3，spec.md「分頁估算
/// 模組」）：純 Dart、無 I/O，供 `ReaderScreen` 依目前生效的版面參數＋全書
/// 字元數快取換算「估計總頁數」／「目前頁碼」，以及頁尾跳頁互動的反向換算
/// （目標頁碼→全書進度比例）。
///
/// 明確聲明：本模組產生的頁碼為模擬估算值，不保證與 Readium 實際渲染逐頁
/// 精確對齊（見 spec.md「分頁估算模組」）。
class EpubPageEstimator {
  const EpubPageEstimator._();

  /// 對應「預設版面參數」（fontSize 倍率 1.0＝16px／lineHeight 1.5／
  /// paragraphSpacing 倍率 1.0＝10px／pageMargins 倍率 1.0＝15px，見
  /// `ReaderSettingsSheet` 的既有預設值）下，估計一螢幕可容納的字元數。
  /// 比照 TXT 引擎「固定字元數量分頁換算」啟發式的既有精神（見
  /// CLAUDE.md「支援格式與渲染方式」）。
  static const int referenceCharsPerScreen = 500;

  /// 依目前生效的版面參數估算「每螢幕可容納字元數」。`null` 代表該欄位
  /// 未被使用者覆寫（見 `ResolvedPreferences` 的既有 null 語意），套用與
  /// `ReaderSettingsSheet` 一致的預設值。字體越大／行距越高／段落間距與
  /// 邊距越寬，可視面積內能容納的字元數越少。
  static int estimateCharsPerScreen({
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? pageMargins,
  }) {
    final fontSizeFactor = fontSize ?? 1.0;
    // epic-18-reader-device-qa Issue 25 把行高滑桿範圍下限改為 0 後，
    // lineHeight 可能真的是 0.0——若不設下限，lineHeightFactor 會是 0、
    // areaFactor 隨之為 0，下面的 (referenceCharsPerScreen / areaFactor)
    // 會得到 double.infinity，對 Infinity 呼叫 .round() 在 Dart 會直接
    // 拋出 UnsupportedError（審查發現，2026-08-05）。0.1 只是避免除以零
    // 的下限，不代表這是「合理」的行高——即使套用這個下限，算出的
    // charsPerScreen 之後仍會被下面既有的 clamp(50, referenceCharsPerScreen
    // * 4) 收斂到同一個上限，不需要更精確的下限值。
    final lineHeightFactor = math.max(0.1, lineHeight ?? 1.5) / 1.5;
    final paragraphSpacingFactor = paragraphSpacing ?? 1.0;
    final pageMarginsFactor = pageMargins ?? 1.0;

    // 字體大小同時影響每行字數與可視行數（面積效應），故取平方項；行距為
    // 單一維度線性效應；段落間距／邊距對整體可視面積的影響較小，以較低
    // 權重（0.1／0.2）線性調整，避免這兩者把估算值推向不合理的極端。
    final areaFactor = fontSizeFactor *
        fontSizeFactor *
        lineHeightFactor *
        (1 + (paragraphSpacingFactor - 1) * 0.1) *
        (1 + (pageMarginsFactor - 1) * 0.2);

    final estimated = (referenceCharsPerScreen / areaFactor).round();
    // 防呆下限/上限，避免極端版面設定（例如字體縮到最小）估算出不合理的
    // 總頁數（例如一本 10 萬字的書被估成上萬頁）。
    return estimated.clamp(50, referenceCharsPerScreen * 4);
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
