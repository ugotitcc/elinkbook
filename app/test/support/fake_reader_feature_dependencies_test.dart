import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_bookmarks_repository.dart';
import 'fake_reader_feature_dependencies.dart';

void main() {
  group('fakeReaderFeatureDependencies', () {
    test('不傳任何覆寫時，18 個欄位全部有預設 fake（非 null）', () {
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

    test('兩次呼叫不共用狀態（各自獨立的 fake 實例）', () {
      final a = fakeReaderFeatureDependencies();
      final b = fakeReaderFeatureDependencies();

      expect(a.bookmarksRepository, isNot(same(b.bookmarksRepository)));
    });
  });

  group('completeLegacyReaderFeatures', () {
    test('覆寫的欄位原樣（同一實例）帶入，其餘維持預設非 null', () {
      final bookmarks = FakeBookmarksRepository();
      final trigger = SyncCheckpointTrigger(
        runCheckpoint: () async => SyncCheckpointResult.notLoggedIn,
      );

      final features = completeLegacyReaderFeatures(
        bookmarksRepository: bookmarks,
        isFullTextSearchAvailable: false,
      );
      final sync =
          completeLegacySyncDependencies(syncCheckpointTrigger: trigger);

      expect(features.bookmarksRepository, same(bookmarks));
      expect(features.isFullTextSearchAvailable, isFalse);
      expect(features.highlightsRepository, isNotNull);
      expect(sync.syncCheckpointTrigger, same(trigger));
    });

    test('舊 bundle 的 15 個閱讀器欄位全部非 null，且 sync 帶有 syncCheckpointTrigger', () {
      final features = completeLegacyReaderFeatures();
      final sync = completeLegacySyncDependencies();

      expect(features.bookmarksRepository, isNotNull);
      expect(features.highlightsRepository, isNotNull);
      expect(features.notesRepository, isNotNull);
      expect(features.customFontsRepository, isNotNull);
      expect(features.downloadableFontStore, isNotNull);
      expect(features.layoutPresetRepository, isNotNull);
      expect(features.bookReaderPrefsRepository, isNotNull);
      expect(features.ttsProvider, isNotNull);
      expect(features.ttsAudio, isNotNull);
      expect(features.ttsAudioFocusSource, isNotNull);
      expect(features.readerActivityTracker, isNotNull);
      expect(features.searchRepository, isNotNull);
      expect(features.bookImportService, isNotNull);
      expect(features.readingStatsRepository, isNotNull);
      expect(sync.syncCheckpointTrigger, isNotNull);
    });
  });
}
