import 'dart:io';

import '../platform/platform_support.dart';
import 'foliate_native_bridge.dart' show cacheBookForServing;
import 'local_book_server.dart';

/// 「書檔供應」（見 `CONTEXT.md`）：把一本書備妥成 WebView 可載入的位址，
/// 並保證一次 [dispose] 同時清掉快取目錄與 loopback 註冊。
///
/// 只有閱讀器與全文索引器使用；EPUB 探針以自訂範圍讀取直接讀原檔，不經
/// 這裡。兩個平台是兩個 adapter：
/// - Android：只有快取目錄，WebView 端由 `InternalStoragePathHandler`
///   以 [cacheDir] 串流服務。
/// - Windows：快取之後另向 [LocalBookServer] 註冊，書檔位址為 [bookBaseUri]。
///
/// 使用方式：`await open()` 之後若發現呼叫端已不需要（例如畫面已離開），
/// 只要呼叫一次 [dispose]，不必自己判斷快取目錄或註冊。
class BookServing {
  /// 快取檔所在目錄（每個實例各自獨立），供 Android `InternalStoragePathHandler`
  /// 使用。
  final String cacheDir;

  /// Windows loopback 書檔基底位址；Android 為 null。
  final Uri? bookBaseUri;

  final BookServeHandle? _handle;
  bool _disposed = false;

  BookServing._(this.cacheDir, this.bookBaseUri, this._handle);

  /// 快取 [filePath]（依 ADR 0002 可為 `content://` URI 或本機路徑）；
  /// Windows 另向 loopback 伺服器註冊。快取失敗回傳 null。
  ///
  /// 註冊失敗時，先刪掉剛複製的快取目錄（可能 200 MB 以上，不刪會成為孤兒）
  /// 再把例外重拋。[register] 為測試用注入點，預設走 [LocalBookServer.instance]。
  static Future<BookServing?> open(
    String filePath,
    String instanceId, {
    Future<BookServeHandle> Function(String cachedPath)? register,
  }) async {
    final cachedPath = await cacheBookForServing(filePath, instanceId);
    if (cachedPath == null) return null;
    final cacheDir = File(cachedPath).parent.path;
    BookServeHandle? handle;
    if (isWindowsPlatform) {
      try {
        handle = await (register ?? LocalBookServer.instance.register)(cachedPath);
      } catch (_) {
        _deleteDir(Directory(cacheDir));
        rethrow;
      }
    }
    return BookServing._(cacheDir, handle?.bookBaseUri, handle);
  }

  /// 釋放 loopback 註冊並刪除快取目錄；冪等。回傳這次呼叫是否「目錄確實存在
  /// 且已刪掉」（供開書追蹤記錄用）；目錄本來就不在、或 Windows 檔案鎖導致
  /// 當下刪不掉（背景會重試）時回傳 false。
  bool dispose() {
    if (_disposed) return false;
    _disposed = true;
    _handle?.dispose();
    final dir = Directory(cacheDir);
    final existed = dir.existsSync();
    final deleted = _deleteDir(dir);
    return existed && deleted;
  }

  /// 刪除目錄；目錄不存在視為成功。失敗（例如 Windows 檔案鎖）時背景重試
  /// 最多 3 次，不向外拋例外。
  static bool _deleteDir(Directory dir) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      return true;
    } catch (_) {
      _retryDelete(dir, 1);
      return false;
    }
  }

  static void _retryDelete(Directory dir, int attempt) {
    if (attempt > 3) return;
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {
        _retryDelete(dir, attempt + 1);
      }
    });
  }
}
