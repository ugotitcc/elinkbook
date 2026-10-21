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
    Future<void> Function(String sourceId)? onEvict,
  }) : _store = store,
       _files = files,
       _onEvict = onEvict;

  final DictionaryStore _store;
  final DictionaryFileStore _files;

  /// 取代匯入換目錄前，先放掉該字典的 reader（檔案控制代碼）。
  final Future<void> Function(String sourceId)? _onEvict;

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

    // 取代匯入時，新檔先放在 `<id>.staging` 暫存目錄，全部成功後才換掉舊目錄；
    // 失敗或取消只刪暫存目錄，舊字典（來源列與檔案）原封不動。
    final replacing = existing != null;
    final workId = replacing ? stagingIdFor(sourceId) : sourceId;
    var committed = false;
    try {
      if (isCancelled()) {
        controller.add(cancelled);
        return;
      }
      // 上次被系統中止時可能留下暫存目錄，先清掉。
      if (replacing) await _files.deleteAll(workId);

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

      // 2. 搬主檔、複製附屬檔（新目錄是空的，不會有上一次殘留的附屬檔）。
      final workPath = await _files.moveInto(
        workId,
        request.filePath,
        request.fileName,
      );
      // 這次匯入提供的檔名（不分大小寫），沿用舊附屬檔時以它們為準。
      final supplied = <String>{p.basename(request.fileName).toLowerCase()};
      for (final companion in request.companions) {
        final lower = companion.name.toLowerCase();
        if (!lower.endsWith('.mdd') && !lower.endsWith('.css')) continue;
        supplied.add(p.basename(companion.name).toLowerCase());
        await _files.copyInto(
          workId,
          // `copyInto` 只用 path 與 name；size 是給 UI 顯示的，這裡不需要。
          PickedFile(path: companion.path, name: companion.name, size: 0),
        );
      }

      // 取代時沿用舊目錄事後補的附屬檔（複製，不搬移：舊目錄要留到換目錄為止）。
      if (replacing) {
        await _carryOverCompanions(
          fromId: sourceId,
          toId: workId,
          oldMainName: p.basename(existing.storagePath),
          supplied: supplied,
        );
      }

      if (isCancelled()) {
        controller.add(cancelled);
        return;
      }

      // 3. 以暫存（或新）目錄的路徑重新開啟，抽樣詞條找引用的樣式表。
      final referencedCss = await _sampleReferencedCss(workPath);

      if (isCancelled()) {
        controller.add(cancelled);
        return;
      }

      // 4. 取代時此刻才換目錄（換完不再檢查取消，進入提交階段），
      //    再單一交易寫來源列；取代時先刪舊列（舊列的 id 相同）。
      // 主檔落地檔名取自 moveInto 的回傳值（已消毒），不自行重算。
      final storagePath = p.join(
        _files.dirFor(sourceId).path,
        p.basename(workPath),
      );
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
      final backupId = '$sourceId.old';
      if (replacing) await _swapInStaging(sourceId, workId, backupId);
      try {
        await _store.transaction((txn) async {
          if (replacing) await txn.deleteSource(sourceId);
          await txn.insertSource(source, contentId: contentId);
          await txn.setReferencedCss(sourceId, referencedCss);
        });
      } catch (_) {
        // 寫入失敗：把舊目錄換回來，舊字典維持可用。
        if (replacing) await _restoreOld(sourceId, workId, backupId);
        rethrow;
      }
      committed = true;
      if (replacing) {
        try {
          await _files.deleteAll(backupId);
        } catch (error) {
          debugPrint('MdxImporter 清理舊目錄失敗（$sourceId）：$error');
        }
      }

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
      if (!committed) await _cleanup(workId);
    }
  }

  /// 把舊目錄的附屬檔（`.mdd`、`.css`，不含舊主檔）複製進暫存目錄。
  ///
  /// 這次匯入已提供同名（不分大小寫）的檔案時以新的為準，不覆蓋。複製走
  /// [DictionaryFileStore.copyInto]，與其他附屬檔使用同一套檔名消毒。
  Future<void> _carryOverCompanions({
    required String fromId,
    required String toId,
    required String oldMainName,
    required Set<String> supplied,
  }) async {
    final oldDir = _files.dirFor(fromId);
    for (final name in await _files.listFiles(fromId)) {
      final lower = name.toLowerCase();
      if (name == oldMainName || supplied.contains(lower)) continue;
      if (!lower.endsWith('.mdd') && !lower.endsWith('.css')) continue;
      await _files.copyInto(
        toId,
        PickedFile(path: p.join(oldDir.path, name), name: name, size: 0),
      );
    }
  }

  /// 暫存目錄的 id；與正式目錄同層，名稱不會和 uuid 衝突。
  @visibleForTesting
  static String stagingIdFor(String sourceId) => '$sourceId.staging';

  /// 舊目錄先改名為備份，暫存目錄再改成正式名稱。
  Future<void> _swapInStaging(
    String sourceId,
    String stagingId,
    String backupId,
  ) async {
    // reader 還開著舊檔時改名會失敗（Windows），也會讀到換到一半的內容。
    await _onEvict?.call(sourceId);
    await _files.deleteAll(backupId);
    if (await _files.dirFor(sourceId).exists()) {
      await _files.renameDir(sourceId, backupId);
    }
    try {
      await _files.renameDir(stagingId, sourceId);
    } catch (_) {
      await _restoreOld(sourceId, stagingId, backupId);
      rethrow;
    }
  }

  /// 換目錄後失敗：把新目錄退回暫存名稱，舊目錄換回正式名稱。盡力而為，
  /// 失敗只記錄，不蓋掉原始錯誤。
  Future<void> _restoreOld(
    String sourceId,
    String stagingId,
    String backupId,
  ) async {
    try {
      if (await _files.dirFor(backupId).exists()) {
        await _files.deleteAll(stagingId);
        if (await _files.dirFor(sourceId).exists()) {
          await _files.renameDir(sourceId, stagingId);
        }
        await _files.renameDir(backupId, sourceId);
      }
    } catch (error) {
      debugPrint('MdxImporter 還原舊目錄失敗（$sourceId）：$error');
    }
  }

  /// 失敗或取消時刪除這次建立的目錄（取代匯入是暫存目錄，新匯入是正式目錄）；
  /// 清理失敗只記錄，不蓋掉原始錯誤。舊字典的來源列與檔案不受影響。
  Future<void> _cleanup(String workId) async {
    try {
      await _files.deleteAll(workId);
    } catch (error) {
      debugPrint('MdxImporter 清理私有目錄失敗（$workId）：$error');
    }
  }

  /// 新來源排在最前面查：目前最大值 + 1。
  Future<int> _nextPriority() async {
    final all = await _store.listSources();
    return all.isEmpty ? 0 : all.map((s) => s.priority).reduce(max) + 1;
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
