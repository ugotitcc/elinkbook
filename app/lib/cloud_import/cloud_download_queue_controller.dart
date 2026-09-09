import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/library_enums.dart';
import 'cloud_book_downloader.dart';
import 'cloud_storage_client.dart';

enum CloudDownloadItemStatus {
  pending,
  downloading,
  checkingDuplicate,
  done,
  duplicateSkipped,
  failed,
  cancelled,
}

/// 佇列裡的一筆下載項目（可變狀態，由 [CloudDownloadQueueController] 內部
/// 更新後透過 `notifyListeners()` 通知畫面重繪，不是不可變 value class——
/// 比照 `LibraryBookListController` 既有的 `ChangeNotifier` 慣例）。
class CloudDownloadQueueItem {
  final String id;
  final String name;
  CloudDownloadItemStatus status;

  /// 0.0–1.0；`null` 代表尚未開始或這次下載沒有回報總位元組數（例如
  /// provider 不支援 `Content-Length`）。
  double? progress;

  CloudDownloadQueueItem({
    required this.id,
    required this.name,
    this.status = CloudDownloadItemStatus.pending,
    this.progress,
  });
}

class _QueuedWork {
  final CloudFileEntry entry;
  final CloudStorageClient client;
  final BookImportService importService;
  final LibraryRepository libraryRepository;
  final ComputeRemoteFingerprint computeFingerprint;
  final BookSource source;
  final String? folderName;

  const _QueuedWork({
    required this.entry,
    required this.client,
    required this.importService,
    required this.libraryRepository,
    required this.computeFingerprint,
    required this.source,
    this.folderName,
  });
}

/// 視覺還原（Visual Accuracy Mode，`docs/research/uiux/VISUAL_ANALYSIS.md`）
/// 的產物：Reference 截圖「來源」畫面底部有一個**常駐**的下載佇列（離開
/// 畫面、切去別的目的地瀏覽，佇列仍在背景繼續跑，回到「來源」隨時看得到
/// 進度），不是原本 [CloudBrowserScreen] 用 `showDialog()` 跳出的**模態**
/// 對話框（畫面一關閉，佇列狀態就沒了）。
///
/// 本控制器把下載迴圈本身（原本在 `CloudDownloadQueueDialog` 的
/// `_runQueue()`/`_downloadOne()`）搬出 widget 生命週期，改成純 Dart
/// `ChangeNotifier`——比照 `main.dart` 既有的 `SyncEngine` 設計原則（見
/// `main.dart` `onReadingPositionConflict` 註解）：本身不依賴 Flutter
/// widget 樹，可離線單元測試；需要彈出「重複匯入」確認對話框時，透過
/// 建構子注入的 [onDuplicateConfirm] 回呼橋接（由 `main.dart` 用
/// `navigatorKey.currentContext` 接上真正的 `showCloudDuplicateConfirmDialog`
/// UI），而不是自己持有 `BuildContext`——這樣即使使用者下載途中離開了
/// `CloudBrowserScreen`（甚至整個「來源」目的地），回呼仍能找到目前可用
/// 的畫面顯示對話框。
///
/// 佇列處理維持與原本 `CloudDownloadQueueDialog` 相同的「序列下載」語意
/// （一本下完才下一本，非平行）：[enqueue] 可以在既有佇列還在跑的時候
/// 呼叫，新項目會接在後面依序處理，不會打斷正在下載的項目、也不會平行
/// 搶頻寬。
class CloudDownloadQueueController extends ChangeNotifier {
  CloudDownloadQueueController({required this.onDuplicateConfirm});

  final Future<bool> Function(String message) onDuplicateConfirm;

  // `Map` 在 Dart 保證依插入順序疊代，直接當成「有序＋可用 id 查找」的
  // 佇列項目存放結構，不需要另外維護一份 List 對照。
  final Map<String, CloudDownloadQueueItem> _itemsById = {};
  final Map<String, _QueuedWork> _workById = {};
  final Map<String, CloudDownloadCancellationToken> _tokens = {};
  final List<String> _pendingIds = [];
  bool _running = false;

  List<CloudDownloadQueueItem> get items =>
      List.unmodifiable(_itemsById.values);

  /// 加入一批下載項目。不等待下載完成——呼叫端（`CloudBrowserScreen`）
  /// 呼叫後可以立即繼續瀏覽或離開畫面，實際下載在背景由本控制器自行跑完。
  void enqueue({
    required List<CloudFileEntry> entries,
    required CloudStorageClient client,
    required BookImportService importService,
    required LibraryRepository libraryRepository,
    required ComputeRemoteFingerprint computeFingerprint,
    required BookSource source,
    String? folderName,
  }) {
    if (entries.isEmpty) return;
    for (final entry in entries) {
      // 同一個檔案 id 若已存在佇列中（例如使用者對同一個檔案重複點了兩次
      // 下載），直接略過，不重複加入，避免出現兩列一樣的項目。
      if (_workById.containsKey(entry.id)) continue;
      _workById[entry.id] = _QueuedWork(
        entry: entry,
        client: client,
        importService: importService,
        libraryRepository: libraryRepository,
        computeFingerprint: computeFingerprint,
        source: source,
        folderName: folderName,
      );
      _itemsById[entry.id] = CloudDownloadQueueItem(
        id: entry.id,
        name: entry.name,
      );
      _pendingIds.add(entry.id);
    }
    notifyListeners();
    if (!_running) unawaited(_runLoop());
  }

  Future<void> _runLoop() async {
    _running = true;
    while (_pendingIds.isNotEmpty) {
      final id = _pendingIds.removeAt(0);
      await _downloadOne(id);
    }
    _running = false;
  }

  Future<void> _downloadOne(String id) async {
    final work = _workById[id];
    final item = _itemsById[id];
    if (work == null || item == null) return;

    item.status = CloudDownloadItemStatus.downloading;
    item.progress = null;
    notifyListeners();
    final token = CloudDownloadCancellationToken();
    _tokens[id] = token;
    String? tempPath;
    try {
      tempPath = await downloadCloudFileToTempFile(
        client: work.client,
        entry: work.entry,
        cancellationToken: token,
        onProgress: (received, total) {
          if (total > 0) {
            item.progress = received / total;
            notifyListeners();
          }
        },
      );

      item.status = CloudDownloadItemStatus.checkingDuplicate;
      notifyListeners();
      // work.entry.format 在此保證非 null：能被使用者勾選、進而進入下載
      // 佇列的檔案，其 format 必然已通過 detectCloudFileFormat() 驗證（見
      // 原 CloudDownloadQueueDialog 既有註解）。
      final fingerprint = await work.computeFingerprint(
        tempPath,
        work.entry.format!,
      );
      final existingByFingerprint = await work.libraryRepository
          .findByContentFingerprint(fingerprint);
      if (existingByFingerprint != null) {
        final proceed = await onDuplicateConfirm(
          '偵測到「${work.entry.name}」與本機已有的一本書內容相同，仍要建立新的一份嗎？',
        );
        if (!proceed) {
          final leftover = File(tempPath);
          if (await leftover.exists()) await leftover.delete();
          item.status = CloudDownloadItemStatus.duplicateSkipped;
          notifyListeners();
          return;
        }
      }

      final permanentPath = await promoteCloudFileToPermanent(tempPath);
      await work.importService.importFiles(
        [permanentPath],
        folderName: work.folderName,
        source: work.source,
        cloudFileIds: {permanentPath: work.entry.id},
      );
      item.status = CloudDownloadItemStatus.done;
      item.progress = 1.0;
      notifyListeners();
    } catch (_) {
      if (tempPath != null) {
        final leftover = File(tempPath);
        if (await leftover.exists()) await leftover.delete();
      }
      item.status = token.isCancelled
          ? CloudDownloadItemStatus.cancelled
          : CloudDownloadItemStatus.failed;
      notifyListeners();
    } finally {
      _tokens.remove(id);
    }
  }

  void cancel(String id) => _tokens[id]?.cancel();

  /// 針對單一失敗／已取消的項目重新下載，不影響佇列中其他項目的順序
  /// （比照原 `CloudDownloadQueueDialog._retry()` 既有行為：立即重跑，
  /// 不用重新排隊等待）。
  Future<void> retry(String id) => _downloadOne(id);

  /// 從畫面上移除一筆已結束（完成／失敗／已取消／重複略過）的項目，讓
  /// 使用者可以自行清掉不想再看到的紀錄，避免佇列清單無限累積。
  void dismiss(String id) {
    _itemsById.remove(id);
    _workById.remove(id);
    notifyListeners();
  }
}
