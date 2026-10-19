// app/lib/dictionary/importers/csv_rows.dart

/// RFC 4180 的最小子集：引號包住的欄位可含逗號與換行，`""` 跳脫成單一引號；
/// `\r\n` 與 `\n` 都算換行；結尾的空列忽略。
List<List<String>> parseCsvRows(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  // 目前這一列是否有任何內容（含空欄位），用來忽略結尾的空列。
  var rowHasContent = false;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    if (rowHasContent) {
      endField();
      rows.add(row);
    }
    row = <String>[];
    field.clear();
    rowHasContent = false;
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
      continue;
    }
    switch (c) {
      case '"':
        inQuotes = true;
        rowHasContent = true;
      case ',':
        rowHasContent = true;
        endField();
      case '\r':
        if (i + 1 < text.length && text[i + 1] == '\n') i++;
        endRow();
      case '\n':
        endRow();
      default:
        field.write(c);
        rowHasContent = true;
    }
  }
  endRow();
  return rows;
}
