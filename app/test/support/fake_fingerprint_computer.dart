import 'package:elinkbook/library/book_content_fingerprint.dart';
import 'package:elinkbook/library/models/library_enums.dart';

/// 供 widget test 使用的 [ComputeRemoteFingerprint] 假實作，避免測試環境
/// 觸碰真實 `computeBookContentFingerprint()` 的 `Isolate.run()`（見
/// `book_content_fingerprint.dart` 對 [ComputeRemoteFingerprint] 的文件
/// 說明）。預設每次呼叫回傳固定值 [nextFingerprint]（預設
/// `'fake-fingerprint'`），測試可依情境覆寫來模擬「這個下載內容與本機某
/// 本書指紋相同」。[calls] 記錄每次呼叫的 `filePath`，供測試驗證呼叫
/// 時機（例如「只在下載成功後、複製到永久位置之前呼叫」）。
class FakeFingerprintComputer {
  String nextFingerprint = 'fake-fingerprint';
  final List<String> calls = [];

  Future<String> call(String filePath, BookFileFormat format) async {
    calls.add(filePath);
    return nextFingerprint;
  }
}
