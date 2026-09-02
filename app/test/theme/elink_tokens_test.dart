import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

const _base = ElinkTokens(
  highlightYellow: Color(0xFF111111),
  highlightGreen: Color(0xFF222222),
  highlightBlue: Color(0xFF333333),
  underlineColor: Color(0xFF444444),
  progressTrack: Color(0xFF555555),
  coverPlaceholder: Color(0xFF666666),
  badgeScrim: Color(0xFF777777),
  ttsActiveHighlight: Color(0xFF888888),
  isEink: false,
  reducedMotion: false,
  discretePaging: false,
);

void _expectAllFieldsEqual(ElinkTokens a, ElinkTokens b) {
  expect(a.highlightYellow, b.highlightYellow);
  expect(a.highlightGreen, b.highlightGreen);
  expect(a.highlightBlue, b.highlightBlue);
  expect(a.underlineColor, b.underlineColor);
  expect(a.progressTrack, b.progressTrack);
  expect(a.coverPlaceholder, b.coverPlaceholder);
  expect(a.badgeScrim, b.badgeScrim);
  expect(a.ttsActiveHighlight, b.ttsActiveHighlight);
  expect(a.isEink, b.isEink);
  expect(a.reducedMotion, b.reducedMotion);
  expect(a.discretePaging, b.discretePaging);
}

void main() {
  group('ElinkTokens.copyWith', () {
    test('不傳任何參數時，回傳的新實例所有欄位與原值相同', () {
      final copy = _base.copyWith();
      _expectAllFieldsEqual(copy, _base);
    });

    test('只覆寫單一 Color 欄位時，只有該欄位改變，其餘欄位維持原值', () {
      final copy = _base.copyWith(highlightYellow: const Color(0xFFAAAAAA));
      expect(copy.highlightYellow, const Color(0xFFAAAAAA));
      expect(copy.highlightGreen, _base.highlightGreen);
      expect(copy.highlightBlue, _base.highlightBlue);
      expect(copy.underlineColor, _base.underlineColor);
      expect(copy.progressTrack, _base.progressTrack);
      expect(copy.coverPlaceholder, _base.coverPlaceholder);
      expect(copy.badgeScrim, _base.badgeScrim);
      expect(copy.ttsActiveHighlight, _base.ttsActiveHighlight);
      expect(copy.isEink, _base.isEink);
      expect(copy.reducedMotion, _base.reducedMotion);
      expect(copy.discretePaging, _base.discretePaging);
    });

    test('只覆寫單一 bool 欄位時，只有該欄位改變，其餘欄位維持原值', () {
      final copy = _base.copyWith(isEink: true);
      expect(copy.isEink, true);
      expect(copy.reducedMotion, _base.reducedMotion);
      expect(copy.discretePaging, _base.discretePaging);
      expect(copy.highlightYellow, _base.highlightYellow);
    });

    test('同時覆寫多個欄位時，指定的欄位全部同時生效，其餘欄位不受影響', () {
      final copy = _base.copyWith(
        highlightBlue: const Color(0xFFBBBBBB),
        reducedMotion: true,
        badgeScrim: const Color(0xFFCCCCCC),
      );
      expect(copy.highlightBlue, const Color(0xFFBBBBBB));
      expect(copy.reducedMotion, true);
      expect(copy.badgeScrim, const Color(0xFFCCCCCC));
      // 沒指定的欄位維持原值
      expect(copy.highlightYellow, _base.highlightYellow);
      expect(copy.isEink, _base.isEink);
      expect(copy.discretePaging, _base.discretePaging);
    });
  });
}
