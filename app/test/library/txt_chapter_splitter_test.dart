import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/txt_chapter_splitter.dart';

void main() {
  group('splitIntoChapters', () {
    test('無章節標題時回傳單一章節，title 為 null', () {
      final chapters = splitIntoChapters('這是一段沒有章節標記的內容\n第二行內容');
      expect(chapters, hasLength(1));
      expect(chapters.single.title, isNull);
      expect(chapters.single.content, '這是一段沒有章節標記的內容\n第二行內容');
    });

    test('「第X章」格式正確切分，標題保留在內容開頭', () {
      final text = '前言內容\n第一章 起源\n正文一\n第二章 發展\n正文二';
      final chapters = splitIntoChapters(text);
      expect(chapters, hasLength(3));
      expect(chapters[0].title, isNull);
      expect(chapters[0].content, '前言內容\n');
      expect(chapters[1].title, '第一章 起源');
      expect(chapters[1].content, contains('正文一'));
      expect(chapters[2].title, '第二章 發展');
      expect(chapters[2].content, contains('正文二'));
    });

    test('「第X回」「第X卷」「第X節」「第X集」皆可辨識', () {
      final text = '第一回 開場\nA\n第二卷 中段\nB\n第三節 尾聲\nC\n第四集 完結\nD';
      final chapters = splitIntoChapters(text);
      expect(chapters.map((c) => c.title), [
        '第一回 開場',
        '第二卷 中段',
        '第三節 尾聲',
        '第四集 完結',
      ]);
    });

    test('中文數字與阿拉伯數字章節編號皆可辨識', () {
      final text = '第1章 一\nA\n第一百二十三章 二\nB';
      final chapters = splitIntoChapters(text);
      expect(chapters.map((c) => c.title), ['第1章 一', '第一百二十三章 二']);
    });

    test('英文 "Chapter N" 格式可辨識', () {
      final text = 'Chapter 1 Beginning\nA\nChapter 2 Middle\nB';
      final chapters = splitIntoChapters(text);
      expect(chapters.map((c) => c.title), ['Chapter 1 Beginning', 'Chapter 2 Middle']);
    });

    test('"Chapter" 大小寫變體（CHAPTER／chapter）皆可辨識（審查修正 Minor #1）', () {
      final text = 'CHAPTER 1 Beginning\nA\nchapter 2 Middle\nB';
      final chapters = splitIntoChapters(text);
      expect(chapters.map((c) => c.title), ['CHAPTER 1 Beginning', 'chapter 2 Middle']);
    });

    test('章節標題須為行首（前導空白容許），行中出現不視為標題', () {
      final text = '這句話裡提到第一章的內容但不是真正的標題\n第二章 才是真正標題\n正文';
      final chapters = splitIntoChapters(text);
      expect(chapters, hasLength(2));
      expect(chapters[0].title, isNull);
      expect(chapters[1].title, '第二章 才是真正標題');
    });
  });

  group('chunkByByteSize', () {
    test('內容未超過門檻時原樣回傳單一區塊', () {
      final chunks = chunkByByteSize('短內容', maxBytes: 1000);
      expect(chunks, ['短內容']);
    });

    test('超過門檻時依行邊界切分為多個區塊，且合併後內容不遺漏', () {
      final lines = List.generate(100, (i) => '第 $i 行內容測試文字');
      final content = lines.join('\n');
      final totalBytes = utf8.encode(content).length;
      final maxBytes = (totalBytes / 3).ceil();

      final chunks = chunkByByteSize(content, maxBytes: maxBytes);

      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(utf8.encode(chunk).length, lessThanOrEqualTo(maxBytes + 200));
      }
      // 合併後應包含原始所有行內容（chunkByByteSize 逐行 writeln，
      // 合併後以換行重組應與原始逐行內容一致）。
      final rejoined = chunks.join().trim();
      for (final line in lines) {
        expect(rejoined, contains(line));
      }
    });

    test('單一行本身即超過門檻時，該行獨立成一個區塊，不會被再切斷', () {
      final hugeLine = '字' * 1000;
      final chunks = chunkByByteSize(hugeLine, maxBytes: 100);
      expect(chunks, hasLength(1));
      expect(chunks.single.trim(), hugeLine);
    });
  });
}
