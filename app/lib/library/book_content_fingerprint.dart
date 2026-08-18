import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'library_repository.dart';
import 'models/library_enums.dart';

/// 內容指紋計算函式型別（epic-30-calibre-remote-library Issue 3，
/// spec.md「重複匯入偵測」第二層檢查）：`RemoteCatalogScreen` 的下載佇列
/// 透過這個型別注入 [computeBookContentFingerprint]，而不直接呼叫該
/// 函式——該函式對非 `content://` 路徑內部使用 `Isolate.run()`，這與
/// `testWidgets()` 的假時間測試環境不相容（epic-30 Issue 2
/// `reviews/review-issue-2.md` 已確認此組合會卡死至 10 分鐘逾時，
/// `tester.runAsync()` 亦無法解決），widget test 需要能替換成不觸碰
/// Isolate 的假函式，比照 `OpdsClient Function() createOpdsClient`
/// 既有的工廠函式注入先例。
typedef ComputeRemoteFingerprint = Future<String> Function(
  String filePath,
  BookFileFormat format,
);

/// 計算書籍內容指紋（epic-8-sync Issue 3，spec.md「書籍內容指紋計算」／
/// 「跨裝置參照設計」）：供跨裝置比對「這是不是同一本書」使用，寫入
/// `books.content_fingerprint`。EPUB 優先採用 OPF identifier（由呼叫端
/// 透過既有 `extractMetadata` 呼叫一併取得並以 [epubIdentifier] 傳入，
/// 本函式不重複發出原生呼叫，取用前先 `trim()`——不規範的 EPUB 檔若在
/// `<dc:identifier>` 塞入純空白字串，不應被當成有效指紋值，見文末
/// 「審查修正紀錄」）；identifier 缺漏（`null`）、trim 後為空字串，
/// 以及 PDF／TXT 一律採用整個檔案內容的 SHA-256。
///
/// [filePath] 依 ADR 0002 可能是本機檔案系統路徑，也可能是 `content://`
/// URI——`dart:io` 的 `File` 無法直接開啟 `content://` URI（沒有對應的
/// 真實檔案系統節點），這種情況委由原生端的 `computeSha256`
/// （`BookMetadataChannel.kt`）以 `ContentResolver` 串流計算，計算過程
/// 與原始位元組皆不經過 Dart 端記憶體，只有最終的雜湊字串透過
/// `MethodChannel` 回傳。本機檔案路徑則在 Dart 端用 `File.openRead()`
/// 串流＋`package:crypto` 的 `Hash.bind()`（官方建議寫法，見
/// `package:crypto` `example/example.dart`），並外包至 `Isolate.run()`
/// 執行，避免大檔案（PRD 要求支援 100MB 以上）阻塞 UI isolate、也避免
/// 一次性讀入整個檔案（本專案已有過同類全檔案讀入記憶體導致 OOM 閃退的
/// 真實事故，見 `epic-20` Issue 8）。
///
/// 計算失敗（檔案不存在／原生端拋出例外／`computeSha256` 未回傳有效值）
/// 時直接拋出例外，由呼叫端（`book_import_service_impl.dart`）決定是否
/// 降級為 `null`，本函式本身不吞掉錯誤。
Future<String> computeBookContentFingerprint(
  String filePath,
  BookFileFormat format, {
  String? epubIdentifier,
}) async {
  final trimmedIdentifier = epubIdentifier?.trim();
  if (format == BookFileFormat.epub &&
      trimmedIdentifier != null &&
      trimmedIdentifier.isNotEmpty) {
    return trimmedIdentifier;
  }
  if (filePath.contains('://')) {
    final hash = await kBookMetadataChannel
        .invokeMethod<String>('computeSha256', {'uri': filePath});
    if (hash == null) {
      throw StateError('computeSha256 未回傳有效的雜湊值：$filePath');
    }
    return hash;
  }
  return Isolate.run(() => _sha256OfLocalFile(filePath));
}

Future<String> _sha256OfLocalFile(String filePath) async {
  final digest = await sha256.bind(File(filePath).openRead()).first;
  return digest.toString();
}
