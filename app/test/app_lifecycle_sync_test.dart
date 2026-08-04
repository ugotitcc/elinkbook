import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/main.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';

import 'support/fake_book_import_service.dart';
import 'support/fake_library_repository.dart';
import 'support/fake_reader_prefs_manager.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App 進入背景（AppLifecycleState.paused）時觸發一次 checkpoint',
      (tester) async {
    var triggerCallCount = 0;
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => true,
      runCheckpoint: () async {
        triggerCallCount++;
      },
    );

    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
        syncCheckpointTrigger: syncCheckpointTrigger,
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(triggerCallCount, 1);
  });

  testWidgets('App 恢復前景（AppLifecycleState.resumed）不觸發 checkpoint', (tester) async {
    var triggerCallCount = 0;
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => true,
      runCheckpoint: () async {
        triggerCallCount++;
      },
    );

    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
        syncCheckpointTrigger: syncCheckpointTrigger,
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(triggerCallCount, 0);
  });

  testWidgets('未提供 syncCheckpointTrigger 時，App 進入背景不拋出例外（零回歸）',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
