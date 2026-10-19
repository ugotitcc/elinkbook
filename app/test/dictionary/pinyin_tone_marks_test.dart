// app/test/dictionary/pinyin_tone_marks_test.dart
import 'package:elinkbook/dictionary/pinyin_tone_marks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('聲調 1 至 4', () {
    expect(pinyinToneMarks('ma1'), 'mā');
    expect(pinyinToneMarks('ma2'), 'má');
    expect(pinyinToneMarks('ma3'), 'mǎ');
    expect(pinyinToneMarks('ma4'), 'mà');
  });

  test('聲調 5 與無數字為輕聲，不標', () {
    expect(pinyinToneMarks('ma5'), 'ma');
    expect(pinyinToneMarks('ma'), 'ma');
  });

  test('標調位置：a 或 e 優先', () {
    expect(pinyinToneMarks('hao3'), 'hǎo');
    expect(pinyinToneMarks('lei2'), 'léi');
    expect(pinyinToneMarks('xie4'), 'xiè');
  });

  test('ou 標在 o', () {
    expect(pinyinToneMarks('gou3'), 'gǒu');
  });

  test('其餘標在最後一個母音', () {
    expect(pinyinToneMarks('gui4'), 'guì');
    expect(pinyinToneMarks('liu2'), 'liú');
    expect(pinyinToneMarks('jiu3'), 'jiǔ');
  });

  test('u: 轉 ü', () {
    expect(pinyinToneMarks('lu:4'), 'lǜ');
    expect(pinyinToneMarks('nu:3'), 'nǚ');
    expect(pinyinToneMarks('Lu:4'), 'Lǜ');
  });

  test('非拼音片段原樣保留', () {
    expect(pinyinToneMarks('3C'), '3C');
    expect(pinyinToneMarks('11'), '11');
    expect(pinyinToneMarks('A'), 'A');
    expect(pinyinToneMarks('A xue2'), 'A xué');
  });

  test('大寫保留', () {
    expect(pinyinToneMarks('Zhong1'), 'Zhōng');
    expect(pinyinToneMarks('Er2'), 'Ér');
  });

  test('多音節以空白分隔，空白保留', () {
    expect(pinyinToneMarks('pin1 yin1'), 'pīn yīn');
    expect(pinyinToneMarks('  pin1   yin1 '), 'pīn yīn');
  });

  test('沒有母音的片段只去掉數字', () {
    expect(pinyinToneMarks('r5'), 'r');
  });

  test('空字串回傳空字串', () {
    expect(pinyinToneMarks(''), '');
    expect(pinyinToneMarks('   '), '');
  });
}
