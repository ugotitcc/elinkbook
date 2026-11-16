import 'dart:async';

import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/reading_session.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:elinkbook/sync/sync_reading_position.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_reader_prefs_manager.dart';

/// Issue 43：開書時並行檢查雲端位置（方案 A、並行）。
/// 開書不等檢查；使用者選「保留雲端」後才通知畫面跳轉。
void main() {
  late List<String> checked;
  late Completer<ReadingPositionChoice?> pending;
  late int accepted;

  setUp(() {
    checked = [];
    pending = Completer<ReadingPositionChoice?>();
    accepted = 0;
  });

  ReadingSession build({bool hasJumpTarget = false, bool withTrigger = true}) =>
      ReadingSession(
        bookId: 'b1',
        prefsManager: FakeReaderPrefsManager(),
        hasJumpTarget: hasJumpTarget,
        syncCheckpointTrigger: withTrigger
            ? SyncCheckpointTrigger(
                runCheckpoint: () async => SyncCheckpointResult.synced,
                checkReadingPositionOnOpen: (id) {
                  checked.add(id);
                  return pending.future;
                },
              )
            : null,
        onCloudPositionAccepted: () => accepted++,
      );

  test('start() 立即以本書 id 檢查一次雲端位置，且不阻塞（檢查未完成 start 就返回）', () {
    build().start();
    expect(checked, ['b1']);
    expect(pending.isCompleted, isFalse);
  });

  test('帶跳轉目標開書（搜尋結果、書籤）：不檢查，避免覆蓋使用者明確指定的位置', () {
    build(hasJumpTarget: true).start();
    expect(checked, isEmpty);
  });

  test('使用者選保留雲端：通知畫面跳轉一次', () async {
    build().start();
    pending.complete(ReadingPositionChoice.keepCloud);
    await Future<void>.delayed(Duration.zero);
    expect(accepted, 1);
  });

  test('保留本機、未決定、無衝突（null）：不通知跳轉', () async {
    for (final result in [ReadingPositionChoice.keepLocal, null]) {
      accepted = 0;
      pending = Completer<ReadingPositionChoice?>();
      build().start();
      pending.complete(result);
      await Future<void>.delayed(Duration.zero);
      expect(accepted, 0, reason: '結果 $result 不應跳轉');
    }
  });

  test('結果回來前已離開閱讀畫面：選了保留雲端也不再通知（畫面已不存在）', () async {
    final session = build()..start();
    session.close(BookFileFormat.pdf);
    pending.complete(ReadingPositionChoice.keepCloud);
    await Future<void>.delayed(Duration.zero);
    expect(accepted, 0);
  });

  test('未提供 syncCheckpointTrigger：start() 不檢查、不拋例外', () {
    build(withTrigger: false).start();
    expect(checked, isEmpty);
  });
}
