import 'dart:convert';
import 'dart:io';

/// ARB 一致性守衛的偵測邏輯（`epic-54-architecture-optimization` Issue 6）。
///
/// 每個 `*Violations` 函式都是純函式，回傳「違規訊息」清單，空清單代表沒有
/// 違規；真實 ARB 的檢查見 `arb_consistency_test.dart`，這些函式自身會不會
/// 抓到違規，由 `arb_consistency_helpers_test.dart` 用合成資料證明（真實
/// 資料目前全數通過，光跑真實檔案看不出守衛抓不抓得到）。

/// 從 `{name}`、`{name, plural, ...}` 抽出 placeholder 名稱。已驗證在全部
/// 鍵上與 template 的 `@key.placeholders` 宣告零差異。已知限制：ICU `select`
/// 或 `plural` 的單字分支（如 `=0{None}`、`{He}`）會被誤判成 placeholder，
/// 測試會報錯。遇到時把分支寫成含空格的片語（如 `=0{no items}`）即可避開；
/// 尾隨空格（`{None }`）無效，因為 `\s*` 會吃掉空格。現有 18 個 plural 鍵
/// 不受影響。
final RegExp _placeholderPattern = RegExp(r'\{\s*(\w+)\s*(?:,|\})');

final RegExp _cjkPattern = RegExp(r'[一-鿿]');

/// 去掉 `@@locale` 與所有 `@key` 中繼資料，回傳「鍵 → 字串」。
Map<String, String> messagesOf(Map<String, dynamic> arb) => {
      for (final entry in arb.entries)
        if (!entry.key.startsWith('@') && entry.value is String)
          entry.key: entry.value as String,
    };

/// 讀取 ARB 檔並呼叫 [messagesOf]。涉及檔案 I/O，不在合成資料測試內覆蓋，
/// 由 `arb_consistency_test.dart` 讀真實 ARB 時一併驗證。
Map<String, String> loadArbMessages(String path) {
  final json =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return messagesOf(json);
}

/// 字串內所有 placeholder 名稱（含 ICU plural 巢狀分支內的）。
Set<String> placeholderNames(String message) => {
      for (final match in _placeholderPattern.allMatches(message))
        match.group(1)!,
    };

String _sorted(Iterable<String> items) => (items.toList()..sort()).join(', ');

/// [other] 相對 [base]（zh_TW）缺了哪些鍵、多了哪些鍵。
List<String> keySetViolations(
  String label,
  Map<String, String> base,
  Map<String, String> other,
) {
  final missing = base.keys.where((k) => !other.containsKey(k));
  final extra = other.keys.where((k) => !base.containsKey(k));
  return [
    if (missing.isNotEmpty) '[$label] 缺鍵：${_sorted(missing)}',
    if (extra.isNotEmpty) '[$label] 多鍵：${_sorted(extra)}',
  ];
}

/// 兩邊都有的鍵，placeholder 名稱集合是否一致。只存在於一邊的鍵交給
/// [keySetViolations]，這裡不重複回報。
List<String> placeholderViolations(
  String label,
  Map<String, String> base,
  Map<String, String> other,
) {
  final violations = <String>[];
  for (final key in (base.keys.toList()..sort())) {
    final otherMessage = other[key];
    if (otherMessage == null) continue;
    final baseNames = _sorted(placeholderNames(base[key]!));
    final otherNames = _sorted(placeholderNames(otherMessage));
    if (baseNames != otherNames) {
      violations.add(
        '[$label] 鍵 $key 的 placeholder 不一致：'
        'zh_TW={$baseNames}，$label={$otherNames}',
      );
    }
  }
  return violations;
}

/// `app_zh.arb` 只是 gen-l10n 要求的 base fallback，沒有獨立翻譯，必須與
/// zh_TW 逐字相同。
List<String> zhMirrorViolations(
  Map<String, String> base,
  Map<String, String> zh,
) {
  final differing = base.keys.where(
    (k) => zh.containsKey(k) && zh[k] != base[k],
  );
  return [
    if (differing.isNotEmpty) '[zh] 與 zh_TW 文字不同的鍵：${_sorted(differing)}',
  ];
}

/// `en` 的值與 zh_TW 相同、或含中文字元，視為漏翻；[allowlist]（鍵 → 理由）
/// 內的鍵例外。白名單項目若不再命中（或鍵已不存在）視為過期，同樣回報。
List<String> enUntranslatedViolations(
  Map<String, String> base,
  Map<String, String> en,
  Map<String, String> allowlist,
) {
  bool suspicious(String key) {
    final value = en[key];
    if (value == null) return false;
    return value == base[key] || _cjkPattern.hasMatch(value);
  }

  final untranslated =
      en.keys.where((k) => suspicious(k) && !allowlist.containsKey(k));
  final stale = allowlist.keys.where((k) => !suspicious(k));
  return [
    if (untranslated.isNotEmpty)
      '[en] 疑似漏翻（與 zh_TW 相同或含中文字元）：${_sorted(untranslated)}',
    if (stale.isNotEmpty)
      '[en] 白名單已過期（不再與 zh_TW 相同、也不含中文字元，或鍵已不存在）：${_sorted(stale)}',
  ];
}
