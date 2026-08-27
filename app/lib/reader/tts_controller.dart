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

  /// 朗讀段切換時呼叫（epic-34-tts-readalong Issue 3，spec.md「高亮渲染」／
  /// ADR 0026）：帶入即將開始朗讀的 [TtsSegmentCfi]，或在播放結束/合成失敗
  /// 導致重設回 idle 時帶入 `null` 通知呼叫端清除高亮。呼叫端
  /// （[ReaderScreen]）注入實際呼叫 `FoliateReaderView.showTtsHighlight()`/
  /// `clearTtsHighlight()` 的邏輯——本類別完全不知道 `FoliateReaderView`
  /// 或高亮如何渲染，只負責在正確時機通知「現在該顯示哪一段」，比照
  /// [loadSegments] 既有的解耦模式。切換到新段落時呼叫端不需要自行先清除
  /// 舊高亮再顯示新高亮——`window.showTtsHighlight()`（main.js）內部已處理
  /// 「顯示新的之前先清除舊的」，呼叫端只需忠實轉發每次收到的值。
  final void Function(TtsSegmentCfi? segment)? onHighlightSegment;

  /// 依「畫面目前可視位置」決定 [play] 從 `idle` 開始播放時的起始段落索引
  /// （epic-34-tts-readalong Issue 4，2026-08-27 Issue 3 真機驗收追加範圍：
  /// 首次播放與手動導覽後恢復播放皆須套用，見 [handleExternalPositionChange]
  /// 文件註解）。呼叫端（[ReaderScreen]）注入實際呼叫
  /// `FoliateReaderView.lookupSegmentByCfi()` 的邏輯——本類別完全不知道
  /// `FoliateReaderView` 存在，比照 [loadSegments]／[onHighlightSegment]
  /// 既有的解耦模式。回傳值超出 [segments] 範圍（含負數）時，[play] 會
  /// 安全 clamp 回 `0`；未提供本參數時退回既有的「固定從第 0 段開始」
  /// 行為，向後相容既有呼叫端。
  final Future<int> Function(List<TtsSegmentCfi> segments)? lookupStartIndex;

  TtsController({
    required this.provider,
    required this.player,
    required this.loadSegments,
    this.onHighlightSegment,
    this.lookupStartIndex,
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
        onHighlightSegment?.call(null);
        notifyListeners();
      }
      return;
    }
    // idle：第一次播放（或手動導覽觸發重置後的播放，見
    // handleExternalPositionChange），先載入目前章節的朗讀段。
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
    // 起始段落改由 lookupStartIndex 依「畫面目前可視位置」決定
    // （epic-34-tts-readalong Issue 4），不再固定從第 0 段開始——這個
    // 分支同時涵蓋「使用者從未開始朗讀，直接按下播放鍵」與「手動導覽
    // 觸發自動暫停（見 handleExternalPositionChange）後再次按下播放鍵」
    // 兩種情境，因為後者也會先把狀態重設回 idle，兩者共用同一段程式碼
    // 路徑。未提供 lookupStartIndex 時（例如尚未接上 ReaderScreen 的
    // 測試情境）退回既有的「從第 0 段開始」行為，向後相容。
    final startIndex =
        lookupStartIndex == null ? 0 : await lookupStartIndex!(loaded);
    if (_disposed) return;
    _currentIndex =
        (startIndex >= 0 && startIndex < _segments.length) ? startIndex : 0;
    await _playCurrentSegment();
  }

  void pause() {
    if (_status != TtsPlaybackStatus.playing) return;
    _status = TtsPlaybackStatus.paused;
    notifyListeners();
    // player.pause() 回傳的 Future 若稍後才 reject（常見於平台 channel API），
    // 同步 try/catch 攔不到——一律改用 catchError 承接，避免變成未捕捉的
    // 非同步例外（複審 review-issue-2-code.md 殘留技術細節）。
    try {
      player.pause().catchError((_) {});
    } catch (_) {}
  }

  /// 偵測到非 TTS 自身觸發的畫面位置變化時呼叫（epic-34-tts-readalong
  /// Issue 4，`issues.md`「手動導覽觸發暫停時須清除舊高亮」）——呼叫端
  /// （[ReaderScreen]）在既有 relocate 類事件（`onLocatorChanged`）內
  /// 無條件呼叫本方法即可，不需要自行判斷「是否為 TTS 自身觸發」：
  /// [TtsController] 在目前架構下從未呼叫任何導覽方法（只呼叫
  /// [onHighlightSegment] 疊加高亮，不移動畫面），故每一次
  /// `onLocatorChanged` 事件必然是使用者手動導覽（翻頁/捲動/跳章/開書）。
  ///
  /// 完全重設回 [TtsPlaybackStatus.idle]（而非停在 [TtsPlaybackStatus.paused]）
  /// ——不只是暫停播放，是刻意清空 [_segments]／[_currentIndex]：手動導覽
  /// 後使用者可能已經跳到不同章節，舊的朗讀段清單已經不適用，下一次呼叫
  /// [play] 時必須重新呼叫 [loadSegments] 取得目前章節的朗讀段。這也讓
  /// 「首次播放」與「手動導覽後恢復播放」共用完全同一段起始邏輯（見
  /// [play] 內 `lookupStartIndex` 呼叫處），不需要另外維護一個「暫停原因」
  /// 的旗標。狀態本來就是 idle（尚未播放過，或已經自然播放完畢）時為
  /// no-op，避免每次翻頁都觸發不必要的 [notifyListeners]。
  ///
  /// [_disposed] 防護（審查 `review-plan-issue-4.md` Important #1）：
  /// `ReaderScreen` 銷毀過程中，WebView 的 JS 橋接回呼（`onLocatorChanged`）
  /// 可能在 `_ttsController?.dispose()` 已執行、但 `ReaderScreen` 自身尚未
  /// 完全 unmount 之間的窄縫觸發，若在此時仍呼叫 [notifyListeners]，
  /// `ChangeNotifier` 會拋出「used after being disposed」例外導致崩潰——
  /// 比照本類別其餘會呼叫 [notifyListeners] 的方法（[_playCurrentSegment]／
  /// [_handleSegmentCompleted]）皆已有的既有防護慣例。
  void handleExternalPositionChange() {
    if (_disposed) return;
    if (_status == TtsPlaybackStatus.idle) return;
    _status = TtsPlaybackStatus.idle;
    _currentIndex = -1;
    _segments = const [];
    // 同 pause()：player.pause() 若非同步才失敗，同步 try/catch 攔不到，
    // 改用 catchError 承接（比照既有 pause() 的既有修法）。
    try {
      player.pause().catchError((_) {});
    } catch (_) {}
    onHighlightSegment?.call(null);
    notifyListeners();
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
      onHighlightSegment?.call(segment);
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
      onHighlightSegment?.call(null);
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
      onHighlightSegment?.call(null);
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
