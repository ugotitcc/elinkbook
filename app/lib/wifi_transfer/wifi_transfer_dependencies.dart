import 'package:flutter/foundation.dart';

import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import 'network_availability.dart';

/// WiFi 傳書畫面的依賴注入 bundle（epic-44-wifi-book-transfer spec.md
/// 「依賴注入收斂」），比照既有 `LibraryCloudAccountDependencies`／
/// `LibraryRemoteLibraryDependencies` 慣例：全部欄位皆可為 `null`，
/// `SourcesHomeScreen` 依此決定是否顯示「WiFi 傳書」入口（任一欄位為
/// `null` 即不顯示）。
///
/// `materializeContentUri`／`deleteFile` 刻意不進這個 bundle——兩者是純
/// 技術轉接（既有 `readContentUriAll` 頂層函式／`dart:io` 檔案刪除），
/// 沒有「功能未啟用時為 null」的語意，直接在 `WifiTransferScreen`
/// 內部以頂層函式呼叫，不需要呼叫端逐層注入（比照 `RemoteCatalogDependencies`
/// 刻意排除 `computeFingerprint` 的先例：只收斂「呼叫端可能沒有」的
/// 依賴，不收斂「處處皆可用的既有機制」）。純資料容器，無邏輯，不另立
/// 專屬測試檔——由 Task 7/8 的 widget test 間接驗證其欄位正確傳遞。
@immutable
class WifiTransferDependencies {
  final LibraryRepository? libraryRepository;
  final BookImportService? importService;
  final ComputeRemoteFingerprint? computeFingerprint;
  final CheckNetworkAvailability? checkNetworkAvailability;

  const WifiTransferDependencies({
    this.libraryRepository,
    this.importService,
    this.computeFingerprint,
    this.checkNetworkAvailability,
  });
}
