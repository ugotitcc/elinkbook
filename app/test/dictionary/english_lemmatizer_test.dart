// app/test/dictionary/english_lemmatizer_test.dart
import 'package:elinkbook/dictionary/lemmatize/english_lemmatizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('不規則：ran→run、mice→mouse、children→child', () {
    expect(lemmatizeEnglish('ran').first, 'run');
    expect(lemmatizeEnglish('mice').first, 'mouse');
    expect(lemmatizeEnglish('children').first, 'child');
    expect(lemmatizeEnglish('went').first, 'go');
    expect(lemmatizeEnglish('was').first, 'be');
    expect(lemmatizeEnglish('were').first, 'be');
    expect(lemmatizeEnglish('better').first, 'good');
    expect(lemmatizeEnglish('feet').first, 'foot');
    expect(lemmatizeEnglish('men').first, 'man');
    expect(lemmatizeEnglish('women').first, 'woman');
    expect(lemmatizeEnglish('teeth').first, 'tooth');
  });

  test('規則：複數', () {
    expect(lemmatizeEnglish('cats'), contains('cat'));
    expect(lemmatizeEnglish('boxes'), contains('box'));
    expect(lemmatizeEnglish('flies'), contains('fly'));
    expect(lemmatizeEnglish('wolves'), contains('wolf'));
    expect(lemmatizeEnglish('knives'), contains('knife'));
  });

  test('規則：過去式', () {
    expect(lemmatizeEnglish('walked'), contains('walk'));
    expect(lemmatizeEnglish('studied'), contains('study'));
    expect(lemmatizeEnglish('stopped'), contains('stop'));
    expect(lemmatizeEnglish('hoped'), contains('hope'));
  });

  test('規則：-ing', () {
    expect(lemmatizeEnglish('running'), contains('run'));
    expect(lemmatizeEnglish('making'), contains('make'));
    expect(lemmatizeEnglish('walking'), contains('walk'));
  });

  test('規則：比較級', () {
    expect(lemmatizeEnglish('bigger'), contains('big'));
    expect(lemmatizeEnglish('happiest'), contains('happy'));
    expect(lemmatizeEnglish('happier'), contains('happy'));
    expect(lemmatizeEnglish('nicest'), contains('nice'));
  });

  test('analyses 先出 analysis 再出 analyse', () {
    final c = lemmatizeEnglish('analyses');
    expect(c, contains('analysis'));
    expect(c, contains('analyse'));
    expect(c.indexOf('analysis'), lessThan(c.indexOf('analyse')));
  });

  test('大寫輸入先轉小寫', () {
    expect(lemmatizeEnglish('Running'), contains('run'));
  });

  test('非英文單詞回傳空清單', () {
    for (final w in ['蘋果', 'café', 'state-of-the-art', 'kick the', '', '123']) {
      expect(lemmatizeEnglish(w), isEmpty, reason: w);
    }
  });

  test('1 至 2 個字母的詞不丟例外，也不產生空字串或自身', () {
    for (final w in ['a', 'is', 'as', 'us', 'be', 'bus', 'gas', 'this']) {
      final c = lemmatizeEnglish(w);
      expect(c.every((e) => e.isNotEmpty), isTrue, reason: w);
      expect(c.contains(w), isFalse, reason: w);
      expect(c.toSet().length, c.length, reason: w);
    }
    // 短詞不套規則，只查不規則表。
    expect(lemmatizeEnglish('as'), isEmpty);
    expect(lemmatizeEnglish('us'), isEmpty);
    expect(lemmatizeEnglish('a'), isEmpty);
  });

  test('回傳清單不含輸入本身且無重複', () {
    const words = [
      'running', 'cats', 'boxes', 'flies', 'wolves', 'walked', 'studied',
      'stopped', 'making', 'bigger', 'happiest', 'analyses', 'passes',
      'passed', 'buses', 'glasses', 'ran', 'mice', 'taking', 'dying',
    ];
    for (final w in words) {
      final c = lemmatizeEnglish(w);
      expect(c.every((e) => e.isNotEmpty), isTrue, reason: w);
      expect(c.contains(w), isFalse, reason: w);
      expect(c.toSet().length, c.length, reason: w);
    }
  });

  test('順序：常見詞的正確原形排在碰巧也是單字的錯詞幹前面', () {
    const expectedFirst = {
      'notes': 'note',
      'rates': 'rate',
      'uses': 'use',
      'used': 'use',
      'cares': 'care',
      'cared': 'care',
      'planes': 'plane',
      'hopes': 'hope',
      'hoped': 'hope',
      'hoping': 'hope',
      'riding': 'ride',
      'rides': 'ride',
      'hated': 'hate',
      'finer': 'fine',
      'stared': 'stare',
      'dying': 'die',
      'lying': 'lie',
      // 雙寫子音：原形沒有 e。
      'hopped': 'hop',
      'stopped': 'stop',
      'running': 'run',
      'bigger': 'big',
      'planned': 'plan',
      // 詞幹本來就以 s／x／ch／l 等結尾。
      'boxes': 'box',
      'passed': 'pass',
      'called': 'call',
      'cats': 'cat',
      'walked': 'walk',
      'walking': 'walk',
    };
    expectedFirst.forEach((word, lemma) {
      expect(lemmatizeEnglish(word).first, lemma, reason: word);
    });
  });

  test('規則產生的候選至少 3 個字母，不產生 us、hi 這類短詞', () {
    expect(lemmatizeEnglish('uses'), isNot(contains('us')));
    expect(lemmatizeEnglish('used'), isNot(contains('us')));
    expect(lemmatizeEnglish('his'), isEmpty);
    expect(lemmatizeEnglish('dying'), isNot(contains('dy')));
  });
}
