import 'package:flutter/services.dart';

import '../library/library_repository.dart' show kBookMetadataChannel;

/// 對 [uri] 持久化讀取授權（見 CONTEXT.md「持久化授權」），讓 App 重啟後仍能
/// 讀取這個 `content://` 檔案或資料夾。核發成功回傳 `true`；部分文件提供者
/// （例如媒體庫）不保證核發，原生端會拋出 [PlatformException]，此時回傳
/// `false`。
///
/// 本函式只集中「呼叫與例外轉換」，**不決定失敗後怎麼辦**——各呼叫端的處置
/// 刻意不同：書籍匯入／重新連結改複製一份到 App 私有目錄（ADR 0029）；字型
/// 不複製、忽略失敗（ADR 0021）；資料夾匯入無法列舉就中止。只轉換
/// [PlatformException]，其他例外（例如測試環境沒有原生實作的
/// [MissingPluginException]）維持原樣拋出。
Future<bool> persistReadAccess(String uri) async {
  try {
    await kBookMetadataChannel.invokeMethod<void>(
      'takePersistableUriPermission',
      {'uri': uri},
    );
    return true;
  } on PlatformException {
    return false;
  }
}
