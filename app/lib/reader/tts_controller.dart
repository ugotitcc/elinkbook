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

  /// 目前語速（epic-34-tts-readalong Issue 5）。初始值 `1.0`——與
  /// [TtsProvider.synthesize] 既有預設參數值一致（見 `tts_provider.dart`），
  /// 也是 [TtsAudioPlayer.setSpeed] 的「正常速度」語意，兩者恰好在 `1.0`
  /// 這個值上一致，初始狀態不需要額外轉換。
  double _speed = 1.0;
  double get speed => _speed;

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
      // _segments／_currentIndex 一起賦值、放在兩個 await 之後、確認世代
      // 仍有效才寫入——避免中途被中止的呼叫留下「_segments 已覆寫、但
      // 從未真正開始播放」的孤兒狀態（同一個 review Important #1／#2 的
      // 修法延伸）。
      _segments = loaded;
      _currentIndex =
          (startIndex >= 0 && startIndex < _segments.length) ? startIndex : 0;
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
  bool _suppressNextPositionChange = false;

  void suppressNextExternalPositionChange() {
    if (_disposed) return;
    _suppressNextPositionChange = true;
  }

  void handleExternalPositionChange() {
    if (_disposed) return;
    if (_suppressNextPositionChange) {
      _suppressNextPositionChange = false;
      return;
    }
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
    final segment = _segments[_currentIndex];
    final generation = ++_segmentGeneration;
    try {
      _status = TtsPlaybackStatus.playing;
      onHighlightSegment?.call(segment);
      notifyListeners();
      final result = await provider.synthesize(
        segment.text,
        voice: TtsVoice.systemDefault,
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
    } catch (_) {
      if (_disposed || generation != _segmentGeneration) return;
      _suppressNextPositionChange = false;
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
    _suppressNextPositionChange = false;
    _completedSub?.cancel();
    player.dispose();
    super.dispose();
  }
}
