import 'book_reader_prefs.dart';

/// 版面設定預設集（epic-28-reader-settings-enhancements Issue 3），見
/// spec.md「資料模型」。[id] 為 `null` 代表尚未存入資料庫（新建立時的
/// 暫存物件）；一旦指定後在 `LayoutPresetRepository.replace()`（覆蓋）
/// 流程中維持不變（同一個 slot 身份）。[prefs] 快照內容須先經
/// `BookReaderPrefs.reflowableEpubFields()` 過濾才寫入，見該方法文件。
class LayoutPreset {
  final int? id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final BookReaderPrefs prefs;

  const LayoutPreset({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.prefs,
  });
}

/// 預設集命名驗證（spec.md「命名驗證」）：trim 後為空字串（含純空白輸入）
/// 回傳 `null`（拒絕儲存）；超過 20 字元直接截斷（design.md 允許的兩種
/// 處理方式之一——本專案選擇截斷而非拒絕輸入）；允許重複名稱，呼叫端
/// 不需要做唯一性檢查。
String? validateLayoutPresetName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length > 20 ? trimmed.substring(0, 20) : trimmed;
}
