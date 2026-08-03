import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/sync/sync_merge.dart';
import 'package:elinkbook/sync/sync_models.dart';
import 'package:elinkbook/sync/sync_table_specs.dart';

void main() {
  group('normalizeDeletedAt', () {
    test('null 視為未刪除', () {
      expect(normalizeDeletedAt(null), isNull);
    });

    test('0（PocketBase number 欄位未設值的零值）視為未刪除', () {
      expect(normalizeDeletedAt(0), isNull);
    });

    test('非 0 的真實時間戳記正確保留', () {
      expect(normalizeDeletedAt(1735689600000), 1735689600000);
    });
  });

  group('resolveMergeDecision', () {
    test('book_fingerprint 查得到對應本機書籍時，回傳可直接寫入的完整本機列', () {
      final input = RemoteRecordMergeInput(
        remoteId: 'pb-1',
        clientId: 'bm1',
        bookFingerprint: 'fp-1',
        deletedAt: null,
        rawFields: {
          'name': '第一章',
          'epub_locator_json': '',
          'progression': 0.1,
          'pdf_page_index': 0,
        },
      );

      final decision = resolveMergeDecision(
        spec: bookmarksSyncSpec,
        input: input,
        booksByFingerprint: {
          'fp-1': const BookLookup(id: 'b1', format: BookFileFormat.epub),
        },
        notDirtyUpdatedAt: 5000,
      );

      expect(decision.resolved, isTrue);
      expect(decision.localRow!['id'], 'bm1');
      expect(decision.localRow!['book_id'], 'b1');
      expect(decision.localRow!['deleted_at'], isNull);
      expect(decision.localRow!['updated_at'], 5000);
      expect(decision.localRow!['name'], '第一章');
      expect(decision.localRow!['progression'], 0.1);
      expect(decision.localRow!['pdf_page_index'], isNull,
          reason: 'EPUB 格式，pdf_page_index 一律 null');
    });

    test('book_fingerprint 查無對應本機書籍時，回傳暫緩合併決定', () {
      final input = RemoteRecordMergeInput(
        remoteId: 'pb-2',
        clientId: 'bm2',
        bookFingerprint: 'fp-unknown',
        deletedAt: null,
        rawFields: {
          'name': '未匯入書籍的書籤',
          'epub_locator_json': null,
          'progression': 0.2,
          'pdf_page_index': null,
        },
      );

      final decision = resolveMergeDecision(
        spec: bookmarksSyncSpec,
        input: input,
        booksByFingerprint: {},
        notDirtyUpdatedAt: 5000,
      );

      expect(decision.resolved, isFalse);
      expect(decision.localRow, isNull);
    });

    test('bookFingerprint 為 null 時，同樣回傳暫緩合併決定（防禦性情境）', () {
      final input = RemoteRecordMergeInput(
        remoteId: 'pb-3',
        clientId: 'bm3',
        bookFingerprint: null,
        deletedAt: null,
        rawFields: {
          'name': 'X',
          'epub_locator_json': null,
          'progression': 0.1,
          'pdf_page_index': null,
        },
      );

      final decision = resolveMergeDecision(
        spec: bookmarksSyncSpec,
        input: input,
        booksByFingerprint: {'fp-1': const BookLookup(id: 'b1', format: BookFileFormat.epub)},
        notDirtyUpdatedAt: 5000,
      );

      expect(decision.resolved, isFalse);
    });
  });

  group('idsPastTombstoneRetention', () {
    test('deleted_at 早於 30 天前的紀錄被選中', () {
      final now = DateTime.fromMillisecondsSinceEpoch(40 * 24 * 60 * 60 * 1000);
      final rows = [
        {'id': 'a', 'deleted_at': 1 * 24 * 60 * 60 * 1000}, // 遠早於 30 天前
      ];

      expect(idsPastTombstoneRetention(rows: rows, now: now), ['a']);
    });

    test('deleted_at 晚於 30 天前（保留期限內）的紀錄不被選中', () {
      final now = DateTime.fromMillisecondsSinceEpoch(40 * 24 * 60 * 60 * 1000);
      final rows = [
        {'id': 'a', 'deleted_at': 39 * 24 * 60 * 60 * 1000}, // 僅 1 天前
      ];

      expect(idsPastTombstoneRetention(rows: rows, now: now), isEmpty);
    });

    test('deleted_at 為 null（未刪除）的紀錄不受影響', () {
      final now = DateTime.now();
      final rows = [
        {'id': 'a', 'deleted_at': null},
      ];

      expect(idsPastTombstoneRetention(rows: rows, now: now), isEmpty);
    });
  });

  group('maxUpdatedCursor', () {
    test('回傳字串比較後最大的值', () {
      final result = maxUpdatedCursor(
        ['2026-08-01 00:00:00.000Z', '2026-08-03 00:00:00.000Z', '2026-08-02 00:00:00.000Z'],
        null,
      );

      expect(result, '2026-08-03 00:00:00.000Z');
    });

    test('清單為空時維持目前的游標值', () {
      expect(maxUpdatedCursor([], '2026-08-01 00:00:00.000Z'), '2026-08-01 00:00:00.000Z');
    });

    test('新值皆小於等於目前游標時，維持目前游標（不倒退）', () {
      final result = maxUpdatedCursor(
        ['2026-08-01 00:00:00.000Z'],
        '2026-08-02 00:00:00.000Z',
      );

      expect(result, '2026-08-02 00:00:00.000Z');
    });
  });
}
