import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum DownloadItemStatus {
  pending,
  downloading,
  checkingDuplicate,
  done,
  duplicateSkipped,
  failed,
  cancelled,
}

/// 佇列裡的一筆下載項目（可變狀態，由 [DownloadQueueController] 內部
/// 更新後透過 `notifyListeners()` 通知畫面重繪，不是不可變 value class——
/// 比照 `LibraryBookListController` 既有的 `ChangeNotifier` 慣例）。
class DownloadQueueItem {
  final String id;
  final String name;
  DownloadItemStatus status;

  /// 0.0–1.0；`null` 代表尚未開始或這次下載沒有回報總位元組數。
  double? progress;

  DownloadQueueItem({
    required this.id,
    required this.name,
    this.status = DownloadItemStatus.pending,
    this.progress,
  });
}

/// 佇列裡一筆下載工作的完整生命週期封裝，由個別來源（雲端硬碟／OPDS
/// 遠端書庫，見 `cloud_import/cloud_download_job.dart`／
/// `remote/remote_download_job.dart`）各自實作背後細節——[DownloadQueueController]
/// 只透過這組介面驅動，不需要認得 `CloudStorageClient`／`OpdsClient` 等
/// 個別 provider 型別，讓「來源」畫面能用同一份常駐佇列同時容納兩種來源
/// 的下載工作（視覺還原 Visual Accuracy Mode，`docs/research/uiux/reference/
/// 來源.png` 的下載佇列不分來源，是同一份清單）。
abstract class QueuedDownloadJob {
  String get id;
  String get name;

  /// 下載到暫存檔，回傳暫存檔路徑。實作內部應建立自己 provider 專屬的
  /// cancellation token，並讓 [cancel] 呼叫它、[isCancelled] 回報其狀態。
  Future<String> download({
    required void Function(int received, int total) onProgress,
  });

  /// 呼叫後應中止進行中的 [download]。
  void cancel();

  /// [download] 是否因呼叫過 [cancel] 而失敗（用於分辨「失敗」與
  /// 「已取消」兩種終態）。
  bool get isCancelled;

  /// 依暫存檔內容計算指紋，供重複匯入偵測使用。
  Future<String> computeFingerprint(String tempPath);

  /// 依指紋查詢本機是否已有內容相同的書籍。
  Future<bool> hasDuplicate(String fingerprint);

  /// 把暫存檔搬到永久位置，回傳永久路徑。
  Future<String> promote(String tempPath);

  /// 匯入圖書庫（單一項目）。
  Future<void> import(String permanentPath);
}

/// 視覺還原（Visual Accuracy Mode，`docs/research/uiux/VISUAL_ANALYSIS.md`）
/// 的產物：Reference 截圖「來源」畫面底部有一個**常駐**的下載佇列（離開
/// 畫面、切去別的目的地瀏覽，佇列仍在背景繼續跑，回到「來源」隨時看得到
/// 進度，且不分下載來源，同一份清單），不是原本 `CloudBrowserScreen`／
/// `RemoteCatalogScreen` 各自用 `showDialog()` 跳出的**模態**對話框（畫面
/// 一關閉，佇列狀態就沒了；兩者也各自維護獨立的佇列，不會顯示在同一份
/// 清單）。
///
/// 本控制器把下載迴圈本身搬出 widget 生命週期，改成純 Dart
/// `ChangeNotifier`——比照 `main.dart` 既有的 `SyncEngine` 設計原則（見
/// `main.dart` `onReadingPositionConflict` 註解）：本身不依賴 Flutter
/// widget 樹，可離線單元測試；需要彈出「重複匯入」確認對話框時，透過
/// 建構子注入的 [onDuplicateConfirm] 回呼橋接（由 `main.dart` 用
/// `navigatorKey.currentContext` 接上真正的 `showCloudDuplicateConfirmDialog`
/// UI），而不是自己持有 `BuildContext`——這樣即使使用者下載途中離開了
/// 觸發下載的那個畫面，回呼仍能找到目前可用的畫面顯示對話框。
///
/// 佇列處理維持「序列下載」語意（一本下完才下一本，非平行）：[enqueueJobs]
/// 可以在既有佇列還在跑的時候呼叫，新項目會接在後面依序處理，不會打斷
/// 正在下載的項目、也不會平行搶頻寬——不論這批新項目來自雲端硬碟還是
/// OPDS 遠端書庫，都進同一條隊伍。
///
/// 【與原本兩份獨立實作的行為差異，刻意調整】原本 OPDS 版本
/// （`RemoteCatalogScreen._DownloadQueueDialog`）把整批下載全部跑完後才
/// 一次呼叫 `importFiles()`（批次匯入），雲端硬碟版本則是每下載完一筆就
/// 立刻呼叫一次。這個常駐佇列沒有「這批何時算跑完」的明確邊界（因為
/// [enqueueJobs] 可以在佇列還在跑的時候持續加入新項目），故統一採用
/// 「每個項目下載完成後立即各自呼叫一次 [QueuedDownloadJob.import]」，
/// 與原本雲端硬碟版本的既有行為一致——結果對圖書庫而言等價（所有成功
/// 下載的檔案最終都會被匯入），只是匯入時機從「整批結束後一次呼叫」變成
/// 「逐筆完成時各自呼叫」。
class DownloadQueueController extends ChangeNotifier {
  DownloadQueueController({required this.onDuplicateConfirm});

  final Future<bool> Function(String name) onDuplicateConfirm;

  // `Map` 在 Dart 保證依插入順序疊代，直接當成「有序＋可用 id 查找」的
  // 佇列項目存放結構，不需要另外維護一份 List 對照。
  final Map<String, DownloadQueueItem> _itemsById = {};
  final Map<String, QueuedDownloadJob> _jobsById = {};
  final List<String> _pendingIds = [];
  bool _running = false;

  List<DownloadQueueItem> get items => List.unmodifiable(_itemsById.values);

  /// 加入一批下載工作。不等待下載完成——呼叫端可以立即繼續瀏覽或離開
  /// 畫面，實際下載在背景由本控制器自行跑完。
  void enqueueJobs(List<QueuedDownloadJob> jobs) {
    if (jobs.isEmpty) return;
    for (final job in jobs) {
      // 同一個 id 若已存在佇列中（例如使用者對同一個檔案重複點了兩次
      // 下載），直接略過，不重複加入，避免出現兩列一樣的項目。
      if (_jobsById.containsKey(job.id)) continue;
      _jobsById[job.id] = job;
      _itemsById[job.id] = DownloadQueueItem(id: job.id, name: job.name);
      _pendingIds.add(job.id);
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
    final job = _jobsById[id];
    final item = _itemsById[id];
    if (job == null || item == null) return;

    item.status = DownloadItemStatus.downloading;
    item.progress = null;
    notifyListeners();
    String? tempPath;
    try {
      tempPath = await job.download(
        onProgress: (received, total) {
          if (total > 0) {
            item.progress = received / total;
            notifyListeners();
          }
        },
      );

      item.status = DownloadItemStatus.checkingDuplicate;
      notifyListeners();
      final fingerprint = await job.computeFingerprint(tempPath);
      final hasDuplicate = await job.hasDuplicate(fingerprint);
      if (hasDuplicate) {
        final proceed = await onDuplicateConfirm(job.name);
        if (!proceed) {
          await _deleteIfExists(tempPath);
          item.status = DownloadItemStatus.duplicateSkipped;
          notifyListeners();
          return;
        }
      }

      final permanentPath = await job.promote(tempPath);
      await job.import(permanentPath);
      item.status = DownloadItemStatus.done;
      item.progress = 1.0;
      notifyListeners();
    } catch (_) {
      if (tempPath != null) await _deleteIfExists(tempPath);
      item.status = job.isCancelled
          ? DownloadItemStatus.cancelled
          : DownloadItemStatus.failed;
      notifyListeners();
    }
  }

  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  void cancel(String id) => _jobsById[id]?.cancel();

  /// 針對單一失敗／已取消的項目重新下載，不影響佇列中其他項目的順序
  /// （立即重跑，不用重新排隊等待）。
  Future<void> retry(String id) => _downloadOne(id);

  /// 從畫面上移除一筆已結束（完成／失敗／已取消／重複略過）的項目，讓
  /// 使用者可以自行清掉不想再看到的紀錄，避免佇列清單無限累積。
  void dismiss(String id) {
    _itemsById.remove(id);
    _jobsById.remove(id);
    notifyListeners();
  }
}
