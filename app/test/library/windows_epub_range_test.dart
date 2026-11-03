// Windows EPUB metadata 區段讀取輔助函式測試（epic-66 Issue 2，審查 Important 2、3）。
//
// readFileRange：只讀檔案的一段位元組，不把整本書載入記憶體。
// parseBookRange：從攔截到的請求網址解析 start／end 查詢參數。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:elinkbook/library/windows_epub_metadata.dart';

void main() {
  late Directory tempDir;
  late String filePath;
  // 0..255 的位元組，每個位置的值等於位置本身（以 256 為模），方便比對切片內容。
  final content = Uint8List.fromList(List<int>.generate(1000, (i) => i % 256));

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('epub_range_test_');
    filePath = '${tempDir.path}${Platform.pathSeparator}book.epub';
    await File(filePath).writeAsBytes(content);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('readFileRange', () {
    test('回傳 [start, end) 的位元組', () async {
      final bytes = await readFileRange(filePath, 10, 20);
      expect(bytes, content.sublist(10, 20));
    });

    test('end 超過檔案長度時夾回檔案結尾', () async {
      final bytes = await readFileRange(filePath, 990, 5000);
      expect(bytes, content.sublist(990));
    });

    test('整個檔案範圍可讀', () async {
      final bytes = await readFileRange(filePath, 0, 1000);
      expect(bytes, content);
    });

    test('start 為負數回 null', () async {
      expect(await readFileRange(filePath, -1, 10), isNull);
    });

    test('start 大於等於檔案長度回 null', () async {
      expect(await readFileRange(filePath, 1000, 1010), isNull);
    });

    test('end 小於等於 start 回 null', () async {
      expect(await readFileRange(filePath, 20, 20), isNull);
      expect(await readFileRange(filePath, 20, 10), isNull);
    });

    test('單次範圍超過上限回 null（防止整本書被一次要走）', () async {
      final big = File('${tempDir.path}${Platform.pathSeparator}big.bin');
      await big.writeAsBytes(Uint8List(kMaxBookRangeBytes + 10));
      expect(await readFileRange(big.path, 0, kMaxBookRangeBytes + 1), isNull);
      // 剛好等於上限仍可讀。
      final ok = await readFileRange(big.path, 0, kMaxBookRangeBytes);
      expect(ok?.length, kMaxBookRangeBytes);
    });

    test('檔案不存在回 null', () async {
      expect(await readFileRange('${tempDir.path}/missing.epub', 0, 10), isNull);
    });
  });

  group('parseBookRange', () {
    test('解析 start 與 end', () {
      final r = parseBookRange(Uri.parse('https://x.local/book/current.epub?start=5&end=15'));
      expect(r, isNotNull);
      expect(r!.start, 5);
      expect(r.end, 15);
    });

    test('缺少參數回 null', () {
      expect(parseBookRange(Uri.parse('https://x.local/book/current.epub')), isNull);
      expect(parseBookRange(Uri.parse('https://x.local/book/current.epub?start=5')), isNull);
      expect(parseBookRange(Uri.parse('https://x.local/book/current.epub?end=5')), isNull);
    });

    test('非整數回 null', () {
      expect(parseBookRange(Uri.parse('https://x.local/b?start=a&end=10')), isNull);
      expect(parseBookRange(Uri.parse('https://x.local/b?start=1.5&end=10')), isNull);
    });
  });
}
