// app/test/dictionary/lookup_text_normalizer_test.dart
import 'package:elinkbook/dictionary/lookup_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

NormalizedSelection _ok(String raw) {
  final r = normalizeLookupSelection(raw);
  expect(r, isA<NormalizedSelection>(), reason: '「$raw」應通過');
  return r as NormalizedSelection;
}

void _rejected(String raw, SelectionProblem problem) {
  final r = normalizeLookupSelection(raw);
  expect(r, isA<RejectedSelection>(), reason: '「$raw」應被拒絕');
  expect((r as RejectedSelection).problem, problem, reason: raw);
}

void main() {
  test('去頭尾標點：「相濡以沫」與《紅樓夢》', () {
    final a = _ok('「相濡以沫」');
    expect(a.text, '相濡以沫');
    expect(a.charType, SelectionCharType.cjk);
    final b = _ok('《紅樓夢》');
    expect(b.text, '紅樓夢');
    expect(b.charType, SelectionCharType.cjk);
  });

  test('去頭尾空白與換行', () {
    expect(_ok('  \n run \t').text, 'run');
  });

  test('內部標點：天地，玄黃 回傳 invalidSelection', () {
    _rejected('天地，玄黃', SelectionProblem.invalidSelection);
  });

  test('連字號與撇號：state-of-the-art、don\'t、don’t 通過', () {
    expect(_ok('state-of-the-art').text, 'state-of-the-art');
    expect(_ok("don't").text, "don't");
    expect(_ok('don’t').text, 'don’t');
  });

  test('含空白的片語允許內部標點，整串通過', () {
    expect(_ok('Hello, world').text, 'Hello, world');
  });

  test('跨行選取的片語整理成單一空白', () {
    expect(_ok('kick  the\nbucket').text, 'kick the bucket');
  });

  test('CJK 8 字通過，9 字 tooLong', () {
    expect(_ok('一二三四五六七八').text, '一二三四五六七八');
    _rejected('一二三四五六七八九', SelectionProblem.tooLong);
  });

  test('含空白的片語不受 8 字限制', () {
    final phrase = 'a bcdefghijklmnopqrs';
    expect(phrase.length, 20);
    expect(_ok(phrase).text, phrase);
  });

  test('標點檢查先於長度檢查', () {
    _rejected('一二三四五，六七八九', SelectionProblem.invalidSelection);
  });

  test('空字串與純標點、純空白回傳 invalidSelection', () {
    _rejected('', SelectionProblem.invalidSelection);
    _rejected('「」', SelectionProblem.invalidSelection);
    _rejected(' \n\t ', SelectionProblem.invalidSelection);
    _rejected('...', SelectionProblem.invalidSelection);
  });

  test('混合文字的 CJK 長度算整串字元數', () {
    final a = _ok('iPhone手機');
    expect(a.charType, SelectionCharType.mixed);
    _rejected('iPhone手機手機手機', SelectionProblem.tooLong);
  });

  test('內部有連字號但含 CJK 時不放行', () {
    _rejected('相濡-以沫', SelectionProblem.invalidSelection);
  });

  test('detectCharType：拉丁、CJK、混合、純數字', () {
    expect(detectCharType('apple'), SelectionCharType.latin);
    expect(detectCharType('蘋果'), SelectionCharType.cjk);
    expect(detectCharType('iPhone手機'), SelectionCharType.mixed);
    expect(detectCharType('123'), SelectionCharType.latin);
  });

  test('帶重音的拉丁字母算拉丁', () {
    expect(_ok('café').charType, SelectionCharType.latin);
  });

  test('擴展 B 區的漢字算 CJK', () {
    expect(detectCharType('𠀀'), SelectionCharType.cjk);
  });
}
