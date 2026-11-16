import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:elinkbook/sync/sync_reading_position.dart';
import 'package:flutter_test/flutter_test.dart';

/// Issue 43：開書時位置檢查經由 SyncCheckpointTrigger 傳給閱讀畫面。
void main() {
  SyncCheckpointTrigger build({
    Future<ReadingPositionChoice?> Function(String)? check,
  }) =>
      SyncCheckpointTrigger(
        runCheckpoint: () async => SyncCheckpointResult.synced,
        checkReadingPositionOnOpen: check,
      );

  test('checkOnOpen 以書籍 id 呼叫注入的檢查函式並回傳使用者選擇', () async {
    String? seen;
    final trigger = build(check: (id) async {
      seen = id;
      return ReadingPositionChoice.keepCloud;
    });

    expect(await trigger.checkOnOpen('b1'), ReadingPositionChoice.keepCloud);
    expect(seen, 'b1');
  });

  test('未注入檢查函式：回傳 null，不拋例外', () async {
    expect(await build().checkOnOpen('b1'), isNull);
  });

  test('檢查函式拋例外：吞掉並回傳 null，不影響開書', () async {
    final trigger = build(check: (id) async => throw StateError('boom'));
    expect(await trigger.checkOnOpen('b1'), isNull);
  });
}
