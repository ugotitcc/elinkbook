import 'package:flutter_test/flutter_test.dart';

import 'fake_bookmarks_repository.dart';
import 'fake_full_text_search_settings_repository.dart';
import 'fake_reader_feature_dependencies.dart';

void main() {
  group('fakeReaderFeatureDependencies', () {
    test('不傳任何覆寫時，19 個欄位全部有預設 fake（非 null）', () {
      final deps = fakeReaderFeatureDependencies();

      expect(deps.prefsManager, isNotNull);
      expect(deps.libraryRepository, isNotNull);
      expect(deps.bookImportService, isNotNull);
      expect(deps.bookmarksRepository, isNotNull);
      expect(deps.highlightsRepository, isNotNull);
      expect(deps.notesRepository, isNotNull);
      expect(deps.customFontsRepository, isNotNull);
      expect(deps.downloadableFontStore, isNotNull);
      expect(deps.layoutPresetRepository, isNotNull);
      expect(deps.bookReaderPrefsRepository, isNotNull);
      expect(deps.searchRepository, isNotNull);
      expect(deps.fullTextSearchSettingsRepository, isNotNull);
      expect(deps.readingStatsRepository, isNotNull);
      expect(deps.readerActivityTracker, isNotNull);
      expect(deps.syncCheckpointTrigger, isNotNull);
      expect(deps.ttsProvider, isNotNull);
      expect(deps.ttsAudio, isNotNull);
      expect(deps.ttsAudioFocusSource, isNotNull);
      expect(deps.isFullTextSearchAvailable, isTrue);
    });

    test('覆寫的欄位原樣（同一實例）帶入，其餘維持預設', () {
      final bookmarks = FakeBookmarksRepository();

      final deps = fakeReaderFeatureDependencies(
        bookmarksRepository: bookmarks,
        isFullTextSearchAvailable: false,
      );

      expect(deps.bookmarksRepository, same(bookmarks));
      expect(deps.isFullTextSearchAvailable, isFalse);
    });

    test('fullTextSearchSettingsRepository 覆寫原樣（同一實例）帶入', () {
      final fts = FakeFullTextSearchSettingsRepository();

      final deps = fakeReaderFeatureDependencies(
        fullTextSearchSettingsRepository: fts,
      );

      expect(deps.fullTextSearchSettingsRepository, same(fts));
    });

    test('兩次呼叫不共用狀態（各自獨立的 fake 實例）', () {
      final a = fakeReaderFeatureDependencies();
      final b = fakeReaderFeatureDependencies();

      expect(a.bookmarksRepository, isNot(same(b.bookmarksRepository)));
    });
  });
}
