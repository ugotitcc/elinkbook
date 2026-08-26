import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tts_audio_player.dart';
import 'tts_provider.dart';
import 'tts_segment_cfi.dart';

enum TtsPlaybackStatus { idle, playing, paused }

/// 朗讀狀態機的核心協調者（epic-34-tts-readalong Issue 2，spec.md
/// 「Implementation Decisions」）。純 Dart、不依賴 Flutter widget 樹或
/// WebView，[loadSegments] 由呼叫端（[ReaderScreen]）注入，內部實際呼叫
/// `FoliateReaderView.loadTtsSegments()`——本類別完全不知道 `FoliateReaderView`
/// 存在，只透過這個 callback 取得朗讀段清單。`extends ChangeNotifier`
/// 讓 UI（本 Issue 的簡易播放/暫停按鈕、Issue 6 的 Mini Player）可直接
/// 訂閱狀態變化（見 `review-issues.md` Minor #1「單一事實來源」）。
///
/// Phase 1 MVP 簡化：不維護獨立的「音訊播放位置 → 朗讀段」二分搜尋索引
/// （原研究報告的 `TtsTimeline` 設計）——每個朗讀段各自合成為獨立音訊檔、
/// 依序播放（非單一連續跨段落音訊流，見 design.md 決策 9「音訊合成一律
/// 走檔案管線」），「目前是哪一段」天然等同 [currentIndex] 這個整數游標，
/// 不需要對「音訊時間」做二分搜尋。Issue 4 若需要「畫面位置 → 朗讀段」
/// 反向查找（`lookupSegmentByCfi`），可直接對 [segments] 做線性/二分搜尋
/// （已依文件順序排序），不影響本類別既有結構。
class TtsController extends ChangeNotifier {
  final TtsProvider provider;
  final TtsAudioPlayer player;
  final Future<List<TtsSegmentCfi>> Function() loadSegments;

  TtsController({
    required this.provider,
    required this.player,
    required this.loadSegments,
  }) {
    _completedSub = player.completedStream.listen((_) => _handleSegmentCompleted());
  }

  TtsPlaybackStatus _status = TtsPlaybackStatus.idle;
  TtsPlaybackStatus get status => _status;

  List<TtsSegmentCfi> _segments = const [];
  List<TtsSegmentCfi> get segments => _segments;

  int _currentIndex = -1;
  int get currentIndex => _currentIndex;

  StreamSubscription<void>? _completedSub;
  bool _disposed = false;

  /// `play()` 在 `idle` 狀態下要先 `await loadSegments()`（涉及 JS bridge
  /// 往返，非立即完成）——這段期間 `_status` 仍是 `idle`，若不設防重入
  /// 旗標，使用者連點播放鍵會觸發第二次 `loadSegments()`／合成流程互相
  /// 打架（審查 review-plan-issue-2.md Important #2）。
  bool _isLoadingSegments = false;

  Future<void> play() async {
    if (_status == TtsPlaybackStatus.playing) return;
    if (_isLoadingSegments) return;
    if (_status == TtsPlaybackStatus.paused) {
      _status = TtsPlaybackStatus.playing;
      notifyListeners();
      try {
        await player.play();
      } catch (_) {
        if (_disposed) return;
        _status = TtsPlaybackStatus.idle;
        _currentIndex = -1;
        _segments = const [];
        notifyListeners();
      }
      return;
    }
    // idle：第一次播放，先載入目前章節的朗讀段。
    _isLoadingSegments = true;
    List<TtsSegmentCfi> loaded;
    try {
      loaded = await loadSegments();
    } finally {
      _isLoadingSegments = false;
    }
    if (_disposed) return;
    if (loaded.isEmpty) return; // 沒有可朗讀的內容，維持 idle。
    _segments = loaded;
    _currentIndex = 0;
    await _playCurrentSegment();
  }

  void pause() {
    if (_status != TtsPlaybackStatus.playing) return;
    _status = TtsPlaybackStatus.paused;
    notifyListeners();
    try {
      player.pause();
    } catch (_) {}
  }

  /// 合成並播放 [_currentIndex] 對應的朗讀段。`provider.synthesize()`／
  /// `player.loadFile()` 任一步驟拋出例外時（例如真機上 Android TTS
  /// 引擎失敗、磁碟寫入錯誤），一律捕捉並重設回 `idle`——不重新拋出
  /// （審查 review-plan-issue-2.md Important #1）。這個方法同時被
  /// [play] 與 [_handleSegmentCompleted]（自動接續下一句）呼叫，後者是
  /// 在 `completedStream` 的 `listen()` callback 內以「非 async 回呼
  /// 型別」的方式觸發（`void Function(T)`，Dart 不會 await 這個
  /// callback 回傳的 `Future`），若不在這裡就地捕捉例外，會變成沒人
  /// 接住的非同步例外，且 `_status` 會永遠卡在 `playing`（使用者看到
  /// 暫停圖示但實際上沒在播放，怎麼點都沒反應）。
  Future<void> _playCurrentSegment() async {
    final segment = _segments[_currentIndex];
    try {
      _status = TtsPlaybackStatus.playing;
      notifyListeners();
      final result = await provider.synthesize(
        segment.text,
        voice: TtsVoice.systemDefault,
      );
      if (_disposed) return;
      await player.loadFile(result.audioFilePath);
      // 重要修復（review-issue-2-code.md Important #1）：若在 synthesize/loadFile
      // 非同步期間使用者按下了暫停鍵（_status 變更為 paused），檔案載入完成後
      // 不得再呼叫 player.play()，應維持在 paused 狀態，等待使用者下次主動按下播放鍵。
      if (_disposed || _status != TtsPlaybackStatus.playing) return;
      await player.play();
    } catch (_) {
      if (_disposed) return;
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      notifyListeners();
    }
  }

  Future<void> _handleSegmentCompleted() async {
    if (_disposed) return;
    if (_status != TtsPlaybackStatus.playing) return;
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _segments.length) {
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      notifyListeners();
      return;
    }
    _currentIndex = nextIndex;
    await _playCurrentSegment();
  }

  @override
  void dispose() {
    _disposed = true;
    _completedSub?.cancel();
    player.dispose();
    super.dispose();
  }
}
