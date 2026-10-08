import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/main.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';

import 'support/fake_book_import_service.dart';
import 'support/fake_source_dependencies.dart';
import 'support/fake_library_repository.dart';
import 'support/fake_reader_prefs_manager.dart';
import 'support/fake_reader_feature_dependencies.dart';
import 'support/fake_sync_dependencies.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App 進入背景（AppLifecycleState.paused）時觸發一次 checkpoint', (
    tester,
  ) async {
    var triggerCallCount = 0;
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      runCheckpoint: () async {
        triggerCallCount++;
        return SyncCheckpointResult.synced;
      },
    );

    await tester.pumpWidget(
      ElinkBookApp(
        sources: fakeSourceDependencies(),
        readerFeatures: fakeReaderFeatureDependencies(
          libraryRepository: FakeLibraryRepository(),
          bookImportService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
        ),
        sync: fakeSyncDependencies(
          syncCheckpointTrigger: syncCheckpointTrigger,
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(triggerCallCount, 1);
  });

  testWidgets('App 恢復前景（AppLifecycleState.resumed）不觸發 checkpoint', (
    tester,
  ) async {
    var triggerCallCount = 0;
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      runCheckpoint: () async {
        triggerCallCount++;
        return SyncCheckpointResult.synced;
      },
    );

    await tester.pumpWidget(
      ElinkBookApp(
        sources: fakeSourceDependencies(),
        readerFeatures: fakeReaderFeatureDependencies(
          libraryRepository: FakeLibraryRepository(),
          bookImportService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
        ),
        sync: fakeSyncDependencies(
          syncCheckpointTrigger: syncCheckpointTrigger,
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(triggerCallCount, 0);
  });

  testWidgets('App 短暫過渡（AppLifecycleState.inactive）不觸發 checkpoint', (
    tester,
  ) async {
    var triggerCallCount = 0;
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      runCheckpoint: () async {
        triggerCallCount++;
        return SyncCheckpointResult.synced;
      },
    );

    await tester.pumpWidget(
      ElinkBookApp(
        sources: fakeSourceDependencies(),
        readerFeatures: fakeReaderFeatureDependencies(
          libraryRepository: FakeLibraryRepository(),
          bookImportService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
        ),
        sync: fakeSyncDependencies(
          syncCheckpointTrigger: syncCheckpointTrigger,
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(
      triggerCallCount,
      0,
      reason:
          'inactive 只是系統對話框短暫遮蓋等過渡狀態，不是真正進入背景，'
          '不應觸發 checkpoint（比照 reader_screen.dart 既有 '
          'didChangeAppLifecycleState 對 ReadingPositionSaver.save 的同一條判斷準則）',
    );
  });

  testWidgets('未提供 syncCheckpointTrigger 時，App 進入背景不拋出例外（零回歸）', (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        sources: fakeSourceDependencies(),
        readerFeatures: fakeReaderFeatureDependencies(
          libraryRepository: FakeLibraryRepository(),
          bookImportService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
        ),
        sync: fakeSyncDependencies(),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
