// app/lib/dictionary/dictionary_manager.dart
import 'content_id.dart';
import 'dictionary_file_store.dart';
import 'importers/dictionary_importer.dart';
import 'mdx_companion_files.dart';
import 'models/dictionary_source.dart';
import 'storage/dictionary_store.dart';
import 'storage/dictionary_store_provider.dart';

/// 設定畫面清單的一列：來源加上缺少的樣式表。
class DictionaryListItem {
  const DictionaryListItem({required this.source, required this.missingCss});

  final DictionarySource source;

  /// 詞條引用但私有目錄沒有的 `.css` 檔名；只有 MDX 來源會有值。
  final List<String> missingCss;
}

/// 字典管理門面：清單、啟用、排序、刪除、附屬檔案與匯入。
class DictionaryManager {
  DictionaryManager({
    required DictionaryStoreProvider store,
    required DictionaryFileStore files,
    required List<DictionaryImporter Function(DictionaryStore)>
        importerFactories,
    Future<void> Function(String sourceId)? onEvict,
  })  : _store = store,
        _files = files,
        _importerFactories = importerFactories,
        _onEvict = onEvict ?? _noopEvict;

  final DictionaryStoreProvider _store;
  final DictionaryFileStore _files;
  final List<DictionaryImporter Function(DictionaryStore)> _importerFactories;

  /// 來源列被刪除或取代前呼叫；Task 6 用來關掉 reader 池內的控制代碼。
  /// 預設什麼都不做。
  final Future<void> Function(String sourceId) _onEvict;

  static Future<void> _noopEvict(String sourceId) async {}

  Future<List<DictionaryListItem>> list() async {
    final store = await _store();
    final sources = await store.listSources();
    final items = <DictionaryListItem>[];
    for (final source in sources) {
      final missing = source.format == DictionaryFormat.mdx
          ? missingCss(
              referenced: source.referencedCss,
              present: await _files.listFiles(source.id),
            )
          : const <String>[];
      items.add(DictionaryListItem(source: source, missingCss: missing));
    }
    return items;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final store = await _store();
    await store.setEnabled(id, enabled);
  }

  Future<void> reorder(List<String> orderedIds) async {
    final store = await _store();
    await store.reorderSources(orderedIds);
  }

  /// 先刪私有目錄，成功後才刪來源列與詞條。目錄刪除失敗時例外往上丟，
  /// 來源列與詞條保留，使用者可再試一次；反過來會留下查不到的孤兒檔案。
  Future<void> delete(String id) async {
    final store = await _store();
    // 先讓 reader 池放掉控制代碼，否則 Windows／部分 Android 檔案系統上
    // 仍開著的檔案刪不掉。
    await _onEvict(id);
    await _files.deleteAll(id);
    await store.deleteSource(id);
  }

  /// 補上附屬檔案；只接受 `.css`、`.mdd`，其他副檔名忽略。
  Future<void> addCompanions(String sourceId, List<PickedFile> files) async {
    for (final file in files) {
      final name = file.name.toLowerCase();
      if (name.endsWith('.css') || name.endsWith('.mdd')) {
        await _files.copyInto(sourceId, file);
      }
    }
  }

  Future<bool> canImport(String fileName) async {
    final store = await _store();
    return _importerFor(store, fileName) != null;
  }

  Future<ImportHints> readHints(PickedFile file) async {
    final store = await _store();
    final importer = _importerFor(store, file.name);
    if (importer == null) {
      throw const DictionaryImportException('invalidFormat');
    }
    return importer.readHints(file.path, file.name);
  }

  /// 用第一個 `canHandle` 的匯入器匯入。以 `async*` 轉發，呼叫端取消訂閱時
  /// 會一路傳到匯入器（匯入器保證取消訂閱即回復交易）。
  Stream<ImportProgress> import(
    PickedFile file,
    ImportRequest request, {
    required CancelToken cancel,
  }) async* {
    final store = await _store();
    final importer = _importerFor(store, file.name);
    if (importer == null) {
      throw const DictionaryImportException('invalidFormat');
    }
    // 取代前先放掉舊版本的 reader；匯入器會覆蓋同一個 id 的私有檔案。
    if (request.replaceExisting) {
      final contentId = await computeContentId(
        filePath: request.filePath,
        fileName: request.fileName,
      );
      final existingId = await store.findSourceIdByContentId(contentId);
      if (existingId != null) await _onEvict(existingId);
    }
    yield* importer.import(request, cancel: cancel);
  }

  DictionaryImporter? _importerFor(DictionaryStore store, String fileName) {
    for (final factory in _importerFactories) {
      final importer = factory(store);
      if (importer.canHandle(fileName)) return importer;
    }
    return null;
  }
}
