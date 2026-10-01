import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel;

import '../reader/reader_console_log.dart';

/// 背景任務佇列的 method channel，原生端 `ReaderResourceChannel.kt` 的
/// `probeUriAccess` 掛在這條通道上。`MethodChannel` 物件只是依名稱字串指向
/// 同一條平台通道的輕量代理，這裡與 `foliate_native_bridge.dart` 內的同名
/// 宣告是兩個各自獨立、但指向同一條原生通道的物件實例，皆可正常運作。
const _readerResourcesCacheChannel =
    MethodChannel('elinkbook/reader_resources_cache');

/// `content://` URI 存取探測結果（epic-15-storage-permission Issue 1；
/// epic-54 Issue 4 起獨立於閱讀器引擎，見 CONTEXT.md「存取探測」）。
/// 對應原生 `ReaderResourceChannel.probeUriAccess` 回傳的四個代碼字串。
enum StorageAccessProbeResult {
  /// 可以開啟輸入串流。
  readable,

  /// 原生端捕捉到 `SecurityException`：App 對此 URI 的存取權限已失效。
  permissionRevoked,

  /// 原生端捕捉到 `FileNotFoundException`，或內容提供者回傳 null 串流：
  /// 原始檔案可能已被移動、改名或刪除。
  fileNotFound,

  /// 其他例外、逾時、通道不存在，或無法辨識的代碼。
  unknownError,
}

typedef ProbeStorageAccess = Future<StorageAccessProbeResult> Function(
    String uri);

/// 探測原生呼叫的逾時上限。有缺陷的第三方／雲端文件提供者可能讓
/// `openInputStream` 卡住，逾時一律視為 [StorageAccessProbeResult.unknownError]，
/// 閱讀器退回通用錯誤文字，不會永遠停在載入中。
const Duration kStorageAccessProbeTimeout = Duration(seconds: 3);

/// 探測 [uri] 是否仍可讀取（epic-15-storage-permission Issue 1）。
///
/// 可覆寫的頂層函式變數（比照 `cacheBookForServing` 既有慣例），讓 widget
/// test 注入假結果，不需要原生實作。只在開書失敗後呼叫一次，不做背景輪詢。
ProbeStorageAccess probeStorageAccess = probeStorageAccessViaChannel;

/// [probeStorageAccess] 的預設實作：呼叫背景任務佇列通道的
/// `probeUriAccess`。非 `content://` 輸入不呼叫原生。每次結果都寫入
/// [ReaderConsoleLog]，供真機回報時對照 design.md 的成因假說。
@visibleForTesting
Future<StorageAccessProbeResult> probeStorageAccessViaChannel(
  String uri, {
  Duration timeout = kStorageAccessProbeTimeout,
}) async {
  if (!uri.startsWith('content://')) {
    return StorageAccessProbeResult.unknownError;
  }
  StorageAccessProbeResult result;
  try {
    final code = await _readerResourcesCacheChannel
        .invokeMethod<String>('probeUriAccess', {'uri': uri})
        .timeout(timeout);
    result = StorageAccessProbeResult.values.asNameMap()[code] ??
        StorageAccessProbeResult.unknownError;
  } catch (_) {
    // 預期會遇到 TimeoutException（原生卡住）、PlatformException、
    // MissingPluginException（無原生實作的環境），以及原生回傳非字串時
    // invokeMethod<String> 內部轉型拋出的 TypeError（屬於 Error 而非
    // Exception）。一律退回 unknownError：本函式保證永不拋出例外，閱讀器
    // 最壞情況只是顯示通用錯誤文字（審查 I-2）。
    result = StorageAccessProbeResult.unknownError;
  }
  ReaderConsoleLog.add('[probeStorageAccess] $uri → ${result.name}');
  return result;
}
