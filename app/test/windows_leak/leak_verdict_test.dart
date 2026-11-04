import 'package:flutter_test/flutter_test.dart';

import 'leak_verdict.dart';

void main() {
  group('evaluateLeak 記憶體洩漏判定規則', () {
    const bookMb = 200.0;
    const thresholdRatio = 0.05; // 門檻 = 10.0 MB

    test('全部增量遠小於門檻 → leaked == false, ratcheting 視正負而定', () {
      // 基線 300, 增量分別為 +1.0, +2.0, +1.5, +0.5（皆 < 10.0）
      final verdict = evaluateLeak(
        privateMb: [300.0, 301.0, 303.0, 304.5, 305.0],
        bookMb: bookMb,
        thresholdRatio: thresholdRatio,
      );

      expect(verdict.leaked, isFalse);
      expect(verdict.exceededIterations, isEmpty);
      expect(verdict.deltas, [1.0, 2.0, 1.5, 0.5]);
      expect(verdict.ratcheting, isTrue);
    });

    test('某次增量剛好等於門檻 → 不算洩漏（嚴格大於才算）', () {
      // 基線 300, 第 1 次增量剛好 10.0
      final verdict = evaluateLeak(
        privateMb: [300.0, 310.0],
        bookMb: bookMb,
        thresholdRatio: thresholdRatio,
      );

      expect(verdict.leaked, isFalse);
      expect(verdict.exceededIterations, isEmpty);
      expect(verdict.deltas, [10.0]);
    });

    test('某次增量略大於門檻 → leaked == true，exceededIterations 含該次迭代號（1-based）', () {
      // 基線 300, 第 1 次 +2.0, 第 2 次 +10.01（超標）, 第 3 次 +1.0, 第 4 次 +11.0（超標）
      final verdict = evaluateLeak(
        privateMb: [300.0, 302.0, 312.01, 313.01, 324.01],
        bookMb: bookMb,
        thresholdRatio: thresholdRatio,
      );

      expect(verdict.leaked, isTrue);
      expect(verdict.exceededIterations, [2, 4]);
      expect(verdict.ratcheting, isTrue);
    });

    test('增量為負（記憶體下降）→ 不算洩漏，且 ratcheting == false', () {
      // 基線 300, 第 1 次 +5.0, 第 2 次 -1.0, 第 3 次 +2.0
      final verdict = evaluateLeak(
        privateMb: [300.0, 305.0, 304.0, 306.0],
        bookMb: bookMb,
        thresholdRatio: thresholdRatio,
      );

      expect(verdict.leaked, isFalse);
      expect(verdict.exceededIterations, isEmpty);
      expect(verdict.ratcheting, isFalse);
    });

    test('4 次增量皆為正但都低於門檻 → leaked == false 但 ratcheting == true', () {
      final verdict = evaluateLeak(
        privateMb: [300.0, 301.0, 302.0, 303.0, 304.0],
        bookMb: bookMb,
        thresholdRatio: thresholdRatio,
      );

      expect(verdict.leaked, isFalse);
      expect(verdict.exceededIterations, isEmpty);
      expect(verdict.ratcheting, isTrue);
    });

    test('只有基線一筆（無迭代）→ 拋出 ArgumentError', () {
      expect(
        () => evaluateLeak(
          privateMb: [300.0],
          bookMb: bookMb,
          thresholdRatio: thresholdRatio,
        ),
        throwsArgumentError,
      );
    });

    test('privateMb 為空 → 拋出 ArgumentError', () {
      expect(
        () => evaluateLeak(
          privateMb: [],
          bookMb: bookMb,
          thresholdRatio: thresholdRatio,
        ),
        throwsArgumentError,
      );
    });
  });
}
