// app/lib/dictionary/lookup_candidates.dart
import 'lemmatize/lemmatizer.dart';
import 'models/dictionary_entry.dart';

/// 查詢候選清單（spec §3.4），依序：
/// 原字串、小寫、首字大寫（第一個字元大寫、其餘小寫）、全大寫；
/// 再接 `lemmatize(lang, 小寫)` 的結果；
/// 最後把前面每個含變音符號的候選去變音符號後附上（`café` 先於 `cafe`）。
/// 相同字串只保留第一次出現。輸入去空白後為空 → 回傳空清單。
///
/// 清單保留大小寫變體（MDX 字典可能區分大小寫）；不分大小寫的來源請再用
/// [dedupeByHeadwordNorm] 去重。
List<String> lookupCandidates(String text, {required String lang}) {
  final original = text.trim();
  if (original.isEmpty) return const [];

  final lower = original.toLowerCase();
  final out = <String>[];
  void add(String c) {
    if (c.isNotEmpty && !out.contains(c)) out.add(c);
  }

  add(original);
  add(lower);
  add(_capitalize(lower));
  add(original.toUpperCase());
  lemmatize(lang, lower).forEach(add);

  for (final c in List<String>.of(out)) {
    final stripped = stripLatinDiacritics(c);
    if (stripped != c) add(stripped);
  }
  return out;
}

/// 依 `headwordNorm()` 去重，保留第一次出現的順序與原樣字串。
/// 比對不分大小寫的來源（JSON、CSV、CC-CEDICT）用它，避免對同一個詞查三次。
List<String> dedupeByHeadwordNorm(List<String> candidates) {
  final seen = <String>{};
  return [
    for (final c in candidates)
      if (seen.add(headwordNorm(c))) c,
  ];
}

String _capitalize(String lower) {
  final first = String.fromCharCode(lower.runes.first);
  return first.toUpperCase() + lower.substring(first.length);
}

/// 去掉拉丁字母的變音符號。對照表涵蓋 Latin-1 Supplement（U+00C0–U+00FF）與
/// Latin Extended-A（U+0100–U+017F）。不引入套件，也不做 Unicode 正規化。
String stripLatinDiacritics(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_diacriticMap[ch] ?? ch);
  }
  return buffer.toString();
}

/// 單一字母的對照以「目標: 來源字元」描述；多字母展開另列。
const _singleLetterGroups = <String, String>{
  'A': 'ÀÁÂÃÄÅĀĂĄ',
  'a': 'àáâãäåāăą',
  'C': 'ÇĆĈĊČ',
  'c': 'çćĉċč',
  'D': 'ÐĎĐ',
  'd': 'ðďđ',
  'E': 'ÈÉÊËĒĔĖĘĚ',
  'e': 'èéêëēĕėęě',
  'G': 'ĜĞĠĢ',
  'g': 'ĝğġģ',
  'H': 'ĤĦ',
  'h': 'ĥħ',
  'I': 'ÌÍÎÏĨĪĬĮİ',
  'i': 'ìíîïĩīĭįı',
  'J': 'Ĵ',
  'j': 'ĵ',
  'K': 'Ķ',
  'k': 'ķĸ',
  'L': 'ĹĻĽĿŁ',
  'l': 'ĺļľŀł',
  'N': 'ÑŃŅŇŊ',
  'n': 'ñńņňŉŋ',
  'O': 'ÒÓÔÕÖØŌŎŐ',
  'o': 'òóôõöøōŏő',
  'R': 'ŔŖŘ',
  'r': 'ŕŗř',
  'S': 'ŚŜŞŠ',
  's': 'śŝşšſ',
  'T': 'ŢŤŦ',
  't': 'ţťŧ',
  'U': 'ÙÚÛÜŨŪŬŮŰŲ',
  'u': 'ùúûüũūŭůűų',
  'W': 'Ŵ',
  'w': 'ŵ',
  'Y': 'ÝŶŸ',
  'y': 'ýÿŷ',
  'Z': 'ŹŻŽ',
  'z': 'źżž',
};

const _multiLetter = <String, String>{
  'Æ': 'AE',
  'æ': 'ae',
  'Œ': 'OE',
  'œ': 'oe',
  'ß': 'ss',
  'Ĳ': 'IJ',
  'ĳ': 'ij',
  'Þ': 'Th',
  'þ': 'th',
};

final Map<String, String> _diacriticMap = {
  for (final entry in _singleLetterGroups.entries)
    for (final ch in entry.value.split('')) ch: entry.key,
  ..._multiLetter,
};
