import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/highlight_style.dart';

// ignore_for_file: deprecated_member_use

void main() {
  test('highlighterYellow/Pink/Blue 回傳各自固定色票，忽略 primaryColor', () {
    const arbitraryPrimary = Color(0xFF000000);
    expect(
      highlightStyleTint(HighlightStyle.highlighterYellow, primaryColor: arbitraryPrimary),
      highlighterYellowTint.value,
    );
    expect(
      highlightStyleTint(HighlightStyle.highlighterPink, primaryColor: arbitraryPrimary),
      highlighterPinkTint.value,
    );
    expect(
      highlightStyleTint(HighlightStyle.highlighterBlue, primaryColor: arbitraryPrimary),
      highlighterBlueTint.value,
    );
  });

  test('underline 回傳呼叫端傳入的 primaryColor（design.md 決策 #5：不提供顏色選擇）', () {
    const primary = Color(0xFF123456);
    expect(
      highlightStyleTint(HighlightStyle.underline, primaryColor: primary),
      primary.value,
    );
  });

  test('HighlightStyle.fixedTint：螢光筆三色為對應色票，underline 為 null（審查修正）', () {
    expect(HighlightStyle.highlighterYellow.fixedTint, highlighterYellowTint);
    expect(HighlightStyle.highlighterPink.fixedTint, highlighterPinkTint);
    expect(HighlightStyle.highlighterBlue.fixedTint, highlighterBlueTint);
    expect(HighlightStyle.underline.fixedTint, isNull);
  });
}
