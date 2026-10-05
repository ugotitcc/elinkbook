import 'package:flutter/foundation.dart';

import 'tts_audio_handler.dart';

/// 啟動階段建立 [TtsAudioHandler]；失敗時回傳 null，讓 App 照常啟動（epic-61）。
///
/// 真機實測：`AudioService.init` 在 service 綁定逾時（約 10 秒）時會丟出
/// `PlatformException`，若沒有接住，`main()` 會在 `runApp` 之前中斷，整個
/// App 黑屏且沒有任何錯誤提示。系統媒體通知／鎖屏控制只是附加功能，失敗時
/// 降級為本次執行沒有這些控制即可——朗讀本身仍可用（`TtsController` 的建立
/// 不依賴 handler）。目前由 [startTtsAudioHandlerInBackground] 在背景呼叫本函式，
/// 結果經 [TtsAudioHandlerHolder] 交給下游（`ReaderScreen` 等），下游只透過
/// holder 讀取可為 null 的 handler。
///
/// 注意：失敗後不可重試。`AudioService.init` 以 `assert(_cacheManager == null)`
/// 擋重複初始化（僅 debug 生效），失敗時 `_cacheManager` 已被設定。
///
/// 此函式會接住所有例外（含 `builder` 內的程式錯誤）；啟動路徑上寧可降級
/// 也不黑屏，錯誤會以 `debugPrint` 留下紀錄。
///
/// [init] 以參數注入，讓單元測試不必真的呼叫 `AudioService.init`
/// （它需要原生端 service）。同步丟出的例外也一併接住。
Future<TtsAudioHandler?> initTtsAudioHandlerSafely(
  Future<TtsAudioHandler> Function() init,
) async {
  try {
    return await init();
  } catch (e, st) {
    debugPrint('TTS 音訊服務初始化失敗，本次執行沒有媒體通知／鎖屏控制：$e\n$st');
    return null;
  }
}

/// 啟動階段 TTS 音訊服務的狀態（epic-61 Issue 2）。
///
/// [pending]＝初始化中（背景啟動函式剛回傳、init 尚未結束；測試中「不關心
/// TTS」的預設也是它，不提示）；[ready]＝handler 已就緒；[failed]＝初始化已
/// 失敗、降級提示待顯示。狀態只會單向轉移，不會從 [ready] 或 [failed] 回到
/// [pending]。
enum TtsAudioHandlerStatus { pending, ready, failed }

/// 同時承載「handler 是否就緒」與「降級提示是否待顯示」的啟動階段 holder
/// （epic-61 Issue 2），取代分開傳遞的 `ttsAudioHandler` 與
/// `TtsDegradedNotice` 兩個參數——下游只需同步一個物件。
///
/// 三個建構子的意圖：
/// - [TtsAudioHandlerHolder.ready]：handler 已就緒，不降級。
/// - [TtsAudioHandlerHolder.degraded]：初始化已失敗（[failed]）、提示待顯示。
/// - [TtsAudioHandlerHolder.unavailable]：初始化中（[pending]），不提示；
///   供只是需要傳一個依賴的一般測試最小改動使用，不會意外觸發提示。
class TtsAudioHandlerHolder extends ChangeNotifier {
  TtsAudioHandlerHolder.ready(TtsAudioHandler handler)
      : _status = TtsAudioHandlerStatus.ready,
        _handler = handler,
        _noticePending = false;

  TtsAudioHandlerHolder.degraded()
      : _status = TtsAudioHandlerStatus.failed,
        _handler = null,
        _noticePending = true;

  TtsAudioHandlerHolder.unavailable()
      : _status = TtsAudioHandlerStatus.pending,
        _handler = null,
        _noticePending = false;

  TtsAudioHandlerHolder._pending()
      : _status = TtsAudioHandlerStatus.pending,
        _handler = null,
        _noticePending = false;

  TtsAudioHandlerStatus _status;
  TtsAudioHandler? _handler;
  bool _noticePending;

  TtsAudioHandlerStatus get status => _status;

  /// 只有 [status] 為 [TtsAudioHandlerStatus.ready] 時非 null。
  TtsAudioHandler? get handler => _handler;

  /// 只有 [status] 為 [TtsAudioHandlerStatus.failed] 且尚未提示時回傳 true，
  /// 並標記為已提示（沿用 Issue 1 `TtsDegradedNotice.consume` 語意）。
  bool consumeDegradedNotice() {
    if (_status != TtsAudioHandlerStatus.failed || !_noticePending) {
      return false;
    }
    _noticePending = false;
    return true;
  }

  void _completeReady(TtsAudioHandler handler) {
    if (_status != TtsAudioHandlerStatus.pending) return;
    _handler = handler;
    _status = TtsAudioHandlerStatus.ready;
    notifyListeners();
  }

  void _completeFailed() {
    if (_status != TtsAudioHandlerStatus.pending) return;
    _status = TtsAudioHandlerStatus.failed;
    _noticePending = true;
    notifyListeners();
  }
}

/// 同步回傳 [pending] 狀態的 holder，背景執行 [initTtsAudioHandlerSafely]
/// （接住所有例外、失敗回傳 null 的語意不變），完成後把 holder 改成 [ready]
/// 或 [failed] 並通知一次；init 永遠不回來時 holder 維持 [pending]、不提示。
///
/// [AudioService.init] 全程式只呼叫一次、失敗後不可重試的限制不變——背景
/// 執行不改變這點，呼叫端仍只可呼叫一次本函式。
TtsAudioHandlerHolder startTtsAudioHandlerInBackground(
  Future<TtsAudioHandler> Function() init,
) {
  final holder = TtsAudioHandlerHolder._pending();
  initTtsAudioHandlerSafely(init).then((handler) {
    if (handler != null) {
      holder._completeReady(handler);
    } else {
      holder._completeFailed();
    }
  });
  return holder;
}
