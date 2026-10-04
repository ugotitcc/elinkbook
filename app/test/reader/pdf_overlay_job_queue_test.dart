import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:elinkbook/reader/pdf_overlay_job_queue.dart';

// epic-59：手動裁切／加粗覆蓋圖的計算風暴回歸測試。
// 真機實測：連翻 30 頁曾發出 888 次計算、同時排隊 644 個，頁面長時間全白。

/// 可由測試手動完成的假工作，並記錄是否被執行。
class _FakeJob {
  final started = Completer<void>();
  final _finish = Completer<void>();
  int runCount = 0;

  Future<void> run() {
    runCount++;
    if (!started.isCompleted) started.complete();
    return _finish.future;
  }

  void finish() => _finish.complete();
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('PdfOverlayJobQueue', () {
    test('同一頁、同一組設定重複登記，只執行一次', () async {
      final queue = PdfOverlayJobQueue();
      final job = _FakeJob();

      for (var i = 0; i < 10; i++) {
        queue.enqueue(page: 5, key: 'k', stillWanted: () => true, run: job.run);
      }
      await _flush();
      job.finish();
      await _flush();

      expect(job.runCount, 1);
    });

    test('一次只跑一個，前一個完成後才開始下一個', () async {
      final queue = PdfOverlayJobQueue();
      final a = _FakeJob();
      final b = _FakeJob();

      queue.enqueue(page: 1, key: 'k', stillWanted: () => true, run: a.run);
      await _flush(); // a 已開跑
      queue.enqueue(page: 2, key: 'k', stillWanted: () => true, run: b.run);
      await _flush();

      expect(a.runCount, 1);
      expect(b.runCount, 0, reason: '前一個尚未完成，不可同時進行');

      a.finish();
      await _flush();
      expect(b.runCount, 1);
      b.finish();
    });

    test('排隊中的工作以最新登記者優先', () async {
      final queue = PdfOverlayJobQueue();
      final running = _FakeJob();
      final older = _FakeJob();
      final newer = _FakeJob();

      queue.enqueue(page: 1, key: 'k', stillWanted: () => true, run: running.run);
      await _flush();
      queue.enqueue(page: 2, key: 'k', stillWanted: () => true, run: older.run);
      queue.enqueue(page: 3, key: 'k', stillWanted: () => true, run: newer.run);

      running.finish();
      await _flush();

      expect(newer.runCount, 1, reason: '最新翻到的頁面先算');
      expect(older.runCount, 0);
      newer.finish();
      await _flush();
      expect(older.runCount, 1);
      older.finish();
    });

    test('輪到時已看不到的頁面，直接丟棄不執行', () async {
      final queue = PdfOverlayJobQueue();
      final running = _FakeJob();
      final stale = _FakeJob();
      var visible = true;

      queue.enqueue(page: 1, key: 'k', stillWanted: () => true, run: running.run);
      await _flush();
      queue.enqueue(
          page: 2, key: 'k', stillWanted: () => visible, run: stale.run);
      visible = false; // 使用者已翻走

      running.finish();
      await _flush();

      expect(stale.runCount, 0);
    });

    test('被丟棄或完成後，同一頁同設定可以重新登記', () async {
      final queue = PdfOverlayJobQueue();
      final first = _FakeJob();
      final second = _FakeJob();
      var wanted = false;

      queue.enqueue(page: 7, key: 'k', stillWanted: () => wanted, run: first.run);
      await _flush();
      expect(first.runCount, 0, reason: '開工前已看不到，丟棄');

      wanted = true;
      queue.enqueue(page: 7, key: 'k', stillWanted: () => wanted, run: second.run);
      await _flush();
      expect(second.runCount, 1);
      second.finish();
    });

    test('同一頁設定改變時，舊設定的排隊工作被新設定取代', () async {
      final queue = PdfOverlayJobQueue();
      final running = _FakeJob();
      final oldKey = _FakeJob();
      final newKey = _FakeJob();

      queue.enqueue(page: 1, key: 'k', stillWanted: () => true, run: running.run);
      await _flush();
      queue.enqueue(page: 9, key: 'old', stillWanted: () => true, run: oldKey.run);
      queue.enqueue(page: 9, key: 'new', stillWanted: () => true, run: newKey.run);

      running.finish();
      await _flush();
      newKey.finish();
      await _flush();

      expect(newKey.runCount, 1);
      expect(oldKey.runCount, 0);
    });

    test('工作丟出例外不會讓佇列卡死', () async {
      final queue = PdfOverlayJobQueue();
      final next = _FakeJob();

      queue.enqueue(
        page: 1,
        key: 'k',
        stillWanted: () => true,
        run: () async => throw StateError('boom'),
      );
      queue.enqueue(page: 2, key: 'k', stillWanted: () => true, run: next.run);
      await _flush();
      await _flush();

      expect(next.runCount, 1);
      next.finish();
    });

    test('風暴情境：30 頁各被重繪數十次，每頁最多只執行一次', () async {
      final queue = PdfOverlayJobQueue();
      final perPage = <int, int>{};

      Future<void> runFor(int page) async {
        perPage.update(page, (v) => v + 1, ifAbsent: () => 1);
      }

      for (var redraw = 0; redraw < 30; redraw++) {
        for (var page = 1; page <= 30; page++) {
          queue.enqueue(
            page: page,
            key: 'k',
            stillWanted: () => true,
            run: () => runFor(page),
          );
        }
      }
      for (var i = 0; i < 40; i++) {
        await _flush();
      }

      expect(perPage.length, 30);
      expect(perPage.values.every((n) => n == 1), isTrue,
          reason: '實測前：888 次開始／244 次完成');
    });
  });

  group('pdfOverlayPageWanted', () {
    const visible = Rect.fromLTWH(0, 1000, 800, 1200);

    test('頁面與可視範圍有交集 → 仍需要', () {
      expect(
        pdfOverlayPageWanted(
            pageRect: const Rect.fromLTWH(0, 900, 800, 400),
            visibleRect: visible),
        isTrue,
      );
    });

    test('緊鄰可視範圍的前後頁（預取範圍內）→ 仍需要，翻頁時才不會閃出未裁切原圖', () {
      expect(
        pdfOverlayPageWanted(
            pageRect: const Rect.fromLTWH(0, 0, 800, 900), // 上一頁
            visibleRect: visible),
        isTrue,
      );
      expect(
        pdfOverlayPageWanted(
            pageRect: const Rect.fromLTWH(0, 2300, 800, 900), // 下一頁
            visibleRect: visible),
        isTrue,
      );
    });

    test('離可視範圍超過一個畫面高度 → 不需要（連翻時被甩在後面的頁面）', () {
      expect(
        pdfOverlayPageWanted(
            pageRect: const Rect.fromLTWH(0, -5000, 800, 900),
            visibleRect: visible),
        isFalse,
      );
      expect(
        pdfOverlayPageWanted(
            pageRect: const Rect.fromLTWH(0, 9000, 800, 900),
            visibleRect: visible),
        isFalse,
      );
    });
  });
}
