import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/byte_range.dart';

void main() {
  group('parseByteRange', () {
    const fileLength = 1000;

    test('null 或空字串回傳 full', () {
      expect(parseByteRange(null, fileLength), const ByteRangeResult.full());
      expect(parseByteRange('', fileLength), const ByteRangeResult.full());
      expect(parseByteRange('   ', fileLength), const ByteRangeResult.full());
    });

    test('標準指定起訖範圍 bytes=0-99', () {
      expect(
        parseByteRange('bytes=0-99', fileLength),
        const ByteRangeResult.partial(0, 99),
      );
    });

    test('指定起點至檔尾 bytes=100-', () {
      expect(
        parseByteRange('bytes=100-', fileLength),
        const ByteRangeResult.partial(100, 999),
      );
    });

    test('尾端指定位元組 bytes=-500', () {
      expect(
        parseByteRange('bytes=-500', fileLength),
        const ByteRangeResult.partial(500, 999),
      );
    });

    test('尾端指定位元組大於檔案大小 bytes=-1500 回傳整檔 partial', () {
      expect(
        parseByteRange('bytes=-1500', fileLength),
        const ByteRangeResult.partial(0, 999),
      );
    });

    test('end 超過檔尾截斷為 fileLength-1', () {
      expect(
        parseByteRange('bytes=50-2000', fileLength),
        const ByteRangeResult.partial(50, 999),
      );
    });

    test('start >= fileLength 回傳 unsatisfiable', () {
      expect(
        parseByteRange('bytes=1000-', fileLength),
        const ByteRangeResult.unsatisfiable(),
      );
      expect(
        parseByteRange('bytes=1000-1050', fileLength),
        const ByteRangeResult.unsatisfiable(),
      );
      expect(
        parseByteRange('bytes=1500-1600', fileLength),
        const ByteRangeResult.unsatisfiable(),
      );
    });

    test('bytes=-0 回傳 unsatisfiable', () {
      expect(
        parseByteRange('bytes=-0', fileLength),
        const ByteRangeResult.unsatisfiable(),
      );
    });

    test('start > end 等無效範圍回退為 full', () {
      expect(
        parseByteRange('bytes=500-200', fileLength),
        const ByteRangeResult.full(),
      );
    });

    test('非數值 bytes=abc 等無法解析者回退為 full', () {
      expect(
        parseByteRange('bytes=abc', fileLength),
        const ByteRangeResult.full(),
      );
      expect(
        parseByteRange('bytes=abc-def', fileLength),
        const ByteRangeResult.full(),
      );
    });

    test('非 bytes 單位（如 items=0-1）回退為 full', () {
      expect(
        parseByteRange('items=0-1', fileLength),
        const ByteRangeResult.full(),
      );
    });

    test('多段範圍 bytes=0-1,5-6 回退為 full', () {
      expect(
        parseByteRange('bytes=0-1,5-6', fileLength),
        const ByteRangeResult.full(),
      );
    });

    test('fileLength == 0 時：任何 Range 回傳 unsatisfiable，無 Range 回傳 full', () {
      expect(parseByteRange(null, 0), const ByteRangeResult.full());
      expect(parseByteRange('', 0), const ByteRangeResult.full());
      expect(parseByteRange('bytes=0-0', 0), const ByteRangeResult.unsatisfiable());
      expect(parseByteRange('bytes=0-', 0), const ByteRangeResult.unsatisfiable());
      expect(parseByteRange('bytes=-1', 0), const ByteRangeResult.unsatisfiable());
    });
  });
}
