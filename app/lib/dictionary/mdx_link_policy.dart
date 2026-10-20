// MDX 詞條內的連結政策（epic-63 Issue 6a Task 4）。
//
// 詞條 HTML 一律以 JavaScript 關閉、禁止網路與檔案存取的 WebView 顯示。
// 點擊時先經過這裡分類，只有「詞條」與「頁內錨點」兩種動作會被執行，
// 其餘（http／https／file／sound／javascript／data…）全部封鎖。
//
// 這支檔案是純函式，不 import flutter_inappwebview，方便單元測試。
import 'dart:core';

/// 詞條文件載入時使用的虛擬來源。
///
/// WebView 只允許這個來源；頁內錨點會變成 `https://dict.local/#x`。
const String kMdxBaseUrl = 'https://dict.local/';

/// 連結分類結果。
sealed class MdxLinkAction {
  const MdxLinkAction();
}

/// 跳到另一筆詞條（`entry://詞`、`bword://詞`）。
final class MdxEntryLink extends MdxLinkAction {
  const MdxEntryLink(this.word);

  /// 已 URL 解碼、去掉結尾斜線的詞條文字。
  final String word;

  @override
  bool operator ==(Object other) => other is MdxEntryLink && other.word == word;

  @override
  int get hashCode => word.hashCode;

  @override
  String toString() => 'MdxEntryLink($word)';
}

/// 頁內錨點：`#x` 或 `https://dict.local/#x`。不攔截，交給 WebView 捲動。
final class MdxAnchorLink extends MdxLinkAction {
  const MdxAnchorLink();
}

/// 其餘一律封鎖，不載入也不開啟。
final class MdxBlockedLink extends MdxLinkAction {
  const MdxBlockedLink();
}

const List<String> _entrySchemes = ['entry://', 'bword://'];

/// 判斷一個連結該怎麼處理。
///
/// - `entry://詞`、`bword://詞` → [MdxEntryLink]（percent-decoding、去尾斜線）。
/// - `#x`、`https://dict.local/#x` → [MdxAnchorLink]。
/// - 其他（含 `http`、`https`、`file`、`sound`、`javascript`、相對路徑）→
///   [MdxBlockedLink]。
MdxLinkAction classifyLink(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return const MdxBlockedLink();

  if (trimmed.startsWith('#')) return const MdxAnchorLink();
  if (trimmed.startsWith('$kMdxBaseUrl#')) return const MdxAnchorLink();

  final lower = trimmed.toLowerCase();
  for (final scheme in _entrySchemes) {
    if (!lower.startsWith(scheme)) continue;
    final rawTarget = trimmed.substring(scheme.length);
    // entry://#x 是頁內錨點，不是查詢 #x 這筆詞。
    if (rawTarget.startsWith('#')) return const MdxAnchorLink();
    try {
      final word = Uri.decodeComponent(
        rawTarget,
      ).trim().replaceFirst(RegExp(r'/+$'), '');
      if (word.isEmpty) return const MdxBlockedLink();
      return MdxEntryLink(word);
    } on Object {
      // 不合法的 percent-encoding：寧可封鎖，也不要猜。
      return const MdxBlockedLink();
    }
  }

  return const MdxBlockedLink();
}
