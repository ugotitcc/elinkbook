import 'dart:async';
import 'dart:io';

import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/downloadable_font_store.dart';

/// 測試用 Fake（epic-49）。下載不會自動完成，由測試透過 [activeDownload]
/// 控制進度、成功或失敗，才能精確驗證畫面在每個階段的顯示。
class FakeDownloadableFontStore implements DownloadableFontStore {
  FakeDownloadableFontStore({this.directory = _defaultDirectory});

  /// 依平台建立：Android 真機的 integration 測試會用真的 `InAppWebView`，原生端的
  /// `WebViewAssetLoader.InternalStoragePathHandler` 會拒絕不存在、或位於禁用目錄
  /// （`code_cache/`、`databases/` 等）底下的目錄並丟 `PlatformException`（epic-54 Issue 16）。
  /// Android 的 `Directory.systemTemp` 指向 `code_cache/`（禁用），所以改用它的上一層
  /// 底下的 `cache/`（允許），並建立真實存在的暫存子目錄；其他平台（桌面主機的
  /// `flutter test`）維持假目錄。[isAndroid]、[systemTemp] 預設取目前平台，只在測試這個
  /// 方法本身時才傳入。
  factory FakeDownloadableFontStore.forPlatform({
    bool? isAndroid,
    Directory? systemTemp,
  }) {
    if (isAndroid ?? Platform.isAndroid) {
      final cacheRoot = Directory(
        '${(systemTemp ?? Directory.systemTemp).parent.path}/cache',
      )..createSync(recursive: true);
      return FakeDownloadableFontStore(
        directory: cacheRoot.createTempSync('fake-fonts').path,
      );
    }
    return FakeDownloadableFontStore();
  }

  static const String _defaultDirectory = '/fake/downloaded-fonts';

  /// 目前視為已下載的字型；測試可以直接預先設定。
  final Set<AppFont> installed = {};

  /// [delete] 被呼叫過的字型，依呼叫順序。
  final List<AppFont> deleted = [];

  /// 最近一次 [download] 呼叫；沒有呼叫過時為 null。
  FakeFontDownload? activeDownload;

  /// 若非 null，[delete] 會拋出這個例外（模擬檔案被占用等刪除失敗）。
  Object? deleteError;

  /// 若非 null，[installedFonts] 會先等待它完成才回傳，供測試控制載入完成的時機
  /// （Issue 4 驗證 ReaderScreen 在已下載字型載入完成前延後建構閱讀器）。
  Completer<void>? installedFontsGate;

  /// [supportedFonts] 回傳的字型；測試可以改成部分或空清單，模擬舊版系統 WebView（Issue 7）。
  List<AppFont> supported = List.of(AppFont.values);

  @override
  List<AppFont> get supportedFonts => supported;

  @override
  final String directory;

  @override
  Future<void> prepare() async {}

  @override
  Future<Set<AppFont>> installedFonts() async {
    if (installedFontsGate != null) await installedFontsGate!.future;
    // 比照真的 store：不在 supportedFonts 裡的字型，檔案存在也不算已下載（Issue 7）
    return installed.where(supported.contains).toSet();
  }

  @override
  Future<void> delete(AppFont font) async {
    if (deleteError != null) throw deleteError!;
    installed.remove(font);
    deleted.add(font);
  }

  @override
  Future<void> download(
    AppFont font, {
    void Function(int percent)? onProgress,
    FontDownloadCancellationToken? cancellationToken,
  }) {
    final download = FakeFontDownload(font, onProgress, cancellationToken);
    activeDownload = download;
    return download._completer.future.then((_) => installed.add(font));
  }
}

class FakeFontDownload {
  FakeFontDownload(this.font, this._onProgress, this.cancellationToken);

  final AppFont font;
  final void Function(int percent)? _onProgress;
  final FontDownloadCancellationToken? cancellationToken;
  final Completer<void> _completer = Completer<void>();

  void progress(int percent) => _onProgress?.call(percent);
  void succeed() => _completer.complete();

  /// 以任意例外結束下載；通常是 [FontDownloadException]，也可以模擬未預期的例外。
  void fail(Object error) => _completer.completeError(error);
}
