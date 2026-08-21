import 'package:flutter/foundation.dart';

import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/cloud_storage_client.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../cloud_import/onedrive_oauth_client.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/bookmarks_repository.dart';
import '../reader/custom_fonts_repository.dart';
import '../reader/highlights_repository.dart';
import '../reader/layout_preset_repository.dart';
import '../reader/notes_repository.dart';
import '../remote/opds_client.dart';
import '../remote/remote_server_repository.dart';
import '../remote/remote_thumbnail_cache.dart';
import '../sync/sync_account_repository.dart';
import '../sync/sync_checkpoint_trigger.dart';
import '../sync/sync_client.dart';
import '../theme/app_theme.dart';

/// 收斂 `LibraryScreen` 建構子中「轉送給 `ReaderScreen` 的個人化閱讀功能」
/// 相關欄位（epic-26-architecture-hardening Issue 7），取代原本 6 個獨立
/// 具名參數各自宣告/轉送的做法。皆為 nullable——維持 `LibraryScreen` 現行
/// 「功能未啟用時為 null」的既有語意，純粹收斂宣告/轉送方式，非改變可用性
/// 判斷邏輯。**範圍刻意不含 `syncAccountRepository`**——後者從未轉送給
/// `ReaderScreen`，與本 bundle 其餘欄位足跡不同（詳見
/// `plans/plan-issue-7.md`「規劃階段查證」），改併入 [LibrarySyncDependencies]。
@immutable
class LibraryReaderFeatureRepositories {
  final BookmarksRepository? bookmarksRepository;
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;
  final CustomFontsRepository? customFontsRepository;
  final LayoutPresetRepository? layoutPresetRepository;
  final BookReaderPrefsRepository? bookReaderPrefsRepository;

  const LibraryReaderFeatureRepositories({
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.customFontsRepository,
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
  });
}

/// 收斂帳號同步相關欄位（epic-26-architecture-hardening Issue 7）。
@immutable
class LibrarySyncDependencies {
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final SyncCheckpointTrigger? syncCheckpointTrigger;

  const LibrarySyncDependencies({
    this.syncAccountRepository,
    this.syncClient,
    this.syncCheckpointTrigger,
  });
}

/// 收斂 Google Drive／OneDrive 雲端帳號與匯入相關欄位
/// （epic-26-architecture-hardening Issue 7）。**刻意不含
/// `remoteServerRepository`**——OPDS/Calibre 遠端書庫是獨立網域，且
/// `_openGroupFilteredView()` 自我遞迴目前整組轉送本 bundle 五個欄位、卻
/// 完全不轉送 `remoteServerRepository`，併入會造成欄位洩漏風險（詳見
/// `plans/plan-issue-7.md`「規劃階段查證」），改併入
/// [LibraryRemoteLibraryDependencies]。
@immutable
class LibraryCloudAccountDependencies {
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;
  final CloudStorageClient? googleDriveStorageClient;
  final CloudStorageClient? oneDriveStorageClient;

  const LibraryCloudAccountDependencies({
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.googleDriveStorageClient,
    this.oneDriveStorageClient,
  });
}

/// 收斂 OPDS/Calibre 遠端書庫相關欄位（epic-26-architecture-hardening
/// Issue 7）。**刻意不含 `computeFingerprint`**——`computeFingerprint`
/// 同時被 Google Drive／OneDrive 雲端匯入重複偵測共用，且
/// `_openGroupFilteredView()` 自我遞迴目前轉送 `computeFingerprint` 卻不
/// 轉送本 bundle 任何欄位，兩者足跡不同（詳見 `plans/plan-issue-7.md`
/// 「規劃階段查證」），`computeFingerprint` 維持 `LibraryScreen` 獨立參數。
@immutable
class LibraryRemoteLibraryDependencies {
  final RemoteServerRepository? remoteServerRepository;
  final OpdsClient Function()? createOpdsClient;
  final RemoteThumbnailCache? thumbnailCache;

  const LibraryRemoteLibraryDependencies({
    this.remoteServerRepository,
    this.createOpdsClient,
    this.thumbnailCache,
  });
}

/// 收斂主題／顯示控制相關欄位（epic-26-architecture-hardening Issue 7）。
/// `currentTheme`/`isEinkMode` 沿用 `LibraryScreen` 原欄位現行預設值
/// （`AppTheme.light`/`false`），維持不傳入時的既有行為。
@immutable
class LibraryThemeDependencies {
  final AppTheme currentTheme;
  final bool isEinkMode;
  final ValueChanged<AppTheme>? onThemeChanged;
  final ValueChanged<bool>? onEinkModeChanged;

  const LibraryThemeDependencies({
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.onEinkModeChanged,
  });
}
