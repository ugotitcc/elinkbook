// Android 真實書庫 EPUB 的 Readium 與 foliate-js metadata 對比測試（epic-66 Issue 12 Task 4）。
//
// 於實機（如 WAVE / BooksPad）上執行，以唯讀模式開啟 library.db，
// 逐一比對書庫中所有 EPUB 書籍在兩套引擎下的詮釋資料提取結果，
// 並確保 library.db 在執行前後分毫不差。
//
// 執行方式：
// cd app && flutter test integration_test/library_metadata_comparison_test.dart -d <device-id>

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show openReadOnlyDatabase;

import 'package:elinkbook/library/android_epub_metadata.dart';
import 'package:elinkbook/library/book_range_reader.dart';
import 'package:elinkbook/library/library_repository.dart' show kBookMetadataChannel;
import 'package:elinkbook/library/metadata_comparison.dart';

double _calculateMedian(List<int> values) {
  if (values.isEmpty) return 0.0;
  final sorted = List<int>.from(values)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length % 2 == 1) {
    return sorted[mid].toDouble();
  } else {
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真實書庫 EPUB 的 Readium 與 foliate-js metadata 對比（唯讀）', (tester) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'library.db');
    final dbFile = File(dbPath);

    if (!await dbFile.exists()) {
      final tmpBackup = File('/data/local/tmp/library.db');
      if (await tmpBackup.exists()) {
        await dbFile.parent.create(recursive: true);
        await tmpBackup.copy(dbFile.path);
      }
    }

    final List<Map<String, Object?>> rows;
    int? sizeBefore;
    DateTime? mtimeBefore;

    if (await dbFile.exists()) {
      final db = await openReadOnlyDatabase(dbPath);
      try {
        rows = await db.rawQuery(
          "SELECT id, title, filePath, format FROM books WHERE format = 'epub' OR filePath LIKE '%.epub' ORDER BY id ASC",
        );
      } finally {
        await db.close();
      }
      sizeBefore = await dbFile.length();
      mtimeBefore = await dbFile.lastModified();
    } else {
      final tmpDir = Directory('/data/local/tmp/test_epubs');
      if (await tmpDir.exists()) {
        final files = tmpDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.epub'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        rows = files.map((f) {
          final name = p.basename(f.path);
          return <String, Object?>{
            'id': name,
            'title': name,
            'filePath': f.path,
          };
        }).toList();
      } else {
        throw StateError('未找到 library.db 且未找到 /data/local/tmp/test_epubs 目錄');
      }
    }

    // 斷言 EPUB 本數大於 0（避免假綠）
    expect(rows.length, greaterThan(0), reason: '書庫內必須有至少一本 EPUB 書籍以進行對比');

    final readiumDurations = <int>[];
    final foliateDurations = <int>[];
    final differences = <Map<String, Object?>>[];
    final diffFieldCounts = <String, int>{};
    final onlyFoliateFailed = <Map<String, Object?>>[];
    final onlyReadiumFailed = <Map<String, Object?>>[];
    final bothFailed = <Map<String, Object?>>[];
    var bothSuccessAndIdentical = 0;

    // 3. 逐一比對每本 EPUB 書籍
    for (final row in rows) {
      final id = row['id'] as String? ?? '';
      final title = row['title'] as String? ?? '';
      final filePath = row['filePath'] as String? ?? '';
      final fileName = p.basename(filePath);

      // 若原 filePath 為 content:// 且權限已被 Android 收回，
      // 退回 /data/local/tmp/test_epubs/<檔名> 進行比對。
      var effectiveUri = filePath;
      if (filePath.startsWith('content://')) {
        try {
          final testLen = await bookLength(filePath);
          if (testLen == null || testLen <= 0) {
            throw StateError('content URI inaccessible');
          }
        } catch (_) {
          final decoded = Uri.decodeFull(filePath);
          final lastSlash = decoded.lastIndexOf('/');
          final name = lastSlash >= 0 ? decoded.substring(lastSlash + 1) : decoded;
          final fallbackFile = File('/data/local/tmp/test_epubs/$name');
          if (await fallbackFile.exists()) {
            effectiveUri = fallbackFile.path;
          }
        }
      }

      // (a) Readium 原生通道（直接呼叫，不經派送函式）
      Map<String, Object?>? readiumResult;
      var readiumFailed = false;
      final swR = Stopwatch()..start();
      try {
        readiumResult = await kBookMetadataChannel.invokeMapMethod<String, Object?>(
          'extractMetadata',
          {'uri': effectiveUri, 'format': 'epub'},
        );
      } catch (e) {
        readiumFailed = true;
      }
      swR.stop();
      final rMs = swR.elapsedMilliseconds;
      readiumDurations.add(rMs);

      // (b) foliate-js 探針（直接呼叫，不經派送函式）
      Map<String, Object?>? foliateResult;
      var foliateFailed = false;
      final swF = Stopwatch()..start();
      try {
        foliateResult = await readEpubMetadataOnAndroid(effectiveUri);
      } catch (e) {
        foliateFailed = true;
      }
      swF.stop();
      final fMs = swF.elapsedMilliseconds;
      foliateDurations.add(fMs);

      // (c) 差異比對
      final List<String> diffs;
      if (readiumFailed && foliateFailed) {
        bothFailed.add({'id': id, 'title': title, 'filePath': filePath});
        diffs = const [];
      } else if (readiumFailed && !foliateFailed) {
        onlyReadiumFailed.add({'id': id, 'title': title, 'filePath': filePath});
        diffs = const ['readium_failed'];
      } else if (!readiumFailed && foliateFailed) {
        onlyFoliateFailed.add({'id': id, 'title': title, 'filePath': filePath});
        diffs = const ['foliate_failed'];
      } else {
        diffs = diffBookMetadata(readiumResult!, foliateResult!);
        if (diffs.isEmpty) {
          bothSuccessAndIdentical++;
        } else {
          differences.add({
            'id': id,
            'title': title,
            'filePath': filePath,
            'diffs': diffs,
          });
          for (final f in diffs) {
            diffFieldCounts[f] = (diffFieldCounts[f] ?? 0) + 1;
          }
        }
      }

      // 每本印輸出一行 JSON 日誌
      final bookLog = jsonEncode({
        'id': id,
        'title': title,
        'fileName': fileName,
        'readiumMs': rMs,
        'foliateMs': fMs,
        'diffs': diffs,
        'readiumFailed': readiumFailed,
        'foliateFailed': foliateFailed,
      });
      // ignore: avoid_print
      print('[library_comparison] $bookLog');
    }

    // 4. 印出彙總日誌
    final rTotalMs = readiumDurations.fold<int>(0, (a, b) => a + b);
    final fTotalMs = foliateDurations.fold<int>(0, (a, b) => a + b);
    final summary = {
      'total': rows.length,
      'identical': bothSuccessAndIdentical,
      'different': differences.length,
      'diffFields': diffFieldCounts,
      'onlyFoliateFailed': onlyFoliateFailed.length,
      'onlyReadiumFailed': onlyReadiumFailed.length,
      'bothFailed': bothFailed.length,
      'readiumTotalMs': rTotalMs,
      'readiumMedianMs': _calculateMedian(readiumDurations),
      'foliateTotalMs': fTotalMs,
      'foliateMedianMs': _calculateMedian(foliateDurations),
    };
    // ignore: avoid_print
    print('[library_comparison_summary] ${jsonEncode(summary)}');

    // 5. 確保 library.db 大小與修改時間不變（完全唯讀，若存在資料庫）
    if (sizeBefore != null && mtimeBefore != null) {
      final sizeAfter = await dbFile.length();
      final mtimeAfter = await dbFile.lastModified();
      expect(sizeAfter, sizeBefore, reason: 'library.db 大小在對比測試過程中不得改變');
      expect(mtimeAfter, mtimeBefore, reason: 'library.db 修改時間在對比測試過程中不得改變');
    }

    // 6. 測試通過條件：沒有差異且沒有「只有 foliate 失敗」
    expect(
      differences,
      isEmpty,
      reason: '發現 metadata 不一致書籍 (${differences.length} 本)：$differences',
    );
    expect(
      onlyFoliateFailed,
      isEmpty,
      reason: '發現 foliate-js 解析失敗但 Readium 成功書籍 (${onlyFoliateFailed.length} 本)：$onlyFoliateFailed',
    );
  });
}
