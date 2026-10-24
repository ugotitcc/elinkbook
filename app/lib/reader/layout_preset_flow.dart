import 'package:flutter/foundation.dart';

import 'book_reader_prefs.dart';
import 'book_reader_prefs_repository.dart';
import 'layout_preset.dart';
import 'layout_preset_repository.dart';

/// 預設集操作的結果（epic-54 Issue 26）：畫面依此決定要不要顯示失敗提示。
enum LayoutPresetOutcome {
  /// 操作完成（含「畫面已關閉，寫入完成但不通知」）。
  done,

  /// 使用者在任一個對話框按了取消，或沒有目標可套用；沒有寫入任何資料。
  cancelled,

  /// 讀取或寫入丟例外；細節已 `debugPrint`，畫面顯示對應的 SnackBar。
  failed,
}

/// [LayoutPresetFlow] 需要問使用者的事。畫面端以真實對話框實作，測試以假的
/// 實作；每個方法回傳 `null`／`false` 代表取消（包含畫面已卸載）。
abstract interface class LayoutPresetPrompts {
  /// 命名對話框；取消回傳 `null`。
  Future<String?> askName();

  /// 預設集已滿 3 組時，選擇要覆蓋哪一組；取消回傳 `null`。
  Future<LayoutPreset?> pickOverwriteTarget(List<LayoutPreset> presets);

  Future<bool> confirmOverwrite(String presetName);

  /// 「即將覆蓋 [bookCount] 本書」的確認。
  Future<bool> confirmApplyToOthers(int bookCount);

  Future<bool> confirmDelete(String presetName);
}

/// 版面設定預設集 module（epic-54 Issue 26，見 `CONTEXT.md`「版面設定預設集」）：
/// 持有預設集清單，提供「另存／套用／從其他書複製／刪除」四個操作。
///
/// - 不碰 `BuildContext`：要問使用者的事一律透過 [LayoutPresetPrompts]；
///   畫面已卸載時由畫面端實作回傳取消，所以本類別不知道 `mounted`。
/// - 是 [ChangeNotifier]：清單有兩個使用者（設定面板與覆蓋選單），在不同路由上。
///   四個操作結束時**不論結果**都通知一次（原本 4 個回呼處理完都無條件
///   `setSheetState`，面板「套用後」靠它才拿到新的 `_prefs`）；[dispose]
///   之後不再通知。
/// - 套用成功且目標含目前書籍時，**先**呼叫 [onCurrentBookPrefsApplied]，
///   **再**通知，面板重畫時畫面端的 `_prefs` 已是新值。
///
/// 原本分散的頂層操作函式（Issue 26 之前的預設集寫入函式）已併入本類別的私有方法。
class LayoutPresetFlow extends ChangeNotifier {
  LayoutPresetFlow({
    required LayoutPresetRepository presetRepository,
    required BookReaderPrefsRepository prefsRepository,
    required String currentBookId,
    required LayoutPresetPrompts prompts,
    required void Function(BookReaderPrefs prefs) onCurrentBookPrefsApplied,
  })  : _presetRepository = presetRepository,
        _prefsRepository = prefsRepository,
        _currentBookId = currentBookId,
        _prompts = prompts,
        _onCurrentBookPrefsApplied = onCurrentBookPrefsApplied;

  final LayoutPresetRepository _presetRepository;
  final BookReaderPrefsRepository _prefsRepository;
  final String _currentBookId;
  final LayoutPresetPrompts _prompts;
  final void Function(BookReaderPrefs prefs) _onCurrentBookPrefsApplied;

  /// 預設集上限（`spec.md`）；已滿時另存改走覆蓋流程。
  static const int _maxPresets = 3;

  List<LayoutPreset> _presets = const [];
  bool _disposed = false;

  List<LayoutPreset> get presets => _presets;

  /// 載入失敗只 `debugPrint`，清單保持原樣、不通知。
  Future<void> load() async {
    try {
      final list = await _presetRepository.listAll();
      if (_disposed) return;
      _presets = list;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load layout presets: $e');
    }
  }

  /// 另存為新預設集：取名 →（已滿 3 組才）選覆蓋目標 → 覆蓋確認 → 寫入。
  ///
  /// 「是否已滿 3 組」在取名之後才判斷（取名對話框開著的期間清單可能變動）。
  /// 寫入前先以 `reflowableEpubFields()` 過濾（`LayoutPresetRepository` 本身
  /// 不過濾）。
  Future<LayoutPresetOutcome> saveAsPreset(BookReaderPrefs currentDraft) async {
    try {
      final name = await _prompts.askName();
      if (name == null) return _finish(LayoutPresetOutcome.cancelled);
      final filtered = currentDraft.reflowableEpubFields();
      List<LayoutPreset> updated;
      if (_presets.length < _maxPresets) {
        updated = await _insert(name: name, prefs: filtered);
      } else {
        final target = await _prompts.pickOverwriteTarget(_presets);
        if (target == null) return _finish(LayoutPresetOutcome.cancelled);
        final confirmed = await _prompts.confirmOverwrite(target.name);
        if (!confirmed) return _finish(LayoutPresetOutcome.cancelled);
        updated = await _overwrite(target: target, name: name, prefs: filtered);
      }
      _presets = updated;
      return _finish(LayoutPresetOutcome.done);
    } catch (e, stackTrace) {
      debugPrint('另存為新預設集失敗：$e\n$stackTrace');
      return _finish(LayoutPresetOutcome.failed);
    }
  }

  /// 套用預設集到一批書籍。
  Future<LayoutPresetOutcome> applyPreset(
    LayoutPreset preset, {
    required List<String> targetBookIds,
  }) async {
    return _finish(await _applyToTargets(preset.prefs, targetBookIds));
  }

  /// 書籍設定複製：先讀取來源書籍目前的設定，以 `reflowableEpubFields()`
  /// 過濾後套用到一批書籍。
  ///
  /// 讀取來源失敗與後續套用失敗是兩層獨立保護，同一次失敗只回報一次
  /// [LayoutPresetOutcome.failed]。讀取完成後若畫面已關閉（[dispose]），
  /// 回傳 [LayoutPresetOutcome.cancelled]、不寫入。
  Future<LayoutPresetOutcome> applyFromBook(
    String sourceBookId, {
    required List<String> targetBookIds,
  }) async {
    if (targetBookIds.isEmpty) return _finish(LayoutPresetOutcome.cancelled);
    try {
      final sourcePrefs =
          (await _prefsRepository.load(sourceBookId)).reflowableEpubFields();
      if (_disposed) return LayoutPresetOutcome.cancelled;
      return _finish(await _applyToTargets(sourcePrefs, targetBookIds));
    } catch (e, stackTrace) {
      debugPrint('套用版面設定失敗：$e\n$stackTrace');
      return _finish(LayoutPresetOutcome.failed);
    }
  }

  /// 刪除預設集：先確認再刪除。
  ///
  /// 確認對話框刻意在 try 之外（沿用原行為）：它丟例外時直接往上拋。
  /// 找不到 [id] 時名稱用空字串，仍然跳確認。
  Future<LayoutPresetOutcome> deletePreset(int id) async {
    var presetName = '';
    for (final preset in _presets) {
      if (preset.id == id) {
        presetName = preset.name;
        break;
      }
    }
    final confirmed = await _prompts.confirmDelete(presetName);
    if (!confirmed) return _finish(LayoutPresetOutcome.cancelled);
    try {
      await _presetRepository.delete(id);
      _presets = await _presetRepository.listAll();
      return _finish(LayoutPresetOutcome.done);
    } catch (e, stackTrace) {
      debugPrint('刪除預設集失敗：$e\n$stackTrace');
      return _finish(LayoutPresetOutcome.failed);
    }
  }

  /// 套用的共用核心：確認（目標不是「只有目前書籍」才問）→ 寫入 →（目標含
  /// 目前書籍才）呼叫 [onCurrentBookPrefsApplied]。不通知，由呼叫端
  /// [_finish]。
  ///
  /// 「只有目前書籍」的判斷刻意不是 `targetBookIds.length > 1`：使用者透過
  /// 「套用到其他書籍」picker 只勾選 1 本其他書時 `length == 1`，但仍需要
  /// 確認。
  Future<LayoutPresetOutcome> _applyToTargets(
    BookReaderPrefs prefs,
    List<String> targetBookIds,
  ) async {
    if (targetBookIds.isEmpty) return LayoutPresetOutcome.cancelled;
    try {
      final currentBookOnly =
          targetBookIds.length == 1 && targetBookIds.single == _currentBookId;
      if (!currentBookOnly) {
        final confirmed =
            await _prompts.confirmApplyToOthers(targetBookIds.length);
        if (!confirmed) return LayoutPresetOutcome.cancelled;
      }
      if (targetBookIds.length == 1) {
        await _prefsRepository.save(targetBookIds.first, prefs);
      } else {
        await _prefsRepository.saveMultiple(targetBookIds, prefs);
      }
      if (_disposed) return LayoutPresetOutcome.done;
      if (targetBookIds.contains(_currentBookId)) {
        _onCurrentBookPrefsApplied(prefs);
      }
      return LayoutPresetOutcome.done;
    } catch (e, stackTrace) {
      debugPrint('套用版面設定失敗：$e\n$stackTrace');
      return LayoutPresetOutcome.failed;
    }
  }

  /// 新增一組預設集（未滿 3 組時的路徑）。完成後回傳目前的完整清單。
  Future<List<LayoutPreset>> _insert({
    required String name,
    required BookReaderPrefs prefs,
  }) async {
    final now = DateTime.now();
    await _presetRepository.insert(LayoutPreset(
      id: null,
      name: name,
      createdAt: now,
      updatedAt: now,
      prefs: prefs,
    ));
    return _presetRepository.listAll();
  }

  /// 覆蓋既有一組（已滿 3 組時的路徑）。[target] 須為已持久化的預設集
  /// （`id` 非 null），否則視為呼叫端邏輯錯誤。
  Future<List<LayoutPreset>> _overwrite({
    required LayoutPreset target,
    required String name,
    required BookReaderPrefs prefs,
  }) async {
    assert(target.id != null,
        'Target layout preset must have a valid id for overwrite');
    await _presetRepository.replace(
      target.id!,
      LayoutPreset(
        id: target.id,
        name: name,
        createdAt: target.createdAt,
        updatedAt: DateTime.now(),
        prefs: prefs,
      ),
    );
    return _presetRepository.listAll();
  }

  /// 操作結束：通知一次（[dispose] 之後不通知），回傳 [outcome]。
  LayoutPresetOutcome _finish(LayoutPresetOutcome outcome) {
    if (!_disposed) notifyListeners();
    return outcome;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
