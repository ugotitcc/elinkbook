# Issue 5：上一句/下一句/語速調整控制 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `TtsController` 新增「上一句」／「下一句」／「語速調整」三個播放控制能力，並在 `ReaderScreen` 補上對應的陽春按鈕（比照 Issue 2 既有播放/暫停按鈕的陽春 UI 慣例，正式 Mini Player 視覺是 Issue 6 範圍）。語速調整須符合「目前段落零延遲變速、下一段才用新語速合成」的契約（`review-spec.md` Minor #2）。

**Architecture:** `TtsController` 新增 `nextSegment()`／`previousSegment()`（直接把 `_currentIndex` 移到指定段落後呼叫既有 `_playCurrentSegment()`，重用同一段程式碼路徑）與 `setSpeed()`（更新 `_speed` 欄位；非 idle 狀態下額外呼叫 `player.setSpeed()` 做執行期變速，`_playCurrentSegment()` 呼叫 `provider.synthesize()` 時一併帶入 `speed: _speed`，讓「下一段」自然套用新語速）。`nextSegment()`／`previousSegment()` 讓 `_playCurrentSegment()` 首次出現「可能被連續快速呼叫、彼此重疊」的情境（例如連按兩下「下一句」），因此同步新增一個專屬的世代編號防重入機制（比照 `play()` 既有 `_playGeneration` 手法，見 Task 1），對既有呼叫路徑（`play()`／自動接續）零影響。`ReaderScreen` 只做 UI 接線，不新增 `TtsController` 建構參數。

**Tech Stack:** 沿用既有 `TtsController`/`TtsAudioPlayer`/`TtsProvider`/`just_audio`，`TtsAudioPlayer` 抽象介面新增 `setSpeed(double speed)`（`just_audio` 既有 `AudioPlayer.setSpeed()`，`1.0`＝正常速度語意，已於本機 `just_audio-0.10.6` 原始碼確認），無新增套件依賴。

**Spec:** `docs/epics/epic-34-tts-readalong/issues.md`「Issue 5」；`docs/epics/epic-34-tts-readalong/spec.md`「Implementation Decisions」語速調整生效時機契約（第 109 行）；`docs/epics/epic-34-tts-readalong/reviews/review-spec.md` Minor #2。**本計畫已依 `docs/epics/epic-34-tts-readalong/reviews/review-plan-issue-5.md` 建議 1 修訂**：`handleExternalPositionChange()` 一併遞增 `_segmentGeneration`，讓手動導覽發生時，正在進行中的段落合成能在 `synthesize()` 返回當下就提前放棄，不再多做一次不會真正播放、卻仍寫入本機檔案系統的 `player.loadFile()` 呼叫（見 Task 1 Step 7）。

## Global Constraints

- `TtsController` 保持格式無關、完全不知道 `FoliateReaderView`／WebView 存在——本 Issue 不新增任何 JS↔Dart 橋接，`nextSegment()`／`previousSegment()`／`setSpeed()` 純粹是 `TtsController` 既有狀態機的延伸（比照既有 `loadSegments`／`onHighlightSegment` 的既有解耦模式，本 Issue 不需要新增類似的注入 callback）。
- **語速刻度不做轉換、如實記錄落差**：`TtsProvider.synthesize()` 的 `speed` 參數是 `flutter_tts` 慣例（`0.0` 最慢～`1.0` 最快，`SystemTtsProvider.synthesize()` 既有 `speed.clamp(0.0, 1.0)`，本 Issue 不修改該檔案）；`TtsAudioPlayer.setSpeed()` 是 `just_audio` 慣例（`1.0`＝正常速度，可超過 `1.0` 加速）。`TtsController` 刻意把同一個 `_speed` 數值直接轉發給兩邊 API，不做刻度換算——代價是 UI 語速預設清單中大於 `1.0` 的值（`1.25`／`1.5`／`1.75`／`2.0`）在「下一段」合成時會被 `SystemTtsProvider` 既有的 `clamp(0.0, 1.0)` 統一收斂成 `1.0`（最快），只有「目前正在播放的段落」才會透過 `player.setSpeed()` 真正聽到差異化的加速效果。這是刻意的已知限制、非本 Issue 缺陷，已於 Task 1 程式碼註解與本文件「測試策略總結」明確記錄，待真機測試回報體感不理想時再另立工單校準（比照本專案 `tapMaxDurationMs` 既有校準先例）。
- 不做 Mini Player 正式視覺（Issue 6 範圍）、不做背景播放/`audio_service`（Issue 7 範圍）、不做 E-Ink 安全視窗（Issue 8 範圍）——`ReaderScreen` 只新增三顆陽春 FAB 按鈕，沿用 Issue 2 既有播放/暫停按鈕的 `ClipOval` + `Container` + `IconButton` 樣式與 `_themedFabBackgroundColor`/`_themedFabIconColor`，垂直堆疊在既有播放/暫停按鈕（`top: 296`）下方（`top: 352`／`408`／`464`），Issue 6 會整個重新整理這個按鈕群的版面。
- 新增/修改的 Dart 檔案沿用既有扁平結構（`app/lib/reader/`，不建子目錄）；測試沿用既有檔案位置（`app/test/reader/tts_controller_test.dart`／`app/test/screens/reader_screen_test.dart`／`app/test/support/fake_tts_audio_player.dart`／`app/test/support/fake_tts_provider.dart`，皆為既有檔案新增內容，不新建檔案）。

---

### Task 1：`TtsAudioPlayer`／`TtsController`——上一句/下一句/語速調整（TDD）

**Files:**
- Modify: `app/lib/reader/tts_audio_player.dart`
- Modify: `app/lib/reader/tts_controller.dart`
- Modify: `app/test/support/fake_tts_audio_player.dart`
- Modify: `app/test/support/fake_tts_provider.dart`
- Test: `app/test/reader/tts_controller_test.dart`（既有檔案，新增測試案例）

**Interfaces:**
- Consumes：既有 `TtsSegmentCfi`（`tts_segment_cfi.dart`）、既有 `TtsProvider.synthesize()` 的 `speed` 具名參數（`tts_provider.dart`，已存在，未變更簽章）
- Produces：`TtsAudioPlayer` 新增抽象方法 `Future<void> setSpeed(double speed)`（`JustAudioTtsPlayer` 實作）；`TtsController` 新增公開方法 `Future<void> nextSegment()`／`Future<void> previousSegment()`／`Future<void> setSpeed(double newSpeed)` 與公開 getter `double get speed`——皆供 Task 2 的 `ReaderScreen` 使用

- [x] **Step 1：`FakeTtsAudioPlayer`／`FakeTtsProvider` 測試替身新增 speed 記錄能力**

在 `app/test/support/fake_tts_audio_player.dart` 找到既有的 `pause()`／`dispose()` 之間的區塊：

```dart
  @override
  Future<void> pause() async {
    callLog.add('pause');
    if (pauseShouldThrow) {
      pauseShouldThrow = false;
      throw Exception('fake pause failure');
    }
  }

  @override
  Future<void> dispose() async {
```

整段取代為：

```dart
  @override
  Future<void> pause() async {
    callLog.add('pause');
    if (pauseShouldThrow) {
      pauseShouldThrow = false;
      throw Exception('fake pause failure');
    }
  }

  /// 記錄每次 [setSpeed] 呼叫的實際數值（epic-34-tts-readalong Issue 5），
  /// 供測試驗證「目前段落」是否確實走執行期變速這條路徑，而非重新合成。
  final List<double> speedCalls = [];

  @override
  Future<void> setSpeed(double speed) async {
    speedCalls.add(speed);
    callLog.add('setSpeed');
  }

  @override
  Future<void> dispose() async {
```

在 `app/test/support/fake_tts_provider.dart` 找到既有的 `synthesize()` 方法：

```dart
  @override
  Future<TtsSynthesisResult> synthesize(
    String text, {
    required TtsVoice voice,
    double speed = 1.0,
    double pitch = 1.0,
  }) async {
    synthesizeCallCount++;
    synthesizedTexts.add(text);
    final completer = nextSynthesizeCompleter;
```

整段取代為：

```dart
  /// 記錄每次 [synthesize] 呼叫實際收到的 `speed` 參數（epic-34-tts-readalong
  /// Issue 5），供測試驗證「下一段」合成確實套用了呼叫當下的最新語速。
  final List<double> synthesizeSpeeds = [];

  @override
  Future<TtsSynthesisResult> synthesize(
    String text, {
    required TtsVoice voice,
    double speed = 1.0,
    double pitch = 1.0,
  }) async {
    synthesizeCallCount++;
    synthesizedTexts.add(text);
    synthesizeSpeeds.add(speed);
    final completer = nextSynthesizeCompleter;
```

- [x] **Step 2：寫失敗測試**

在 `app/test/reader/tts_controller_test.dart` 檔案結尾（最後一個 `test()` 之後、`}` 之前）新增：

```dart
  test('初始 speed 為 1.0', () {
    final controller = buildController();
    expect(controller.speed, 1.0);
  });

  test('setSpeed() 於 idle 狀態下只更新 speed 值，不呼叫 player.setSpeed()（尚無正在播放的段落可變速）',
      () async {
    final controller = buildController();

    await controller.setSpeed(1.5);

    expect(controller.speed, 1.5);
    expect(player.callLog, isEmpty);
  });

  test('setSpeed() 於 playing 狀態下呼叫 player.setSpeed()，不重新呼叫 synthesize'
      '（目前段落零延遲變速，語速契約澄清 review-spec.md Minor #2）', () async {
    final controller = buildController();
    await controller.play();
    expect(provider.synthesizeCallCount, 1);

    await controller.setSpeed(1.5);

    expect(controller.speed, 1.5);
    expect(player.speedCalls, [1.5]);
    expect(provider.synthesizeCallCount, 1); // 不重新合成
  });

  test('setSpeed() 於 paused 狀態下同樣呼叫 player.setSpeed()（暫停中的段落之後恢復時沿用新語速）',
      () async {
    final controller = buildController();
    await controller.play();
    controller.pause();

    await controller.setSpeed(0.75);

    expect(player.speedCalls, [0.75]);
  });

  test('setSpeed() 後，自動接續下一段時 synthesize() 收到新的 speed 值（下一段才用新語速合成）',
      () async {
    final controller = buildController();
    await controller.play();
    await controller.setSpeed(1.5);
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);

    expect(provider.synthesizeSpeeds, [1.0, 1.5]);
  });

  test('nextSegment() 於 idle 狀態下為 no-op，不呼叫 synthesize', () async {
    final controller = buildController();

    await controller.nextSegment();

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(provider.synthesizeCallCount, 0);
  });

  test('nextSegment() 從第一段跳到第二段並開始播放', () async {
    final controller = buildController();
    await controller.play();

    await controller.nextSegment();

    expect(controller.currentIndex, 1);
    expect(provider.synthesizedTexts, ['第一句。', '第二句。']);
    expect(controller.status, TtsPlaybackStatus.playing);
  });

  test('nextSegment() 於最後一段時，回到 idle 並清除高亮（等同自然播放完畢）', () async {
    final highlighted = <TtsSegmentCfi?>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      onHighlightSegment: highlighted.add,
    );
    await controller.play();
    await controller.nextSegment(); // 到第二段（最後一段）

    await controller.nextSegment(); // 已是最後一段，視同播放完畢

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.currentIndex, -1);
    expect(controller.segments, isEmpty);
    expect(highlighted.last, isNull);
  });

  test('nextSegment() 於 paused 狀態下呼叫，跳到下一段並自動恢復播放', () async {
    final controller = buildController();
    await controller.play();
    controller.pause();
    expect(controller.status, TtsPlaybackStatus.paused);

    await controller.nextSegment();

    expect(controller.currentIndex, 1);
    expect(controller.status, TtsPlaybackStatus.playing);
  });

  test('previousSegment() 於 idle 狀態下為 no-op', () async {
    final controller = buildController();

    await controller.previousSegment();

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(provider.synthesizeCallCount, 0);
  });

  test('previousSegment() 於第一段（currentIndex=0）呼叫為 no-op，不迴繞到最後一段', () async {
    final controller = buildController();
    await controller.play();
    expect(controller.currentIndex, 0);

    await controller.previousSegment();

    expect(controller.currentIndex, 0);
    expect(provider.synthesizeCallCount, 1); // 沒有新的合成呼叫
  });

  test('previousSegment() 從第二段跳回第一段並重新播放', () async {
    final controller = buildController();
    await controller.play();
    await controller.nextSegment(); // 到第二段

    await controller.previousSegment();

    expect(controller.currentIndex, 0);
    expect(provider.synthesizedTexts, ['第一句。', '第二句。', '第一句。']);
  });

  test('nextSegment() 連續快速呼叫兩次時，只有最後一次呼叫的結果生效，不播放到過期段落'
      '（防重入，比照 review-issue-4-code.md Important #2 手法）', () async {
    const threeSegments = [
      TtsSegmentCfi(segmentId: '0', cfi: 'epubcfi(/6/4!/1:0)', text: '第一句。'),
      TtsSegmentCfi(segmentId: '1', cfi: 'epubcfi(/6/4!/1:5)', text: '第二句。'),
      TtsSegmentCfi(segmentId: '2', cfi: 'epubcfi(/6/4!/1:10)', text: '第三句。'),
    ];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => threeSegments,
    );
    await controller.play(); // 目前在第 0 段（playing）

    final firstSynthCompleter = Completer<void>();
    provider.nextSynthesizeCompleter = firstSynthCompleter;
    final firstNext = controller.nextSegment(); // 跳到第 1 段，等待合成
    await Future<void>.delayed(Duration.zero);

    final secondSynthCompleter = Completer<void>();
    provider.nextSynthesizeCompleter = secondSynthCompleter;
    final secondNext = controller.nextSegment(); // 跳到第 2 段，等待合成
    await Future<void>.delayed(Duration.zero);

    // 讓第一次呼叫（較舊、應該過期）反而先完成合成。
    firstSynthCompleter.complete();
    await Future<void>.delayed(Duration.zero);
    secondSynthCompleter.complete();
    await firstNext;
    await secondNext;

    // 只有第 2 段（最新一次呼叫）的音訊被實際載入播放，第 1 段的
    // （過期）合成結果被安全捨棄，不會讓使用者聽到「跳回舊句子」。
    expect(controller.currentIndex, 2);
    expect(player.loadedFiles, ['/fake/segment_1.wav', '/fake/segment_3.wav']);
  });

  test('handleExternalPositionChange() 於 nextSegment() 合成進行中呼叫時，讓該次呼叫的音訊'
      '不被載入播放器（review-plan-issue-5.md 建議 1：_segmentGeneration 提前失效）',
      () async {
    final controller = buildController();
    await controller.play(); // 第 0 段已在播放中

    final synthCompleter = Completer<void>();
    provider.nextSynthesizeCompleter = synthCompleter;
    final nextFuture = controller.nextSegment(); // 跳到第 1 段，合成進行中
    await Future<void>.delayed(Duration.zero);

    controller.handleExternalPositionChange(); // 模擬合成期間發生手動導覽
    synthCompleter.complete(); // 合成這時才完成（結果已過期）
    await nextFuture;

    expect(controller.status, TtsPlaybackStatus.idle);
    // 過期結果不應該被載入播放器——沒有這項修法時，loadFile() 仍會被呼叫
    // （只是事後因 _status != playing 而不會真的播放出聲音）；本測試驗證
    // handleExternalPositionChange() 讓 _segmentGeneration 提前失效後，
    // 連 loadFile() 這個不必要的呼叫也不會發生。
    expect(player.loadedFiles, isEmpty);
  });

  test('dispose() 後呼叫 nextSegment()/previousSegment()/setSpeed() 不拋出例外', () async {
    final controller = buildController();
    await controller.play();
    controller.dispose();

    expect(() => controller.nextSegment(), returnsNormally);
    expect(() => controller.previousSegment(), returnsNormally);
    expect(() => controller.setSpeed(1.5), returnsNormally);
  });
```

- [x] **Step 3：跑測試確認全數失敗**

```
flutter test test/reader/tts_controller_test.dart
```

Expected：FAIL——`TtsController`／`TtsAudioPlayer`／`FakeTtsAudioPlayer`／`FakeTtsProvider` 尚未有 `speed`／`setSpeed`／`nextSegment`／`previousSegment`／`speedCalls`／`synthesizeSpeeds` 等成員，編譯期即報錯。

- [x] **Step 4：`TtsAudioPlayer` 新增 `setSpeed()`**

在 `app/lib/reader/tts_audio_player.dart` 找到既有的抽象介面：

```dart
abstract class TtsAudioPlayer {
  Future<void> loadFile(String path);
  Future<void> play();
  Future<void> pause();

  /// 目前載入的音訊播放完畢時發出一個事件（不攜帶資料）。
  Stream<void> get completedStream;

  Future<void> dispose();
}
```

整段取代為：

```dart
abstract class TtsAudioPlayer {
  Future<void> loadFile(String path);
  Future<void> play();
  Future<void> pause();

  /// 執行期變速（epic-34-tts-readalong Issue 5，spec.md「語速調整的生效
  /// 時機」契約）：只影響「目前已載入、可能正在播放/暫停中」的音訊，不
  /// 重新合成、不中斷播放。[speed] 為 `just_audio` 慣例的倍率語意
  /// （`1.0`＝正常速度），與 [TtsProvider.synthesize] 的 `speed` 參數
  /// （`flutter_tts` 慣例的 `0.0`（最慢）～`1.0`（最快）語意）刻度不同——
  /// [TtsController] 目前刻意把同一個數值直接轉發給兩邊 API，未做刻度
  /// 換算（見 `tts_controller.dart` 對應註解），真機實際聽感落差待真機
  /// 測試後再校準。
  Future<void> setSpeed(double speed);

  /// 目前載入的音訊播放完畢時發出一個事件（不攜帶資料）。
  Stream<void> get completedStream;

  Future<void> dispose();
}
```

找到既有的 `JustAudioTtsPlayer` 內 `play()`／`pause()` 之間的區塊：

```dart
  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();
```

整段取代為：

```dart
  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
```

- [x] **Step 5：`TtsController` 新增 `speed` 欄位**

在 `app/lib/reader/tts_controller.dart` 找到既有的：

```dart
  int _currentIndex = -1;
  int get currentIndex => _currentIndex;

  StreamSubscription<void>? _completedSub;
```

整段取代為：

```dart
  int _currentIndex = -1;
  int get currentIndex => _currentIndex;

  /// 目前語速（epic-34-tts-readalong Issue 5）。初始值 `1.0`——與
  /// [TtsProvider.synthesize] 既有預設參數值一致（見 `tts_provider.dart`），
  /// 也是 [TtsAudioPlayer.setSpeed] 的「正常速度」語意，兩者恰好在 `1.0`
  /// 這個值上一致，初始狀態不需要額外轉換。
  double _speed = 1.0;
  double get speed => _speed;

  StreamSubscription<void>? _completedSub;
```

- [x] **Step 6：`TtsController` 新增 `setSpeed()`／`nextSegment()`／`previousSegment()`**

找到既有的 `pause()` 方法：

```dart
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
```

緊接其後（在下一段 `/// 偵測到非 TTS 自身觸發的畫面位置變化時呼叫...`／`handleExternalPositionChange` 之前）新增：

```dart
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
```

- [x] **Step 7：`handleExternalPositionChange()` 一併使 `_segmentGeneration` 提前失效（審查 `review-plan-issue-5.md` 建議 1）**

找到既有的 `handleExternalPositionChange()` 方法（Issue 4 已新增）：

```dart
  void handleExternalPositionChange() {
    if (_disposed) return;
    _playGeneration++;
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
```

整段取代為（只在 `_playGeneration++;` 之後多插入一行，不更動既有邏輯順序）：

```dart
  void handleExternalPositionChange() {
    if (_disposed) return;
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
```

- [x] **Step 8：`_playCurrentSegment()` 新增世代防重入機制與 speed 參數**

找到既有的：

```dart
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
```

整段取代為：

```dart
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
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      onHighlightSegment?.call(null);
      notifyListeners();
    }
  }
```

- [x] **Step 9：跑測試確認全數通過**

```
flutter test test/reader/tts_controller_test.dart
```

Expected：全數 PASS（既有測試＋新增測試皆通過，零回歸）。

```
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 10：Commit**

```bash
git add app/lib/reader/tts_audio_player.dart app/lib/reader/tts_controller.dart app/test/support/fake_tts_audio_player.dart app/test/support/fake_tts_provider.dart app/test/reader/tts_controller_test.dart
git commit -m "feat(epic-34): TtsController 新增上一句/下一句/語速調整（Issue 5 Task 1）"
```

---

### Task 2：`ReaderScreen` 接線——上一句/下一句/語速按鈕 UI

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`（既有檔案，新增測試案例）

**Interfaces:**
- Consumes：Task 1 的 `TtsController.nextSegment()`／`previousSegment()`／`setSpeed()`／`speed` getter；既有 `_ttsControllerOrNull`／`_themedFabBackgroundColor`／`_themedFabIconColor`
- Produces：`ReaderScreen` 內部接線（無新增公開 API），新增三個 `Key`：`reader_tts_previous_button`／`reader_tts_next_button`／`reader_tts_speed_button`

- [x] **Step 1：寫失敗測試**

在 `app/test/screens/reader_screen_test.dart` 找到 Issue 4 新增的 `group('手動導覽自動暫停與恢復播放（epic-34-tts-readalong Issue 4）', ...)` 結尾的 `});`，在它之後新增一個新的 group：

```dart
  group('上一句/下一句/語速調整控制（epic-34-tts-readalong Issue 5）', () {
    testWidgets('未提供 ttsProvider 時，不顯示上一句/下一句/語速按鈕', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts5_no_provider',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView =
          tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('reader_tts_previous_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_next_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_speed_button')), findsNothing);
    });

    testWidgets(
        'CBZ 格式提供 ttsProvider 時，上一句/下一句/語速按鈕皆不顯示（僅播放/暫停停用按鈕存在）',
        (tester) async {
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.cbz',
            bookId: 'b_tts5_cbz',
            prefsManager: prefsManager,
            isFixedLayout: true,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView =
          tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('reader_tts_play_pause_button')), findsOneWidget);
      expect(find.byKey(const Key('reader_tts_previous_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_next_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_speed_button')), findsNothing);
    });

    testWidgets(
        '提供 ttsProvider 時，流式 EPUB 顯示上一句/下一句/語速按鈕，初始語速顯示 1.00x',
        (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts5_buttons',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView =
          tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('reader_tts_previous_button')), findsOneWidget);
      expect(find.byKey(const Key('reader_tts_next_button')), findsOneWidget);
      final speedButtonFinder = find.byKey(const Key('reader_tts_speed_button'));
      expect(speedButtonFinder, findsOneWidget);
      expect(
        find.descendant(of: speedButtonFinder, matching: find.text('1.00x')),
        findsOneWidget,
      );
    });

    testWidgets(
        '提供 ttsProvider 時，點擊上一句/下一句按鈕不崩潰（誠實測試邊界：flutter_test 環境下'
        'FoliateReaderView 的 _controller 恆為 null，loadSegments 恆回傳空清單，'
        'TtsController 永遠不會真正進入 playing 狀態，這裡驗證的是 UI 接線不崩潰這個'
        '結構性保證；真正的段落跳轉行為由 tts_controller_test.dart（Task 1）完整涵蓋）',
        (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts5_tap',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView =
          tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_tts_previous_button')));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('reader_tts_next_button')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '點擊語速按鈕依序循環預設語速清單，畫面數字同步更新'
        '（單一事實來源：直接顯示 TtsController.speed，比照既有播放/暫停按鈕的'
        'AnimatedBuilder 訂閱模式）', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts5_speed',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView =
          tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      final speedButtonFinder = find.byKey(const Key('reader_tts_speed_button'));
      expect(
        find.descendant(of: speedButtonFinder, matching: find.text('1.00x')),
        findsOneWidget,
      );

      await tester.tap(speedButtonFinder);
      await tester.pump();
      expect(
        find.descendant(of: speedButtonFinder, matching: find.text('1.25x')),
        findsOneWidget,
      );

      await tester.tap(speedButtonFinder);
      await tester.pump();
      expect(
        find.descendant(of: speedButtonFinder, matching: find.text('1.50x')),
        findsOneWidget,
      );
    });
  });
```

- [x] **Step 2：跑測試確認全數失敗**

```
flutter test test/screens/reader_screen_test.dart
```

Expected：FAIL——`reader_tts_previous_button`／`reader_tts_next_button`／`reader_tts_speed_button` 尚不存在，`findsOneWidget` 斷言失敗。

- [x] **Step 3：新增語速預設清單與循環 helper**

在 `app/lib/screens/reader_screen.dart` 找到既有的 `_ttsControllerOrNull` getter 結尾（Issue 4 已新增 `lookupStartIndex`）：

```dart
      lookupStartIndex: (segs) async {
        final visibleCfi = extractCfi(_epubPositionInfo?.locatorJson);
        if (visibleCfi == null) return 0;
        return FoliateReaderView.lookupSegmentByCfi(
          _foliateEpubReaderViewKey,
          visibleCfi,
          segs.map((s) => s.cfi).toList(),
        );
      },
    );
  }
```

緊接其後（在下一段 `Widget _buildNativeView(...)` 之前）新增：

```dart

  /// 語速調整（epic-34-tts-readalong Issue 5）的 UI 預設清單，`1.0` 為
  /// 正常速度、其餘為使用者常見的加速/減速倍率選項。點擊「語速」按鈕
  /// 依序循環，找不到目前值（理論上不會發生，僅作防禦）時回退到 `1.0`。
  /// 這批數值直接轉發給 [TtsController.setSpeed]，大於 `1.0` 的選項在
  /// 「下一段」合成時會被 `SystemTtsProvider` 既有的 `clamp(0.0, 1.0)`
  /// 收斂成最快速——僅「目前段落」的執行期變速會如實呈現差異（見
  /// `plan-issue-5.md` Global Constraints「語速刻度不做轉換」說明）。
  static const List<double> _ttsSpeedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  double _nextTtsSpeedPreset(double current) {
    final index =
        _ttsSpeedPresets.indexWhere((p) => (p - current).abs() < 0.001);
    if (index == -1) return 1.0;
    return _ttsSpeedPresets[(index + 1) % _ttsSpeedPresets.length];
  }
```

- [x] **Step 4：新增上一句/下一句/語速三顆 FAB 按鈕**

在 `app/lib/screens/reader_screen.dart` 找到既有的 TTS 播放/暫停按鈕區塊結尾（CBZ 三元運算式的 `AnimatedBuilder` 分支結束處）：

```dart
                    : AnimatedBuilder(
                        animation: _ttsControllerOrNull!,
                        builder: (context, _) {
                          final controller = _ttsControllerOrNull!;
                          final playing =
                              controller.status == TtsPlaybackStatus.playing;
                          return ClipOval(
                            child: Container(
                              color: _themedFabBackgroundColor,
                              child: IconButton(
                                key: const Key('reader_tts_play_pause_button'),
                                icon: Icon(
                                  playing ? Icons.pause : Icons.play_arrow,
                                  color: _themedFabIconColor,
                                ),
                                tooltip: playing ? '暫停朗讀' : '開始朗讀',
                                onPressed:
                                    playing ? controller.pause : () => controller.play(),
                              ),
                            ),
                          );
                        },
                      ),
              ),
```

整段取代為：

```dart
                    : AnimatedBuilder(
                        animation: _ttsControllerOrNull!,
                        builder: (context, _) {
                          final controller = _ttsControllerOrNull!;
                          final playing =
                              controller.status == TtsPlaybackStatus.playing;
                          return ClipOval(
                            child: Container(
                              color: _themedFabBackgroundColor,
                              child: IconButton(
                                key: const Key('reader_tts_play_pause_button'),
                                icon: Icon(
                                  playing ? Icons.pause : Icons.play_arrow,
                                  color: _themedFabIconColor,
                                ),
                                tooltip: playing ? '暫停朗讀' : '開始朗讀',
                                onPressed:
                                    playing ? controller.pause : () => controller.play(),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            // 上一句/下一句/語速調整（epic-34-tts-readalong Issue 5）：CBZ
            // 完全不支援朗讀（無文字節點），連同播放/暫停以外的三顆控制
            // 按鈕一併排除，不只顯示停用狀態——這三顆按鈕本來就不該出現
            // 在 CBZ 畫面上，跟播放/暫停按鈕「顯示但停用」的既有設計不同。
            // 陽春 FAB 樣式（沿用 Issue 2 既有慣例），Issue 6 會整理成正式
            // Mini Player 版面。
            if (isFoliateFormat(format) &&
                _chromeVisible &&
                widget.ttsProvider != null &&
                format != BookFormat.cbz)
              Positioned(
                top: 352,
                right: 16,
                child: AnimatedBuilder(
                  animation: _ttsControllerOrNull!,
                  builder: (context, _) {
                    final controller = _ttsControllerOrNull!;
                    return ClipOval(
                      child: Container(
                        color: _themedFabBackgroundColor,
                        child: IconButton(
                          key: const Key('reader_tts_previous_button'),
                          icon: Icon(Icons.skip_previous, color: _themedFabIconColor),
                          tooltip: '上一句',
                          onPressed: () => controller.previousSegment(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (isFoliateFormat(format) &&
                _chromeVisible &&
                widget.ttsProvider != null &&
                format != BookFormat.cbz)
              Positioned(
                top: 408,
                right: 16,
                child: AnimatedBuilder(
                  animation: _ttsControllerOrNull!,
                  builder: (context, _) {
                    final controller = _ttsControllerOrNull!;
                    return ClipOval(
                      child: Container(
                        color: _themedFabBackgroundColor,
                        child: IconButton(
                          key: const Key('reader_tts_next_button'),
                          icon: Icon(Icons.skip_next, color: _themedFabIconColor),
                          tooltip: '下一句',
                          onPressed: () => controller.nextSegment(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (isFoliateFormat(format) &&
                _chromeVisible &&
                widget.ttsProvider != null &&
                format != BookFormat.cbz)
              Positioned(
                top: 464,
                right: 16,
                child: AnimatedBuilder(
                  animation: _ttsControllerOrNull!,
                  builder: (context, _) {
                    final controller = _ttsControllerOrNull!;
                    final speedLabel = '${controller.speed.toStringAsFixed(2)}x';
                    return ClipOval(
                      child: Container(
                        color: _themedFabBackgroundColor,
                        child: IconButton(
                          key: const Key('reader_tts_speed_button'),
                          icon: Text(
                            speedLabel,
                            style: TextStyle(
                              color: _themedFabIconColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          tooltip: '朗讀語速：$speedLabel（點擊切換）',
                          onPressed: () => controller
                              .setSpeed(_nextTtsSpeedPreset(controller.speed)),
                        ),
                      ),
                    );
                  },
                ),
              ),
```

- [x] **Step 5：跑測試確認全數通過、零回歸**

```
flutter test test/screens/reader_screen_test.dart
```

Expected：全數 PASS（含新增的 5 個測試，既有測試零回歸）。

```
flutter test
```

Expected：全專案測試全數通過，零回歸。

```
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-34): ReaderScreen 接線——上一句/下一句/語速按鈕 UI（Issue 5 Task 2）"
```

---

## 測試策略總結（Self-Review 用，非額外步驟）

- **純 Dart 單元測試**（Task 1）：`TtsController.nextSegment()`／`previousSegment()` 在 idle／playing／paused／最後一段／第一段等邊界狀態下的正確行為；`setSpeed()` 在 idle 狀態下只更新欄位、非 idle 狀態下呼叫 `player.setSpeed()` 且不重新合成、新語速確實套用在下一段的 `synthesize()` 呼叫；連續快速呼叫 `nextSegment()` 時不會播放到過期段落（防重入）；`handleExternalPositionChange()` 於段落合成進行中觸發時，過期結果連 `player.loadFile()` 都不會被呼叫（審查 `review-plan-issue-5.md` 建議 1，Task 1 Step 7）。
- **`ReaderScreen` widget test**（Task 2）：驗證 UI 接線層級——按鈕在提供/未提供 `ttsProvider`、CBZ/非 CBZ 下的顯示與否；點擊上一句/下一句不崩潰；點擊語速按鈕時畫面數字（單一事實來源直讀 `TtsController.speed`）正確依預設清單循環。
- **無法自動化、須真機手動驗證的部分**（比照既有 Issue「測試策略總結」慣例，合併前建議至少手動跑一次）：
  1. 朗讀中點擊「下一句」，確認立即跳到下一句並開始播放，不需要等目前這句念完。
  2. 朗讀中點擊「上一句」，確認重新播放上一句；在第一句時點擊「上一句」確認沒有反應（不會跳到最後一句）。
  3. 朗讀中點擊語速按鈕調整到 `1.5x`／`2.0x`，確認「目前正在念的這句」立即變速（不是等這句念完才生效），且不會有短暫的音訊中斷/雜音。
  4. 語速調整到大於 `1.0` 的值後，讓目前段落自然念完、自動接續下一句，確認下一句的合成語速體感（因既有 `SystemTtsProvider` 的 `clamp(0.0, 1.0)`，預期會是「最快」而非精確對應 UI 顯示的倍率——這是本計畫 Global Constraints 已記錄的已知限制，真機確認體感是否需要另立校準工單）。
  5. 章節最後一句時點擊「下一句」，確認朗讀正常停止（回到 idle），不是卡住或報錯。

---

## Self-Review 檢查結果

- **Spec coverage**：`issues.md` Issue 5 設計要點與驗收標準逐條對應——`TtsController` 新增 `nextSegment()`／`previousSegment()`（Task 1 Step 6，重用 `_playCurrentSegment()` 同一段程式碼路徑）、語速調整生效時機契約（Task 1 Step 6 `setSpeed()`＋Step 8 `_playCurrentSegment()` 帶入 `speed: _speed`，`review-spec.md` Minor #2 明確對應）、`ReaderScreen` widget test 驗證上一句/下一句按鈕觸發跳轉與語速調整走播放器變速 API（Task 2）、`flutter analyze`／`flutter test` 全數通過（兩個 Task 皆有驗證步驟）。**另已納入 `review-plan-issue-5.md` 建議 1**：`handleExternalPositionChange()` 一併遞增 `_segmentGeneration`（Task 1 Step 7），讓手動導覽發生時正在進行中的段落合成能更早放棄，不再多做一次不會真正播放的 `player.loadFile()` 呼叫，並有對應單元測試（Task 1 Step 2 新增測試）驗證。無缺口。
- **Placeholder scan**：全文搜尋未發現「TBD」/「之後補」/「處理錯誤」等空話；所有程式碼步驟皆有完整程式碼區塊與精確的既有程式碼比對錨點。
- **Type consistency**：`TtsAudioPlayer.setSpeed(double speed)`（Task 1 Step 4 定義）與 `JustAudioTtsPlayer`／`FakeTtsAudioPlayer` 實作簽章一致；`TtsController.setSpeed(double newSpeed)`／`nextSegment()`／`previousSegment()`（皆回傳 `Future<void>`，Task 1 Step 6 定義）與 Task 2 `ReaderScreen` 呼叫端（`onPressed: () => controller.setSpeed(...)` 等，fire-and-forget，比照既有 `controller.play()` 呼叫慣例）一致；`double get speed`（Task 1 Step 5 定義）與 Task 2 `controller.speed`／`_nextTtsSpeedPreset(controller.speed)` 呼叫端一致。
