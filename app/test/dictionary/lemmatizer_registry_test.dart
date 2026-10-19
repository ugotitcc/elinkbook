// app/test/dictionary/lemmatizer_registry_test.dart
import 'package:elinkbook/dictionary/lemmatize/lemmatizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('未登錄語言回傳空清單，不套用英文規則', () {
    expect(lemmatize('zh', 'running'), isEmpty);
    expect(lemmatize('fr', 'running'), isEmpty);
    expect(lemmatize('', 'running'), isEmpty);
  });

  test('en 與 en-US 都走英文', () {
    expect(lemmatize('en', 'ran'), contains('run'));
    expect(lemmatize('en-US', 'ran'), contains('run'));
    expect(lemmatize('en_GB', 'ran'), contains('run'));
  });

  test('語言碼不分大小寫', () {
    expect(lemmatize('EN', 'ran'), contains('run'));
  });
}
