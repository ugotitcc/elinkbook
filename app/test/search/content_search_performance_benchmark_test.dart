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
  group(
    '全庫搜尋效能驗證 Benchmark（Issue 0 Spike）',
    () {
      SqliteLibraryRepository? repository;
      Directory? tempDir;

      setUpAll(() async {
        TestWidgetsFlutterBinding.ensureInitialized();
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;

        tempDir =
            await Directory.systemTemp.createTemp('elinkbook_search_benchmark');
        final dbPath = p.join(tempDir!.path, 'benchmark.db');

        repository = await SqliteLibraryRepository.open(dbPath);
        await repository!.database.execute('PRAGMA synchronous = OFF');
        await repository!.database.execute('PRAGMA journal_mode = OFF');
        await repository!.database.execute('PRAGMA temp_store = MEMORY');
        await repository!.database.execute('PRAGMA cache_size = -500000');

        final seedStopwatch = Stopwatch()..start();
        await _seedSyntheticContentIndex(
          repository!.database,
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
        await repository?.close();
        if (tempDir != null && await tempDir!.exists()) {
          await tempDir!.delete(recursive: true);
        }
      });

    test(
      '記錄 book_content_fts MATCH 查詢在 1,000 本書規模下的耗時（NFR-2 觀測，PASS/FAIL 結論見 epic.md，不在此斷言）',
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
        final matchOnlyRows = await repository!.database.rawQuery(
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
        final coldRows = await repository!.database
            .rawQuery(productionQuery, [tokenizedQuery, perBookLimit]);
        coldStopwatch.stop();

        final warmDurations = <Duration>[];
        for (var i = 0; i < 4; i++) {
          final warmStopwatch = Stopwatch()..start();
          await repository!.database
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

        // 【review-issue-0.md I-1 修正】NFR-2 的 500ms PASS/FAIL 判定已於
        // Task 3 正式記錄在 epic.md（目前結論：FAIL，Cold 727ms），不在這裡
        // 用 `expect(coldStopwatch.elapsed, lessThan(500ms))` 斷言——若斷言，
        // 這支測試會恆定失敗，等於把一個已知會紅的斷言留在程式碼庫裡用
        // `skip:` 靜音，日後容易被遺忘。改為單純記錄數字（見上方
        // `[benchmark]` print），之後兩層式索引 Issue 完成、要重新驗證時，
        // 直接比對這裡印出的數字與 epic.md 記錄的 NFR-2 門檻即可。
        // 下面這個寬鬆存活檢查不是 NFR-2 門檻，只用來攔截「查詢卡死／
        // 效能劣化到荒謬程度」這種本測試該抓到的意外（例如誤刪索引導致
        // 全表掃描）。
        expect(
          coldStopwatch.elapsed,
          lessThan(const Duration(seconds: 10)),
          reason: '存活檢查（非 NFR-2 門檻）：查詢耗時不應超過 10 秒，超過代表查詢邏輯本身壞掉'
              '（例如意外退化為全表掃描），而非單純未達 500ms——後者的 PASS/FAIL 判定記錄於 '
              'epic.md，不在此斷言。',
        );
      },
      timeout: const Timeout(Duration(minutes: 30)),
    );
  }, skip: '全庫規模 Benchmark（耗時約 20 分鐘，非日常套件項目，見 plan-issue-0.md Task 3 前言），僅供手動執行：flutter test test/search/content_search_performance_benchmark_test.dart --run-skipped');
}
