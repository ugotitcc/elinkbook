// app/test/dictionary/lookup_request_test.dart
import 'dart:io';

import 'package:elinkbook/dictionary/models/lookup_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('相同的詞視為相等', () {
    expect(const LookupRequest('run'), const LookupRequest('run'));
    expect(const LookupRequest('run'), isNot(const LookupRequest('ran')));
  });

  test('型別只有 word 一個欄位，防止日後加前後文欄位', () {
    // Dart 無法反射列舉欄位，所以用原始碼掃描守住這條隱私底線
    // （對應 spec §3.2：從型別上保證不可能把書中內容送出去）。
    // regex 只吃「恰好兩格縮排」：dart format 保證類別成員縮排兩格，
    // 方法內的區域變數至少四格，不會被誤算。
    final source =
        File('lib/dictionary/models/lookup_request.dart').readAsStringSync();
    final fieldCount =
        RegExp(r'^  (final|late|var)\s', multiLine: true).allMatches(source).length;
    expect(fieldCount, 1);
    expect(source, contains('final String word;'));
  });
}
