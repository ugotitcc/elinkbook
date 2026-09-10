@Timeout(Duration(minutes: 30))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/search/cjk_tokenizer.dart';

/// 依 spec.md §8 的估算基準：一般中文小說 20-30 萬字、7,000-12,000 句，
/// 取 8,000 句／本作為代表值。[bookCount] 預設 1,000（NFR-2 明訂的規模）。
const int _benchmarkBookCount = 1000;
const int _benchmarkSentencesPerBook = 8000;

void _heartbeat() {
  (Zone.current[#test.invoker] as dynamic)?.heartbeat();
}

/// 產生近真實規模的合成內容索引資料，直接寫入 Task 1 建立的
/// `book_content_index`（AFTER INSERT trigger 會自動同步進
/// `book_content_fts`）。每本書每 5,000 句安插一句含
/// 「測試句子編號」關鍵詞的句子，確保之後的 MATCH 查詢有真實命中可算。
Future<void> _seedSyntheticContentIndex(
  Database db, {
  required int bookCount,
  required int sentencesPerBook,
}) async {
  const chunkSize = 2500;
  var batch = db.batch();
  var pendingInBatch = 0;

  Future<void> flushIfNeeded() async {
    if (pendingInBatch >= chunkSize) {
      await batch.commit(noResult: true);
      batch = db.batch();
      pendingInBatch = 0;
      _heartbeat();
    }
  }

  for (var b = 0; b < bookCount; b++) {
    if (b > 0 && b % 100 == 0) {
      // ignore: avoid_print
      print('[benchmark] 資料建置進度：$b / $bookCount 本書...');
    }
    final bookId = 'bench-book-$b';
    batch.insert('books', {
      'id': bookId,
      'title': '效能測試書 $b',
      'format': 'epub',
      'filePath': 'content://bench/$b',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
      'is_downloaded': 1,
    });
    pendingInBatch++;
    for (var s = 0; s < sentencesPerBook; s++) {
      final rawText = s % 5000 == 0
          ? '這是第 $b 本書測試句子編號 $s，包含可搜尋的關鍵詞。'
          : '這是第 $b 本書的普通內容第 $s 句，純粹填充資料量體不含特殊關鍵詞。';
      batch.insert('book_content_index', {
        'id': 'bench-$b-$s',
        'book_id': bookId,
        'chapter_index': s ~/ 100,
        'locator': 'epubcfi(/6/${(s % 20) * 2 + 2}!/4/2/1:0)',
        'raw_text': rawText,
        'token_text': tokenizeForIndex(rawText),
        'created_at': 1000,
      });
      pendingInBatch++;
      await flushIfNeeded();
    }
  }
  if (pendingInBatch > 0) {
    await batch.commit(noResult: true);
  }
  _heartbeat();
}

void main() {
  group('全庫搜尋效能驗證 Benchmark（Issue 0 Spike）', () {
    late SqliteLibraryRepository repository;
    late Directory tempDir;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      tempDir =
          await Directory.systemTemp.createTemp('elinkbook_search_benchmark');
      final dbPath = p.join(tempDir.path, 'benchmark.db');

      repository = await SqliteLibraryRepository.open(dbPath);
      await repository.database.execute('PRAGMA synchronous = OFF');
      await repository.database.execute('PRAGMA journal_mode = OFF');
      await repository.database.execute('PRAGMA temp_store = MEMORY');
      await repository.database.execute('PRAGMA cache_size = -500000');

      final seedStopwatch = Stopwatch()..start();
      await _seedSyntheticContentIndex(
        repository.database,
        bookCount: _benchmarkBookCount,
        sentencesPerBook: _benchmarkSentencesPerBook,
      );
      seedStopwatch.stop();
      // ignore: avoid_print
      print(
          '[benchmark] 合成資料建置完成：$_benchmarkBookCount 本書 × $_benchmarkSentencesPerBook 句 '
          '= ${_benchmarkBookCount * _benchmarkSentencesPerBook} 列，耗時 ${seedStopwatch.elapsed}');
    });

    tearDownAll(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    test(
      'book_content_fts MATCH 查詢在 1,000 本書規模下於 500ms 內回應（NFR-2）',
      () async {
        final tokenizedQuery = tokenizeForQuery('測試句子編號');

        const productionQuery = '''
        SELECT book_id, locator, raw_text FROM (
          SELECT bci.book_id, bci.locator, bci.raw_text,
                 ROW_NUMBER() OVER (
                   PARTITION BY bci.book_id
                   ORDER BY bm25(book_content_fts)
                 ) AS rn
          FROM book_content_fts
          JOIN book_content_index bci ON bci.rowid = book_content_fts.rowid
          WHERE book_content_fts MATCH ?
        ) WHERE rn <= ?
      ''';
        const perBookLimit = 3;

        final matchOnlyStopwatch = Stopwatch()..start();
        final matchOnlyRows = await repository.database.rawQuery(
          'SELECT bci.book_id FROM book_content_fts '
          'JOIN book_content_index bci ON bci.rowid = book_content_fts.rowid '
          'WHERE book_content_fts MATCH ?',
          [tokenizedQuery],
        );
        matchOnlyStopwatch.stop();
        // ignore: avoid_print
        print('[benchmark] 對照組（純 MATCH，不分組排序）耗時：'
            '${matchOnlyStopwatch.elapsedMilliseconds}ms，命中 ${matchOnlyRows.length} 筆'
            '（僅供對照，不參與 NFR-2 判定）');

        final coldStopwatch = Stopwatch()..start();
        final coldRows = await repository.database
            .rawQuery(productionQuery, [tokenizedQuery, perBookLimit]);
        coldStopwatch.stop();

        final warmDurations = <Duration>[];
        for (var i = 0; i < 4; i++) {
          final warmStopwatch = Stopwatch()..start();
          await repository.database
              .rawQuery(productionQuery, [tokenizedQuery, perBookLimit]);
          warmStopwatch.stop();
          warmDurations.add(warmStopwatch.elapsed);
        }
        final warmMillis = warmDurations.map((d) => d.inMilliseconds).toList()
          ..sort();
        final warmMedian = warmMillis[warmMillis.length ~/ 2];

        // ignore: avoid_print
        print('[benchmark] 正式查詢（含 ROW_NUMBER/bm25 分組排序）'
            'Cold：${coldStopwatch.elapsedMilliseconds}ms，命中 ${coldRows.length} 筆；'
            'Warm 4 次：$warmMillis ms，中位數 ${warmMedian}ms');

        expect(coldRows, isNotEmpty, reason: '合成資料應包含至少一筆命中，否則測試本身有誤');
        expect(
          coldStopwatch.elapsed,
          lessThan(const Duration(milliseconds: 500)),
          reason: 'NFR-2：全庫搜尋在 1,000 本書規模下應於 500ms 內回應（以 cold cache '
              '量測，最貼近使用者實際體驗）。若這裡失敗，依 spec.md §8／ADR 0027 決策 4，'
              '需另開 Issue 補建兩層式索引（書籍/章節級粗篩 FTS ＋ 命中後才查句級明細），'
              '不要放寬這個斷言。',
        );
      },
      timeout: const Timeout(Duration(minutes: 30)),
    );
  });
}
