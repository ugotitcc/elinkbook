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

/// 規則產生的候選至少要有幾個字母；避免 `uses`→`us`、`his`→`hi` 這類短詞。
/// 真正 2 個字母的原形（`be`、`go`）走不規則表。
const _minRuleLength = 3;

/// 回傳 [word] 的英文詞元候選（有序、不含自身、無重複）。
///
/// 不是純 ASCII 字母（中文、帶重音、含空白或連字號）回傳空清單。不規則表優先，
/// 再依規則產生。查詢端「第一個命中就停」，所以排序很重要：碰巧也是單字的錯詞幹
/// （`notes`→`not`、`hoped`→`hop`）必須排在正確原形之後。長度 1 至 2 個字母的詞
/// 不套規則，只查不規則表。
List<String> lemmatizeEnglish(String word) {
  final w = word.toLowerCase();
  if (!_letters.hasMatch(w)) return const [];

  final out = <String>[];
  void add(String c, {int minLength = _minRuleLength}) {
    if (c.length >= minLength && c != w && !out.contains(c)) out.add(c);
  }

  for (final c in _irregular[w] ?? const <String>[]) {
    add(c, minLength: 2);
  }
  if (w.length <= 2) return out;

  // 複數與第三人稱。
  if (w.endsWith('ies')) add('${_cut(w, 3)}y');
  if (w.endsWith('ves')) {
    add('${_cut(w, 3)}f');
    add('${_cut(w, 3)}fe');
  }
  // analyses → analysis（名詞優先）。詞幹太短（uses→usis）不套用。
  if (w.endsWith('ses') && w.length >= 7) add('${_cut(w, 3)}sis');
  if (w.endsWith('es')) {
    // 詞幹以 s／x／z／ch／sh／o 結尾，-es 才是加在原形上（boxes→box）；
    // 其他情況只是加了 -s（notes→note）。
    final stem = _cut(w, 2);
    if (RegExp(r'(s|x|z|ch|sh|o)$').hasMatch(stem)) {
      add(stem);
      add(_cut(w, 1));
    } else {
      add(_cut(w, 1));
      add(stem);
    }
  } else if (w.endsWith('s') && !w.endsWith('ss')) {
    add(_cut(w, 1));
  }

  // 過去式與過去分詞。
  if (w.endsWith('ied')) add('${_cut(w, 3)}y');
  if (w.endsWith('ed')) _addStems(add, _cut(w, 2));

  // -ing。dying→die、lying→lie：詞幹只剩一個字母的 -ying。
  if (w.endsWith('ying') && w.length == 5) add('${_cut(w, 4)}ie');
  if (w.endsWith('ing')) _addStems(add, _cut(w, 3));

  // 比較級與最高級。
  if (w.endsWith('ier')) add('${_cut(w, 3)}y');
  if (w.endsWith('er')) _addStems(add, _cut(w, 2));
  if (w.endsWith('iest')) add('${_cut(w, 4)}y');
  if (w.endsWith('est')) _addStems(add, _cut(w, 3));

  return out;
}

String _cut(String w, int n) => w.substring(0, w.length - n);

bool _isVowel(String ch) => _vowels.contains(ch);

/// 詞幹是「子音＋單一母音＋單一子音」（結尾不是 w／x／y），例如 `hop`、`rid`、`mak`。
/// 這種詞幹加了 -ed／-ing 卻沒有雙寫子音，原形幾乎一定帶 e（hoped→hope）。
bool _endsConsonantVowelConsonant(String stem) {
  if (stem.length < 3) return false;
  final last = stem[stem.length - 1];
  final mid = stem[stem.length - 2];
  final first = stem[stem.length - 3];
  return !_isVowel(last) &&
      !'wxy'.contains(last) &&
      _isVowel(mid) &&
      !_isVowel(first);
}

/// 詞幹本身、雙寫子音還原（`runn`→`run`）、補回 `e`（`mak`→`make`）。
/// 排序（第一個命中就停，所以先放最可能的）：
/// - 雙寫子音（stopp）：還原後的 `stop` 先。例外是 l／s／f／z，這些字母原形
///   本來就常雙寫（`pass`、`call`、`stuff`），詞幹本身先。
/// - 沒雙寫、結尾是 CVC（hop）：`hope` 先，因為原形若是 `hop` 過去式會寫成 hopped。
/// - 其餘：詞幹本身先，再補 e。
void _addStems(void Function(String) add, String stem) {
  final last = stem.isEmpty ? '' : stem[stem.length - 1];
  final doubled = stem.length >= 3 &&
      last == stem[stem.length - 2] &&
      !_isVowel(last);
  if (doubled && !'lsfz'.contains(last)) {
    add(_cut(stem, 1));
    add(stem);
    add('${stem}e');
  } else if (doubled) {
    add(stem);
    add(_cut(stem, 1));
    add('${stem}e');
  } else if (_endsConsonantVowelConsonant(stem)) {
    add('${stem}e');
    add(stem);
  } else {
    add(stem);
    add('${stem}e');
  }
}
