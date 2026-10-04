import 'package:flutter/foundation.dart';

import 'tts_audio_handler.dart';

/// 啟動階段建立 [TtsAudioHandler]；失敗時回傳 null，讓 App 照常啟動（epic-61）。
///
/// 真機實測：`AudioService.init` 在 service 綁定逾時（約 10 秒）時會丟出
/// `PlatformException`，若沒有接住，`main()` 會在 `runApp` 之前中斷，整個
/// App 黑屏且沒有任何錯誤提示。系統媒體通知／鎖屏控制只是附加功能，失敗時
/// 降級為本次執行沒有這些控制即可——朗讀本身仍可用（`TtsController` 的建立
/// 不依賴 handler）。下游（`ReaderScreen` 等）的 `ttsAudioHandler` 本來就是
/// 可為 null 的型別，使用處皆為 `?.`。
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
