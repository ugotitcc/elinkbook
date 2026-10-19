// app/lib/dictionary/pinyin_tone_marks.dart

/// 每個母音的 1 至 4 聲預組字元。
const _toneTable = <String, List<String>>{
  'a': ['ā', 'á', 'ǎ', 'à'],
  'e': ['ē', 'é', 'ě', 'è'],
  'i': ['ī', 'í', 'ǐ', 'ì'],
  'o': ['ō', 'ó', 'ǒ', 'ò'],
  'u': ['ū', 'ú', 'ǔ', 'ù'],
  'ü': ['ǖ', 'ǘ', 'ǚ', 'ǜ'],
  'A': ['Ā', 'Á', 'Ǎ', 'À'],
  'E': ['Ē', 'É', 'Ě', 'È'],
  'I': ['Ī', 'Í', 'Ǐ', 'Ì'],
  'O': ['Ō', 'Ó', 'Ǒ', 'Ò'],
  'U': ['Ū', 'Ú', 'Ǔ', 'Ù'],
  'Ü': ['Ǖ', 'Ǘ', 'Ǚ', 'Ǜ'],
};

/// 音節（字母與 `u:`）加聲調數字，例如 `pin1`、`lu:4`。
final _syllable = RegExp(r'^([A-Za-zÜü:]+)([1-5])$');

/// 把 CC-CEDICT 的聲調數字拼音轉成聲調符號，例如 `pin1 yin1` → `pīn yīn`。
///
/// 以空白切成片段，逐段處理，用單一空白重新連接。不符合「音節＋聲調數字」的
/// 片段（`3C`、`11`、單獨的大寫字母）原樣保留。規則見 spec §5。
String pinyinToneMarks(String raw) {
  final parts = raw.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.map(_convert).join(' ');
}

String _convert(String part) {
  final m = _syllable.firstMatch(part);
  if (m == null) return part;

  final letters = m.group(1)!.replaceAll('u:', 'ü').replaceAll('U:', 'Ü');
  final tone = int.parse(m.group(2)!);
  if (tone == 5) return letters;

  final index = _markIndex(letters);
  if (index < 0) return letters;
  final marked = _toneTable[letters[index]]![tone - 1];
  return letters.replaceRange(index, index + 1, marked);
}

/// 標調位置：有 a 或 e 標在它上面；否則有 ou 標在 o；否則標在最後一個母音。
/// 沒有母音回傳 -1。
int _markIndex(String letters) {
  final lower = letters.toLowerCase();
  final ae = lower.indexOf(RegExp('[ae]'));
  if (ae >= 0) return ae;
  final ou = lower.indexOf('ou');
  if (ou >= 0) return ou;
  return lower.lastIndexOf(RegExp('[iouü]'));
}
