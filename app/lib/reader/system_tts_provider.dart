import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tts_provider.dart';

/// 系統原生語音朗讀（Android `TextToSpeech`，透過 `flutter_tts` 套件）。
/// [synthesize] 呼叫 `synthesizeToFile()`（檔案合成，非 `speak()` 即時
/// 朗讀——見 design.md 決策 9），固定寫入單一暫存檔路徑並每次覆寫（見
/// Global Constraints「暫存音訊檔生命週期」），呼叫端（[TtsController]）
/// 負責在播放完成/切換書籍/dispose 時視需要清除該檔案。
class SystemTtsProvider implements TtsProvider {
  final FlutterTts _flutterTts;

  SystemTtsProvider({FlutterTts? flutterTts})
      : _flutterTts = flutterTts ?? FlutterTts();

  @override
  Future<List<TtsVoice>> getAvailableVoices() async {
    // Phase 1 僅系統預設語音，無選單需求，呼叫端不依賴此結果。
    return const [TtsVoice.systemDefault];
  }

  @override
  Future<TtsSynthesisResult> synthesize(
    String text, {
    required TtsVoice voice,
    double speed = 1.0,
    double pitch = 1.0,
  }) async {
    final filePath = await _resolveOutputPath();

    // flutter_tts 的語速範圍是 0.0（最慢）～1.0（最快），本專案呼叫端
    // 目前恆傳 1.0（Issue 5 才會有語速調整 UI），clamp 純防禦。
    await _flutterTts.setSpeechRate(speed.clamp(0.0, 1.0));

    final completer = Completer<void>();
    _flutterTts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    _flutterTts.setErrorHandler((dynamic message) {
      if (!completer.isCompleted) {
        completer.completeError(TtsSynthesisException(message.toString()));
      }
    });

    // isFullPath=true：呼叫端自己決定完整路徑並覆寫，不依賴套件自行組裝
    // 路徑的預設行為（見 Global Constraints「固定命名空間、覆寫」）。
    await _flutterTts.synthesizeToFile(text, filePath, true);
    await completer.future;

    return TtsSynthesisResult(audioFilePath: filePath);
  }

  Future<String> _resolveOutputPath() async {
    final tempDir = await getTemporaryDirectory();
    final ttsDir = Directory(p.join(tempDir.path, 'elinkbook_tts'));
    if (!await ttsDir.exists()) {
      await ttsDir.create(recursive: true);
    }
    return p.join(ttsDir.path, 'current_segment.wav');
  }
}