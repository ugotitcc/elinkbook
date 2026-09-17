import 'dart:async';

/// 收斂「發一個 JS 請求、等 JS 呼叫 handler 回來、完成 Completer」這個
/// 重複樣板的深模組（epic-26-architecture-hardening Issue 13）。不直接
/// 依賴 InAppWebViewController，改收 [evaluate]／[registerHandler] 兩個
/// 注入函式，讓這個類別可以脫離真正的 WebView 環境被單元測試——現有的
/// `fake_inappwebview_platform.dart` 沒有能力模擬 JS handler 回呼，這是
/// 過去三個 `_requestXxx` 完全沒有 Dart 測試涵蓋的根本原因。
///
/// 同一個 [handlerName] 同時只能有一個 pending 請求：呼叫端必須自行保證
/// 不會在前一次對同一 handler 的 [request] 完成前又發出新的請求，否則
/// 回應會被誤配對給錯的呼叫。若違反這個約定，舊請求會被視為過期並以
/// `StateError` 提前結束（見 [request] 實作），不會靜默覆寫或無限期掛住
/// （epic-41-search-architecture-hardening Issue 6）。
class JsBridgeGateway {
  JsBridgeGateway({
    required this.evaluate,
    required this.registerHandler,
  });

  /// 實際執行一段 JS 程式碼的注入函式。呼叫端通常是
  /// `(js) => controller?.evaluateJavascript(source: js)`——忽略回傳值，
  /// 回應資料一律由 JS 端主動呼叫對應 handler 取得，不透過
  /// evaluateJavascript 本身的回傳值。
  final void Function(String js) evaluate;

  /// 掛一個具名 JS→Dart handler 的注入函式。呼叫端通常是
  /// `(name, callback) => controller.addJavaScriptHandler(handlerName: name, callback: callback)`。
  final void Function(
    String handlerName,
    dynamic Function(List<dynamic> args) callback,
  ) registerHandler;

  final Map<String, Completer<dynamic>> _pending = {};
  final Map<String, dynamic> _fallbackByHandler = {};

  /// 設定期呼叫一次（每種請求類型各呼叫一次）：註冊 [handlerName] 對應
  /// 的 JS handler，記錄「怎麼把回傳的 args 解析成 [T]」（[parse]）與
  /// 「解析失敗或逾時時要退回的值」（[fallback]）。
  void register<T>({
    required String handlerName,
    required T Function(List<dynamic> args) parse,
    required T fallback,
  }) {
    _fallbackByHandler[handlerName] = fallback;
    registerHandler(handlerName, (args) {
      final completer = _pending.remove(handlerName);
      if (completer == null) return null;
      try {
        completer.complete(parse(args));
      } catch (_) {
        // 例如 JS 端回傳的 JSON 格式意外損壞——parse() 拋出的例外若不在
        // 這裡攔截，會被 flutter_inappwebview 的 method channel 邊界吞掉
        // （已查證：不會讓 App crash，但 completer 永遠不會被 complete，
        // 呼叫端的 await 會無限期卡住；若這個請求類型沒有設 timeout，
        // 沒有其他機制能救回來）。這是本次重構額外新增的防護，非單純
        // 從 foliate_reader_view.dart 搬移過來的既有行為。
        completer.complete(fallback);
      }
      return null;
    });
  }

  /// 每次請求呼叫一次：發出 [jsCall]，等 [handlerName] 對應的 handler
  /// 回呼完成。[timeout] 為 `null` 表示不設逾時上限（原樣等待，對應
  /// TOC 目前的既有行為）；設定逾時時，逾時後退回 [register] 當初登記
  /// 的 fallback 值。
  Future<T> request<T>({
    required String jsCall,
    required String handlerName,
    Duration? timeout,
  }) {
    assert(
      _fallbackByHandler.containsKey(handlerName),
      'Handler "$handlerName" 尚未透過 register() 註冊 fallback 值',
    );
    // 同一 handler 若已有尚未完成的舊請求，代表呼叫端在前一次請求完成前
    // 又發出了新請求——依既有不變量（completer 只要還留在 _pending 裡
    // 就一定尚未 complete，見 register() 的 callback 與下方 timeout 的
    // onTimeout，皆是「complete 的同時立即 remove」成對發生），此時直接
    // 讓舊請求以明確錯誤結束，取代原本「靜默覆寫、舊呼叫者的回應被之後
    // 抵達的 JS 回呼誤配對，或完全沒設 timeout 時永遠掛住」的行為
    // （epic-41-search-architecture-hardening Issue 6，全 build 強制生效，
    // 不可用 assert()——release build 會被整個移除）。
    final existing = _pending[handlerName];
    if (existing != null) {
      existing.completeError(
        StateError(
          'JsBridgeGateway: handler "$handlerName" 的前一個 request() '
          '尚未完成前又收到新的請求，舊請求已被取代並以錯誤結束（呼叫端'
          '需自行保證同一 handler 不會重疊發出請求）。',
        ),
      );
    }
    final completer = Completer<T>();
    _pending[handlerName] = completer;
    evaluate(jsCall);
    final future = completer.future;
    if (timeout == null) return future;
    return future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(handlerName);
        return _fallbackByHandler[handlerName] as T;
      },
    );
  }
}
