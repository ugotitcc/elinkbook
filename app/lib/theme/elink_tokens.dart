import 'package:flutter/material.dart';

/// 依 `DESIGN.md` §1.2 定案的語意色 Token，透過
/// `Theme.of(context).extension<ElinkTokens>()` 存取，取代畫面各自寫死顏色。
/// 各欄位在四套主題（晴空藍天／夜讀水墨／宣紙古風／E-Ink）下的實際色值，由
/// `app_theme_data.dart` 的 `resolveThemeData()` 組裝並掛進
/// `ThemeData.extensions`（見 `epic-35-design-system-tokens` Issue 2）；本檔案
/// 只定義型別本身，此時尚未被任何主題實際使用。
class ElinkTokens extends ThemeExtension<ElinkTokens> {
  final Color highlightYellow;
  // 取代舊有 highlighterPinkTint，語意色由粉紅改綠（DESIGN.md §1.2 既有決策，
  // 見 epic-35 spec.md「既有語意色遷移到 ElinkTokens」）。
  final Color highlightGreen;
  final Color highlightBlue;
  final Color underlineColor;
  final Color progressTrack;
  final Color coverPlaceholder;
  final Color badgeScrim;
  final Color ttsActiveHighlight;

  /// 是否為 E-Ink 高對比模式。
  final bool isEink;

  /// 是否簡化動態效果（E-Ink 下為 true）。
  final bool reducedMotion;

  /// 是否採離散換頁（E-Ink 下為 true）。
  final bool discretePaging;

  const ElinkTokens({
    required this.highlightYellow,
    required this.highlightGreen,
    required this.highlightBlue,
    required this.underlineColor,
    required this.progressTrack,
    required this.coverPlaceholder,
    required this.badgeScrim,
    required this.ttsActiveHighlight,
    required this.isEink,
    required this.reducedMotion,
    required this.discretePaging,
  });

  @override
  ElinkTokens copyWith({
    Color? highlightYellow,
    Color? highlightGreen,
    Color? highlightBlue,
    Color? underlineColor,
    Color? progressTrack,
    Color? coverPlaceholder,
    Color? badgeScrim,
    Color? ttsActiveHighlight,
    bool? isEink,
    bool? reducedMotion,
    bool? discretePaging,
  }) {
    return ElinkTokens(
      highlightYellow: highlightYellow ?? this.highlightYellow,
      highlightGreen: highlightGreen ?? this.highlightGreen,
      highlightBlue: highlightBlue ?? this.highlightBlue,
      underlineColor: underlineColor ?? this.underlineColor,
      progressTrack: progressTrack ?? this.progressTrack,
      coverPlaceholder: coverPlaceholder ?? this.coverPlaceholder,
      badgeScrim: badgeScrim ?? this.badgeScrim,
      ttsActiveHighlight: ttsActiveHighlight ?? this.ttsActiveHighlight,
      isEink: isEink ?? this.isEink,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      discretePaging: discretePaging ?? this.discretePaging,
    );
  }

  @override
  ElinkTokens lerp(ThemeExtension<ElinkTokens>? other, double t) {
    if (other is! ElinkTokens) return this;
    return ElinkTokens(
      highlightYellow: Color.lerp(highlightYellow, other.highlightYellow, t)!,
      highlightGreen: Color.lerp(highlightGreen, other.highlightGreen, t)!,
      highlightBlue: Color.lerp(highlightBlue, other.highlightBlue, t)!,
      underlineColor: Color.lerp(underlineColor, other.underlineColor, t)!,
      progressTrack: Color.lerp(progressTrack, other.progressTrack, t)!,
      coverPlaceholder:
          Color.lerp(coverPlaceholder, other.coverPlaceholder, t)!,
      badgeScrim: Color.lerp(badgeScrim, other.badgeScrim, t)!,
      ttsActiveHighlight:
          Color.lerp(ttsActiveHighlight, other.ttsActiveHighlight, t)!,
      // bool 欄位沒有漸變意義，t < 0.5 取自己、t >= 0.5 取對方（離散跳變）。
      isEink: t < 0.5 ? isEink : other.isEink,
      reducedMotion: t < 0.5 ? reducedMotion : other.reducedMotion,
      discretePaging: t < 0.5 ? discretePaging : other.discretePaging,
    );
  }
}
