// app/lib/dictionary/importers/import_pipeline.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../content_id.dart';
import '../models/dictionary_entry.dart';
import '../models/dictionary_source.dart';
import '../storage/dictionary_store.dart';
import 'dictionary_importer.dart';

/// 單筆 `definition` 的上限（UTF-8 位元組）。
const int kMaxDefinitionBytes = 65536;

/// 每批寫入的詞條數。
const int kImportBatchSize = 2000;

/// 交給 Isolate 的解析輸入。只含可跨 Isolate 傳遞的型別。
///
/// [sourceId] 在解析前就決定好，解析器直接用它建立詞條，主 Isolate 寫入時
/// 不必再逐筆複製。
class ParseInput {
  const ParseInput({required this.filePath, required this.sourceId});

  final String filePath;
  final String sourceId;
}

/// 解析結果。[entries] 的 `sourceId` 已填好。
class ParsedDictionary {
  const ParsedDictionary({
    required this.entries,
    this.name,
    this.sourceLang,
    this.targetLang,
    this.licenseNote,
    this.skippedCount = 0,
    this.skipSamples = const [],
  });

  final String? name;
  final String? sourceLang;
  final String? targetLang;
  final String? licenseNote;
  final List<DictionaryEntry> entries;
  final int skippedCount;
  final List<ImportSkip> skipSamples;
}

/// 解析函式必須是頂層函式（見 `CLAUDE.md`：`Isolate.run()` 的 closure 限制）。
typedef DictionaryParser = ParsedDictionary Function(ParseInput input);

/// 在背景 Isolate 執行 [parser]。頂層函式，closure 只引用兩個參數。
Future<ParsedDictionary> runParserInIsolate(
  DictionaryParser parser,
  ParseInput input,
) =>
    Isolate.run(() => parser(input));

/// 收集被略過的筆數與前 [_maxSamples] 筆樣本。
class SkipTracker {
  static const _maxSamples = 5;

  int count = 0;
  final List<ImportSkip> samples = [];

  void add(int index, String reason) {
    count++;
    if (samples.length < _maxSamples) {
      samples.add(ImportSkip(index: index, reason: reason));
    }
  }
}

/// 讀檔並以嚴格 UTF-8 解碼，去掉開頭的 BOM。
/// 讀不到 → `unreadableFile`；非法位元組 → `invalidEncoding`。
String readImportText(String filePath) {
  final List<int> bytes;
  try {
    bytes = File(filePath).readAsBytesSync();
  } on FileSystemException {
    throw const DictionaryImportException('unreadableFile');
  }
  final String text;
  try {
    text = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw const DictionaryImportException('invalidEncoding');
  }
  return text.startsWith('﻿') ? text.substring(1) : text;
}

/// 去掉副檔名的檔名，當作字典名稱的最後備案。
String fileNameWithoutExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}

class _ImportCancelled implements Exception {
  const _ImportCancelled();
}

/// 兩個匯入器共用的流程：
/// 重複偵測 → 決定 sourceId → Isolate 解析 → 單一交易分批寫入 → 取消回復。
///
/// 所有失敗都用 `addError` 發出再關閉 stream，不在非同步回呼裡直接丟出。
Stream<ImportProgress> runImportPipeline({
  required DictionaryStore store,
  required ImportRequest request,
  required CancelToken cancel,
  required DictionaryFormat format,
  required DictionaryParser parser,
  String Function()? newId,
  DateTime Function()? now,
}) {
  final controller = StreamController<ImportProgress>();

  Future<void> run() async {
    try {
      await _execute(
        controller: controller,
        store: store,
        request: request,
        cancel: cancel,
        format: format,
        parser: parser,
        newId: newId ?? () => const Uuid().v4(),
        now: now ?? DateTime.now,
      );
    } catch (e, st) {
      controller.addError(e, st);
    } finally {
      await controller.close();
    }
  }

  controller.onListen = () => unawaited(run());
  return controller.stream;
}

Future<void> _execute({
  required StreamController<ImportProgress> controller,
  required DictionaryStore store,
  required ImportRequest request,
  required CancelToken cancel,
  required DictionaryFormat format,
  required DictionaryParser parser,
  required String Function() newId,
  required DateTime Function() now,
}) async {
  const cancelled = ImportProgress(
    processed: 0,
    total: 0,
    stage: ImportStage.cancelled,
  );
  controller.add(
    const ImportProgress(processed: 0, total: 0, stage: ImportStage.parsing),
  );
  if (cancel.isCancelled) {
    controller.add(cancelled);
    return;
  }

  final contentId = await computeContentId(
    filePath: request.filePath,
    fileName: request.fileName,
  );
  final existingId = await store.findSourceIdByContentId(contentId);
  if (existingId != null && !request.replaceExisting) {
    throw DuplicateDictionaryException(existingId);
  }

  // 解析前先決定 sourceId、優先順序與啟用狀態。取代時沿用舊字典的三者，
  // 使用者排好的順序與開關不因取代而重設。
  final existing = (request.replaceExisting && existingId != null)
      ? await store.getSource(existingId)
      : null;
  final String sourceId;
  final int priority;
  final bool enabled;
  if (existing != null) {
    sourceId = existing.id;
    priority = existing.priority;
    enabled = existing.enabled;
  } else {
    sourceId = newId();
    final all = await store.listSources();
    priority = all.isEmpty ? 0 : all.map((s) => s.priority).reduce(max) + 1;
    enabled = true;
  }

  final parsed = await runParserInIsolate(
    parser,
    ParseInput(filePath: request.filePath, sourceId: sourceId),
  );
  if (parsed.entries.isEmpty) {
    throw const DictionaryImportException('noValidEntries');
  }
  if (cancel.isCancelled) {
    controller.add(cancelled);
    return;
  }

  final entries = parsed.entries;
  final total = entries.length;
  final licenseNote = request.licenseNote.isNotEmpty
      ? request.licenseNote
      : (parsed.licenseNote ?? '');
  final source = DictionarySource(
    id: sourceId,
    name: request.name ??
        parsed.name ??
        fileNameWithoutExtension(request.fileName),
    format: format,
    sourceLang: request.sourceLang,
    targetLang: request.targetLang,
    priority: priority,
    enabled: enabled,
    storagePath: '',
    entryCount: total,
    licenseNote: licenseNote,
    importedAt: now(),
  );

  try {
    // 交易內所有寫入只能用 txnStore，用外層 store 會等不到連線而卡死。
    await store.transaction((txnStore) async {
      if (existing != null) await txnStore.deleteSource(sourceId);
      await txnStore.insertSource(source, contentId: contentId);
      for (var i = 0; i < total; i += kImportBatchSize) {
        if (cancel.isCancelled) throw const _ImportCancelled();
        final end = min(i + kImportBatchSize, total);
        await txnStore.insertEntries(entries.sublist(i, end));
        controller.add(ImportProgress(processed: end, total: total));
      }
      if (cancel.isCancelled) throw const _ImportCancelled();
    });
  } on _ImportCancelled {
    controller.add(cancelled);
    return;
  }

  controller.add(
    ImportProgress(
      processed: total,
      total: total,
      stage: ImportStage.done,
      summary: ImportSummary(
        sourceId: sourceId,
        importedCount: total,
        skippedCount: parsed.skippedCount,
        skipSamples: parsed.skipSamples,
      ),
    ),
  );
}
