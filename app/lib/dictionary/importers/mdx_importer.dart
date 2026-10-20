// MdxImporter：把 `.mdx`（含 `.mdd`、`.css`）搬進 App 私有目錄並寫入來源列
// （epic-63 Issue 6a Task 5）。
//
// 與 JSON/CSV 不同，MDX 匯入不把詞條複製進 `dictionary.db`：整本字典留在
// 私有目錄，查詢時由 reader 池直接讀。因此「匯入」的工作是：
// 重複偵測 → 整檔區塊檢查（主 isolate，見 Task 3）→ 搬檔 → 抽樣前 200 筆
// 找引用的樣式表 → 寫一列來源。
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../content_id.dart';
import '../dictionary_file_store.dart';
import '../mdx_companion_files.dart';
import '../models/dictionary_source.dart';
import '../storage/dictionary_store.dart';
import '../storage/mdx_reader.dart';
import 'dictionary_importer.dart';

/// 匯入 MDX 字典。同一個內容已存在時，`replaceExisting` 會沿用舊的 id、
/// 優先順序與啟用狀態。
class MdxImporter implements DictionaryImporter {
  MdxImporter({
    required DictionaryStore store,
    required DictionaryFileStore files,
  }) : _store = store,
       _files = files;

  final DictionaryStore _store;
  final DictionaryFileStore _files;

  /// 抽樣找 `<link href>` 的詞條數。只讀開頭，不掃整本字典。
  static const int sampleSize = 200;

  @override
  bool canHandle(String fileName) => fileName.toLowerCase().endsWith('.mdx');

  @override
  Future<ImportHints> readHints(String filePath, String fileName) async {
    MdxReader? reader;
    try {
      reader = await MdxReader.open(filePath);
      return ImportHints(name: reader.displayName(fileName));
    } on MdxException catch (error) {
      throw DictionaryImportException(_importCode(error.kind));
    } finally {
      await reader?.close();
    }
  }

  @override
  Stream<ImportProgress> import(
    ImportRequest request, {
    required CancelToken cancel,
  }) {
    final controller = StreamController<ImportProgress>();
    // 呼叫端取消訂閱（離開畫面）也要中止，否則檔案會在背景搬完。
    var unsubscribed = false;
    bool isCancelled() => cancel.isCancelled || unsubscribed;

    Future<void> run() async {
      try {
        await _execute(
          controller: controller,
          request: request,
          isCancelled: isCancelled,
        );
      } catch (error, stack) {
        controller.addError(error, stack);
      } finally {
        await controller.close();
      }
    }

    controller.onListen = () => unawaited(run());
    controller.onCancel = () => unsubscribed = true;
    return controller.stream;
  }

  Future<void> _execute({
    required StreamController<ImportProgress> controller,
    required ImportRequest request,
    required bool Function() isCancelled,
  }) async {
    const cancelled = ImportProgress(
      processed: 0,
      total: 0,
      stage: ImportStage.cancelled,
    );
    controller.add(
      const ImportProgress(processed: 0, total: 0, stage: ImportStage.parsing),
    );
    if (isCancelled()) {
      controller.add(cancelled);
      return;
    }

    final contentId = await computeContentId(
      filePath: request.filePath,
      fileName: request.fileName,
    );
    final existingId = await _store.findSourceIdByContentId(contentId);
    if (existingId != null && !request.replaceExisting) {
      throw DuplicateDictionaryException(existingId);
    }
    // 取代時沿用舊字典的 id、優先順序與啟用狀態，使用者排好的順序不重設。
    final existing = (request.replaceExisting && existingId != null)
        ? await _store.getSource(existingId)
        : null;
    final sourceId = existing?.id ?? const Uuid().v4();
    final priority = existing?.priority ?? await _nextPriority();
    final enabled = existing?.enabled ?? true;

    // 只有真的動到私有目錄後才需要清理；失敗時刪掉整個來源目錄。
    var touchedFiles = false;
    var committed = false;
    try {
      if (isCancelled()) {
        controller.add(cancelled);
        return;
      }

      // 1. 開檔、整檔區塊檢查。先 close 再搬檔，避免之後 rename 時檔案
      //    仍被佔用（Windows／部分 Android 檔案系統會失敗）。
      final reader = await MdxReader.open(request.filePath);
      final String displayName;
      final int entryCount;
      try {
        await reader.validateBlocks(
          onProgress: (done, total) => controller.add(
            ImportProgress(
              processed: done,
              total: total,
              stage: ImportStage.parsing,
            ),
          ),
        );
        displayName = reader.displayName(request.fileName);
        entryCount = reader.meta.entryCount;
      } finally {
        await reader.close();
      }

      if (isCancelled()) {
        controller.add(cancelled);
        return;
      }

      // 2. 搬主檔，複製附屬檔，移除上一次留下、這次沒選到的附屬檔。
      touchedFiles = true;
      final storagePath = await _files.moveInto(
        sourceId,
        request.filePath,
        request.fileName,
      );
      final keep = <String>{p.basename(request.fileName)};
      for (final companion in request.companions) {
        final lower = companion.name.toLowerCase();
        if (!lower.endsWith('.mdd') && !lower.endsWith('.css')) continue;
        await _files.copyInto(
          sourceId,
          // `copyInto` 只用 path 與 name；size 是給 UI 顯示的，這裡不需要。
          PickedFile(path: companion.path, name: companion.name, size: 0),
        );
        keep.add(p.basename(companion.name));
      }
      await _removeStaleFiles(sourceId, keep);

      if (isCancelled()) {
        controller.add(cancelled);
        return;
      }

      // 3. 以私有路徑重新開啟，抽樣詞條找引用的樣式表。
      final referencedCss = await _sampleReferencedCss(storagePath);

      if (isCancelled()) {
        controller.add(cancelled);
        return;
      }

      // 4. 單一交易寫來源列；取代時先刪舊列（舊列的 id 相同）。
      final source = DictionarySource(
        id: sourceId,
        name: request.name ?? displayName,
        format: DictionaryFormat.mdx,
        sourceLang: request.sourceLang,
        targetLang: request.targetLang,
        priority: priority,
        enabled: enabled,
        storagePath: storagePath,
        entryCount: entryCount,
        licenseNote: request.licenseNote,
        importedAt: DateTime.now(),
      );
      await _store.transaction((txn) async {
        if (existing != null) await txn.deleteSource(sourceId);
        await txn.insertSource(source, contentId: contentId);
        await txn.setReferencedCss(sourceId, referencedCss);
      });
      committed = true;

      controller.add(
        ImportProgress(
          processed: entryCount,
          total: entryCount,
          stage: ImportStage.done,
          summary: ImportSummary(
            sourceId: sourceId,
            importedCount: entryCount,
            skippedCount: 0,
            skipSamples: const [],
          ),
        ),
      );
    } on MdxException catch (error) {
      throw DictionaryImportException(_importCode(error.kind));
    } on FileSystemException {
      throw const DictionaryImportException('unreadableFile');
    } finally {
      if (!committed && touchedFiles) {
        await _cleanup(sourceId, replacing: existing != null);
      }
    }
  }

  /// 失敗或取消時刪除私有目錄；清理失敗只記錄，不蓋掉原始錯誤。
  ///
  /// 取代既有字典時，舊來源列指向的檔案已被這次匯入覆蓋或刪除，留著只會
  /// 變成查不到的壞字典，所以連來源列一起刪掉（使用者重新匯入即可）。
  Future<void> _cleanup(String sourceId, {required bool replacing}) async {
    try {
      await _files.deleteAll(sourceId);
    } catch (error) {
      debugPrint('MdxImporter 清理私有目錄失敗（$sourceId）：$error');
    }
    if (!replacing) return;
    try {
      await _store.deleteSource(sourceId);
    } catch (error) {
      debugPrint('MdxImporter 清理來源列失敗（$sourceId）：$error');
    }
  }

  /// 新來源排在最前面查：目前最大值 + 1。
  Future<int> _nextPriority() async {
    final all = await _store.listSources();
    return all.isEmpty ? 0 : all.map((s) => s.priority).reduce(max) + 1;
  }

  /// 移除私有目錄內不在 [keep] 的舊附屬檔（例如換了一批 `.css`）。
  Future<void> _removeStaleFiles(String sourceId, Set<String> keep) async {
    final dir = _files.dirFor(sourceId);
    for (final name in await _files.listFiles(sourceId)) {
      if (keep.contains(name)) continue;
      await File('${dir.path}/$name').delete();
    }
  }

  Future<List<String>> _sampleReferencedCss(String storagePath) async {
    final reader = await MdxReader.open(storagePath);
    try {
      final bodies = await reader.sampleEntryBodies(limit: sampleSize);
      final names = extractReferencedCssNames(bodies).toList()..sort();
      return names;
    } finally {
      await reader.close();
    }
  }
}

/// [MdxErrorKind] 轉成 `DictionaryImportException.code`。
String _importCode(MdxErrorKind kind) => switch (kind) {
  MdxErrorKind.unsupportedCompression => 'unsupportedCompression',
  MdxErrorKind.encryptedRecords => 'encryptedRecords',
  MdxErrorKind.corrupt => 'corruptFile',
  MdxErrorKind.notFound => 'unreadableFile',
  MdxErrorKind.other => 'invalidFormat',
};
