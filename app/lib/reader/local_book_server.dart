import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'local_book_handler.dart';

/// 書籍註冊服務 handle。
class BookServeHandle {
  /// 書籍基底 URL（例如 `http://127.0.0.1:53211/book/<token>/`）。
  final Uri bookBaseUri;

  /// 對外檔名（例如 `current.epub`）。
  final String fileName;

  final void Function() _onDispose;

  BookServeHandle({
    required this.bookBaseUri,
    required this.fileName,
    required void Function() onDispose,
  }) : _onDispose = onDispose;

  /// 釋放此註冊，移出 registry 並主動中止任何進行中的檔案串流。
  void dispose() {
    _onDispose();
  }
}

/// Windows 專用本機 loopback 書檔 HTTP 伺服器。
class LocalBookServer {
  /// 全域實例。綁定位址預設 `127.0.0.1`；實驗與診斷時可用
  /// `--dart-define=LOCAL_BOOK_SERVER_BIND=127.0.0.2` 改綁其他 IPv4 loopback 位址
  /// （epic-66 Issue 11：某些機器的 127.0.0.1 會隨機重設連線，見該 Issue 報告）。
  /// 一般建置不要帶這個開關。
  static final instance = LocalBookServer(
    bindAddress: bindAddressFromDefine(
      const String.fromEnvironment('LOCAL_BOOK_SERVER_BIND'),
    ),
  );

  /// 解析 `LOCAL_BOOK_SERVER_BIND` 的值。
  ///
  /// 只接受 IPv4 且為 loopback 的位址；空字串、無法解析、非 loopback
  /// （例如 `0.0.0.0`、區網 IP，會把書檔服務暴露到區網）或 IPv6（`::1` 會讓
  /// `http://::1:port` 無法被 `Uri.parse`）一律退回 `127.0.0.1`，不拋例外。
  static InternetAddress bindAddressFromDefine(String value) {
    final address = InternetAddress.tryParse(value);
    if (address != null &&
        address.type == InternetAddressType.IPv4 &&
        address.isLoopback) {
      return address;
    }
    return InternetAddress.loopbackIPv4;
  }

  final Random _random;
  final InternetAddress _bindAddress;
  final int _bindPort;
  final String _allowedOrigin;

  HttpServer? _server;
  Future<void>? _initFuture;
  final Map<String, RegisteredBook> _registry = {};
  final Map<String, Completer<void>> _completers = {};

  LocalBookServer({
    Random? random,
    InternetAddress? bindAddress,
    int port = 0, // 0 代表由系統隨機配置；僅測試會指定固定埠
    String allowedOrigin = 'https://appassets.androidplatform.net',
  })  : _random = random ?? Random.secure(),
        _bindAddress = bindAddress ?? InternetAddress.loopbackIPv4,
        _bindPort = port,
        _allowedOrigin = allowedOrigin;

  InternetAddress? get address => _server?.address;
  int? get port => _server?.port;

  /// 註冊一本書檔至本機伺服器。若伺服器尚未啟動，將在此時惰性啟動。
  Future<BookServeHandle> register(
    String filePath, {
    String? fileName,
    String? contentType,
  }) async {
    await _ensureStarted();

    final actualFileName = fileName ?? p.basename(filePath);
    final actualContentType = contentType ?? _deduceContentType(actualFileName);

    final token = _generateToken();
    final completer = Completer<void>();

    final registeredBook = RegisteredBook(
      filePath: filePath,
      fileName: actualFileName,
      contentType: actualContentType,
      disposed: completer.future,
    );

    _registry[token] = registeredBook;
    _completers[token] = completer;

    final bookBaseUri = Uri.parse(
      'http://${_server!.address.address}:${_server!.port}/book/$token/',
    );

    return BookServeHandle(
      bookBaseUri: bookBaseUri,
      fileName: actualFileName,
      onDispose: () {
        _registry.remove(token);
        final c = _completers.remove(token);
        if (c != null && !c.isCompleted) {
          c.complete();
        }
      },
    );
  }

  Future<void> _ensureStarted() async {
    if (_server != null) return;
    final future = _initFuture ??= _startServer();
    try {
      await future;
    } catch (_) {
      // 啟動失敗不可永久快取失敗結果，否則之後每次 register 都重丟同一例外，
      // 必須重啟 App 才能恢復；清空後下一次 register 會重新嘗試綁定
      if (identical(_initFuture, future)) _initFuture = null;
      rethrow;
    }
  }

  Future<void> _startServer() async {
    final handler = createLocalBookHandler(
      registry: _registry,
      expectedHost: () => '${_server!.address.address}:${_server!.port}',
      allowedOrigin: _allowedOrigin,
    );

    _server = await shelf_io.serve(handler, _bindAddress, _bindPort);
  }

  String _generateToken() {
    // 至少 128 位元（16 位元組）之 URL-safe 亂數
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _deduceContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.epub')) return 'application/epub+zip';
    if (lower.endsWith('.cbz')) return 'application/x-cbz';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  /// 關閉伺服器並釋放所有已註冊書籍之進行中串流。
  Future<void> close() async {
    for (final completer in _completers.values) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _completers.clear();
    _registry.clear();

    final server = _server;
    _server = null;
    _initFuture = null;
    if (server != null) {
      await server.close(force: true);
    }
  }
}
