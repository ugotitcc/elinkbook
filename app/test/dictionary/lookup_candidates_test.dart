// app/test/dictionary/lookup_candidates_test.dart
import 'package:elinkbook/dictionary/lookup_candidates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lookupCandidates', () {
    test('順序：原字串、小寫、首字大寫、全大寫', () {
      final c = lookupCandidates('aPPle', lang: 'en');
      expect(c.take(4), ['aPPle', 'apple', 'Apple', 'APPLE']);
    });

    test('首字大寫與原字串相同時去重', () {
      final c = lookupCandidates('Apple', lang: 'en');
      expect(c.take(3), ['Apple', 'apple', 'APPLE']);
    });

    test('小寫輸入的完整順序', () {
      expect(lookupCandidates('run', lang: 'en'), ['run', 'Run', 'RUN']);
    });

    test('詞形還原接在大小寫變體後面', () {
      final c = lookupCandidates('ran', lang: 'en');
      expect(c, contains('run'));
      expect(c.indexOf('run'), greaterThan(c.indexOf('RAN')));
    });

    test('去變音符號只當備援：café 先於 cafe', () {
      final c = lookupCandidates('café', lang: 'en');
      expect(c, contains('cafe'));
      expect(c.indexOf('café'), lessThan(c.indexOf('cafe')));
      // 變體的去變音版本接在所有原有候選之後。
      expect(c.indexOf('cafe'), greaterThan(c.indexOf('CAFÉ')));
    });

    test('去變音符號對照表抽查', () {
      expect(stripLatinDiacritics('naïve'), 'naive');
      expect(stripLatinDiacritics('Ångström'), 'Angstrom');
      expect(stripLatinDiacritics('straße'), 'strasse');
      expect(stripLatinDiacritics('Łódź'), 'Lodz');
      expect(stripLatinDiacritics('œuvre'), 'oeuvre');
      expect(stripLatinDiacritics('Æon'), 'AEon');
      expect(stripLatinDiacritics('Øl'), 'Ol');
      expect(stripLatinDiacritics('Đa'), 'Da');
      expect(stripLatinDiacritics('plain'), 'plain');
      expect(stripLatinDiacritics('蘋果'), '蘋果');
    });

    test('中文字典（lang zh）不套用英文詞形還原', () {
      final c = lookupCandidates('running', lang: 'zh');
      expect(c, isNot(contains('run')));
    });

    test('CJK 文字的大小寫變體全部相同，去重後只剩一個', () {
      expect(lookupCandidates('蘋果', lang: 'zh'), ['蘋果']);
    });

    test('空字串與純空白回傳空清單', () {
      expect(lookupCandidates('', lang: 'en'), isEmpty);
      expect(lookupCandidates('  \n', lang: 'en'), isEmpty);
    });

    test('清單無重複字串', () {
      for (final w in ['Run', 'RUN', 'café', 'ran', '蘋果', 'Straße']) {
        final c = lookupCandidates(w, lang: 'en');
        expect(c.toSet().length, c.length, reason: w);
      }
    });

    test('片語首字大寫只動第一個字元', () {
      expect(
        lookupCandidates('kick the bucket', lang: 'en').take(3),
        ['kick the bucket', 'Kick the bucket', 'KICK THE BUCKET'],
      );
    });
  });

  group('dedupeByHeadwordNorm', () {
    test('套用公式後相同的候選只留第一個', () {
      expect(
        dedupeByHeadwordNorm(['Run', 'run', 'RUN', 'ran']),
        ['Run', 'ran'],
      );
    });

    test('保留原樣字串與順序', () {
      expect(
        dedupeByHeadwordNorm(['ran', 'RAN', 'Run', 'run']),
        ['ran', 'Run'],
      );
      expect(dedupeByHeadwordNorm(const []), isEmpty);
    });
  });
}
