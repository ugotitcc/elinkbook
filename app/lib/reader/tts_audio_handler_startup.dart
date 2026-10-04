import 'package:flutter/foundation.dart';

import 'tts_audio_handler.dart';

/// 啟動階段建立 [TtsAudioHandler]；失敗時回傳 null，讓 App 照常啟動（epic-61）。
///
/// 真機實測：`AudioService.init` 在 service 綁定逾時（約 10 秒）時會丟出
/// `PlatformException`，若沒有接住，`main()` 會在 `runApp` 之前中斷，整個
/// App 黑屏且沒有任何錯誤提示。朗讀（TTS）只是附加功能，失敗時降級為
/// 「本次執行不可用」即可——下游（`ReaderScreen` 等）的 `ttsAudioHandler`
/// 本來就是可為 null 的型別，使用處皆為 `?.`。
///
/// [init] 以參數注入，讓單元測試不必真的呼叫 `AudioService.init`
/// （它需要原生端 service）。同步丟出的例外也一併接住。
Future<TtsAudioHandler?> initTtsAudioHandlerSafely(
  Future<TtsAudioHandler> Function() init,
) async {
  try {
    return await init();
  } catch (e, st) {
    debugPrint('TTS 音訊服務初始化失敗，本次執行朗讀不可用：$e\n$st');
    return null;
  }
}
