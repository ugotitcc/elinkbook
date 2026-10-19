// app/lib/dictionary/importers/cedict_importer.dart
import 'dart:convert';
import 'dart:isolate';

import '../models/dictionary_entry.dart';
import '../models/dictionary_source.dart';
import '../storage/dictionary_store.dart';
import 'dictionary_importer.dart';
import 'import_pipeline.dart';

/// 匯入 CC-CEDICT 格式的純文字字典（格式見 spec §5）。
class CedictImporter implements DictionaryImporter {
  CedictImporter({required DictionaryStore store}) : _store = store;

  final DictionaryStore _store;

  @override
  bool canHandle(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.u8') || lower.endsWith('.txt');
  }

  @override
  Stream<ImportProgress> import(
    ImportRequest request, {
    required CancelToken cancel,
  }) =>
      runImportPipeline(
        store: _store,
        request: request,
        cancel: cancel,
        format: DictionaryFormat.cedict,
        parser: parseCedictFile,
      );

  @override
  Future<ImportHints> readHints(String filePath, String fileName) =>
      readCedictHintsInIsolate(filePath, fileName);
}

/// 在背景 Isolate 讀檔頭授權。頂層函式，closure 只引用兩個字串參數。
Future<ImportHints> readCedictHintsInIsolate(
  String filePath,
  String fileName,
) =>
    Isolate.run(() => _readCedictHints(filePath, fileName));

ImportHints _readCedictHints(String filePath, String fileName) {
  final text = readImportText(filePath);
  return ImportHints(
    name: fileNameWithoutExtension(fileName),
    sourceLang: 'zh',
    targetLang: 'en',
    licenseNote: _licenseOf(text),
  );
}

final _licenseHeader = RegExp(r'^#!\s*license=(.*)$', multiLine: true);

String? _licenseOf(String text) {
  final value = _licenseHeader.firstMatch(text)?.group(1)?.trim();
  return (value == null || value.isEmpty) ? null : value;
}

/// `繁體 簡體 [pin1 yin1] /釋義1/釋義2/`
final _dataLine = RegExp(r'^(\S+)\s+(\S+)\s+\[([^\]]*)\]\s+/(.*)/$');

/// 解析 CC-CEDICT。頂層函式，在 Isolate 內執行。
ParsedDictionary parseCedictFile(ParseInput input) {
  final text = readImportText(input.filePath);
  final skips = SkipTracker();
  final entries = <DictionaryEntry>[];
  var recordCount = 0;

  final lines = const LineSplitter().convert(text);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final m = _dataLine.firstMatch(line);
    if (m == null) {
      skips.add(i + 1, 'malformedLine');
      continue;
    }
    final traditional = m.group(1)!;
    final simplified = m.group(2)!;
    final pronunciation = m.group(3)!;
    // 行尾的 `/` 會切出空字串，濾掉才不會讓 body 頭尾多出空行。
    final body = m
        .group(4)!
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .join('\n');
    if (body.isEmpty) {
      skips.add(i + 1, 'malformedLine');
      continue;
    }
    recordCount++;
    for (final headword in {traditional, simplified}) {
      entries.add(
        DictionaryEntry(
          sourceId: input.sourceId,
          headword: headword,
          pronunciation: pronunciation.isEmpty ? null : pronunciation,
          body: body,
          bodyKind: EntryBodyKind.plainText,
        ),
      );
    }
  }

  return ParsedDictionary(
    licenseNote: _licenseOf(text),
    entries: entries,
    recordCount: recordCount,
    skippedCount: skips.count,
    skipSamples: skips.samples,
  );
}
