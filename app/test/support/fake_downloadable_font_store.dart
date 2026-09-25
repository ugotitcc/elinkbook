import 'dart:async';

import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/downloadable_font_store.dart';

/// 測試用 Fake（epic-49）。下載不會自動完成，由測試透過 [activeDownload]
/// 控制進度、成功或失敗，才能精確驗證畫面在每個階段的顯示。
class FakeDownloadableFontStore implements DownloadableFontStore {
  /// 目前視為已下載的字型；測試可以直接預先設定。
  final Set<AppFont> installed = {};

  /// [delete] 被呼叫過的字型，依呼叫順序。
  final List<AppFont> deleted = [];

  /// 最近一次 [download] 呼叫；沒有呼叫過時為 null。
  FakeFontDownload? activeDownload;

  /// 若非 null，[installedFonts] 會先等待它完成才回傳，供測試控制載入完成的時機
  /// （Issue 4 驗證 ReaderScreen 在已下載字型載入完成前延後建構閱讀器）。
  Completer<void>? installedFontsGate;

  @override
  String get directory => '/fake/downloaded-fonts';

  @override
  Future<void> prepare() async {}

  @override
  Future<Set<AppFont>> installedFonts() async {
    if (installedFontsGate != null) await installedFontsGate!.future;
    return {...installed};
  }

  @override
  Future<void> delete(AppFont font) async {
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
  void fail(FontDownloadException error) => _completer.completeError(error);
}
