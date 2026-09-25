import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'app_font.dart';
import 'font_download_catalog.dart';

/// 字型下載失敗的原因（epic-49，spec.md「可下載字型儲存」）。UI 依原因顯示在地化訊息，
/// 本模組不產生任何使用者可見的文字（比照 ADR 0034 的精神）。
/// spec 中的 `http` 在這裡命名為 [httpStatus]，避免和 `package:http` 的匯入前綴撞名。
enum FontDownloadFailure { network, httpStatus, integrity, storage, cancelled }

class FontDownloadException implements Exception {
  const FontDownloadException(this.reason, {this.statusCode});

  final FontDownloadFailure reason;

  /// 只在 [FontDownloadFailure.httpStatus] 時有值。
  final int? statusCode;

  @override
  String toString() =>
      'FontDownloadException(${reason.name}${statusCode == null ? '' : ', HTTP $statusCode'})';
}

/// 取消下載用的旗標。store 每收到一個資料區塊就檢查一次（比照雲端下載的既有做法）。
class FontDownloadCancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// 可下載字型的下載與保管（epic-49，見 docs/adr/0035-downloadable-fonts-via-r2-worker.md）。
///
/// 「已下載」只看正式檔案是否存在：下載先寫到 `<正式檔名>.part`，SHA-256 相符才改名，
/// 所以正式檔案存在就代表內容完整，不需要另外用資料表記錄狀態。
class DownloadableFontStore {
  DownloadableFontStore({
    required http.Client httpClient,
    required Directory directory,
    Uri? baseUri,
    FontDownloadSpec Function(AppFont font) specOf = fontDownloadSpecOf,
  })  : _httpClient = httpClient,
        _directory = directory,
        _baseUri = baseUri ?? Uri.parse(kFontDownloadBaseUrl),
        _specOf = specOf;

  final http.Client _httpClient;
  final Directory _directory;
  final Uri _baseUri;
  final FontDownloadSpec Function(AppFont font) _specOf;

  /// 同一時間只允許一個下載（spec「字型管理畫面」與規格審查 I-2）。
  bool _downloading = false;

  /// 存放目錄的絕對路徑，供閱讀器設定 WebView 的串流處理器（Issue 4）。
  String get directory => _directory.path;

  File _fileFor(AppFont font) =>
      File(p.joinAll([_directory.path, ..._specOf(font).publishPath.split('/')]));

  File _partFileFor(AppFont font) => File('${_fileFor(font).path}.part');

  /// App 啟動時呼叫一次：建立存放目錄，並刪除 App 被系統終止時殘留的 `.part` 檔
  /// （這種情況下 dispose 與 finally 都不一定會執行）。呼叫時不可有進行中的下載。
  Future<void> prepare() async {
    await _directory.create(recursive: true);
    await for (final entity in _directory.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.part')) {
        // 盡力清理：單一檔案刪不掉（被占用、權限異常）就略過，繼續清其他的；
        // 留下的 .part 不影響「已下載」判斷，下次下載前也會先刪除同名暫存檔
        try {
          await entity.delete();
        } on FileSystemException {
          // 略過
        }
      }
    }
  }

  Future<Set<AppFont>> installedFonts() async {
    final installed = <AppFont>{};
    for (final font in AppFont.values) {
      if (await _fileFor(font).exists()) installed.add(font);
    }
    return installed;
  }

  /// 刪除已下載的字型檔；檔案不存在時不視為錯誤。不修改任何書籍偏好（ADR 0035）。
  Future<void> delete(AppFont font) async {
    final file = _fileFor(font);
    if (await file.exists()) await file.delete();
  }

  /// 下載 [font]。[onProgress] 收到 0～100 的整數百分比，只在數值變大時才呼叫
  /// （電子紙裝置重繪代價高，設計審查 I-3）。失敗一律拋出 [FontDownloadException]，
  /// 並且不留下暫存檔、不影響既有的正式檔案。已有下載進行中時拋出 [StateError]。
  Future<void> download(
    AppFont font, {
    void Function(int percent)? onProgress,
    FontDownloadCancellationToken? cancellationToken,
  }) async {
    // 必須在任何 await 之前檢查並設定，才能擋住緊接著的第二次呼叫
    if (_downloading) {
      throw StateError('已有字型下載進行中，不可同時下載兩款字型');
    }
    _downloading = true;
    final spec = _specOf(font);
    final target = _fileFor(font);
    final part = _partFileFor(font);
    IOSink? sink;
    try {
      await _preparePartFile(part);
      final response = await _send(spec);
      if (response.statusCode != 200) {
        throw FontDownloadException(FontDownloadFailure.httpStatus,
            statusCode: response.statusCode);
      }

      final total = response.contentLength ?? spec.sizeBytes;
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;
      var lastPercent = -1;
      try {
        sink = part.openWrite();
        await for (final chunk in response.stream) {
          if (cancellationToken?.isCancelled ?? false) {
            throw const FontDownloadException(FontDownloadFailure.cancelled);
          }
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          final percent = total > 0 ? (received * 100 ~/ total).clamp(0, 100) : 0;
          if (percent > lastPercent) {
            lastPercent = percent;
            onProgress?.call(percent);
          }
        }
        await sink.close();
        sink = null;
      } on SocketException {
        throw const FontDownloadException(FontDownloadFailure.network);
      } on http.ClientException {
        throw const FontDownloadException(FontDownloadFailure.network);
      } on FileSystemException {
        throw const FontDownloadException(FontDownloadFailure.storage);
      }

      hasher.close();
      if (digestSink.value.toString() != spec.sha256) {
        throw const FontDownloadException(FontDownloadFailure.integrity);
      }
      if (lastPercent < 100) onProgress?.call(100);
      await _promote(part, target);
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        // 寫入已經失敗時 close 會再拋一次同樣的錯誤；原本的例外已經往上拋，這裡忽略
      }
      if (await part.exists()) await part.delete();
      _downloading = false;
    }
  }

  Future<void> _preparePartFile(File part) async {
    try {
      await part.parent.create(recursive: true);
      if (await part.exists()) await part.delete();
    } on FileSystemException {
      throw const FontDownloadException(FontDownloadFailure.storage);
    }
  }

  Future<http.StreamedResponse> _send(FontDownloadSpec spec) async {
    try {
      return await _httpClient.send(http.Request('GET', _baseUri.resolve(spec.publishPath)));
    } on SocketException {
      throw const FontDownloadException(FontDownloadFailure.network);
    } on http.ClientException {
      throw const FontDownloadException(FontDownloadFailure.network);
    }
  }

  /// 把驗證通過的暫存檔改名為正式檔案。Windows 上 rename 不能覆蓋既有檔案，所以先刪除舊檔。
  Future<void> _promote(File part, File target) async {
    try {
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } on FileSystemException {
      throw const FontDownloadException(FontDownloadFailure.storage);
    }
  }
}

/// 接收 [sha256.startChunkedConversion] 的最終結果。
class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
