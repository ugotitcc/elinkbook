import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/sync/sync_models.dart';
import 'package:elinkbook/sync/sync_push_planner.dart';
import 'package:elinkbook/sync/sync_table_specs.dart';

void main() {
  group('isDirtyRow', () {
    test('updatedAt 晚於 lastPushCompletedAt 時為 dirty', () {
      expect(isDirtyRow(200, 100), isTrue);
    });

    test('updatedAt 早於或等於 lastPushCompletedAt 時非 dirty', () {
      expect(isDirtyRow(100, 100), isFalse);
      expect(isDirtyRow(50, 100), isFalse);
    });

    test('lastPushCompletedAt 為 null（從未推送過）時，任何 updatedAt 皆為 dirty', () {
      expect(isDirtyRow(1, null), isTrue);
    });
  });

  group('buildPushOperations', () {
    test('每筆操作皆帶 user／client_id／book_fingerprint／deleted_at 與 collection 專屬欄位',
        () {
      final ops = buildPushOperations(
        spec: bookmarksSyncSpec,
        joinedRows: [
          {
            'id': 'bm1',
            'name': '第一章',
            'epub_locator_json': null,
            'progression': 0.1,
            'pdf_page_index': null,
            'deleted_at': null,
            'book_fingerprint': 'fp-1',
          },
        ],
        remoteIdsByClientId: {},
        userId: 'user-1',
      );

      expect(ops, hasLength(1));
      expect(ops.single.collection, SyncCollection.bookmarks);
      expect(ops.single.remoteId, isNull, reason: '從未推送過，走 create');
      expect(ops.single.body['user'], 'user-1');
      expect(ops.single.body['client_id'], 'bm1');
      expect(ops.single.body['book_fingerprint'], 'fp-1');
      expect(ops.single.body['deleted_at'], isNull);
      expect(ops.single.body['name'], '第一章');
    });

    test('remoteIdsByClientId 已有對照時，remoteId 帶入該值（走 update）', () {
      final ops = buildPushOperations(
        spec: bookmarksSyncSpec,
        joinedRows: [
          {
            'id': 'bm1',
            'name': '改名後',
            'epub_locator_json': null,
            'progression': 0.1,
            'pdf_page_index': null,
            'deleted_at': null,
            'book_fingerprint': 'fp-1',
          },
        ],
        remoteIdsByClientId: {'bm1': 'pb-record-abc'},
        userId: 'user-1',
      );

      expect(ops.single.remoteId, 'pb-record-abc');
    });

    test('book_fingerprint 為 null 的列被排除，不產生推送操作', () {
      final ops = buildPushOperations(
        spec: bookmarksSyncSpec,
        joinedRows: [
          {
            'id': 'bm1',
            'name': '第一章',
            'epub_locator_json': null,
            'progression': 0.1,
            'pdf_page_index': null,
            'deleted_at': null,
            'book_fingerprint': null,
          },
        ],
        remoteIdsByClientId: {},
        userId: 'user-1',
      );

      expect(ops, isEmpty);
    });
  });

  group('planPushBatches', () {
    test('筆數未超過上限時只產生一個批次', () {
      final ops = List.generate(
        50,
        (i) => PushOperation(collection: SyncCollection.bookmarks, remoteId: null, body: {'i': i}),
      );

      final batches = planPushBatches(ops, batchLimit: 100);

      expect(batches, hasLength(1));
      expect(batches.single, hasLength(50));
    });

    test('筆數超過上限（101 筆，上限 100）時正確拆成兩個批次', () {
      final ops = List.generate(
        101,
        (i) => PushOperation(collection: SyncCollection.bookmarks, remoteId: null, body: {'i': i}),
      );

      final batches = planPushBatches(ops, batchLimit: 100);

      expect(batches, hasLength(2));
      expect(batches[0], hasLength(100));
      expect(batches[1], hasLength(1));
    });

    test('操作清單為空時回傳空的批次清單', () {
      expect(planPushBatches(const []), isEmpty);
    });
  });
}
