import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/highlight_style.dart';

void main() {
  test('highlighterYellow/Pink/Blue 回傳各自固定色票，忽略 primaryColor', () {
    const arbitraryPrimary = Color(0xFF000000);
    expect(
      highlightStyleTint(HighlightStyle.highlighterYellow, primaryColor: arbitraryPrimary),
      highlighterYellowTint.toARGB32(),
    );
    expect(
      highlightStyleTint(HighlightStyle.highlighterPink, primaryColor: arbitraryPrimary),
      highlighterPinkTint.toARGB32(),
    );
    expect(
      highlightStyleTint(HighlightStyle.highlighterBlue, primaryColor: arbitraryPrimary),
      highlighterBlueTint.toARGB32(),
    );
  });

  test('underline 回傳呼叫端傳入的 primaryColor（design.md 決策 #5：不提供顏色選擇）', () {
    const primary = Color(0xFF123456);
    expect(
      highlightStyleTint(HighlightStyle.underline, primaryColor: primary),
      primary.toARGB32(),
    );
  });

  test('HighlightStyle.fixedTint：螢光筆三色為對應色票，underline 為 null（審查修正）', () {
    expect(HighlightStyle.highlighterYellow.fixedTint, highlighterYellowTint);
    expect(HighlightStyle.highlighterPink.fixedTint, highlighterPinkTint);
    expect(HighlightStyle.highlighterBlue.fixedTint, highlighterBlueTint);
    expect(HighlightStyle.underline.fixedTint, isNull);
  });
}
