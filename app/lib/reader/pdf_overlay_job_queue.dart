import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 判斷某頁的覆蓋圖計算是否還有意義：頁面落在「可視範圍外擴一個畫面高度」內才需要。
///
/// 外擴是預取：緊鄰的前後頁先算好，翻頁時才不會先閃出未裁切的原圖。
/// 離開這個範圍的頁面（連翻時被甩在後面的）就不再值得計算。
///
/// [pageRect]／[visibleRect] 皆為文件座標（與 `PdfViewerController.layout`、
/// `PdfViewerController.visibleRect` 同一座標系）。
bool pdfOverlayPageWanted({
  required Rect pageRect,
  required Rect visibleRect,
}) =>
    pageRect.overlaps(visibleRect.inflate(visibleRect.height));

/// 手動裁切／加粗覆蓋圖的計算佇列（epic-59）。
///
/// 每頁覆蓋圖需要一次整頁 `page.render()`＋`Isolate.run()` 像素運算，很重。
/// 實機曾發生：覆蓋圖尚未算好的頁面，每次重繪都再發一次計算，完成又觸發
/// `setState` 重繪，形成正回饋迴圈——連翻 30 頁發出 888 次計算、同時排隊 644 個，
/// PDFium 序列化渲染被塞住，頁面長時間全白。
///
/// 這個佇列用三件事打斷迴圈：
/// 1. **去重**：同一頁、同一組設定（[enqueue] 的 `key`）在排隊或執行中時不再登記。
/// 2. **序列化＋最新優先**：一次只跑 [maxConcurrent] 個；排隊中的以最新登記者優先，
///    因為最新翻到的頁面最可能是使用者正在看的那頁。
/// 3. **過期丟棄**：輪到執行時再問一次 `stillWanted`，已翻走的頁面直接略過，
///    不做任何渲染或運算。
class PdfOverlayJobQueue {
  PdfOverlayJobQueue({this.maxConcurrent = 1});

  final int maxConcurrent;

  /// 排隊中的工作；尾端是最新登記者。
  final _pending = <_OverlayJob>[];

  /// 執行中的 (頁碼, 設定) 組合。
  final _running = <(int, Object)>{};

  /// 登記一個計算。
  ///
  /// - [page]：頁碼。
  /// - [key]：這次計算所依據的設定（需有值相等語意，例如裁切範圍＋加粗強度）。
  /// - [stillWanted]：輪到執行時確認這頁是否仍需要；回傳 false 則丟棄。
  /// - [run]：實際的計算。丟出例外會被吞掉並記錄，不影響後續工作。
  void enqueue({
    required int page,
    required Object key,
    required bool Function() stillWanted,
    required Future<void> Function() run,
  }) {
    if (_running.contains((page, key))) return;

    final queuedIndex = _pending.indexWhere((job) => job.page == page);
    if (queuedIndex != -1) {
      // 同頁同設定已在排隊：不重複登記。同頁但設定已變：舊的作廢，由新的取代。
      if (_pending[queuedIndex].key == key) return;
      _pending.removeAt(queuedIndex);
    }

    _pending.add(_OverlayJob(page, key, stillWanted, run));
    scheduleMicrotask(_pump);
  }

  void _pump() {
    while (_running.length < maxConcurrent && _pending.isNotEmpty) {
      final job = _pending.removeLast();
      if (!_isStillWanted(job)) continue;
      final id = (job.page, job.key);
      _running.add(id);
      unawaited(_runJob(job, id));
    }
  }

  bool _isStillWanted(_OverlayJob job) {
    try {
      return job.stillWanted();
    } catch (e) {
      debugPrint('pdf_overlay_job_queue: stillWanted failed: $e');
      return false;
    }
  }

  Future<void> _runJob(_OverlayJob job, (int, Object) id) async {
    try {
      await job.run();
    } catch (e) {
      debugPrint('pdf_overlay_job_queue: job failed (page ${job.page}): $e');
    } finally {
      _running.remove(id);
      scheduleMicrotask(_pump);
    }
  }
}

class _OverlayJob {
  _OverlayJob(this.page, this.key, this.stillWanted, this.run);

  final int page;
  final Object key;
  final bool Function() stillWanted;
  final Future<void> Function() run;
}
