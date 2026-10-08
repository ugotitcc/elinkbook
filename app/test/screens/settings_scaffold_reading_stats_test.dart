import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/screens/adaptive_shell_scaffold.dart';
import 'package:elinkbook/screens/reading_stats_screen.dart';
import 'package:elinkbook/screens/settings_scaffold.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_reading_stats_repository.dart';
import '../support/pump_localized_widget.dart';
import '../support/fake_reader_feature_dependencies.dart';
import '../support/fake_sync_dependencies.dart';

void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('提供 repository 時顯示項目，點擊進入統計畫面', (tester) async {
    _useTallView(tester);
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
        readerFeatures: fakeReaderFeatureDependencies(
          prefsManager: FakeReaderPrefsManager(),
          readingStatsRepository: FakeReadingStatsRepository(),
        ),
        sync: fakeSyncDependencies(),
      ),
    );

    final entry = find.byKey(const Key('settings_reading_stats_button'));
    expect(entry, findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(ReadingStatsScreen), findsOneWidget);
    expect(find.byKey(const Key('reading_stats_heatmap')), findsOneWidget);
  });

  testWidgets('AdaptiveShellScaffold 把 bundle 內的 repository 轉交設定頁', (
    tester,
  ) async {
    _useTallView(tester);
    await pumpLocalizedWidget(
      tester,
      AdaptiveShellScaffold(
        readerFeatures: fakeReaderFeatureDependencies(
          libraryRepository: FakeLibraryRepository(),
          bookImportService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          readingStatsRepository: FakeReadingStatsRepository(),
        ),
        sync: fakeSyncDependencies(),
      ),
    );
    await tester.pumpAndSettle();

    // 書架 → 來源 → 設定（比照 adaptive_shell_scaffold_test.dart 的切換方式）
    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sources_settings_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('settings_reading_stats_button')),
      findsOneWidget,
    );
  });
}
