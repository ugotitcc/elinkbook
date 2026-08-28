import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'reader_console_log.dart';
import 'tts_provider.dart';

/// 系統原生語音朗讀（Android `TextToSpeech`，透過 `flutter_tts` 套件）。
/// [synthesize] 呼叫 `synthesizeToFile()`（檔案合成，非 `speak()` 即時
/// 朗讀——見 design.md 決策 9），固定寫入單一暫存檔路徑（`current_segment.wav`）
/// 並每次覆寫（見 Global Constraints「暫存音訊檔生命週期」），不逐段累積孤兒檔案。
class SystemTtsProvider implements TtsProvider {
  final FlutterTts _flutterTts;

  SystemTtsProvider({FlutterTts? flutterTts})
      : _flutterTts = flutterTts ?? FlutterTts();

  @override
  Future<List<TtsVoice>> getAvailableVoices() async {
    // Phase 1 僅系統預設語音，無選單需求，呼叫端不依賴此結果。
    return const [TtsVoice.systemDefault];
  }

  /// 同時寫入 debug console 與 App 內建的閱讀器 Console Log 畫面
  /// （「設定 → 閱讀器 Console Log」，見 [ReaderConsoleLog]），
  /// 讓真機診斷不必接電腦跑 `adb logcat`。
  void _log(String message) {
    final tagged = '[TTS Diagnostic] $message';
    debugPrint(tagged);
    ReaderConsoleLog.add(tagged);
  }

  @override
  Future<TtsSynthesisResult> synthesize(
    String text, {
    required TtsVoice voice,
    double speed = 1.0,
    double pitch = 1.0,
  }) async {
    // 1. 診斷與防禦性檢查：確認裝置是否有可用 TTS 引擎
    List<dynamic> engines = const [];
    String? defaultEngine;
    try {
      engines = await _flutterTts.getEngines ?? const [];
      defaultEngine = await _flutterTts.getDefaultEngine;
      _log('Available Engines: $engines, Default: $defaultEngine');
    } catch (e) {
      _log('Failed to query engines: $e');
    }

    if (engines.isEmpty) {
      throw TtsSynthesisException(
        '系統中未偵測到任何「文字轉語音 (TTS)」引擎。'
        '請前往 Android 系統設定安裝並啟用支援中文的 TTS 引擎（例如 Google 文字轉語音）。',
      );
    }

    // 1b. 部分裝置（尤其是特規 E-Ink 韌體）系統中已裝妥引擎，卻沒有登記
    // 「預設引擎」（getDefaultEngine 回傳 null），導致 flutter_tts 底層
    // TextToSpeech 初始化行為不可靠。此時明確指定引擎：偵測到的清單中
    // 優先選 com.google.android.tts（穩定、支援中文），否則退回清單
    // 第一個——不寫死成只認 Google TTS，避免沒裝 Google TTS 的裝置被
    // 這段防禦誤傷。
    if (defaultEngine == null) {
      final chosenEngine = engines.contains('com.google.android.tts')
          ? 'com.google.android.tts'
          : engines.first as String;
      try {
        await _flutterTts.setEngine(chosenEngine);
        _log('No default engine reported; explicitly set engine to $chosenEngine');
      } catch (e) {
        _log('Failed to explicitly set engine to $chosenEngine: $e');
      }
    }

    // 2. 明確設定語言（elinkBook 為繁體中文排版，優先設 zh-TW，若不支援則設 zh-CN）
    try {
      int langResult = await _flutterTts.setLanguage("zh-TW");
      if (langResult == 0) {
        await _flutterTts.setLanguage("zh-CN");
      }
    } catch (e) {
      _log('Failed to set language: $e');
    }

    final filePath = await _resolveOutputPath();

    // flutter_tts 的語速範圍是 0.0（最慢）～1.0（最快）。呼叫端
    // （TtsController，epic-34-tts-readalong Issue 5）會傳入使用者實際
    // 選擇的語速，經 clamp(0.0, 1.0) 收斂——大於 1.0 的加速選項（例如
    // UI 上的 1.5x／2.0x）在這裡會被統一收斂成最快速，只有播放器端
    // TtsAudioPlayer.setSpeed() 的執行期變速才能呈現真正差異化的加速
    // 效果（見 plan-issue-5.md Global Constraints「語速刻度不做轉換」
    // 已記錄的已知限制）。
    await _flutterTts.setSpeechRate(speed.clamp(0.0, 1.0));

    final completer = Completer<void>();
    _flutterTts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    _flutterTts.setErrorHandler((dynamic message) {
      if (!completer.isCompleted) {
        _log('Native engine reported synthesis error: $message');
        completer.completeError(TtsSynthesisException(message.toString()));
      }
    });

    // isFullPath=true：呼叫端自己決定完整路徑並覆寫，不依賴套件自行組裝
    // 路徑的預設行為（見 Global Constraints「固定命名空間、覆寫」）。
    await _flutterTts.synthesizeToFile(text, filePath, true);

    // 3. Timeout 兜底防懸掛
    try {
      await completer.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _log('synthesizeToFile timed out after 5s (engine: ${defaultEngine ?? engines}）');
      throw TtsSynthesisException(
        '語音合成逾時（5秒）。這通常是因為系統預設的 TTS 語音引擎卡死或未完成初始化。'
        '請確認系統中已安裝並啟用可用的「文字轉語音 (TTS)」引擎。',
      );
    }

    // 4. 合成音訊檔案防禦性檢查
    final file = File(filePath);
    if (!await file.exists() || await file.length() == 0) {
      _log('Synthesized file missing or empty at $filePath. Engines: $engines');
      throw TtsSynthesisException(
        '語音合成檔案無效或大小為 0。可用的 TTS 引擎列表：$engines。'
        '請確認系統中已安裝並啟用可用的「文字轉語音 (TTS)」引擎。',
      );
    }

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