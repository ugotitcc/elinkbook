import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/leak_meter.dart';

void main() {
  group('leak_meter 量測工具測試', () {
    test('bookSizeMb 能夠解析現有檔案並回傳合理大小', () {
      final size = bookSizeMb();
      if (File(kLargeEpubPath).existsSync()) {
        expect(size, greaterThan(200.0));
        expect(size, lessThan(250.0));
      } else {
        expect(size, equals(0.0));
      }
    });

    test('sampleMemory 在 Windows 上能成功讀取當前程序的記憶體取樣', () async {
      if (!Platform.isWindows) return;

      final sample = await sampleMemory();
      expect(sample.privateMb, greaterThan(0.0));
      expect(sample.wsMb, greaterThan(0.0));
      expect(sample.wv2PrivateMb, greaterThanOrEqualTo(0.0));
      expect(sample.wv2Count, greaterThanOrEqualTo(0));
    });

    test('logLeak 輸出格式正確', () {
      const sample = MemSample(
        privateMb: 123.45,
        wsMb: 234.56,
        wv2PrivateMb: 45.67,
        wv2Count: 2,
      );

      final prints = <String>[];
      final spec = ZoneSpecification(
        print: (self, parent, zone, line) => prints.add(line),
      );

      runZoned(() {
        logLeak('indexer', 1, 'after_wait', sample);
      }, zoneSpecification: spec);

      expect(prints, hasLength(1));
      expect(
        prints.first,
        '[leak] path=indexer iter=1 phase=after_wait private_mb=123.45 ws_mb=234.56 wv2_private_mb=45.67 wv2_count=2',
      );
    });
  });
}
