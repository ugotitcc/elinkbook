import 'dart:async';

import 'package:flutter/foundation.dart';

import '../library/book_import_service.dart'
    show
        BookRelinkFailure,
        BookRelinkFailureReason,
        BookRelinkResult,
        BookRelinkSuccess;
import '../storage/storage_access_probe.dart' show StorageAccessProbeResult;

/// 開書失敗的來源。畫面依它與探測結果決定顯示哪一段說明文字
/// （文字屬於 l10n，本模組不持有）。
enum OpenBookFailureSource {
  /// 閱讀視圖（Foliate／pdfrx）回報了錯誤。
  viewError,

  /// 30 秒內視圖沒有回報任何結果。
  timeout,
}

/// 開書流程的狀態（見 CONTEXT.md「開書流程」）。用密封類別而非列舉加多個
/// 旗標，讓「已渲染卻同時在探測」這類非法組合在型別上不可能出現。
sealed class OpenBookState {
  const OpenBookState();
}

/// 載入中，等待視圖回報結果。
final class OpenBookLoading extends OpenBookState {
  const OpenBookLoading();

  @override
  String toString() => 'OpenBookLoading';
}

/// 已偵測到失敗，正在探測 `content://` 的存取狀況。畫面仍顯示載入指示器，
/// 避免 E-Ink 先閃出通用錯誤再換成分類說明。
final class OpenBookProbing extends OpenBookState {
  const OpenBookProbing();

  @override
  String toString() => 'OpenBookProbing';
}

/// 已成功渲染。此後的錯誤不會再把畫面改成失敗。
final class OpenBookRendered extends OpenBookState {
  const OpenBookRendered();

  @override
  String toString() => 'OpenBookRendered';
}

/// 開書失敗。[probeResult] 只有 `content://` 書籍才有值。
final class OpenBookFailed extends OpenBookState {
  const OpenBookFailed({
    required this.source,
    this.viewMessage,
    this.probeResult,
  });

  final OpenBookFailureSource source;

  /// 視圖回報的錯誤訊息；[source] 為 timeout 時為 null。
  final String? viewMessage;
  final StorageAccessProbeResult? probeResult;

  // 只覆寫 toString：測試斷言失敗時才看得到內容，不會只印 Instance of。
  // 刻意不實作 ==／hashCode：測試以 same() 比對實例即可，沒有人需要值等價。
  @override
  String toString() => 'OpenBookFailed(source: $source, '
      'viewMessage: $viewMessage, probeResult: $probeResult)';
}

/// 重新連結處理中（含選檔期間）。保留進入前的 [failed]，畫面繼續顯示同一個
/// 錯誤視圖，只是按鈕停用並顯示進度。
final class OpenBookRelinking extends OpenBookState {
  const OpenBookRelinking(this.failed);

  final OpenBookFailed failed;

  @override
  String toString() => 'OpenBookRelinking($failed)';
}

/// [OpenBookFlow.relink] 的結果。
sealed class OpenBookRelinkOutcome {
  const OpenBookRelinkOutcome();
}

/// 重新連結成功，已回到 [OpenBookLoading] 並以 [newPath] 重新開書。
/// [newPath] 可能是落地複本的本機路徑，不一定是選取的 URI。
final class OpenBookRelinkReopened extends OpenBookRelinkOutcome {
  const OpenBookRelinkReopened(this.newPath);

  final String newPath;

  @override
  String toString() => 'OpenBookRelinkReopened($newPath)';
}

/// 重新連結失敗，狀態已回到進入前的 [OpenBookFailed]。
final class OpenBookRelinkFailed extends OpenBookRelinkOutcome {
  const OpenBookRelinkFailed(this.reason);

  final BookRelinkFailureReason reason;

  @override
  String toString() => 'OpenBookRelinkFailed($reason)';
}

/// 使用者取消選檔、目前不能重新連結（不在 Failed 狀態、處理中、沒有
/// relink 能力），或選檔期間已離開畫面。不需要提示使用者。
final class OpenBookRelinkCancelled extends OpenBookRelinkOutcome {
  const OpenBookRelinkCancelled();

  @override
  String toString() => 'OpenBookRelinkCancelled';
}

/// 探測 [uri] 的可讀性；保證不拋例外的契約由實作者負責，本模組仍會防禦。
typedef OpenBookProbe = Future<StorageAccessProbeResult> Function(String uri);

/// 以選好的檔案重新連結書籍記錄（`BookImportService.relinkBook` 的包裝）。
typedef OpenBookRelink = Future<BookRelinkResult> Function(
    String uri, String? displayName);

/// 使用者選取的檔案。與 `SingleBookFilePicker` 的回傳型別相同。
typedef OpenBookPickedFile = ({String uri, String? displayName});

/// 計時器工廠，預設是 [Timer.new]；測試注入假計時器以免等待真實時間。
typedef OpenBookTimerFactory = Timer Function(
    Duration duration, void Function() callback);

/// 開書流程控制器（epic-54-architecture-optimization Issue 5）。
///
/// 持有從載入、失敗探測、逾時，到重新連結後重新開書的整段狀態與規則；
/// `ReaderScreen` 只負責把視圖事件餵進來、依狀態畫畫面。`l10n` 文字、
/// SnackBar、選檔器與 EPUB 引擎分派仍屬 `ReaderScreen`。
///
/// 開書逾時哨兵的由來（iReader Ocean 4 Plus 永遠停在載入指示器、慢速裝置
/// 30 秒調整）見 `docs/epics/epic-27-reader-device-compat/reviews/
/// bugfix-repro.md` 與 epic-18-reader-device-qa Issue 33。
class OpenBookFlow extends ChangeNotifier {
  OpenBookFlow({
    required String filePath,
    required this.probe,
    this.relinkBook,
    this.timeout = const Duration(seconds: 30),
    this.timerFactory = Timer.new,
  }) : _filePath = filePath;

  final OpenBookProbe probe;

  /// `null` 代表沒有重新連結能力（例如沒有匯入服務）。
  final OpenBookRelink? relinkBook;

  /// 開書逾時上限。30 秒是 epic-27-reader-device-compat Issue 2 依
  /// 慢速裝置真機回報調整的值（原為 12 秒）。
  final Duration timeout;
  final OpenBookTimerFactory timerFactory;

  String _filePath;

  /// 目前開啟的檔案路徑；重新連結成功後換成新路徑。
  String get filePath => _filePath;

  OpenBookState _state = const OpenBookLoading();
  OpenBookState get state => _state;

  /// 載入中或探測中：畫面仍顯示載入指示器，視圖手勢應忽略。
  bool get isLoading => _state is OpenBookLoading || _state is OpenBookProbing;

  bool get isRendered => _state is OpenBookRendered;

  /// 失敗或重新連結處理中：畫面顯示錯誤視圖。由 [failure] 推導，兩者永遠
  /// 同步（`ReaderScreen` 在 `isFailed` 為真時以 `failure!` 取值）。
  bool get isFailed => failure != null;

  /// 目前的失敗資訊；非失敗狀態為 null。
  OpenBookFailed? get failure => switch (_state) {
        OpenBookFailed failed => failed,
        OpenBookRelinking(:final failed) => failed,
        _ => null,
      };

  Timer? _timer;
  bool _disposed = false;

  /// 啟動開書逾時計時器。`ReaderScreen.initState` 呼叫一次。
  void start() => _restartTimer();

  /// 視圖回報錯誤。只在 [OpenBookLoading] 才處理：已渲染後的錯誤可能只是
  /// 良性警告（例如旋轉螢幕時的 ResizeObserver），不應覆蓋已顯示的內容；
  /// 探測中、失敗中再收到的錯誤也一律忽略。
  void onViewError(String message) {
    if (_disposed || _state is! OpenBookLoading) return;
    _timer?.cancel();
    _fail(OpenBookFailureSource.viewError, message);
  }

  /// 視圖回報已成功渲染。探測進行中先到時，探測結果之後會被捨棄。
  void onRendered() {
    if (_disposed) return;
    if (_state is! OpenBookLoading && _state is! OpenBookProbing) return;
    _timer?.cancel();
    _set(const OpenBookRendered());
  }

  /// 使用者要求重新連結。先進入 [OpenBookRelinking]（期間按鈕停用），再呼叫
  /// 由 Widget 提供的 [pick] 選檔；`null` 代表取消。保證不拋例外：選檔或
  /// relinkBook 的任何例外都視為 failed。
  Future<OpenBookRelinkOutcome> relink(
    Future<OpenBookPickedFile?> Function() pick,
  ) async {
    final current = _state;
    final relinkBook = this.relinkBook;
    if (_disposed || current is! OpenBookFailed || relinkBook == null) {
      return const OpenBookRelinkCancelled();
    }
    _set(OpenBookRelinking(current));

    OpenBookRelinkOutcome outcome;
    try {
      final picked = await pick();
      // 選檔期間使用者可能已離開閱讀器：不再發動 relinkBook，避免白做整檔
      // SHA-256 與持久化授權。
      if (_disposed || picked == null) {
        outcome = const OpenBookRelinkCancelled();
      } else {
        final result = await relinkBook(picked.uri, picked.displayName);
        outcome = switch (result) {
          BookRelinkSuccess(:final updatedBook) =>
            OpenBookRelinkReopened(updatedBook.filePath),
          BookRelinkFailure(:final reason) => OpenBookRelinkFailed(reason),
        };
      }
    } catch (_) {
      outcome = const OpenBookRelinkFailed(BookRelinkFailureReason.failed);
    }

    if (_disposed) return outcome;
    switch (outcome) {
      case OpenBookRelinkReopened(:final newPath):
        _filePath = newPath;
        _set(const OpenBookLoading());
        _restartTimer();
      case OpenBookRelinkFailed() || OpenBookRelinkCancelled():
        _set(current);
    }
    return outcome;
  }

  /// 只在仍是載入中時才建立計時器：已 dispose 或已渲染／失敗後不留下
  /// 無效的 30 秒背景計時器。
  void _restartTimer() {
    if (_disposed || _state is! OpenBookLoading) return;
    _timer?.cancel();
    _timer = timerFactory(timeout, _onTimeout);
  }

  void _onTimeout() {
    if (_disposed || _state is! OpenBookLoading) return;
    _fail(OpenBookFailureSource.timeout, null);
  }

  /// 失敗共同入口。`content://` 先探測再決定錯誤畫面，維持載入指示器；
  /// 其他路徑沒有存取權限問題，直接失敗。
  void _fail(OpenBookFailureSource source, String? viewMessage) {
    if (!_filePath.startsWith('content://')) {
      _set(OpenBookFailed(source: source, viewMessage: viewMessage));
      return;
    }
    _set(const OpenBookProbing());
    unawaited(_probeThenFail(source, viewMessage, _filePath));
  }

  /// 失敗來源與路徑以參數傳入（closure 捕獲），不另存實例欄位。
  Future<void> _probeThenFail(
    OpenBookFailureSource source,
    String? viewMessage,
    String targetPath,
  ) async {
    StorageAccessProbeResult result;
    try {
      result = await probe(targetPath);
    } catch (_) {
      // 計時器在進入探測前已取消或已觸發；探測函式若拋例外而不切到失敗，
      // 閱讀器會永遠停在載入中。
      result = StorageAccessProbeResult.unknownError;
    }
    // 結果回來時若已離開畫面，或開書其實已成功（狀態不再是 Probing），
    // 直接捨棄。
    if (_disposed || _state is! OpenBookProbing) return;
    _set(OpenBookFailed(
      source: source,
      viewMessage: viewMessage,
      probeResult: result,
    ));
  }

  void _set(OpenBookState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  /// 可重複呼叫：已 dispose 時為無害的空操作（`ChangeNotifier.dispose` 本身
  /// 重複呼叫會拋錯，而測試會同時明確 dispose 與 `addTearDown`）。
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}