// app/test/dictionary/mdx_companion_files_test.dart
import 'package:elinkbook/dictionary/mdx_companion_files.dart';
import 'package:flutter_test/flutter_test.dart';

PickedFile _f(String name) => PickedFile(path: '/tmp/$name', name: name, size: 1);

void main() {
  group('planCompanions', () {
    test('mdx + 同主檔名 mdd（不分大小寫）+ css → 一組', () {
      final plan = planCompanions([_f('a.mdx'), _f('a.MDD'), _f('x.css')]);

      expect(plan.groups, hasLength(1));
      expect(plan.groups.single.mdx.name, 'a.mdx');
      expect(plan.groups.single.mdd?.name, 'a.MDD');
      expect(plan.groups.single.css.map((f) => f.name), ['x.css']);
      expect(plan.others, isEmpty);
      expect(plan.unmatchedCompanions, isEmpty);
    });

    test('主檔名不同的 mdd 不配對，進 unmatchedCompanions', () {
      final plan = planCompanions([_f('a.mdx'), _f('b.mdd')]);

      expect(plan.groups.single.mdd, isNull);
      expect(plan.unmatchedCompanions.map((f) => f.name), ['b.mdd']);
    });

    test('兩個 mdx 與一個共用 css → 兩組都帶該 css', () {
      final plan = planCompanions([_f('a.mdx'), _f('b.mdx'), _f('s.css')]);

      expect(plan.groups, hasLength(2));
      for (final g in plan.groups) {
        expect(g.css.map((f) => f.name), ['s.css']);
      }
    });

    test('非 MDX 檔進 others', () {
      final plan = planCompanions([_f('a.json'), _f('b.mdx')]);

      expect(plan.others.map((f) => f.name), ['a.json']);
      expect(plan.groups, hasLength(1));
    });

    test('沒有 mdx 時所有 css 與 mdd 進 unmatchedCompanions', () {
      final plan = planCompanions([_f('x.css'), _f('y.CSS'), _f('z.mdd')]);

      expect(plan.groups, isEmpty);
      expect(
        plan.unmatchedCompanions.map((f) => f.name),
        ['x.css', 'y.CSS', 'z.mdd'],
      );
    });
  });

  group('extractReferencedCssNames', () {
    test('取 link href 的檔名並轉小寫', () {
      final names = extractReferencedCssNames(
        ['<link rel="stylesheet" href="GHYCHYZ.css">'],
      );
      expect(names, {'ghychyz.css'});
    });

    test('帶路徑只取檔名', () {
      final names = extractReferencedCssNames(
        ['<link rel="stylesheet" type="text/css" href="css/a.css">'],
      );
      expect(names, {'a.css'});
    });

    test('@import 不算', () {
      final names = extractReferencedCssNames(
        ['<style>@import url(x.css);</style>'],
      );
      expect(names, isEmpty);
    });

    test('多筆去重', () {
      final names = extractReferencedCssNames([
        '<link href="a.css">',
        '<link href="A.CSS"><link href="b.css">',
      ]);
      expect(names, {'a.css', 'b.css'});
    });
  });

  group('missingCss', () {
    test('不分大小寫比對，齊全則為空', () {
      expect(
        missingCss(referenced: ['ghychyz.css'], present: ['GHYCHYZ.CSS']),
        isEmpty,
      );
    });

    test('現有為空 → 全部缺', () {
      expect(
        missingCss(referenced: ['ghychyz.css'], present: const []),
        ['ghychyz.css'],
      );
    });

    test('維持 referenced 的順序與原寫法', () {
      expect(
        missingCss(referenced: ['B.css', 'a.css', 'c.css'], present: ['a.css']),
        ['B.css', 'c.css'],
      );
    });
  });
}
