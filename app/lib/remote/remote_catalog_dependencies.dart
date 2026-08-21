// Copyright (c) 2024 elinkBook. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import '../library/book_content_fingerprint.dart';
import 'opds_client.dart';
import 'remote_thumbnail_cache.dart';

/// 收斂 `RemoteServerListScreen`／`RemoteCatalogScreen`（含其自我遞迴
/// `_openSubsection()`）之間永遠同時出現、缺一不可的三個依賴，取代原本
/// 各自宣告/轉送 3 個獨立具名參數的做法（epic-26-architecture-hardening
/// Issue 6，docs/research/architecture-review-library-remote-screens.md
/// 候選 3）。**範圍刻意侷限這兩個畫面**——`LibraryScreen`／`main.dart`／
/// `CloudBrowserScreen`／`CloudDownloadQueueDialog` 對這三個依賴有各自
/// 獨立、不完全重疊的使用組合，不適合套用同一個 bundle（詳見
/// `plans/plan-issue-6.md`「規劃階段查證」段落），故不動這些檔案。
class RemoteCatalogDependencies {
  final ComputeRemoteFingerprint computeFingerprint;
  final RemoteThumbnailCache thumbnailCache;
  final OpdsClient Function() createOpdsClient;

  const RemoteCatalogDependencies({
    required this.computeFingerprint,
    required this.thumbnailCache,
    required this.createOpdsClient,
  });
}
