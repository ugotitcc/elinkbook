// app/lib/dictionary/lookup_text_normalizer.dart

/// 選字被拒絕的原因。
enum SelectionProblem { invalidSelection, tooLong }

/// 選字的文字類型。
enum SelectionCharType { latin, cjk, mixed }

/// [normalizeLookupSelection] 的結果：通過或被拒絕。
sealed class SelectionNormalization {
  const SelectionNormalization();
}

final class NormalizedSelection extends SelectionNormalization {
  const NormalizedSelection({required this.text, required this.charType});

  final String text;
  final SelectionCharType charType;
}

final class RejectedSelection extends SelectionNormalization {
  const RejectedSelection(this.problem);

  final SelectionProblem problem;
}

/// 不含空白的 CJK 選字，字元數上限。
const int kMaxCjkSelectionLength = 8;

final _edge = RegExp(r'^[\s\p{P}\p{S}]+|[\s\p{P}\p{S}]+$', unicode: true);
final _whitespaceRun = RegExp(r'\s+');
final _han = RegExp(r'\p{Script=Han}', unicode: true);
final _latin = RegExp(r'\p{Script=Latin}', unicode: true);
final _notWordChar = RegExp(r'[\p{P}\p{S}\p{Cc}]', unicode: true);

/// 選字處理（spec §3.4），依序：
/// 1. 去頭尾空白與標點；空字串 → [SelectionProblem.invalidSelection]。
/// 2. 內部連續空白（含換行）整理成單一空白。
/// 3. 含空白 → 片語：內部標點允許，不設長度上限。
/// 4. 不含空白：內部有標點或控制字元 → invalidSelection，只有「不含 CJK 且
///    是 `-`、`'`、`’`」例外（`state-of-the-art`、`don't`）。
/// 5. 不含空白且含 CJK：字元數超過 [kMaxCjkSelectionLength] → tooLong。
///    標點檢查先於長度檢查。
SelectionNormalization normalizeLookupSelection(String raw) {
  final trimmed = raw.replaceAll(_edge, '');
  if (trimmed.isEmpty) {
    return const RejectedSelection(SelectionProblem.invalidSelection);
  }
  final text = trimmed.replaceAll(_whitespaceRun, ' ');
  final charType = detectCharType(text);

  if (!text.contains(' ')) {
    final hasCjk = _han.hasMatch(text);
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (!_notWordChar.hasMatch(ch)) continue;
      final allowed = !hasCjk && (ch == '-' || ch == "'" || ch == '’');
      if (!allowed) {
        return const RejectedSelection(SelectionProblem.invalidSelection);
      }
    }
    if (hasCjk && text.runes.length > kMaxCjkSelectionLength) {
      return const RejectedSelection(SelectionProblem.tooLong);
    }
  }
  return NormalizedSelection(text: text, charType: charType);
}

/// 含漢字為 CJK，含拉丁字母為拉丁，兩者皆有為 mixed；兩者皆無（例如純數字）
/// 歸 latin。
SelectionCharType detectCharType(String text) {
  final han = _han.hasMatch(text);
  final latin = _latin.hasMatch(text);
  if (han && latin) return SelectionCharType.mixed;
  if (han) return SelectionCharType.cjk;
  return SelectionCharType.latin;
}
