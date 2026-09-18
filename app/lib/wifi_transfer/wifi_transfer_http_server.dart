import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'wifi_transfer_service.dart';

/// 「來源」畫面 WiFi 傳書入口啟動的本機 HTTP Server 薄殼層
/// （epic-44-wifi-book-transfer spec.md「`wifi_transfer_http_server.dart`」）。
/// 未使用 `shelf_router`（非本專案依賴）——路由改用簡單的 `request.url.path`
/// 字串/正則比對，路由數量少（4 條），手動比對已足夠清楚。
class WifiTransferHttpServer {
  final WifiTransferService service;
  final int maxConcurrentTransfers;

  WifiTransferHttpServer({
    required this.service,
    this.maxConcurrentTransfers = 2,
  });

  final ValueNotifier<int> _activeTransfersNotifier = ValueNotifier<int>(0);

  /// 目前活躍中的上傳/下載請求數（進入 [withTransferPermit] 的 action
  /// 時 +1、結束/例外時 -1），供 `WifiTransferScreen` 的 `PopScope`
  /// 判斷「離開畫面時是否有傳輸進行中」。
  ValueListenable<int> get activeTransfersNotifier => _activeTransfersNotifier;

  int _activePermits = 0;
  final List<Completer<void>> _waitQueue = [];
  bool _stopped = false;

  /// 併發節流：進入實際傳輸邏輯前先取得許可（超過 [maxConcurrentTransfers]
  /// 時在此等待，不回錯誤碼給客戶端，符合「零意外」原則），結束時（含
  /// 拋出例外）一律釋放並同步更新 [activeTransfersNotifier]。上傳路由
  /// （Issue 3）會在同一個 [action] 呼叫內同步讀完整個請求 body 才回傳，
  /// 可直接把處理邏輯包在這個方法內呼叫。
  ///
  /// **（Issue 2 撰寫下載路由時發現並修正的設計限制）** 下載路由不能沿用
  /// 這個包裝寫法：`shelf` 的 handler 一旦回傳 `shelf.Response`（內含尚未
  /// 被消費的 `Stream<List<int>>` 主體），實際位元組傳輸是在 handler 回傳
  /// 之後才由 `shelf_io` 非同步消費該 Stream；若把「建構 Response」當成
  /// 這裡的 [action]，`finally` 會在 Response 物件建好、位元組其實還沒送
  /// 到客戶端前就釋放許可，讓併發節流對下載形同虛設、
  /// [activeTransfersNotifier] 也無法正確反映「離開畫面時是否真的有傳輸
  /// 中」。下載路由改用下方 [_acquirePermit]／[_releasePermit] 手動配對，
  /// 於串流真正結束時才釋放，見 `_handleDownload`。
  Future<T> withTransferPermit<T>(Future<T> Function() action) async {
    await _acquirePermit();
    try {
      return await action();
    } finally {
      _releasePermit();
    }
  }

  /// 取得一個併發傳輸許可；超過 [maxConcurrentTransfers] 時在此等待，直到
  /// 有人呼叫 [_releasePermit]。伺服器已 [stop] 時，仍在排隊中的呼叫會
  /// 以 [StateError] 結束（見 [stop]）。
  Future<void> _acquirePermit() async {
    if (_activePermits >= maxConcurrentTransfers) {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      await completer.future;
      if (_stopped) {
        throw StateError('WifiTransferHttpServer 已停止，取消排隊中的請求');
      }
    }
    _activePermits++;
    // 【`/receiving-code-review` 審查修正，review-plan-issue-2.md C-1】
    // 伺服器已 dispose() 時，_activeTransfersNotifier 已被銷毀，不可再
    // 寫入 .value（會拋出 FlutterError）——此時已沒有任何 UI 在監聽，
    // 純粹略過通知，計數本身仍照常維護。
    if (!_disposed) {
      _activeTransfersNotifier.value = _activePermits;
    }
  }

  /// 釋放一個由 [_acquirePermit] 取得的許可，喚醒排隊中的下一個呼叫（若有）。
  void _releasePermit() {
    _activePermits--;
    if (!_disposed) {
      _activeTransfersNotifier.value = _activePermits;
    }
    if (_waitQueue.isNotEmpty && !_stopped) {
      _waitQueue.removeAt(0).complete();
    }
  }

  /// 實際 bind 一律用 `InternetAddress.anyIPv4`（`0.0.0.0`），不使用
  /// [ipAddress] 本身 bind——部分客製化 Android 系統對熱點虛擬網卡 IP
  /// 執行 socket bind 容易遇到 `EADDRNOTAVAIL`；[ipAddress] 目前在本方法
  /// 內未使用，只保留給呼叫端（`WifiTransferScreen`）組顯示網址／QR Code
  /// 使用，與實際監聽位址脫鉤，更具強韌性。[port] 為 0 時系統動態分配，
  /// 回傳的 `HttpServer.port` 是實際監聽的埠號。
  Future<HttpServer> start({required String ipAddress, required int port}) {
    return shelf_io.serve(_handleRequest, InternetAddress.anyIPv4, port);
  }

  /// **（`/receiving-code-review` 審查修正，M-4）** 關閉伺服器前先讓
  /// 仍在 [_waitQueue] 排隊等待許可的呼叫端以例外結束（而非永遠卡在
  /// `await completer.future`）——伺服器都已經要關閉了，繼續等待一個
  /// 不會再被釋放的許可沒有意義，讓呼叫端（Issue 2/3 的路由 handler）
  /// 能明確得知「伺服器已關閉」並結束該次 HTTP 請求，而不是讓連線懸掛。
  Future<void> stop(HttpServer server) async {
    _stopped = true;
    while (_waitQueue.isNotEmpty) {
      _waitQueue.removeAt(0).complete();
    }
    await server.close(force: true);
  }

  bool _disposed = false;

  /// 釋放 [_activeTransfersNotifier] 持有的資源（`/receiving-code-review`
  /// 審查修正，review-issue-1.md Minor #2）。呼叫端（`WifiTransferScreen.
  /// dispose()`）應在呼叫 [stop] 之後一併呼叫本方法。
  ///
  /// **（`/receiving-code-review` 審查修正，review-plan-issue-2.md C-1）**
  /// 先標記 [_disposed]，讓仍在進行中的下載（`stop()` 是非同步的，呼叫端
  /// 不會 `await` 它就緊接著呼叫本方法）稍後觸發 [_releasePermit] 時不會
  /// 對已銷毀的 [_activeTransfersNotifier] 賦值。
  void dispose() {
    _disposed = true;
    _activeTransfersNotifier.dispose();
  }

  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    final path = request.url.path;
    // 【`/receiving-code-review` 審查修正，M-3】容錯使用者/瀏覽器手動
    // 輸入 `/index.html` 的情境；`cache-control: no-cache` 避免 App 版本
    // 更新後，PC 端瀏覽器快取了舊版 HTML/JS（此頁面每次由 App 當下的
    // asset bundle 即時提供，不該被瀏覽器快取）。
    if (request.method == 'GET' && (path == '' || path == 'index.html')) {
      final html =
          await rootBundle.loadString('assets/wifi_transfer/index.html');
      return shelf.Response.ok(
        html,
        headers: {
          'content-type': 'text/html; charset=utf-8',
          'cache-control': 'no-cache',
        },
      );
    }
    if (request.method == 'GET' && path == 'api/books') {
      // Issue 2 補上：service.listDownloadableBooks()。
      return shelf.Response(501, body: 'Not Implemented');
    }
    if (request.method == 'GET' &&
        RegExp(r'^api/books/[^/]+/download$').hasMatch(path)) {
      // Issue 2 補上：service.resolveDownloadSource()。
      return shelf.Response(501, body: 'Not Implemented');
    }
    if (request.method == 'POST' && path == 'api/upload') {
      // Issue 3 補上：shelf_multipart 解析＋service.handleUploadedFile()。
      return shelf.Response(501, body: 'Not Implemented');
    }
    return shelf.Response.notFound('Not Found');
  }
}

/// 把 [source] 包裝成一個轉接 `Stream`，在來源串流真正結束時（正常
/// EOF、讀取例外，或下游訂閱被取消——三者對應下載請求的「正常完成」
/// 「讀取失敗」「客戶端中途取消/斷線」）非同步呼叫恰好一次 [onFinished]
/// （epic-44-wifi-book-transfer spec.md「HTTP 路由表」暫存檔清理時機）。
/// `shelf` 的 `Response` 沒有內建「串流真正傳輸完成」回呼，若在回傳
/// `Response.ok(...)` 之後立即清理暫存檔／釋放併發許可，會在客戶端仍在
/// 讀取串流中途執行，造成 0 位元組回應或許可提前釋放讓節流形同虛設。
Stream<List<int>> wrapStreamWithCleanup(
  Stream<List<int>> source,
  Future<void> Function() onFinished,
) {
  var finished = false;
  Future<void> finishOnce() {
    if (finished) return Future<void>.value();
    finished = true;
    return onFinished();
  }

  StreamSubscription<List<int>>? subscription;
  late final StreamController<List<int>> controller;
  controller = StreamController<List<int>>(
    onListen: () {
      subscription = source.listen(
        controller.add,
        onError: (Object error, StackTrace stackTrace) {
          controller.addError(error, stackTrace);
          controller.close();
          finishOnce();
        },
        onDone: () {
          // 【`/receiving-code-review` 審查修正 I-1】controller.close() 只
          // 代表「不會再新增事件」，controller.done 才是「done 事件已真正
          // 送達下游監聽者」——許可（Task 3 的 _releasePermit）／暫存檔
          // 清理必須等到這個時間點才執行，否則會在資料其實還在 controller
          // 內部緩衝佇列、尚未送達 shelf_io／客戶端時就提前釋放。
          controller.close();
          controller.done.then((_) => finishOnce());
        },
        cancelOnError: true,
      );
    },
    // 【`/receiving-code-review` 審查修正 I-1】把下游（`shelf_io` 寫入
    // socket 時）的暫停/恢復訊號轉發給內部對 [source] 的訂閱，避免
    // `file.openRead()` 在慢速網路下無視背壓、把整個檔案讀進無界的
    // controller 內部緩衝佇列（大檔案 OOM 風險）。
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      // 【`/receiving-code-review` 審查修正 I-2】先 await 內部訂閱真正
      // 取消完成（底層檔案控制代碼確實釋放）才呼叫 finishOnce()（可能
      // 觸發 deleteFile()），避免控制代碼尚未釋放就嘗試刪除檔案。
      await subscription?.cancel();
      await finishOnce();
    },
  );
  return controller.stream;
}
