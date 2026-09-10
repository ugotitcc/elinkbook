/// CJK 表意文字判定（Unicode Han 基本區 U+4E00–U+9FFF，`epic-10-search`
/// ADR 0027 範圍）。用整數區間比較而非 RegExp——`plan-issue-0.md` 審查
/// 實測：逐字元呼叫 `RegExp.hasMatch()` 比整數比較慢兩個數量級，且本函式
/// 會在 Issue 1 用於背景逐句掃描整本書、在 Task 3 效能驗證掃描 800 萬句
/// 合成資料，這個差距會被放大到分鐘等級，不是次要細節。
bool _isHanRune(int rune) => rune >= 0x4e00 && rune <= 0x9fff;

/// 供寫入索引使用：CJK 表意文字逐字以空白分隔，其餘字元（ASCII 字母/
/// 數字、既有標點）維持原樣不拆，讓 FTS5 標準 `unicode61` tokenizer 把
/// 每個 CJK 字元視為獨立 token，同時仍保留英文單字的既有詞級比對能力
/// （見 `docs/epics/epic-10-search/spec.md` §2、ADR 0027 決策 1）。
///
/// 實作刻意避開兩個效能陷阱（`plan-issue-0.md` 審查實測 100,000 次呼叫，
/// 換成本寫法後從每秒 15,420 次提升到每秒 135,685 次，約 9 倍）：
/// 1. **不在迴圈內呼叫 `buffer.toString()`**——那會把目前已累積的全部
///    內容複製成一個新字串，對含多個中文字的句子等於 O(N²) 的字串複製，
///    改用 [endsWithSpace] 布林變數追蹤「上一個字元是不是空白」。
/// 2. **不在函式內建立新的 `RegExp` 物件**——原本結尾的
///    `replaceAll(RegExp(r' +'), ' ')` 每次呼叫都會重新編譯一次正則，
///    改成在寫入當下就避免產生多餘空白，不需要事後再跑一次正則清理。
String tokenizeForIndex(String text) {
  if (text.isEmpty) return '';
  final buffer = StringBuffer();
  var endsWithSpace = false;

  for (final rune in text.runes) {
    if (_isHanRune(rune)) {
      if (buffer.isNotEmpty && !endsWithSpace) {
        buffer.write(' ');
      }
      buffer.writeCharCode(rune);
      buffer.write(' ');
      endsWithSpace = true;
    } else if (rune == 0x20 || rune == 0x3000 || rune == 0x09) {
      // 一般空白、全形空白（\u3000）或 Tab（\t）字元：只在「目前不是緊接在
      // 空白之後、且已經有內容」時才寫入半形空格，達成跟 CJK 逐字空白分隔
      // 相容的「連續空白收斂成一個半形空白」效果。
      if (!endsWithSpace && buffer.isNotEmpty) {
        buffer.write(' ');
        endsWithSpace = true;
      }
    } else {
      buffer.writeCharCode(rune);
      endsWithSpace = false;
    }
  }

  final result = buffer.toString();
  return endsWithSpace ? result.substring(0, result.length - 1) : result;
}

/// 供查詢使用：對使用者輸入做相同的字元切分，再包成 FTS5 phrase query
/// （雙引號包住、內部雙引號跳脫為 `""`），要求 token 依序相鄰，達成等效
/// 子字串比對。空字串輸入回傳空字串，呼叫端須自行判斷是否要送出查詢
/// （不應對 SQLite 送出 `MATCH '""'`）。
String tokenizeForQuery(String query) {
  final tokenized = tokenizeForIndex(query);
  if (tokenized.isEmpty) return '';
  final escaped = tokenized.replaceAll('"', '""');
  return '"$escaped"';
}
