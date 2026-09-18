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
  /// 拋出例外）一律釋放並同步更新 [activeTransfersNotifier]。Issue 2／3
  /// 的下載/上傳路由須把各自的實際傳輸邏輯包在這個方法內呼叫，例如：
  /// `return withTransferPermit(() => _handleDownload(bookId));`
  Future<T> withTransferPermit<T>(Future<T> Function() action) async {
    if (_activePermits >= maxConcurrentTransfers) {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      await completer.future;
      if (_stopped) {
        throw StateError('WifiTransferHttpServer 已停止，取消排隊中的請求');
      }
    }
    _activePermits++;
    _activeTransfersNotifier.value = _activePermits;
    try {
      return await action();
    } finally {
      _activePermits--;
      _activeTransfersNotifier.value = _activePermits;
      if (_waitQueue.isNotEmpty && !_stopped) {
        _waitQueue.removeAt(0).complete();
      }
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

  /// 釋放 [_activeTransfersNotifier] 持有的資源（`/receiving-code-review`
  /// 審查修正，review-issue-1.md Minor #2）。呼叫端（`WifiTransferScreen.
  /// dispose()`）應在呼叫 [stop] 之後一併呼叫本方法。
  void dispose() {
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
