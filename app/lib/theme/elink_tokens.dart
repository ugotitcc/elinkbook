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

  /// 閱讀統計貢獻圖五級色階（epic-9-stats Issue 5，色值取自 `epic.md`
  /// Issue 1 原型定案表）：0 無紀錄、1 未滿 15 分、2 未滿 30 分、
  /// 3 未滿 60 分、4 六十分以上。E-Ink 下為階梯灰階；`Color` 無法表達紋理，
  /// 網點／斜線由貢獻圖元件自己的繪製邏輯疊加（見 `reading_heatmap.dart`）。
  final Color heatmapLevel0;
  final Color heatmapLevel1;
  final Color heatmapLevel2;
  final Color heatmapLevel3;
  final Color heatmapLevel4;

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
    required this.heatmapLevel0,
    required this.heatmapLevel1,
    required this.heatmapLevel2,
    required this.heatmapLevel3,
    required this.heatmapLevel4,
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
    Color? heatmapLevel0,
    Color? heatmapLevel1,
    Color? heatmapLevel2,
    Color? heatmapLevel3,
    Color? heatmapLevel4,
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
      heatmapLevel0: heatmapLevel0 ?? this.heatmapLevel0,
      heatmapLevel1: heatmapLevel1 ?? this.heatmapLevel1,
      heatmapLevel2: heatmapLevel2 ?? this.heatmapLevel2,
      heatmapLevel3: heatmapLevel3 ?? this.heatmapLevel3,
      heatmapLevel4: heatmapLevel4 ?? this.heatmapLevel4,
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
      heatmapLevel0: Color.lerp(heatmapLevel0, other.heatmapLevel0, t)!,
      heatmapLevel1: Color.lerp(heatmapLevel1, other.heatmapLevel1, t)!,
      heatmapLevel2: Color.lerp(heatmapLevel2, other.heatmapLevel2, t)!,
      heatmapLevel3: Color.lerp(heatmapLevel3, other.heatmapLevel3, t)!,
      heatmapLevel4: Color.lerp(heatmapLevel4, other.heatmapLevel4, t)!,
      // bool 欄位沒有漸變意義，t < 0.5 取自己、t >= 0.5 取對方（離散跳變）。
      isEink: t < 0.5 ? isEink : other.isEink,
      reducedMotion: t < 0.5 ? reducedMotion : other.reducedMotion,
      discretePaging: t < 0.5 ? discretePaging : other.discretePaging,
    );
  }

  /// 依貢獻圖級別（0–4）取對應色階；超出範圍拋 [RangeError]。
  Color heatmapLevelColor(int level) => [
        heatmapLevel0,
        heatmapLevel1,
        heatmapLevel2,
        heatmapLevel3,
        heatmapLevel4,
      ][level];
}
