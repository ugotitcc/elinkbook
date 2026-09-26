import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// [mockPocketBase] 對 `auth-refresh` 回應的新 token。
const refreshedTestToken = 'refreshed-token';

/// 包裝假 PocketBase 伺服器：`SyncEngine.runCheckpoint()` 每次開頭都會先
/// 呼叫 `authRefresh`（epic-50-sync-token-refresh），這裡統一回應一張新
/// token，其餘請求交給 [handler]，各測試不必各自處理 `auth-refresh`。
/// [onAuthRefresh] 在回應 `auth-refresh` 之前執行，用來模擬續期請求進行中
/// 帳號狀態被改變（例如使用者登出）的競態。
MockClient mockPocketBase(
  Future<http.Response> Function(http.Request request) handler, {
  Future<void> Function()? onAuthRefresh,
}) {
  return MockClient((request) async {
    if (request.url.path == '/api/collections/users/auth-refresh') {
      await onAuthRefresh?.call();
      return http.Response(
        jsonEncode({
          'token': refreshedTestToken,
          'record': {'id': 'user-1'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return handler(request);
  });
}
