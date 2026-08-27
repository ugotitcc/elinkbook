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
      final message =
          '[TTS Diagnostic] Available Engines: $engines, Default: $defaultEngine';
      debugPrint(message);
      ReaderConsoleLog.add(message);
    } catch (e) {
      final message = '[TTS Diagnostic] Failed to query engines: $e';
      debugPrint(message);
      ReaderConsoleLog.add(message);
    }

    if (engines.isEmpty) {
      throw TtsSynthesisException(
        '系統中未偵測到任何「文字轉語音 (TTS)」引擎。'
        '請前往 Android 系統設定安裝並啟用支援中文的 TTS 引擎（例如 Google 文字轉語音）。',
      );
    }

    // 2. 明確設定語言（elinkBook 為繁體中文排版，優先設 zh-TW，若不支援則設 zh-CN）
    try {
      int langResult = await _flutterTts.setLanguage("zh-TW");
      if (langResult == 0) {
        await _flutterTts.setLanguage("zh-CN");
      }
    } catch (e) {
      final message = '[TTS Diagnostic] Failed to set language: $e';
      debugPrint(message);
      ReaderConsoleLog.add(message);
    }

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
    
    // 3. Timeout 兜底防懸掛
    try {
      await completer.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      throw TtsSynthesisException(
        '語音合成逾時（5秒）。這通常是因為系統預設的 TTS 語音引擎卡死或未完成初始化。'
        '請確認系統中已安裝並啟用可用的「文字轉語音 (TTS)」引擎。',
      );
    }

    // 4. 合成音訊檔案防禦性檢查
    final file = File(filePath);
    if (!await file.exists() || await file.length() == 0) {
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