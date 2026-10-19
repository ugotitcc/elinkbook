// app/lib/dictionary/lemmatize/english_lemmatizer.dart

/// 不規則變化表。值為有序的詞元候選。
const _irregular = <String, List<String>>{
  'ran': ['run'],
  'mice': ['mouse'],
  'children': ['child'],
  'went': ['go'],
  'gone': ['go'],
  'was': ['be'],
  'were': ['be'],
  'been': ['be'],
  'is': ['be'],
  'are': ['be'],
  'am': ['be'],
  'better': ['good', 'well'],
  'best': ['good', 'well'],
  'feet': ['foot'],
  'men': ['man'],
  'women': ['woman'],
  'teeth': ['tooth'],
  'had': ['have'],
  'has': ['have'],
  'did': ['do'],
  'done': ['do'],
  'does': ['do'],
  'saw': ['see'],
  'seen': ['see'],
  'took': ['take'],
  'taken': ['take'],
  'got': ['get'],
  'made': ['make'],
  'said': ['say'],
  'came': ['come'],
  'knew': ['know'],
  'known': ['know'],
  'thought': ['think'],
};

final _letters = RegExp(r'^[a-z]+$');
const _vowels = 'aeiou';

/// 回傳 [word] 的英文詞元候選（有序、不含自身、無重複）。
///
/// 不是純 ASCII 字母（中文、帶重音、含空白或連字號）回傳空清單。不規則表優先，
/// 再依規則產生：寧可多產生，錯的詞幹只會查不到。長度 1 至 2 個字母的詞不套規則，
/// 避免 `is`→`i`、`as`→`a` 之類的候選。
List<String> lemmatizeEnglish(String word) {
  final w = word.toLowerCase();
  if (!_letters.hasMatch(w)) return const [];

  final out = <String>[];
  void add(String c) {
    if (c.length >= 2 && c != w && !out.contains(c)) out.add(c);
  }

  for (final c in _irregular[w] ?? const <String>[]) {
    add(c);
  }
  if (w.length <= 2) return out;

  // 複數與第三人稱。
  if (w.endsWith('ies')) add('${_cut(w, 3)}y');
  if (w.endsWith('ves')) {
    add('${_cut(w, 3)}f');
    add('${_cut(w, 3)}fe');
  }
  if (w.endsWith('ses')) add('${_cut(w, 3)}sis'); // analyses → analysis（名詞優先）
  if (w.endsWith('es')) add(_cut(w, 2));
  if (w.endsWith('s') && !w.endsWith('ss')) add(_cut(w, 1));

  // 過去式與過去分詞。
  if (w.endsWith('ied')) add('${_cut(w, 3)}y');
  if (w.endsWith('ed')) _addStems(add, _cut(w, 2));

  // -ing。
  if (w.endsWith('ing')) _addStems(add, _cut(w, 3));

  // 比較級與最高級。
  if (w.endsWith('ier')) add('${_cut(w, 3)}y');
  if (w.endsWith('er')) _addStems(add, _cut(w, 2));
  if (w.endsWith('iest')) add('${_cut(w, 4)}y');
  if (w.endsWith('est')) _addStems(add, _cut(w, 3));

  return out;
}

String _cut(String w, int n) => w.substring(0, w.length - n);

/// 詞幹本身、雙寫子音還原（`runn`→`run`）、補回 `e`（`mak`→`make`）。
/// 詞幹本身排在還原之前：`passed`→`pass` 優先於 `pas`。
void _addStems(void Function(String) add, String stem) {
  add(stem);
  if (stem.length >= 3 &&
      stem[stem.length - 1] == stem[stem.length - 2] &&
      !_vowels.contains(stem[stem.length - 1])) {
    add(_cut(stem, 1));
  }
  add('${stem}e');
}
