// app/test/library/txt_charset_detection_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/txt_charset_detection.dart';

void main() {
  group('detectAndDecodeTxt：UTF-8', () {
    test('純 ASCII 內容偵測為 utf8', () {
      final result = detectAndDecodeTxt(Uint8List.fromList(utf8.encode('Hello world')));
      expect(result.encoding, TxtEncoding.utf8);
      expect(result.text, 'Hello world');
    });

    test('合法 UTF-8 中文內容偵測為 utf8', () {
      final result = detectAndDecodeTxt(Uint8List.fromList(utf8.encode('繁體中文測試')));
      expect(result.encoding, TxtEncoding.utf8);
      expect(result.text, '繁體中文測試');
    });

    test('UTF-8 BOM（EF BB BF）開頭時剝除 BOM 且偵測為 utf8', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('測試')]);
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.utf8);
      expect(result.text, '測試');
    });
  });

  group('detectAndDecodeTxt：Big5', () {
    test('「測試」的 Big5 位元組（0xB4FA 0xB8D5）正確解碼', () {
      final bytes = Uint8List.fromList([0xB4, 0xFA, 0xB8, 0xD5]);
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.big5);
      expect(result.text, '測試');
    });

    test('Big5 混合 ASCII 內容正確解碼', () {
      // "AB測試CD"：A=0x41 B=0x42 測=0xB4FA 試=0xB8D5 C=0x43 D=0x44
      final bytes = Uint8List.fromList(
        [0x41, 0x42, 0xB4, 0xFA, 0xB8, 0xD5, 0x43, 0x44],
      );
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.big5);
      expect(result.text, 'AB測試CD');
    });
  });

  group('detectAndDecodeTxt：GBK', () {
    test('GBK 專有字元（如「嗢」0x86EC，Big5 無此碼位）與「测试」正確解碼為 gbk', () {
      // 0xB2E2（测）0xCAD4（试）0x86EC（嗢，U+55E2）
      // 因 0x86EC 落在 GBK 擴充區（高位元組 0x86 在 Big5 未定義），Big5 查表失敗退回 GBK
      final bytes = Uint8List.fromList([0xB2, 0xE2, 0xCA, 0xD4, 0x86, 0xEC]);
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.gbk);
      expect(result.text, '测试嗢');
    });
  });

  group('detectAndDecodeTxt：UTF-16', () {
    test('UTF-16LE（FF FE BOM）正確解碼', () {
      // BOM(FF FE) + "測"(0x6E2C -> 2C 6E LE) + "試"(0x8A66 -> 66 8A LE)
      final bytes = Uint8List.fromList(
        [0xFF, 0xFE, 0x2C, 0x6E, 0x66, 0x8A],
      );
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.utf16);
      expect(result.text, '測試');
    });

    test('UTF-16BE（FE FF BOM）正確解碼', () {
      final bytes = Uint8List.fromList(
        [0xFE, 0xFF, 0x6E, 0x2C, 0x8A, 0x66],
      );
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.utf16);
      expect(result.text, '測試');
    });
  });

  group('detectAndDecodeTxt：Fixture 檔案驗證', () {
    test('sample_big5.txt 正確偵測為 big5 並解碼出正確中文', () async {
      final bytes = await File('test/fixtures/sample_big5.txt').readAsBytes();
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.big5);
      expect(result.text, contains('第一章 測試開始'));
      expect(result.text, contains('第二章 測試結束'));
    });

    test('sample_utf8_chapters.txt 正確偵測為 utf8 並解碼出正確中文', () async {
      final bytes = await File('test/fixtures/sample_utf8_chapters.txt').readAsBytes();
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.utf8);
      expect(result.text, contains('第一章 起源'));
      expect(result.text, contains('第二章 冒險'));
      expect(result.text, contains('第三章 結局'));
    });
  });
}
