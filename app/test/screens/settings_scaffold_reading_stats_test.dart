import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/screens/adaptive_shell_scaffold.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/reading_stats_screen.dart';
import 'package:elinkbook/screens/settings_scaffold.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_reading_stats_repository.dart';
import '../support/pump_localized_widget.dart';

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

  testWidgets('readingStatsRepository 為 null 時不顯示「閱讀統計」項目', (tester) async {
    _useTallView(tester);
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
    );
    expect(find.byKey(const Key('settings_reading_stats_button')), findsNothing);
  });

  testWidgets('提供 repository 時顯示項目，點擊進入統計畫面', (tester) async {
    _useTallView(tester);
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        readingStatsRepository: FakeReadingStatsRepository(),
      ),
    );

    final entry = find.byKey(const Key('settings_reading_stats_button'));
    expect(entry, findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(ReadingStatsScreen), findsOneWidget);
    expect(find.byKey(const Key('reading_stats_heatmap')), findsOneWidget);
  });

  testWidgets('AdaptiveShellScaffold 把 bundle 內的 repository 轉交設定頁', (tester) async {
    _useTallView(tester);
    await pumpLocalizedWidget(
      tester,
      AdaptiveShellScaffold(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          readingStatsRepository: FakeReadingStatsRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 書架 → 來源 → 設定（比照 adaptive_shell_scaffold_test.dart 的切換方式）
    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sources_settings_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings_reading_stats_button')), findsOneWidget);
  });

  testWidgets('AdaptiveShellScaffold 的 bundle 沒有 repository 時設定頁不顯示項目', (tester) async {
    _useTallView(tester);
    await pumpLocalizedWidget(
      tester,
      AdaptiveShellScaffold(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sources_settings_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings_reading_stats_button')), findsNothing);
  });
}
