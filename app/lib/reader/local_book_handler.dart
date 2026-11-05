import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';

import 'byte_range.dart';

/// 已註冊供本機 HTTP 伺服器服務的書籍資訊。
class RegisteredBook {
  /// 檔案在本機檔案系統之實體絕對路徑。
  final String filePath;

  /// 對外服務之檔名（例如 `current.epub`）。
  final String fileName;

  /// 回應之 MIME 類型（例如 `application/epub+zip`、`application/x-cbz`）。
  final String contentType;

  /// 此註冊項目被釋放時完成的 Future，用以主動中止進行中的串流。
  final Future<void> disposed;

  const RegisteredBook({
    required this.filePath,
    required this.fileName,
    required this.contentType,
    required this.disposed,
  });
}

/// 建立書籍本機 HTTP 伺服器的 shelf [Handler]。
///
/// - 只允許 `GET`、`HEAD`、`OPTIONS`，其餘回傳 405（附 `Allow` 標頭）。
/// - 驗證 `Host` 標頭等於 [expectedHost] 回傳值，不符時回傳 403。
/// - 固定路徑格式為 `/book/<token>/<fileName>`，權杖不在 [registry]、
///   檔名不符、或檔案不存在時一律回傳 404。
/// - `OPTIONS` 預檢回應 204 與完整 CORS 及 Private Network 標頭。
/// - 所有錯誤回應皆無條件附加 `Access-Control-Allow-Origin: [allowedOrigin]`
///   與 `Vary: Origin`。
/// - 本文以 [File.openRead] 串流傳輸，並監聽 [RegisteredBook.disposed] 以主動
///   關閉底層檔案 handle。
Handler createLocalBookHandler({
  required Map<String, RegisteredBook> registry,
  required String Function() expectedHost,
  required String allowedOrigin,
}) {
  final corsHeaders = {
    'Access-Control-Allow-Origin': allowedOrigin,
    'Vary': 'Origin',
  };

  return (Request request) async {
    // 1. OPTIONS 預檢
    if (request.method == 'OPTIONS') {
      return Response(
        204,
        headers: {
          ...corsHeaders,
          'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
          'Access-Control-Allow-Headers': 'Range',
          'Access-Control-Allow-Private-Network': 'true',
          'Access-Control-Max-Age': '86400',
        },
      );
    }

    // 2. 方法檢查
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response(
        405,
        headers: {
          ...corsHeaders,
          'Allow': 'GET, HEAD, OPTIONS',
        },
      );
    }

    // 3. Host 檢查（防 DNS rebinding）
    final host = request.headers['host'];
    if (host != expectedHost()) {
      return Response.forbidden('Forbidden', headers: corsHeaders);
    }

    // 4. 路徑與權杖查表
    final segments = request.url.pathSegments;
    if (segments.length != 3 || segments[0] != 'book') {
      return Response.notFound('Not Found', headers: corsHeaders);
    }

    final token = segments[1];
    final fileName = segments[2];

    final registeredBook = registry[token];
    if (registeredBook == null || registeredBook.fileName != fileName) {
      return Response.notFound('Not Found', headers: corsHeaders);
    }

    final file = File(registeredBook.filePath);
    if (!file.existsSync()) {
      return Response.notFound('Not Found', headers: corsHeaders);
    }

    final fileLength = file.lengthSync();
    final rangeResult = parseByteRange(request.headers['range'], fileLength);

    final commonHeaders = {
      ...corsHeaders,
      'Accept-Ranges': 'bytes',
      'Content-Type': registeredBook.contentType,
      'Cache-Control': 'no-store',
      'Access-Control-Expose-Headers':
          'Content-Length, Content-Range, Accept-Ranges',
    };

    if (rangeResult is ByteRangeUnsatisfiable) {
      return Response(
        416,
        headers: {
          ...commonHeaders,
          'Content-Range': 'bytes */$fileLength',
        },
      );
    }

    int start;
    int end;
    int statusCode;
    Map<String, String> responseHeaders;

    if (rangeResult is ByteRangePartial) {
      start = rangeResult.start;
      end = rangeResult.end;
      final length = end - start + 1;
      statusCode = 206;
      responseHeaders = {
        ...commonHeaders,
        'Content-Range': 'bytes $start-$end/$fileLength',
        'Content-Length': '$length',
      };
    } else {
      start = 0;
      end = fileLength > 0 ? fileLength - 1 : -1;
      statusCode = 200;
      responseHeaders = {
        ...commonHeaders,
        'Content-Length': '$fileLength',
      };
    }

    if (request.method == 'HEAD') {
      return Response(statusCode, headers: responseHeaders);
    }

    final stream = _createManagedStream(
      file,
      start,
      fileLength > 0 ? end + 1 : 0,
      registeredBook.disposed,
    );

    return Response(
      statusCode,
      headers: responseHeaders,
      body: stream,
    );
  };
}

/// 建立受控的檔案串流，監聽 [disposed] 於釋放時立即取消訂閱以釋放 OS 檔案 handle。
Stream<List<int>> _createManagedStream(
  File file,
  int start,
  int end,
  Future<void> disposed,
) {
  late final StreamController<List<int>> controller;
  StreamSubscription<List<int>>? subscription;

  Future<void> closeSub() async {
    final sub = subscription;
    subscription = null;
    try {
      await sub?.cancel();
    } catch (_) {}
    if (!controller.isClosed) {
      controller.addError(const SocketException('Stream aborted'));
      await controller.close();
    }
  }

  controller = StreamController<List<int>>(
    onListen: () {
      subscription = file.openRead(start, end > 0 ? end : 0).listen(
        controller.add,
        onError: controller.addError,
        onDone: () {
          if (!controller.isClosed) {
            controller.close();
          }
        },
        cancelOnError: true,
      );
      disposed.then((_) => closeSub()).catchError((_) => closeSub());
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () => closeSub(),
  );

  return controller.stream;
}
