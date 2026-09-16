/// `ReaderScreen` 版面設定預設集「另存／套用／套用來源書籍／刪除」共用
/// 操作的純函式模組（Epic 43 Issue 2）。頂層函式，不做成類別——
/// `LayoutPresetRepository`／`BookReaderPrefsRepository` 分屬不同操作
/// 子集，已證實不永遠成對提供（`issues.md` Issue 2 Q3），比照
/// `bookmark_toggle.dart` 既有風格，各函式各自宣告自己實際需要的
/// repository 為必要參數。
library;

import 'book_reader_prefs.dart';
import 'book_reader_prefs_repository.dart';
import 'layout_preset.dart';
import 'layout_preset_repository.dart';

/// `_handleApplyPreset`/`_handleApplyFromBook` 原本各自重複的 inline
/// 判斷抽成純函式——「套用到目前書籍」的快速動作固定產生
/// `targetBookIds == [currentBookId]` 這個形狀，用來與「套用到其他
/// 書籍」picker 只勾選 1 本其他書籍時的 `targetBookIds.length == 1`
/// 區分開來（後者仍需要確認對話框，見 `ReaderScreen._applyPrefsToTargets`
/// 文件）。
bool layoutPresetTargetsCurrentBookOnly(
  List<String> targetBookIds,
  String currentBookId,
) =>
    targetBookIds.length == 1 && targetBookIds.single == currentBookId;

/// 新增一組預設集（未滿 3 組時的路徑）。[prefs] 須由呼叫端先以
/// `BookReaderPrefs.reflowableEpubFields()` 過濾（`LayoutPresetRepository`
/// 本身不做過濾，見該類別文件）。完成後回傳 [repository] 目前的完整
/// 清單，取代呼叫端另外呼叫 `_loadLayoutPresets()`。
Future<List<LayoutPreset>> insertNewLayoutPreset(
  LayoutPresetRepository repository, {
  required String name,
  required BookReaderPrefs prefs,
}) async {
  final now = DateTime.now();
  await repository.insert(LayoutPreset(
    id: null,
    name: name,
    createdAt: now,
    updatedAt: now,
    prefs: prefs,
  ));
  return repository.listAll();
}

/// 覆蓋既有一組（存滿 3 組時的路徑）。[target] 須為已持久化的預設集
/// （`target.id` 非 null）——未存檔的暫存物件呼叫本函式屬於呼叫端邏輯
/// 錯誤，assert 讓誤傳時有明確的除錯訊息，而非隱蔽的 `target.id!`
/// 執行期 null check 崩潰。[prefs] 過濾責任同 [insertNewLayoutPreset]。
Future<List<LayoutPreset>> overwriteLayoutPreset(
  LayoutPresetRepository repository, {
  required LayoutPreset target,
  required String name,
  required BookReaderPrefs prefs,
}) async {
  assert(target.id != null,
      'Target layout preset must have a valid id for overwrite');
  await repository.replace(
    target.id!,
    LayoutPreset(
      id: target.id,
      name: name,
      createdAt: target.createdAt,
      updatedAt: DateTime.now(),
      prefs: prefs,
    ),
  );
  return repository.listAll();
}

/// 刪除一組預設集，完成後回傳 [repository] 目前的完整清單，取代呼叫端
/// 另外呼叫 `_loadLayoutPresets()`。
Future<List<LayoutPreset>> deleteLayoutPreset(
  LayoutPresetRepository repository,
  int id,
) async {
  await repository.delete(id);
  return repository.listAll();
}

/// `_handleApplyPreset`/`_handleApplyFromBook` 共用的核心：只做寫入
/// （單筆 `save`／批次 `saveMultiple`），不含確認對話框、不含
/// `_handlePrefsChanged` 呼叫（皆需要 BuildContext／ReaderScreen 自身
/// 狀態，留在呼叫端，比照 Epic 43 Issue 1 一貫的邊界原則）。
///
/// I-1（審查修訂）：`targetBookIds` 為空清單時提早返回——本函式是
/// `layout_preset_actions.dart` 模組導出的公開頂層函式，即使目前唯一
/// 呼叫端 `ReaderScreen._applyPrefsToTargets` 已自行 guard
/// `targetBookIds.isEmpty`，本函式仍應有自我防禦能力，避免空清單落入
/// `else` 分支對 `saveMultiple([], prefs)` 開啟一次無謂的 SQLite
/// transaction。
Future<void> applyLayoutPresetPrefs(
  BookReaderPrefsRepository repository, {
  required BookReaderPrefs prefs,
  required List<String> targetBookIds,
}) async {
  if (targetBookIds.isEmpty) return;
  if (targetBookIds.length == 1) {
    await repository.save(targetBookIds.first, prefs);
  } else {
    await repository.saveMultiple(targetBookIds, prefs);
  }
}
