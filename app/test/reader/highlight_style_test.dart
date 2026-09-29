import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

void main() {
  const tokens = ElinkTokens(
    highlightYellow: Color(0xFFFEF08A),
    highlightGreen: Color(0xFFBBF7D0),
    highlightBlue: Color(0xFFBFDBFE),
    underlineColor: Color(0xFF0284C7),
    progressTrack: Color(0xFFCBDFE9),
    coverPlaceholder: Color(0xFFE6F1FA),
    badgeScrim: Color(0xFF94A3B8),
    ttsActiveHighlight: Color(0xFFE0F2FE),
    heatmapLevel0: Color(0xFFEAF1F5),
    heatmapLevel1: Color(0xFFBAE6FD),
    heatmapLevel2: Color(0xFF7DD3FC),
    heatmapLevel3: Color(0xFF38BDF8),
    heatmapLevel4: Color(0xFF0284C7),
    isEink: false,
    reducedMotion: false,
    discretePaging: false,
  );

  test('highlightStyleColor()：四個樣式各自對應正確的 ElinkTokens 欄位', () {
    expect(
      highlightStyleColor(HighlightStyle.highlighterYellow, tokens: tokens),
      tokens.highlightYellow,
    );
    expect(
      highlightStyleColor(HighlightStyle.highlighterPink, tokens: tokens),
      tokens.highlightGreen,
      reason: 'highlighterPink 語意變更為綠色，DESIGN.md §1.2 既有決策',
    );
    expect(
      highlightStyleColor(HighlightStyle.highlighterBlue, tokens: tokens),
      tokens.highlightBlue,
    );
    expect(
      highlightStyleColor(HighlightStyle.underline, tokens: tokens),
      tokens.underlineColor,
    );
  });

  test('HighlightStyle 列舉成員名稱維持不變（Enum.values.byName() 持久化相容性）', () {
    expect(
      HighlightStyle.values.map((e) => e.name).toList(),
      ['highlighterYellow', 'highlighterPink', 'highlighterBlue', 'underline'],
    );
  });
}
