import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_format.dart';
import 'package:elinkbook/reader/engine_dispatch.dart';

/// 不帶 default 的 switch 運算式：sealed 型別少處理一態就會編譯失敗。
String describe(EngineDispatch d) => switch (d) {
      EngineDispatchKnown(:final isFixedLayout) => 'known:$isFixedLayout',
      EngineDispatchNeedsDetection() => 'needsDetection',
      EngineDispatchNotApplicable() => 'notApplicable',
    };

void main() {
  group('resolveEngineDispatch：宣告值非 null 時任何格式都直接採用', () {
    for (final format in BookFormat.values) {
      for (final declared in [true, false]) {
        test('${format.name} 宣告 $declared → Known($declared)', () {
          expect(
            resolveEngineDispatch(format: format, declared: declared),
            equals(EngineDispatchKnown(declared)),
          );
        });
      }
    }
  });

  group('resolveEngineDispatch：宣告值為 null 時依格式', () {
    test('epub → 需補判斷', () {
      expect(
        resolveEngineDispatch(format: BookFormat.epub, declared: null),
        equals(const EngineDispatchNeedsDetection()),
      );
    });
    test('azw3 → Known(false)（防禦預設，避免永遠停在載入）', () {
      expect(
        resolveEngineDispatch(format: BookFormat.azw3, declared: null),
        equals(const EngineDispatchKnown(false)),
      );
    });
    test('cbz → Known(true)（恆為固定版面）', () {
      expect(
        resolveEngineDispatch(format: BookFormat.cbz, declared: null),
        equals(const EngineDispatchKnown(true)),
      );
    });
    test('txt → Known(false)', () {
      expect(
        resolveEngineDispatch(format: BookFormat.txt, declared: null),
        equals(const EngineDispatchKnown(false)),
      );
    });
    test('md → Known(false)', () {
      expect(
        resolveEngineDispatch(format: BookFormat.md, declared: null),
        equals(const EngineDispatchKnown(false)),
      );
    });
    test('pdf → 不適用', () {
      expect(
        resolveEngineDispatch(format: BookFormat.pdf, declared: null),
        equals(const EngineDispatchNotApplicable()),
      );
    });
    test('unknown → 不適用', () {
      expect(
        resolveEngineDispatch(format: BookFormat.unknown, declared: null),
        equals(const EngineDispatchNotApplicable()),
      );
    });
  });

  group('resolveEngineDispatch：每個格式在 null 宣告下都有明確結果', () {
    test('只有 epub 需補判斷，其餘格式非 Known 即不適用', () {
      final described = {
        for (final f in BookFormat.values)
          f: describe(resolveEngineDispatch(format: f, declared: null)),
      };
      expect(described, {
        BookFormat.epub: 'needsDetection',
        BookFormat.pdf: 'notApplicable',
        BookFormat.azw3: 'known:false',
        BookFormat.cbz: 'known:true',
        BookFormat.txt: 'known:false',
        BookFormat.md: 'known:false',
        BookFormat.unknown: 'notApplicable',
      });
    });
  });

  group('EngineDispatch 值相等與字串表示', () {
    test('同值相等、不同值不等', () {
      expect(const EngineDispatchKnown(true), const EngineDispatchKnown(true));
      expect(const EngineDispatchKnown(true).hashCode,
          const EngineDispatchKnown(true).hashCode);
      expect(const EngineDispatchKnown(true),
          isNot(const EngineDispatchKnown(false)));
      expect(const EngineDispatchNeedsDetection(),
          isNot(const EngineDispatchNotApplicable()));
    });
    test('toString 可讀', () {
      expect(const EngineDispatchKnown(true).toString(), 'Known(true)');
      expect(const EngineDispatchNeedsDetection().toString(), 'NeedsDetection');
      expect(const EngineDispatchNotApplicable().toString(), 'NotApplicable');
    });
  });

  group('reconcileFixedLayoutFlag：宣告為 true 忽略回報，其餘以回報為準', () {
    for (final declared in <bool?>[null, false, true]) {
      for (final reported in [true, false]) {
        for (final current in [true, false]) {
          final expected = declared == true ? current : reported;
          test('宣告 $declared、回報 $reported、目前 $current → $expected', () {
            expect(
              reconcileFixedLayoutFlag(
                declared: declared,
                reported: reported,
                current: current,
              ),
              expected,
            );
          });
        }
      }
    }
  });
}
