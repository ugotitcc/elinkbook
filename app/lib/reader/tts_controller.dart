import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tts_audio_player.dart';
import 'tts_provider.dart';
import 'tts_segment_cfi.dart';
import 'reader_console_log.dart';

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

  /// 目前語速（epic-34-tts-readalong Issue 5）。初始值 `1.0`——與
  /// [TtsProvider.synthesize] 既有預設參數值一致（見 `tts_provider.dart`），
  /// 也是 [TtsAudioPlayer.setSpeed] 的「正常速度」語意，兩者恰好在 `1.0`
  /// 這個值上一致，初始狀態不需要額外轉換。
  double _speed = 1.0;
  double get speed => _speed;

  /// 目前選定的朗讀語音（epic-38-reader-chrome-tts-redesign Issue 2）。
  /// 初始值為 [TtsVoice.systemDefault]，比照 Phase 1 `SystemTtsProvider`
  /// 只有一種語音的既有事實。[TtsPanel.onVoiceTap] 呼叫 [setVoice] 後，
  /// 只影響「下一段」合成——不重新合成目前已載入/正在播放的音訊，比照
  /// 既有 [setSpeed] 對「目前段落執行期變速、下一段才套用新值」的區隔
  /// 原則不同之處在於：語速有播放器執行期變速這條路徑，語音沒有等價
  /// 機制（無法讓已合成完畢的音訊檔案「變成另一個人的聲音」），故
  /// [setVoice] 不需要也不能對 [player] 做任何呼叫，純粹是下一次
  /// [_playCurrentSegment] 呼叫 [TtsProvider.synthesize] 時讀取的欄位。
  TtsVoice _voice = TtsVoice.systemDefault;
  TtsVoice get voice => _voice;

  void setVoice(TtsVoice newVoice) {
    if (_disposed) return;
    _voice = newVoice;
    notifyListeners();
  }

  StreamSubscription<void>? _completedSub;
  bool _disposed = false;

  /// `play()` 在 `idle` 狀態下要先 `await loadSegments()`／`lookupStartIndex()`
  /// （皆涉及 JS bridge 往返，非立即完成）——這段期間 `_status` 仍是
  /// `idle`，若不設防重入旗標，使用者連點播放鍵會觸發第二次
  /// `loadSegments()`／合成流程互相打架（審查 review-plan-issue-2.md
  /// Important #2）。**必須包住 idle 分支內兩個 await（不能只包第一個）**
  /// ——審查 `review-issue-4-code.md` Important #1 已用可控 `Completer`
  /// 實測重現：若只包住 `loadSegments()`，`lookupStartIndex()` 進行中這段
  /// 期間本旗標已提前重設為 `false`、`_status` 仍是 `idle`，使用者連按
  /// 播放鍵會讓第二次 `play()` 呼叫直接通過所有既有守衛、與第一次呼叫
  /// 並行執行，導致 `loadSegments()` 被呼叫兩次、`_segments` 互相覆寫，
  /// 最終聽到「同一句話被合成兩次」而非預期內容。
  bool _isLoadingSegments = false;

  /// `play()` 每次進入 idle 分支時遞增的世代編號（審查
  /// `review-issue-4-code.md` Important #2）：`handleExternalPositionChange()`
  /// 偵測到手動導覽時無條件遞增本欄位，讓當時「正在 loadSegments()／
  /// lookupStartIndex() 兩次 JS bridge 往返中、尚未真正開始播放」的
  /// `play()` 呼叫，在兩個 await 分別回來後比對世代編號、發現自己已經
  /// 過期便主動中止——否則那次呼叫會沿用導覽前算出的（現已過期的）
  /// 章節/起始段落開始朗讀，使用者剛翻到的新頁面反而聽不到對應內容。
  int _playGeneration = 0;

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
        _suppressExpiryTimer?.cancel();
        _suppressNextPositionChange = false;
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
    final generation = ++_playGeneration;
    try {
      final loaded = await loadSegments();
      if (_disposed || generation != _playGeneration) return;
      if (loaded.isEmpty) return; // 沒有可朗讀的內容，維持 idle。
      // 起始段落改由 lookupStartIndex 依「畫面目前可視位置」決定
      // （epic-34-tts-readalong Issue 4），不再固定從第 0 段開始——這個
      // 分支同時涵蓋「使用者從未開始朗讀，直接按下播放鍵」與「手動導覽
      // 觸發自動暫停（見 handleExternalPositionChange）後再次按下播放鍵」
      // 兩種情境，因為後者也會先把狀態重設回 idle，兩者共用同一段程式碼
      // 路徑。未提供 lookupStartIndex 時（例如尚未接上 ReaderScreen 的
      // 測試情境）退回既有的「從第 0 段開始」行為，向後相容。
      final startIndex =
          lookupStartIndex == null ? 0 : await lookupStartIndex!(loaded);
      if (_disposed || generation != _playGeneration) return;
      // 硬性長度上限防線（epic-34-tts-readalong Issue 11）：main.js
      // buildTtsSegments() 已有標點/次要邊界切句規則（見 issues.md Issue
      // 11 設計要點第 1 點），但無法涵蓋所有極端排版，這裡是最後一道
      // 防線——依引擎回報的實際上限，把任何仍然過長的段落硬切成多個
      // 子段落再個別合成。maxInputLength 為 null（引擎未回報上限）時
      // _capSegmentsToMaxLength 直接原樣回傳，不套用任何切分。
      final maxInputLength = await provider.getMaxInputLength();
      if (_disposed || generation != _playGeneration) return;
      final capped = _capSegmentsToMaxLength(loaded, maxInputLength);
      // _segments／_currentIndex 一起賦值、放在所有 await 之後、確認世代
      // 仍有效才寫入——避免中途被中止的呼叫留下「_segments 已覆寫、但
      // 從未真正開始播放」的孤兒狀態（同一個 review Important #1／#2 的
      // 修法延伸）。
      _segments = capped.segments;
      final clampedStartIndex =
          (startIndex >= 0 && startIndex < loaded.length) ? startIndex : 0;
      _currentIndex = capped.startOffsets[clampedStartIndex];
    } finally {
      _isLoadingSegments = false;
    }
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

  /// 真正停止朗讀並釋放音訊焦點（epic-38-reader-chrome-tts-redesign
  /// Issue 2，修正既有 `TtsMiniPlayer.onClose` 只隱藏面板、不停止播放的
  /// 既有落差，`DESIGN.md` §13.1「點擊『✕ 關閉』必須停止 TTS 播放並釋放
  /// 音訊焦點」）。`_playGeneration`／`_segmentGeneration` 無條件遞增，
  /// 比照既有 [handleExternalPositionChange] 的既有防重入慣例——讓正在
  /// 進行中的 [play]／[_playCurrentSegment] 呼叫在下一次 await 之後安全
  /// 放棄，不會在 `stop()` 呼叫後又寫回過期狀態。
  Future<void> stop() async {
    if (_disposed) return;
    _playGeneration++;
    _segmentGeneration++;
    _suppressExpiryTimer?.cancel();
    _suppressNextPositionChange = false;
    _status = TtsPlaybackStatus.idle;
    _currentIndex = -1;
    _segments = const [];
    try {
      await player.stop().catchError((_) {});
    } catch (_) {}
    onHighlightSegment?.call(null);
    notifyListeners();
  }

  /// 調整語速（epic-34-tts-readalong Issue 5，spec.md「語速調整的生效
  /// 時機」契約／`review-spec.md` Minor #2）。無論目前狀態為何都先更新
  /// [_speed]——即使目前是 [TtsPlaybackStatus.idle]，之後第一次 [play]
  /// 呼叫 [_playCurrentSegment] 合成第一段時也要用這個新值，不能遺漏。
  /// 只有 `idle` 以外（`playing`／`paused`，代表 [player] 目前已載入某一段
  /// 音訊）才呼叫 [TtsAudioPlayer.setSpeed]——這是「目前正在播放的段落
  /// 改用播放器的執行期變速，不重新合成、不中斷播放」這句契約的直接對應：
  /// `idle` 狀態下沒有已載入的音訊可以變速，呼叫 [player] 沒有意義。
  Future<void> setSpeed(double newSpeed) async {
    if (_disposed) return;
    _speed = newSpeed;
    notifyListeners();
    if (_status == TtsPlaybackStatus.idle) return;
    try {
      await player.setSpeed(newSpeed);
    } catch (_) {}
  }

  /// 跳到下一段並立即開始播放（epic-34-tts-readalong Issue 5）。`idle`
  /// 狀態下（尚未開始朗讀）為 no-op——沒有「目前段落」可以跳過。已是最後
  /// 一段時，行為等同自然播放完畢（見 [_handleSegmentCompleted]）：回到
  /// `idle` 並清除高亮，而非停在原地不動，讓「跳過已經聽懂的內容」在
  /// 章節結尾有明確、可預期的結果。`paused` 狀態下呼叫會自動恢復播放
  /// （[_playCurrentSegment] 一律把狀態設回 `playing`）——比照一般播放器
  /// 「按下一句／上一句視同要繼續聽」的慣例行為。
  Future<void> nextSegment() async {
    if (_disposed) return;
    if (_status == TtsPlaybackStatus.idle) return;
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _segments.length) {
      _segmentGeneration++;
      _suppressExpiryTimer?.cancel();
      _suppressNextPositionChange = false;
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      try {
        player.pause().catchError((_) {});
      } catch (_) {}
      onHighlightSegment?.call(null);
      notifyListeners();
      return;
    }
    _currentIndex = nextIndex;
    await _playCurrentSegment();
  }

  /// 跳到上一段並立即開始播放（epic-34-tts-readalong Issue 5）。`idle`
  /// 狀態下為 no-op；已是第一段（[currentIndex] 為 `0`）時同樣為 no-op——
  /// 不存在「上一段」可以倒回，維持在目前段落，不迴繞到最後一段（迴繞
  /// 行為不符合「重聽剛剛沒聽清楚的句子」這個使用情境的直覺）。
  Future<void> previousSegment() async {
    if (_disposed) return;
    if (_status == TtsPlaybackStatus.idle) return;
    final prevIndex = _currentIndex - 1;
    if (prevIndex < 0) return;
    _currentIndex = prevIndex;
    await _playCurrentSegment();
  }

  /// 安全視窗跟隨翻頁（epic-34-tts-readalong Issue 8）觸發的自動翻頁，
  /// 即將呼叫端（[ReaderScreen]）對 [FoliateReaderView] 送出下一頁/上一頁
  /// 指令前，須先呼叫本方法——讓接下來一段時間內到來的
  /// [handleExternalPositionChange] 呼叫（由該次翻頁觸發的 relocate 事件
  /// 間接引發）被判斷為「TTS 自己造成的位置變化」而不重設播放狀態，而非
  /// 誤判為使用者手動導覽而錯誤暫停播放。
  ///
  /// **時間窗而非一次性消耗（2026-08-28 真機驗收修復）**：原始版本用一次性
  /// 旗標（呼叫一次 [handleExternalPositionChange] 就消耗掉），真機測試
  /// 發現翻頁方向正確、但翻頁後朗讀仍會中斷——追查 `paginator.js` 發現
  /// 單次 `view.next()`/`view.prev()` 在分頁（非捲動）模式下實際上會觸發
  /// 兩次 `relocate` 事件：一次是換頁本身觸發，另一次來自 `#container`
  /// 原生 `scroll` 事件的 debounce（`paginator.js` 第 1493-1502 行，
  /// `debounce(..., 250)`，`!this.scrolled` 分支沒有 `#isAnimating` 防護，
  /// 換頁動畫造成的 `scrollLeft`/`scrollTop` 位移一定會補觸發這個 250ms
  /// 後才落地的第二次 `relocate`）。一次性旗標只擋得住第一次，第二次會被
  /// 誤判為使用者手動導覽，讓 [TtsController] 重設回 idle、暫停播放器
  /// ——這正是「翻頁方向正確、但翻頁後朗讀中斷」的成因。改為時間窗
  /// （500ms，留有餘裕覆蓋 250ms 的 debounce 加上 JS↔Dart 橋接往返延遲）：
  /// 窗口內任何一次 [handleExternalPositionChange] 呼叫皆視為抑制範圍，
  /// 不消耗、不重設播放狀態，直到 [_suppressExpiryTimer] 到期才自動恢復
  /// 正常判斷。
  bool _suppressNextPositionChange = false;
  Timer? _suppressExpiryTimer;

  void suppressNextExternalPositionChange() {
    if (_disposed) return;
    _suppressNextPositionChange = true;
    _suppressExpiryTimer?.cancel();
    _suppressExpiryTimer = Timer(const Duration(milliseconds: 500), () {
      _suppressNextPositionChange = false;
    });
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
  ///
  /// `_playGeneration` 無條件遞增（審查 `review-issue-4-code.md`
  /// Important #2）：即使目前 `_status` 仍是 `idle`（`play()` 正在
  /// `loadSegments()`／`lookupStartIndex()` 兩次 JS bridge 往返中，尚未
  /// 真正開始播放），也不能讓那次呼叫沿用導覽前算出的（現已過期的）
  /// 章節/起始段落——遞增世代編號讓 [play] 內對應的比對自行偵測並中止，
  /// 不需要在這裡額外判斷「是否有 play() 正在進行中」。
  void handleExternalPositionChange() {
    if (_disposed) return;
    // 時間窗抑制期間（見 suppressNextExternalPositionChange() 文件註解）
    // 內到來的每一次呼叫都直接返回、不消耗旗標——旗標由到期計時器統一
    // 清除，讓單次翻頁觸發的多次 relocate 事件都能被正確吸收。
    if (_suppressNextPositionChange) return;
    _playGeneration++;
    // epic-34-tts-readalong Issue 5（審查 review-plan-issue-5.md 建議 1）：
    // 手動導覽發生時，可能正好有一個 nextSegment()／previousSegment()／
    // 自動接續觸發的 _playCurrentSegment() 呼叫正在等待 synthesize() 回應
    // ——不遞增 _segmentGeneration 的話，那次呼叫在 synthesize() 返回時
    // 世代編號仍然相符，會繼續呼叫 player.loadFile() 把已經過期的音訊
    // 寫入播放器（雖然之後會因 _status != playing 而不會真的播放出聲音，
    // 邏輯上無害，但這個 loadFile() 呼叫本身是完全不必要的）。跟
    // _playGeneration 一樣無條件遞增，讓過期呼叫能在 synthesize() 一返回
    // 就提前放棄，不用等到 loadFile() 之後才被攔下。
    _segmentGeneration++;
    if (_status == TtsPlaybackStatus.idle) return;
    _status = TtsPlaybackStatus.idle;
    _currentIndex = -1;
    _segments = const [];
    try {
      player.pause().catchError((_) {});
    } catch (_) {}
    onHighlightSegment?.call(null);
    notifyListeners();
  }

  /// App 從背景恢復前景時，主動重新送出目前播放位置對應的高亮（
  /// epic-34-tts-readalong Issue 7，spec.md「TtsController」Audio Focus
  /// 段落前的 User Story 28，對應 design.md「App 背景/前景切換時的高亮
  /// 同步落差」／`review-design.md` Important #3）。呼叫端（[ReaderScreen]）
  /// 在 `didChangeAppLifecycleState` 的 `AppLifecycleState.resumed` 分支
  /// 無條件呼叫本方法即可，不需要自行判斷「目前是否正在播放」——`idle`
  /// 狀態下為 no-op（沒有目前段落可以重新顯示），比照 [handleExternalPositionChange]
  /// 既有的「呼叫端無條件呼叫、內部自行判斷是否需要動作」設計慣例。
  ///
  /// **只重送「高亮」，不含 design.md 原文一併提到的「翻頁指令」**：安全
  /// 視窗跟隨翻頁機制是 Issue 8（尚未實作）的範圍，本方法目前只能重新
  /// 顯示高亮本身，不觸發任何捲動/翻頁；Issue 8 完成後若需要一併重新
  /// 觸發跟隨翻頁，屬於該 Issue 落地時的範圍，本方法不預先假設其存在。
  ///
  /// **保留 `_currentIndex` 邊界檢查（審查 `review-plan-issue-7.md` 4.1／
  /// `reviews/review-issue-7-code.md` 追蹤，2026-08-28 人類確認保留）**：
  /// `_status != idle` 時 `_currentIndex` 目前確實恆為 `_segments` 的合法
  /// 索引（由 [play]／[_playCurrentSegment] 等既有內部方法保證，
  /// `_playCurrentSegment()` 本身即無邊界檢查直接存取），但本方法與那些
  /// 方法性質不同——它是本類別**唯一一個由 App 生命週期事件（
  /// `AppLifecycleState.resumed`）觸發的公開方法**，呼叫時機與內部狀態
  /// 轉換完全解耦，不像 `_playCurrentSegment()` 只會被同一組緊密耦合的
  /// 內部呼叫路徑呼叫。這道檢查是刻意留給這個對外邊界的防禦性寫法：即使
  /// 未來 [handleExternalPositionChange]／[play] 的內部順序被改動、
  /// 不慎打破「非 idle 時索引恆合法」這個不變量，本方法也不會因此拋出
  /// `RangeError` 讓 App 崩潰，只是安靜地不重送高亮——這正是本方法既有
  /// 「呼叫端無條件呼叫、內部自行判斷是否需要動作」設計慣例的自然延伸。
  void resyncHighlight() {
    if (_disposed) return;
    if (_status == TtsPlaybackStatus.idle) return;
    if (_currentIndex < 0 || _currentIndex >= _segments.length) return;
    onHighlightSegment?.call(_segments[_currentIndex]);
  }

  /// 每次呼叫 [_playCurrentSegment] 取得的世代編號（epic-34-tts-readalong
  /// Issue 5）：本方法目前有四個呼叫端——[play]（idle 分支尾端）、
  /// [_handleSegmentCompleted]（自動接續下一句）、[nextSegment]、
  /// [previousSegment]。前兩者過去彼此天然不會重疊（同一時間只有一個
  /// 正在進行），但 [nextSegment]／[previousSegment] 讓使用者能在前一次
  /// 呼叫的 `synthesize()` 尚未回應時就再次呼叫本方法（例如連續快速點擊
  /// 「下一句」），而 `synthesize()` 的延遲不固定，兩次呼叫實際完成的
  /// 先後順序無法保證跟呼叫順序一致——若不加防護，較慢完成的那次呼叫會
  /// 在較快完成的呼叫「之後」才把（已過期的）音訊載入播放器，使用者會
  /// 聽到「跳回舊句子」。比照 [play] 既有 `_playGeneration` 的防重入手法
  /// （見該欄位文件註解），這裡新增一個專屬於「目前正在播放哪一段」的
  /// 世代編號：每次呼叫本方法就取得新編號並覆寫本欄位，兩個 await 之後
  /// 只要編號已被後續呼叫超越，就安全放棄、不寫入任何狀態、不呼叫
  /// [player]。既有呼叫路徑（[play]／[_handleSegmentCompleted]）因為從不
  /// 重疊呼叫本方法，這個檢查對它們恆為真、不改變既有行為。
  int _segmentGeneration = 0;

  Future<void> _playCurrentSegment() async {
    final generation = ++_segmentGeneration;
    // epic-34-tts-readalong Issue 11：單一段落合成/播放失敗時不得讓整個
    // 朗讀流程卡死或靜默無反應（例如遇到超出 TTS 引擎輸入長度上限、或
    // 原生端回報 ERROR_OUTPUT 的段落）——改為迴圈跳過失敗段落並嘗試
    // 下一段，直到成功播放某一段，或已無下一段可嘗試（視同章節自然
    // 播放完畢，走既有「重設回 idle」路徑）。
    while (true) {
      if (_disposed || generation != _segmentGeneration) return;
      if (_currentIndex < 0 || _currentIndex >= _segments.length) {
        // 已跳過所有剩餘段落（或呼叫當下本來就已經沒有下一段）：視同
        // 播放自然結束，重設回 idle（比照既有 _handleSegmentCompleted()
        // 章節結尾分支）。
        _suppressExpiryTimer?.cancel();
        _suppressNextPositionChange = false;
        _status = TtsPlaybackStatus.idle;
        _currentIndex = -1;
        _segments = const [];
        onHighlightSegment?.call(null);
        notifyListeners();
        return;
      }
      final segment = _segments[_currentIndex];
      try {
        _status = TtsPlaybackStatus.playing;
        onHighlightSegment?.call(segment);
        notifyListeners();
        final result = await provider.synthesize(
          segment.text,
          voice: _voice,
          speed: _speed,
        );
        if (_disposed || generation != _segmentGeneration) return;
        await player.loadFile(result.audioFilePath);
        // 重要修復（review-issue-2-code.md Important #1）：若在 synthesize/loadFile
        // 非同步期間使用者按下了暫停鍵（_status 變更為 paused），檔案載入完成後
        // 不得再呼叫 player.play()，應維持在 paused 狀態，等待使用者下次主動按下播放鍵。
        if (_disposed || generation != _segmentGeneration) return;
        if (_status != TtsPlaybackStatus.playing) return;
        await player.play();
        return;
      } catch (e) {
        if (_disposed || generation != _segmentGeneration) return;
        final message = '[TTS Diagnostic] 段落索引 $_currentIndex 合成/播放'
            '失敗，跳過並嘗試下一段：$e';
        debugPrint(message);
        ReaderConsoleLog.add(message);
        _currentIndex++;
      }
    }
  }

  Future<void> _handleSegmentCompleted() async {
    if (_disposed) return;
    if (_status != TtsPlaybackStatus.playing) return;
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _segments.length) {
      _suppressExpiryTimer?.cancel();
      _suppressNextPositionChange = false;
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
    _suppressExpiryTimer?.cancel();
    _suppressNextPositionChange = false;
    _completedSub?.cancel();
    player.dispose();
    super.dispose();
  }
}

/// 把 [original] 清單中任何 `text.length` 超過 [maxLength] 的段落，依
/// 字數硬切為多個子段落（沿用同一個原始 CFI——精確的子範圍 CFI 需要
/// 回到 JS 端重新計算，超出本硬性防線的職責範圍；子段落只共用同一個
/// 原始 CFI，高亮在這極端情境下會維持指向整個原段落，不影響「朗讀能
/// 正常繼續進行」這個核心目標，見 epic-34-tts-readalong Issue 11）。
/// [maxLength] 為 `null` 或 `<= 0`（引擎未回報上限）時原樣回傳，不套用
/// 任何切分。回傳值的 `startOffsets[i]` 是 [original] 第 `i` 個段落
/// （切分前）對應到切分後清單中「第一個子段落」的索引，供 `play()` 把
/// `lookupStartIndex` 算出的（切分前）索引正確換算到切分後的位置。
({List<TtsSegmentCfi> segments, List<int> startOffsets}) _capSegmentsToMaxLength(
  List<TtsSegmentCfi> original,
  int? maxLength,
) {
  if (maxLength == null || maxLength <= 0) {
    return (
      segments: original,
      startOffsets: List<int>.generate(original.length, (i) => i),
    );
  }
  final result = <TtsSegmentCfi>[];
  final startOffsets = <int>[];
  for (final segment in original) {
    startOffsets.add(result.length);
    final text = segment.text;
    if (text.length <= maxLength) {
      result.add(segment);
      continue;
    }
    var chunkIndex = 0;
    for (var start = 0; start < text.length; start += maxLength) {
      final end =
          (start + maxLength < text.length) ? start + maxLength : text.length;
      result.add(TtsSegmentCfi(
        segmentId: '${segment.segmentId}_$chunkIndex',
        cfi: segment.cfi,
        text: text.substring(start, end),
      ));
      chunkIndex++;
    }
  }
  return (segments: result, startOffsets: startOffsets);
}
