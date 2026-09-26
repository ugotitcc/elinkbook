import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'app_font.dart';
import 'font_download_catalog.dart';
import 'webview_font_support.dart';

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

/// 取消下載用的旗標。取消會立即中斷下載，不必等下一個資料區塊（連線停住時也有效，
/// 程式審查 I-2）。
class FontDownloadCancellationToken {
  final Completer<void> _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;

  /// 取消時完成。
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// 寫檔時每累積這麼多 bytes 就等資料寫入一次：寫入錯誤（例如磁碟已滿）能及早發現，
/// 磁碟比網路慢時也不會把資料都堆在記憶體裡（程式審查 M-2）。
const int _flushIntervalBytes = 1024 * 1024;

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
    Duration idleTimeout = const Duration(seconds: 30),
    int? webViewMajorVersion,
  })  : _httpClient = httpClient,
        _directory = directory,
        _baseUri = baseUri ?? Uri.parse(kFontDownloadBaseUrl),
        _specOf = specOf,
        _idleTimeout = idleTimeout,
        _webViewMajorVersion = webViewMajorVersion;

  final http.Client _httpClient;
  final Directory _directory;
  final Uri _baseUri;
  final FontDownloadSpec Function(AppFont font) _specOf;

  /// 等伺服器回應、或兩個資料區塊之間，超過這段時間沒有進展就視為網路失敗
  /// （程式審查 I-2）。不是整個下載的時間上限，網路慢但持續有資料時不會誤判。
  final Duration _idleTimeout;

  /// 系統 WebView 主版本號；null 代表讀不到，視同支援全部字型（Issue 7 計畫決定 2）。
  final int? _webViewMajorVersion;

  /// 這台裝置的系統 WebView 載得動的內建字型，依 [AppFont.values] 順序（Issue 7）。
  /// 舊版 WebView 拒絕超過 30MB 的網頁字型，這些字型不列出、不視為已下載。
  List<AppFont> get supportedFonts => [
        for (final font in AppFont.values)
          if (webViewCanLoadFont(
              webViewMajorVersion: _webViewMajorVersion,
              fontSizeBytes: _specOf(font).sizeBytes))
            font,
      ];

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
    // Issue 7：WebView 載不動的字型，檔案留著也用不到，刪掉釋放空間（思源宋體約 57MB）。
    // 不修改任何書籍偏好；WebView 升級後重新下載，偏好會自動生效。讀不到 WebView 版本時
    // supportedFonts 是全部字型，這裡不會刪任何檔案。
    final supported = supportedFonts;
    for (final font in AppFont.values) {
      if (supported.contains(font)) continue;
      try {
        await delete(font);
      } on FileSystemException {
        // 盡力清理：刪不掉不影響判斷，installedFonts() 本來就不會列出它
      }
    }
  }

  Future<Set<AppFont>> installedFonts() async {
    final installed = <AppFont>{};
    for (final font in supportedFonts) {
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
  /// 不檢查 [font] 是否在 [supportedFonts] 裡：唯一的呼叫端（字型管理畫面）只列出
  /// supportedFonts；萬一下載了載不動的字型，下次啟動時 [prepare] 會刪掉（Issue 7）。
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
    // 取消或失敗時中止 HTTP 連線（真實的 IOClient 會關閉 socket）
    final abort = Completer<void>();
    unawaited(cancellationToken?.whenCancelled.then((_) {
      if (!abort.isCompleted) abort.complete();
    }));
    IOSink? sink;
    try {
      await _preparePartFile(part);
      final response = await _send(spec, abort.future, cancellationToken);
      if (response.statusCode != 200) {
        // 丟棄回應內容，讓連線可以回收（程式審查 M-6）
        unawaited(response.stream.listen(null, onError: (_) {}).cancel());
        throw FontDownloadException(FontDownloadFailure.httpStatus,
            statusCode: response.statusCode);
      }

      final total = response.contentLength ?? spec.sizeBytes;
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;
      var unflushed = 0;
      var lastPercent = -1;
      try {
        sink = part.openWrite();
        await for (final chunk in _chunksOf(response, cancellationToken)) {
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          unflushed += chunk.length;
          if (unflushed >= _flushIntervalBytes) {
            await sink.flush();
            unflushed = 0;
          }
          final percent = total > 0 ? (received * 100 ~/ total).clamp(0, 100) : 0;
          if (percent > lastPercent) {
            lastPercent = percent;
            onProgress?.call(percent);
          }
        }
        await sink.close();
        sink = null;
      } on FileSystemException {
        throw const FontDownloadException(FontDownloadFailure.storage);
      } on Object catch (error) {
        throw _asDownloadException(error, cancellationToken);
      }

      hasher.close();
      if (digestSink.value.toString() != spec.sha256) {
        throw const FontDownloadException(FontDownloadFailure.integrity);
      }
      if (lastPercent < 100) onProgress?.call(100);
      await _promote(part, target);
    } finally {
      // 先重設旗標：後面的清理就算出錯，也不會讓之後的下載永遠被擋住（程式審查 I-3）
      _downloading = false;
      if (!abort.isCompleted) abort.complete();
      try {
        await sink?.close();
      } catch (_) {
        // 寫入已經失敗時 close 會再拋一次同樣的錯誤；原本的例外已經往上拋，這裡忽略
      }
      try {
        if (await part.exists()) await part.delete();
      } on FileSystemException {
        // 盡力清理：刪不掉的暫存檔不影響「已下載」判斷，下次下載前也會先刪除
      }
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

  /// 送出請求並等待回應標頭。取消時立即結束（不等伺服器），超過閒置逾時視為網路失敗。
  Future<http.StreamedResponse> _send(
    FontDownloadSpec spec,
    Future<void> abortTrigger,
    FontDownloadCancellationToken? cancellationToken,
  ) async {
    final request = http.AbortableRequest('GET', _baseUri.resolve(spec.publishPath),
        abortTrigger: abortTrigger);
    final result = Completer<http.StreamedResponse>();
    final timer = Timer(_idleTimeout, () {
      if (!result.isCompleted) result.completeError(TimeoutException(null, _idleTimeout));
    });
    unawaited(_httpClient.send(request).then((response) {
      if (result.isCompleted) {
        // 已經取消或逾時才收到回應：丟棄內容，讓連線可以回收
        unawaited(response.stream.listen(null, onError: (_) {}).cancel());
      } else {
        result.complete(response);
      }
    }, onError: (Object error, StackTrace stackTrace) {
      if (!result.isCompleted) result.completeError(error, stackTrace);
    }));
    unawaited(cancellationToken?.whenCancelled.then((_) {
      if (!result.isCompleted) {
        result.completeError(const FontDownloadException(FontDownloadFailure.cancelled));
      }
    }));
    try {
      return await result.future;
    } on Object catch (error) {
      throw _asDownloadException(error, cancellationToken);
    } finally {
      timer.cancel();
    }
  }

  /// 回應內容的資料區塊。兩個區塊之間超過閒置逾時就拋出 [TimeoutException]；
  /// 取消時立即拋出 cancelled，不必等下一個資料區塊。
  Stream<List<int>> _chunksOf(
    http.StreamedResponse response,
    FontDownloadCancellationToken? cancellationToken,
  ) {
    late final StreamController<List<int>> controller;
    StreamSubscription<List<int>>? source;
    controller = StreamController<List<int>>(
      onListen: () {
        source = response.stream.timeout(_idleTimeout).listen(
              controller.add,
              onError: controller.addError,
              onDone: controller.close,
            );
        unawaited(cancellationToken?.whenCancelled.then((_) {
          if (!controller.isClosed) {
            controller.addError(const FontDownloadException(FontDownloadFailure.cancelled));
          }
        }));
      },
      onPause: () => source?.pause(),
      onResume: () => source?.resume(),
      onCancel: () => source?.cancel(),
    );
    return controller.stream;
  }

  /// 把下載過程中的例外統一轉成 [FontDownloadException]（spec：失敗只以這個型別回報）。
  /// 已取消時一律視為 cancelled（中止連線本身也會拋出例外）。TLS 失敗、連線中斷、
  /// 逾時都屬於網路問題（程式審查 I-1）；其他未預期的例外同樣以網路失敗回報，
  /// 讓畫面能顯示錯誤並允許重試，不會變成沒有任何提示的未捕捉錯誤。
  FontDownloadException _asDownloadException(
    Object error,
    FontDownloadCancellationToken? cancellationToken,
  ) {
    if (cancellationToken?.isCancelled ?? false) {
      return const FontDownloadException(FontDownloadFailure.cancelled);
    }
    if (error is FontDownloadException) return error;
    return const FontDownloadException(FontDownloadFailure.network);
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
