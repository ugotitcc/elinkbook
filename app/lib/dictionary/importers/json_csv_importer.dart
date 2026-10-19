// app/lib/dictionary/importers/json_csv_importer.dart
import 'dart:convert';
import 'dart:isolate';

import '../models/dictionary_entry.dart';
import '../models/dictionary_source.dart';
import '../storage/dictionary_store.dart';
import 'csv_rows.dart';
import 'dictionary_importer.dart';
import 'import_pipeline.dart';

/// 匯入 JSON 與 CSV 字典（格式見 spec §5）。
class JsonCsvImporter implements DictionaryImporter {
  JsonCsvImporter({required DictionaryStore store}) : _store = store;

  final DictionaryStore _store;

  @override
  bool canHandle(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.json') || lower.endsWith('.csv');
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
        format: DictionaryFormat.jsonCsv,
        parser: parseJsonCsvFile,
      );

  @override
  Future<ImportHints> readHints(String filePath, String fileName) =>
      readJsonCsvHintsInIsolate(filePath, fileName);
}

/// 在背景 Isolate 讀檔頭資訊。頂層函式，closure 只引用兩個字串參數。
Future<ImportHints> readJsonCsvHintsInIsolate(
  String filePath,
  String fileName,
) =>
    Isolate.run(() => _readJsonCsvHints(filePath, fileName));

ImportHints _readJsonCsvHints(String filePath, String fileName) {
  final fallback = ImportHints(name: fileNameWithoutExtension(fileName));
  if (!filePath.toLowerCase().endsWith('.json')) return fallback;
  final root = _decodeJsonRoot(readImportText(filePath));
  return ImportHints(
    name: _string(root['name']) ?? fallback.name,
    sourceLang: _string(root['sourceLang']),
    targetLang: _string(root['targetLang']),
    licenseNote: _string(root['licenseNote']),
  );
}

String? _string(Object? value) =>
    (value is String && value.trim().isNotEmpty) ? value.trim() : null;

Map<String, Object?> _decodeJsonRoot(String text) {
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    throw const DictionaryImportException('invalidFormat');
  }
  if (root is! Map<String, Object?> || root['entries'] is! List) {
    throw const DictionaryImportException('invalidFormat');
  }
  return root;
}

/// 解析 JSON 或 CSV（依副檔名）。頂層函式，在 Isolate 內執行。
ParsedDictionary parseJsonCsvFile(ParseInput input) {
  final text = readImportText(input.filePath);
  final skips = SkipTracker();
  final entries = <DictionaryEntry>[];
  String? name, sourceLang, targetLang, licenseNote;

  /// 驗證一筆資料；通過就加入 [entries]，否則記錄略過原因。
  void accept(
    int index, {
    String? headword,
    String? definition,
    String? pronunciation,
    String? pos,
  }) {
    final head = headword?.trim() ?? '';
    final body = definition ?? '';
    if (head.isEmpty) {
      skips.add(index, 'missingHeadword');
    } else if (body.trim().isEmpty) {
      skips.add(index, 'missingDefinition');
    } else if (_exceedsLimit(body)) {
      skips.add(index, 'definitionTooLong');
    } else {
      entries.add(
        DictionaryEntry(
          sourceId: input.sourceId,
          headword: head,
          pronunciation: _string(pronunciation),
          partOfSpeech: _string(pos),
          body: body,
          bodyKind: EntryBodyKind.plainText,
        ),
      );
    }
  }

  if (input.filePath.toLowerCase().endsWith('.csv')) {
    final rows = parseCsvRows(text);
    if (rows.isEmpty) throw const DictionaryImportException('invalidFormat');
    final header = rows.first.map((c) => c.trim().toLowerCase()).toList();
    final h = header.indexOf('headword');
    final d = header.indexOf('definition');
    if (h < 0 || d < 0) throw const DictionaryImportException('invalidFormat');
    final p = header.indexOf('pronunciation');
    final o = header.indexOf('pos');
    String? cell(List<String> row, int i) =>
        (i >= 0 && i < row.length) ? row[i] : null;
    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      accept(
        r,
        headword: cell(row, h),
        definition: cell(row, d),
        pronunciation: cell(row, p),
        pos: cell(row, o),
      );
    }
  } else {
    final root = _decodeJsonRoot(text);
    name = _string(root['name']);
    sourceLang = _string(root['sourceLang']);
    targetLang = _string(root['targetLang']);
    licenseNote = _string(root['licenseNote']);
    final list = root['entries']! as List;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e is Map) {
        accept(
          i + 1,
          headword: e['headword'] as String?,
          definition: e['definition'] as String?,
          pronunciation: e['pronunciation'] as String?,
          pos: e['pos'] as String?,
        );
      } else {
        skips.add(i + 1, 'missingHeadword');
      }
    }
  }

  return ParsedDictionary(
    name: name,
    sourceLang: sourceLang,
    targetLang: targetLang,
    licenseNote: licenseNote,
    entries: entries,
    skippedCount: skips.count,
    skipSamples: skips.samples,
  );
}

/// 1 個字元最多 3 個 UTF-8 位元組（BMP）或 4 個（補充平面，佔 2 個 UTF-16
/// 單位），所以 UTF-16 長度 × 3 不超過上限時不必真的編碼。
bool _exceedsLimit(String definition) {
  if (definition.length * 3 <= kMaxDefinitionBytes) return false;
  return utf8.encode(definition).length > kMaxDefinitionBytes;
}
