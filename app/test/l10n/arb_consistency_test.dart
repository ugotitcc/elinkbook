import 'package:flutter_test/flutter_test.dart';

import 'arb_consistency_helpers.dart';

/// `en` 的值刻意與 zh_TW 相同或含中文字元的鍵（鍵 → 理由）。
///
/// 新增項目前先確認真的不該翻譯（專有名詞、語言自稱等），不要為了讓測試
/// 通過就把漏翻的鍵加進來。項目若不再命中（字串已不同、鍵已刪）測試會失敗，
/// 請一併移除。
const Map<String, String> _enAllowlist = {
  'settingsLanguageZhTW': '語言選單中各語言的自稱，刻意不翻譯（zh_TW 與 en 皆為「正體中文」）',
  'settingsLanguageZhCN': '語言選單中各語言的自稱，刻意不翻譯（zh_TW 與 en 皆為「简体中文」）',
  'settingsLanguageEn': '語言選單中各語言的自稱，刻意不翻譯（zh_TW 與 en 皆為「English」）',
};

void main() {
  // `flutter test` 的工作目錄是 app/，與 test/library/book_content_fingerprint_test.dart
  // 讀 test/fixtures/sample.epub 的既有慣例相同。
  final base = loadArbMessages('lib/l10n/app_zh_TW.arb');
  final zh = loadArbMessages('lib/l10n/app_zh.arb');
  final en = loadArbMessages('lib/l10n/app_en.arb');
  final zhCN = loadArbMessages('lib/l10n/app_zh_CN.arb');
  final others = {'zh': zh, 'en': en, 'zh_CN': zhCN};

  void expectNoViolations(List<String> violations) {
    expect(violations, isEmpty, reason: '\n${violations.join('\n')}');
  }

  test('zh／en／zh_CN 與 zh_TW 的鍵集合一致', () {
    expectNoViolations([
      for (final entry in others.entries)
        ...keySetViolations(entry.key, base, entry.value),
    ]);
  });

  test('zh／en／zh_CN 與 zh_TW 的 placeholder 名稱集合一致', () {
    expectNoViolations([
      for (final entry in others.entries)
        ...placeholderViolations(entry.key, base, entry.value),
    ]);
  });

  test('zh 與 zh_TW 逐字相同（zh 只是 gen-l10n 要求的 base fallback）', () {
    expectNoViolations(zhMirrorViolations(base, zh));
  });

  test('en 沒有漏翻（與 zh_TW 相同或含中文字元者須列白名單，且白名單不得過期）', () {
    expectNoViolations(enUntranslatedViolations(base, en, _enAllowlist));
  });
}
