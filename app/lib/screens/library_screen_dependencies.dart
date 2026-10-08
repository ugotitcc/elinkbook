import 'package:flutter/foundation.dart';

import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/cloud_storage_client.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../cloud_import/onedrive_oauth_client.dart';
import '../remote/opds_client.dart';
import '../remote/remote_server_repository.dart';
import '../remote/remote_thumbnail_cache.dart';
import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';

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

/// 收斂介面語言相關欄位（epic-45-interface-i18n Issue 1，`spec.md` §4）。
/// `currentLocaleOverride == null` 代表跟隨系統（比照 `AppLocalePreferences`
/// 既有 nullable 儲存語意，見 `app/lib/l10n/app_locale_preferences.dart`）。
@immutable
class LibraryLocaleDependencies {
  final AppLocale? currentLocaleOverride;
  final ValueChanged<AppLocale?>? onLocaleChanged;

  const LibraryLocaleDependencies({
    this.currentLocaleOverride,
    this.onLocaleChanged,
  });
}
