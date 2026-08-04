import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/sync/sync_reading_position.dart';

void main() {
  group('resolveReadingPositionAction', () {
    test('本機不 dirty（positionUpdatedAt 為 null）時，回傳不需要動作', () {
      final action = resolveReadingPositionAction(
        positionUpdatedAt: null,
        lastPushCompletedAt: 1000,
        positionSyncedServerUpdatedAt: '2026-08-01 00:00:00.000Z',
        remoteServerUpdated: '2026-08-01 00:00:00.000Z',
      );

      expect(action, ReadingPositionSyncAction.noAction);
    });

    test('本機不 dirty（positionUpdatedAt 未晚於 lastPushCompletedAt）時，回傳不需要動作', () {
      final action = resolveReadingPositionAction(
        positionUpdatedAt: 1000,
        lastPushCompletedAt: 1000,
        positionSyncedServerUpdatedAt: null,
        remoteServerUpdated: null,
      );

      expect(action, ReadingPositionSyncAction.noAction);
    });

    test('本機 dirty 且遠端沒有既有紀錄（remoteServerUpdated 為 null）時，直接套用本機', () {
      final action = resolveReadingPositionAction(
        positionUpdatedAt: 2000,
        lastPushCompletedAt: 1000,
        positionSyncedServerUpdatedAt: null,
        remoteServerUpdated: null,
      );

      expect(action, ReadingPositionSyncAction.pushLocalDirectly);
    });

    test('本機 dirty 且伺服器 updated 與本機快取值相同時，直接套用本機', () {
      final action = resolveReadingPositionAction(
        positionUpdatedAt: 2000,
        lastPushCompletedAt: 1000,
        positionSyncedServerUpdatedAt: '2026-08-01 00:00:00.000Z',
        remoteServerUpdated: '2026-08-01 00:00:00.000Z',
      );

      expect(action, ReadingPositionSyncAction.pushLocalDirectly);
    });

    test('本機 dirty 且伺服器 updated 與本機快取值不同時，回傳需要詢問使用者', () {
      final action = resolveReadingPositionAction(
        positionUpdatedAt: 2000,
        lastPushCompletedAt: 1000,
        positionSyncedServerUpdatedAt: '2026-08-01 00:00:00.000Z',
        remoteServerUpdated: '2026-08-02 00:00:00.000Z',
      );

      expect(action, ReadingPositionSyncAction.needsUserDecision);
    });

    test('本機 dirty、本機從未同步過（快取為 null）但遠端已有紀錄時，視為衝突（無法確定沒有其他裝置動過）',
        () {
      final action = resolveReadingPositionAction(
        positionUpdatedAt: 2000,
        lastPushCompletedAt: 1000,
        positionSyncedServerUpdatedAt: null,
        remoteServerUpdated: '2026-08-02 00:00:00.000Z',
      );

      expect(action, ReadingPositionSyncAction.needsUserDecision);
    });

    test('lastPushCompletedAt 為 null（從未推送過）時，任何非 null 的 positionUpdatedAt 皆視為 dirty',
        () {
      final action = resolveReadingPositionAction(
        positionUpdatedAt: 1,
        lastPushCompletedAt: null,
        positionSyncedServerUpdatedAt: null,
        remoteServerUpdated: null,
      );

      expect(action, ReadingPositionSyncAction.pushLocalDirectly);
    });
  });

  group('ReadingPositionConflict', () {
    test('可正確建構並讀取本機/雲端兩個版本的快照', () {
      const conflict = ReadingPositionConflict(
        bookId: 'b1',
        bookTitle: '測試書',
        format: BookFileFormat.pdf,
        local: ReadingPositionSnapshot(pdfPageIndex: 10, progress: 0.5),
        remote: ReadingPositionSnapshot(pdfPageIndex: 20, progress: 0.8),
      );

      expect(conflict.local.pdfPageIndex, 10);
      expect(conflict.remote.pdfPageIndex, 20);
    });
  });
}
