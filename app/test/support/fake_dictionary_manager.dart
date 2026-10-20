import 'dart:async';

import 'package:elinkbook/dictionary/dictionary_manager.dart';
import 'package:elinkbook/dictionary/importers/dictionary_importer.dart';
import 'package:elinkbook/dictionary/mdx_companion_files.dart';
import 'package:elinkbook/dictionary/models/dictionary_source.dart';

/// 不碰資料庫與檔案系統的 [DictionaryManager] 測試替身。
///
/// 以記憶體 [items] 回應 `list()`；`setEnabled`／`reorder`／`delete` 比照正式實作
/// 更新 [items]，並記錄呼叫。`list`／`reorder`／`import` 可用 `*Gate` 卡住、
/// 用 `*Error` 丟例外，供測試驗證樂觀更新與失敗還原。
class FakeDictionaryManager implements DictionaryManager {
  FakeDictionaryManager({List<DictionaryListItem>? items})
      : items = items ?? <DictionaryListItem>[];

  /// 目前的字典清單（可由測試直接改）。
  List<DictionaryListItem> items;

  /// 各方法的呼叫紀錄，依呼叫順序。
  final List<({String id, bool enabled})> setEnabledCalls = [];
  final List<List<String>> reorderCalls = [];
  final List<String> deleteCalls = [];
  final List<({String sourceId, List<PickedFile> files})> addCompanionsCalls =
      [];
  final List<({PickedFile file, ImportRequest request})> importCalls = [];
  final List<PickedFile> readHintsCalls = [];

  /// 設定後對應方法會等到 gate 完成才繼續（用來停在「進行中」狀態）。
  Completer<void>? listGate;
  Completer<void>? reorderGate;
  Completer<void>? importGate;

  /// 設定後對應方法丟出此例外。
  Object? listError;
  Object? reorderError;
  Object? importError;

  /// `addCompanions` 被呼叫後執行，測試可在此更新 [items] 的 `missingCss`。
  void Function(String sourceId, List<PickedFile> files)? onAddCompanions;

  /// 匯入進度；預設直接完成。收到請求與取消信號，可自行產生 stream。
  Stream<ImportProgress> Function(
    PickedFile file,
    ImportRequest request,
    CancelToken cancel,
  )? importStream;

  /// `canImport` 的判斷；預設 `.mdx`／`.mdd`／`.css` 不可匯入，其餘可。
  bool Function(String fileName) canImportFn = (name) {
    final lower = name.toLowerCase();
    return !(lower.endsWith('.mdx') ||
        lower.endsWith('.mdd') ||
        lower.endsWith('.css'));
  };

  /// `readHints` 的回傳；預設以去掉副檔名的檔名為名稱。
  ImportHints Function(PickedFile file)? readHintsFn;

  @override
  Future<List<DictionaryListItem>> list() async {
    await listGate?.future;
    if (listError != null) throw listError!;
    return List<DictionaryListItem>.of(items);
  }

  @override
  Future<void> setEnabled(String id, bool enabled) async {
    setEnabledCalls.add((id: id, enabled: enabled));
    items = [
      for (final item in items)
        item.source.id == id
            ? DictionaryListItem(
                source: _copy(item.source, enabled: enabled),
                missingCss: item.missingCss,
              )
            : item,
    ];
  }

  @override
  Future<void> reorder(List<String> orderedIds) async {
    reorderCalls.add(List<String>.of(orderedIds));
    await reorderGate?.future;
    if (reorderError != null) throw reorderError!;
    final byId = {for (final item in items) item.source.id: item};
    items = [
      for (var i = 0; i < orderedIds.length; i++)
        if (byId[orderedIds[i]] != null)
          DictionaryListItem(
            source: _copy(byId[orderedIds[i]]!.source, priority: i),
            missingCss: byId[orderedIds[i]]!.missingCss,
          ),
    ];
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls.add(id);
    items = items.where((item) => item.source.id != id).toList();
  }

  @override
  Future<void> addCompanions(String sourceId, List<PickedFile> files) async {
    addCompanionsCalls.add((sourceId: sourceId, files: files));
    onAddCompanions?.call(sourceId, files);
  }

  @override
  Future<bool> canImport(String fileName) async => canImportFn(fileName);

  @override
  Future<ImportHints> readHints(PickedFile file) async {
    readHintsCalls.add(file);
    final fn = readHintsFn;
    if (fn != null) return fn(file);
    final dot = file.name.lastIndexOf('.');
    return ImportHints(name: dot > 0 ? file.name.substring(0, dot) : file.name);
  }

  @override
  Stream<ImportProgress> import(
    PickedFile file,
    ImportRequest request, {
    required CancelToken cancel,
  }) async* {
    importCalls.add((file: file, request: request));
    await importGate?.future;
    if (importError != null) throw importError!;
    final factory = importStream;
    if (factory != null) {
      yield* factory(file, request, cancel);
    } else {
      yield const ImportProgress(
        processed: 0,
        total: 0,
        stage: ImportStage.done,
      );
    }
  }

  DictionarySource _copy(DictionarySource s, {bool? enabled, int? priority}) =>
      DictionarySource(
        id: s.id,
        name: s.name,
        format: s.format,
        sourceLang: s.sourceLang,
        targetLang: s.targetLang,
        priority: priority ?? s.priority,
        enabled: enabled ?? s.enabled,
        storagePath: s.storagePath,
        entryCount: s.entryCount,
        licenseNote: s.licenseNote,
        importedAt: s.importedAt,
        referencedCss: s.referencedCss,
      );
}
