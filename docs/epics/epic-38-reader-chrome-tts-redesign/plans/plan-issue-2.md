# Epic 38 Issue 2：`TtsPanel` 重構＋`TtsController.stop()`＋睡眠定時器 實作計劃

> **給實作代理人：** 依照 `sdd-workflow` skill 的生命週期，本計劃屬於「規劃與審查」階段產出，動手寫程式碼前應先發起審查（`requesting-code-review`/`receiving-code-review`），審查者先出報告、不得直接修改本檔案。實作階段建議使用 `superpowers:executing-plans`（逐 Task 執行、每個 Task 之間可停下確認）；每完成一個 Step 就把該行的 `- [x]` 改成 `- [x]`。

**目標：** 新增 `TtsPanel` 取代既有 `TtsMiniPlayer`，與 `ReaderChromeBottomBar` 依 `TtsController.status` 衍生互斥切換（不設手動旗標）；新增 `TtsController.stop()` 真正停止播放並釋放音訊焦點；新增睡眠定時器（15/30/45/60 分＋不限時，到期為暫停不是停止）；`ReaderChromeTopBar` 的小喇叭圖示接上真實邏輯。

**架構：** `TtsPanel`（新 `StatelessWidget`，格式無關）取代 `TtsMiniPlayer`；`reader_screen.dart` 新增 `_buildBottomChrome(BookFormat format)` 方法（比照 Issue 1 審查修正抽出的 `_buildChromeTopBar()` 慣例），依 `_ttsController` 是否存在／`controller.status` 是否為 `idle` 衍生渲染 `ReaderChromeBottomBar` 或 `TtsPanel`；CBZ 因結構性沒有真正的 `TtsController`（見下方「計劃範圍澄清」），改用一個獨立的手動旗標控制其純裝飾用途的停用面板，不受一般格式「衍生而非手動旗標」原則影響。

**技術棧：** Flutter／Dart，既有 `just_audio`／`audio_service` 套件不變；測試延續既有 `flutter_test`＋`package:fake_async`＋本專案既有 Fake（`FakeTtsProvider`／`FakeTtsAudioPlayer`）慣例。

**規格：** [`docs/epics/epic-38-reader-chrome-tts-redesign/spec.md`](../spec.md) §功能③④（`Implementation Decisions`）／`Testing Decisions`／`Out of Scope`；工單摘要見 [`../issues.md`](../issues.md) Issue 2。

## Global Constraints

- 觸控目標依 `DESIGN.md` §7.2：一般模式 48dp、`isEinkMode` 時 56dp（`TtsPanel` 展開列 spec.md 原文用 52dp 作為一般模式基準，本計劃沿用；見 Task 3 說明）。
- `CLAUDE.md`「不可逆的技術決策」：`PdfReaderView`／`FoliateReaderView` 底層渲染維持兩條完全獨立路徑，本 Epic 僅合併 Chrome 層，本 Issue 不例外。
- 睡眠定時器選項固定 15/30/45/60 分＋「不限時」，時間到是「暫停」不是「停止」；不做逐秒倒數顯示（spec.md「Out of Scope」）。
- 語速刻度不做轉換（既有 `_nextTtsSpeedPreset`／`TtsController.setSpeed` 契約不變）。
- PDF／CBZ 無真實 TTS 底層能力的既有邊界維持不變：PDF 恆不建構 `TtsController`、`onTtsTap` 恆為 `null`；CBZ 顯示停用狀態面板，不新增播放能力。
- 語音選擇（`TtsPanel.onVoiceTap`）只做單次朗讀 session 內的臨時切換，不讀取也不寫入 `GlobalReaderPrefs.ttsVoiceId`（spec.md「Out of Scope」，與 `epic-36` `TtsDefaultsScreen` 的全域預設值串接留給後續 Epic）。
- 計時器相關行為一律用 `tester.pump(Duration)` 驅動真實 `Timer`（本檔案既有慣例，例如既有的 30 秒開書逾時測試），不使用真實 `Future.delayed`/`Timer` 等待；不在 `testWidgets` 內巢狀使用 `package:fake_async` 的 `fakeAsync()`（與 `TestWidgetsFlutterBinding` 自己的假時鐘衝突），純 Dart 測試檔（`tts_controller_test.dart`）才使用 `fakeAsync()`。
- `flutter_test` 環境下 `FoliateReaderView.loadTtsSegments()`／`lookupSegmentByCfi()` 因 WebView `_controller` 恆為 `null` 而恆回傳空清單／`0`（`foliate_reader_view.dart:696`／`:708`）——這是既有、跨 Issue 3-8 已多次記錄在案的環境限制，`TtsController.play()` 在 `ReaderScreen` widget test 環境下**結構性永遠無法真正離開 `idle` 狀態**。本計劃所有牽涉 `ReaderScreen` 整合層的測試步驟都已依此限制設計，見下方「計劃範圍澄清」第 2 點。

---

## 計劃範圍澄清（動手前必讀）

1. **CBZ 沒有真正的 `TtsController` 可供衍生視覺狀態**——`_ttsControllerOrNull` getter 的既有設計刻意不對 CBZ 存取（避免每次開啟 CBZ 書籍都白白建構用不到的 `TtsController`／原生 `AudioPlayer`），spec.md 的 `_buildBottomChrome()` 範例程式碼完全沒有處理這個既有事實，直接套用會讓 CBZ 的「◗ 朗讀」按鈕整個失去既有的「顯示停用狀態播放鍵」行為（回歸 Issue 34 既有驗收標準）。**決議（已與人類確認）**：新增一個只給 CBZ 用的獨立手動旗標 `_cbzTtsPanelVisible`，完全不影響一般格式「依 `controller.status` 衍生」的設計；沿用 Issue 1 之前 `TtsMiniPlayer` 對 CBZ 的既有處理精神（純裝飾、恆為停用狀態，`onStop`／`onClose` 只是收合面板本身）。見 Task 4。
2. **`ReaderScreen` 整合層測試無法驗證「切換到 `TtsPanel`」與睡眠定時器「到期呼叫 `controller.pause()`」**——`TtsController.play()` 在 `flutter_test` 環境下因為 `loadSegments()` 恆回傳空清單，`status` 永遠停在 `idle`（見上方 Global Constraints 最後一點），`TtsPanel` 因此結構性不可能出現在 `ReaderScreen` 的 widget 樹裡。這不是本 Issue 新產生的限制——`reader_screen_test.dart` 既有 TTS Issue 3/4/5/7 測試群組已大量使用「誠實測試邊界」註解承認同一件事，只是 Issue 1 之前的 `_ttsMiniPlayerVisible` 是一個與 `TtsController.status` 完全脫鉤的手動旗標，讓那些測試能在不需要真正播放成功的情況下讓 Mini Player 出現。**本 Issue 把顯示邏輯改為衍生自 `controller.status` 後，這個脫鉤消失，大量既有測試的『點擊「◗ 朗讀」→ 斷言 Mini Player 按鈕存在』模式會直接失效**，需要在 Task 8 逐一檢視、改為只斷言「點擊不崩潰、畫面維持在 `ReaderChromeBottomBar`」這類環境限制下仍可觀察的行為，深層狀態機正確性維持既有分工——完全交給純 Dart 的 `tts_controller_test.dart`（不經過 widget 樹，`loadSegments` 由測試自己注入，可自由控制）。
3. **新增測試專用 static helper `ReaderScreen.openSleepTimerPickerForTest`**——`_openSleepTimerPicker()` 只能透過已顯示的 `TtsPanel.onSleepTimerTap` 觸發，但 `TtsPanel` 依第 2 點無法在測試環境下真正出現。比照既有 `ReaderScreen.togglePdfBookmark`／`ReaderScreen.openPdfToc`（「對應 UI 入口在當時尚未接上」的既有 pattern，本情境是「對應 UI 入口在測試環境下結構性不可達」，性質不同但解法相同）新增一個強型別 static helper，直接呼叫 `_openSleepTimerPicker()`，讓睡眠定時器本身的 `Timer`／Bottom Sheet 選項邏輯仍可被完整測試，不因為上面的環境限制就完全放棄這塊測試覆蓋。見 Task 5 Step 5。
4. **`TtsController` 新增語音選擇能力（`spec.md` 未列出的必要補充）**——spec.md 只描述 `TtsPanel.onVoiceTap`「挑選後呼叫 `provider.synthesize` 的 `voice` 參數」，但 `synthesize()` 是 `TtsController._playCurrentSegment()` 內部呼叫的，UI 層不會也不應該直接呼叫它。要讓「選好的語音套用到下一段朗讀」這句話成立，`TtsController` 需要一個可寫入的「目前語音」狀態——新增 `TtsController.setVoice(TtsVoice)`／`voice` getter（比照既有 `setSpeed`／`speed` 的模式），`_playCurrentSegment()` 呼叫 `provider.synthesize` 時從寫死的 `TtsVoice.systemDefault` 改讀這個新欄位。見 Task 2。
5. **`TtsPanel` 補上 `isEinkMode` 建構參數（spec.md 程式碼片段遺漏，審查已確認補上）**——`ReaderChromeTopBar`／`ReaderChromeBottomBar`（Issue 1）皆有 `isEinkMode` 對應 `DESIGN.md` §7.2 觸控目標放大需求，`TtsPanel` 沒有理由是例外。見 Task 3。
6. **`TtsAudioHandler.stop()` 現有程式碼呼叫 `_controller?.pause()`**（`tts_audio_handler.dart:82-85`，Issue 7 當時 `TtsController.stop()` 還不存在時的權宜寫法）——本 Issue 新增 `TtsController.stop()` 後，系統通知欄/鎖定畫面的「停止」控制項理應真正停止並釋放音訊焦點，而非只是暫停。這是走讀既有程式碼發現的既有缺口，非 spec.md 明列項目，一併於 Task 1 修正。

---

## Task 1：`TtsController.stop()`＋`TtsAudioPlayer.stop()`＋`TtsAudioHandler.stop()` 修正

**Files:**
- Modify: `app/lib/reader/tts_controller.dart`
- Modify: `app/lib/reader/tts_audio_player.dart`
- Modify: `app/lib/reader/tts_audio_handler.dart`
- Modify: `app/test/support/fake_tts_audio_player.dart`
- Modify: `app/test/reader/tts_controller_test.dart`
- Modify: `app/test/reader/tts_audio_handler_test.dart`

**Interfaces:**
- Produces：`TtsController.stop()`（`Future<void>`，公開方法）；`TtsAudioPlayer.stop()`（抽象方法，`JustAudioTtsPlayer` 實作）；`FakeTtsAudioPlayer.stop()`（記錄呼叫至既有 `callLog`）。

- [x] **Step 1：`TtsAudioPlayer` 新增 `stop()` 抽象方法＋`JustAudioTtsPlayer` 實作**

編輯 `app/lib/reader/tts_audio_player.dart`，在 `setSpeed` 之後、`completedStream` 之前新增抽象方法：

```dart
  /// 真正停止播放並釋放底層音訊焦點（epic-38-reader-chrome-tts-redesign
  /// Issue 2）。相對於 [pause]（保留音訊焦點以便快速恢復），`just_audio`
  /// 的 `AudioPlayer.stop()` 會釋放平台音訊資源／音訊焦點——這正是「暫停」
  /// 與「真正停止」在音訊焦點語意上的既有官方區別。
  Future<void> stop();
```

`JustAudioTtsPlayer` 類別內，在 `pause()` 實作之後新增：

```dart
  @override
  Future<void> stop() => _player.stop();
```

- [x] **Step 2：`FakeTtsAudioPlayer` 新增 `stop()` 假實作**

編輯 `app/test/support/fake_tts_audio_player.dart`，在 `pause()` 實作之後新增：

```dart
  @override
  Future<void> stop() async {
    callLog.add('stop');
  }
```

- [x] **Step 3：`flutter analyze` 確認尚未實作 `stop()` 的 `TtsController` 不影響編譯**

Run: `flutter analyze`
Expected: `No issues found!`（`TtsAudioPlayer`／`FakeTtsAudioPlayer` 皆已補上 `stop()`，介面完整；`TtsController` 尚未呼叫，不影響現況）

- [x] **Step 4：撰寫 `TtsController.stop()` 的失敗測試**

編輯 `app/test/reader/tts_controller_test.dart`，在檔案最後、`main()` 收尾的 `}` 之前新增（緊接在既有最後一個 `group` 之後）：

```dart

  group('TtsController.stop()（epic-38-reader-chrome-tts-redesign Issue 2）', () {
    test('playing 狀態下呼叫 stop() 後，狀態重設為 idle 且清空段落', () async {
      final controller = buildController();
      await controller.play();
      expect(controller.status, TtsPlaybackStatus.playing);

      await controller.stop();

      expect(controller.status, TtsPlaybackStatus.idle);
      expect(controller.segments, isEmpty);
      expect(controller.currentIndex, -1);
    });

    test('stop() 呼叫 player.stop()，而非 player.pause()', () async {
      final controller = buildController();
      await controller.play();
      player.callLog.clear();

      await controller.stop();

      expect(player.callLog, ['stop']);
    });

    test('stop() 通知 onHighlightSegment 收到 null，清除既有高亮', () async {
      TtsSegmentCfi? lastSegment = const TtsSegmentCfi(
        segmentId: 'sentinel',
        cfi: 'epubcfi(/0)',
        text: 'sentinel',
      );
      provider = FakeTtsProvider();
      player = FakeTtsAudioPlayer();
      final controller = TtsController(
        provider: provider,
        player: player,
        loadSegments: () async => segments,
        onHighlightSegment: (segment) => lastSegment = segment,
      );
      await controller.play();
      expect(lastSegment, isNotNull);

      await controller.stop();

      expect(lastSegment, isNull);
    });

    test('paused 狀態下呼叫 stop() 同樣重設為 idle', () async {
      final controller = buildController();
      await controller.play();
      controller.pause();
      expect(controller.status, TtsPlaybackStatus.paused);

      await controller.stop();

      expect(controller.status, TtsPlaybackStatus.idle);
    });

    test('idle 狀態下呼叫 stop() 不拋例外，狀態維持 idle', () async {
      final controller = buildController();
      expect(controller.status, TtsPlaybackStatus.idle);

      // stop() 內部邏輯無條件執行（不像 pause() 有 _status != playing 的
      // 提前 return 守衛），idle 狀態下呼叫仍會走到 player.stop()——對已經
      // 停止的播放器呼叫一次無害，這裡驗證的是「不拋例外、狀態不受影響」，
      // 不是「no-op 不呼叫 player」。
      await controller.stop();

      expect(controller.status, TtsPlaybackStatus.idle);
      expect(player.callLog, ['stop']);
    });

    test('stop() 呼叫期間若有進行中的 play()，世代編號機制正確中止該次呼叫', () async {
      provider = FakeTtsProvider();
      player = FakeTtsAudioPlayer();
      final synthesizeCompleter = Completer<void>();
      provider.nextSynthesizeCompleter = synthesizeCompleter;
      final controller = TtsController(
        provider: provider,
        player: player,
        loadSegments: () async => segments,
      );

      final playFuture = controller.play(); // 卡在 synthesize() 尚未回應
      await Future<void>.delayed(Duration.zero);
      expect(controller.status, TtsPlaybackStatus.playing,
          reason: '_playCurrentSegment 已先把狀態設為 playing 才呼叫 synthesize');

      await controller.stop();
      expect(controller.status, TtsPlaybackStatus.idle);

      synthesizeCompleter.complete(); // 讓過期的 play() 呼叫繼續往下走
      await playFuture;

      expect(controller.status, TtsPlaybackStatus.idle,
          reason: '世代編號應讓過期呼叫在 synthesize() 完成後安全放棄，'
              '不得把已經 stop() 的狀態又寫回 playing');
      expect(player.loadedFiles, isEmpty,
          reason: '過期呼叫不應該把（已經 stop 的）音訊寫入播放器');
    });
  });
}
```

（最後一行 `}` 取代原本檔案結尾唯一的 `}`——即把新 `group` 插入原本 `main()` 的收尾大括號之前。）

- [x] **Step 5：執行測試確認全數失敗（`TtsController.stop` 尚未定義）**

Run: `flutter test test/reader/tts_controller_test.dart`
Expected: 編譯錯誤（`The method 'stop' isn't defined for the type 'TtsController'`）

- [x] **Step 6：實作 `TtsController.stop()`**

編輯 `app/lib/reader/tts_controller.dart`，在 `pause()` 方法之後新增：

```dart
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
```

- [x] **Step 7：執行測試確認通過**

Run: `flutter test test/reader/tts_controller_test.dart`
Expected: PASS（全部案例，含既有案例零回歸）

- [x] **Step 8：修正 `TtsAudioHandler.stop()` 呼叫真正的 `stop()`（計劃範圍澄清第 6 點）**

編輯 `app/lib/reader/tts_audio_handler.dart`：

Before：
```dart
  @override
  Future<void> stop() async {
    _controller?.pause();
    await super.stop();
  }
```

After：
```dart
  @override
  Future<void> stop() async {
    await _controller?.stop();
    await super.stop();
  }
```

- [x] **Step 9：新增 `TtsAudioHandler.stop()` 回歸測試**

編輯 `app/test/reader/tts_audio_handler_test.dart`，在最後一個 `test(...)` 之後、檔案結尾 `}` 之前新增：

```dart

  test('handler.stop() 呼叫 controller.stop()（真正停止並釋放音訊焦點，而非 pause()）',
      () async {
    final handler = TtsAudioHandler();
    controller = buildRealController();
    handler.attachController(controller, bookTitle: '紅樓夢');
    await controller.play();
    player.callLog.clear();

    await handler.stop();

    expect(player.callLog, ['stop']);
    expect(controller.status, TtsPlaybackStatus.idle);
  });
}
```

- [x] **Step 10：執行測試確認通過**

Run: `flutter test test/reader/tts_audio_handler_test.dart`
Expected: PASS（全部案例）

- [x] **Step 11：`flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 12：Commit**

```bash
git add app/lib/reader/tts_controller.dart app/lib/reader/tts_audio_player.dart app/lib/reader/tts_audio_handler.dart app/test/support/fake_tts_audio_player.dart app/test/reader/tts_controller_test.dart app/test/reader/tts_audio_handler_test.dart
git commit -m "feat(epic-38): Issue 2 Task 1 — TtsController.stop() 真正停止並釋放音訊焦點" -m "新增 TtsAudioPlayer.stop() 抽象方法／JustAudioTtsPlayer 實作／FakeTtsAudioPlayer 假實作；TtsController.stop() 重設狀態機並呼叫 player.stop()（World 编号防重入，比照既有 handleExternalPositionChange 慣例）；修正 TtsAudioHandler.stop() 呼叫真正的 controller.stop() 而非既有的 pause() 權宜寫法（Issue 7 當時 stop() 尚不存在）。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 2：`TtsController` 語音選擇（`setVoice`／`voice`）

**Files:**
- Modify: `app/lib/reader/tts_controller.dart`
- Modify: `app/test/support/fake_tts_provider.dart`
- Modify: `app/test/reader/tts_controller_test.dart`

**Interfaces:**
- Consumes：`TtsVoice`（`app/lib/reader/tts_provider.dart`，既有）。
- Produces：`TtsController.voice`（getter，回傳 `TtsVoice`）；`TtsController.setVoice(TtsVoice)`（公開方法）。Task 6（`_openTtsVoicePicker`）依賴這兩個成員。

- [x] **Step 1：撰寫失敗測試**

編輯 `app/test/reader/tts_controller_test.dart`，在 Task 1 新增的 `group('TtsController.stop()...')` 之後、檔案結尾 `}` 之前新增：

```dart

  group('TtsController 語音選擇（epic-38-reader-chrome-tts-redesign Issue 2）', () {
    const alternateVoice = TtsVoice(id: 'alt', displayName: '替代語音');

    test('初始語音為 TtsVoice.systemDefault', () {
      final controller = buildController();
      expect(controller.voice, TtsVoice.systemDefault);
    });

    test('setVoice() 更新 voice 並觸發 notifyListeners', () {
      final controller = buildController();
      var notified = false;
      controller.addListener(() => notified = true);

      controller.setVoice(alternateVoice);

      expect(controller.voice, alternateVoice);
      expect(notified, isTrue);
    });

    test('setVoice() 後下一段合成套用新語音，不影響已合成的段落', () async {
      final controller = buildController();
      await controller.play();
      expect(provider.synthesizeCallCount, 1);
      expect(provider.synthesizeVoices, [TtsVoice.systemDefault],
          reason: '第一段尚未呼叫 setVoice()，應沿用初始值 TtsVoice.systemDefault');

      controller.setVoice(alternateVoice);
      player.simulateCompleted();
      await Future<void>.delayed(Duration.zero);

      expect(provider.synthesizeCallCount, 2);
      // 審查修正（review-plan-issue-2.md I3）：原本只斷言呼叫次數，即使
      // _playCurrentSegment() 仍寫死 TtsVoice.systemDefault、完全沒有讀
      // _voice 欄位，這裡也會一樣通過，測試形同虛設。改為直接核對第二次
      // synthesize() 實際收到的 voice 參數確實是剛剛 setVoice() 設定的值。
      expect(provider.synthesizeVoices.last, alternateVoice);
    });
  });
}
```

- [x] **Step 2：執行測試確認失敗**

Run: `flutter test test/reader/tts_controller_test.dart`
Expected: 編譯錯誤（`The getter 'voice' isn't defined`）

- [x] **Step 3：`FakeTtsProvider` 新增 `synthesizeVoices` 記錄（審查修正 review-plan-issue-2.md I3）**

`FakeTtsProvider.synthesize()` 簽章早已是 `{required TtsVoice voice, ...}`，但內部從未記錄收到的 `voice` 值——Step 1 新增的測試若不補上這個記錄，即使 `_playCurrentSegment()` 之後仍然寫死 `TtsVoice.systemDefault`、完全沒有讀 `_voice` 欄位，測試也會一樣通過，形同虛設。

編輯 `app/test/support/fake_tts_provider.dart`：

Before：
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
```

After：
```dart
  /// 記錄每次 [synthesize] 呼叫實際收到的 `speed` 參數（epic-34-tts-readalong
  /// Issue 5），供測試驗證「下一段」合成確實套用了呼叫當下的最新語速。
  final List<double> synthesizeSpeeds = [];

  /// 記錄每次 [synthesize] 呼叫實際收到的 `voice` 參數（epic-38-reader-
  /// chrome-tts-redesign Issue 2），供測試驗證 `TtsController.setVoice()`
  /// 後「下一段」合成確實套用了新語音，而不是依然寫死
  /// `TtsVoice.systemDefault`。
  final List<TtsVoice> synthesizeVoices = [];

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
    synthesizeVoices.add(voice);
```

- [x] **Step 4：實作 `voice`／`setVoice()`，並修改 `_playCurrentSegment()` 套用**

編輯 `app/lib/reader/tts_controller.dart`。

在 `_speed`／`speed` 欄位定義之後新增：

```dart
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
```

`_playCurrentSegment()` 內，找到：

```dart
        final result = await provider.synthesize(
          segment.text,
          voice: TtsVoice.systemDefault,
          speed: _speed,
        );
```

改為：

```dart
        final result = await provider.synthesize(
          segment.text,
          voice: _voice,
          speed: _speed,
        );
```

- [x] **Step 5：執行測試確認通過**

Run: `flutter test test/reader/tts_controller_test.dart`
Expected: PASS（全部案例）

- [x] **Step 6：`flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7：Commit**

```bash
git add app/lib/reader/tts_controller.dart app/test/support/fake_tts_provider.dart app/test/reader/tts_controller_test.dart
git commit -m "feat(epic-38): Issue 2 Task 2 — TtsController 新增語音選擇 setVoice()/voice" -m "spec.md 只描述 TtsPanel.onVoiceTap 挑選語音後套用，未列出 TtsController 需要的可寫入狀態——新增 voice getter/setVoice() 方法（比照既有 speed/setSpeed 模式），_playCurrentSegment() 呼叫 provider.synthesize 改讀此欄位，取代原本寫死的 TtsVoice.systemDefault。FakeTtsProvider 新增 synthesizeVoices 記錄，讓測試能真正核對套用的語音而非只看呼叫次數（審查修正 review-plan-issue-2.md I3）。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 3：新增 `TtsPanel` 元件（取代 `TtsMiniPlayer`）

**Files:**
- Create: `app/lib/screens/tts_panel.dart`
- Create: `app/test/screens/tts_panel_test.dart`

**Interfaces:**
- Consumes：`TtsPlaybackStatus`（`app/lib/reader/tts_controller.dart`，既有 enum）。
- Produces：`TtsPanel`（`StatelessWidget`），建構參數：`status`／`speed`／`isCbz`／`isCollapsed`／`sleepTimerRemaining`／`backgroundColor`／`iconColor`／`disabledIconColor`／`isEinkMode`（預設 `false`）／`onPlayPause`／`onPrevious`／`onNext`／`onSpeedTap`／`onVoiceTap`／`onSleepTimerTap`／`onToggleCollapse`／`onStop`。Key：`reader_tts_previous_button`／`reader_tts_play_pause_button`／`reader_tts_next_button`／`reader_tts_speed_button`／`reader_tts_voice_button`／`reader_tts_sleep_timer_button`／`reader_tts_panel_collapse_button`／`reader_tts_stop_button`。Task 4 消費本元件。

- [x] **Step 1：撰寫 `TtsPanel` 獨立 widget test（先寫測試，元件尚未存在）**

建立 `app/test/screens/tts_panel_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tts_controller.dart';
import 'package:elinkbook/screens/tts_panel.dart';

void main() {
  Widget buildPanel({
    TtsPlaybackStatus status = TtsPlaybackStatus.playing,
    double speed = 1.0,
    bool isCbz = false,
    bool isCollapsed = false,
    Duration? sleepTimerRemaining,
    bool isEinkMode = false,
    VoidCallback? onPlayPause,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
    VoidCallback? onSpeedTap,
    VoidCallback? onVoiceTap,
    VoidCallback? onSleepTimerTap,
    VoidCallback? onToggleCollapse,
    VoidCallback? onStop,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TtsPanel(
          status: status,
          speed: speed,
          isCbz: isCbz,
          isCollapsed: isCollapsed,
          sleepTimerRemaining: sleepTimerRemaining,
          backgroundColor: Colors.white,
          iconColor: Colors.black,
          disabledIconColor: Colors.grey,
          isEinkMode: isEinkMode,
          onPlayPause: onPlayPause ?? () {},
          onPrevious: onPrevious ?? () {},
          onNext: onNext ?? () {},
          onSpeedTap: onSpeedTap ?? () {},
          onVoiceTap: onVoiceTap ?? () {},
          onSleepTimerTap: onSleepTimerTap ?? () {},
          onToggleCollapse: onToggleCollapse ?? () {},
          onStop: onStop ?? () {},
        ),
      ),
    );
  }

  testWidgets('isCollapsed: false 且 isCbz: false 時，展開列五顆按鈕皆存在', (tester) async {
    await tester.pumpWidget(buildPanel());
    expect(find.byKey(const Key('reader_tts_previous_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_play_pause_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_next_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_speed_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_voice_button')), findsOneWidget);
  });

  testWidgets('底層動作列三顆按鈕恆常渲染', (tester) async {
    await tester.pumpWidget(buildPanel());
    expect(find.byKey(const Key('reader_tts_sleep_timer_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_panel_collapse_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_stop_button')), findsOneWidget);
  });

  testWidgets('isCollapsed: true 時，展開列四顆不存在，底層動作列仍存在', (tester) async {
    await tester.pumpWidget(buildPanel(isCollapsed: true));
    expect(find.byKey(const Key('reader_tts_previous_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_play_pause_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_next_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_speed_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_voice_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_sleep_timer_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_panel_collapse_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_stop_button')), findsOneWidget);
  });

  testWidgets('isCbz: true 時，只有停用狀態播放鍵，不渲染上一句/下一句/語速/語音', (tester) async {
    await tester.pumpWidget(buildPanel(isCbz: true));
    final playFinder = find.byKey(const Key('reader_tts_play_pause_button'));
    expect(playFinder, findsOneWidget);
    expect(tester.widget<IconButton>(playFinder).onPressed, isNull);
    expect(find.byKey(const Key('reader_tts_previous_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_next_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_speed_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_voice_button')), findsNothing);
  });

  testWidgets('isCbz: true 且 isCollapsed: true 時，展開列（含停用播放鍵）整排不渲染',
      (tester) async {
    await tester.pumpWidget(buildPanel(isCbz: true, isCollapsed: true));
    expect(find.byKey(const Key('reader_tts_play_pause_button')), findsNothing);
  });

  testWidgets('status: playing 時播放鍵顯示暫停圖示，點擊觸發 onPlayPause', (tester) async {
    var called = false;
    await tester.pumpWidget(
      buildPanel(status: TtsPlaybackStatus.playing, onPlayPause: () => called = true),
    );
    final finder = find.byKey(const Key('reader_tts_play_pause_button'));
    final icon = tester.widget<Icon>(
      find.descendant(of: finder, matching: find.byType(Icon)),
    );
    expect(icon.icon, Icons.pause);
    await tester.tap(finder);
    expect(called, isTrue);
  });

  testWidgets('status: paused 時播放鍵顯示播放圖示', (tester) async {
    await tester.pumpWidget(buildPanel(status: TtsPlaybackStatus.paused));
    final finder = find.byKey(const Key('reader_tts_play_pause_button'));
    final icon = tester.widget<Icon>(
      find.descendant(of: finder, matching: find.byType(Icon)),
    );
    expect(icon.icon, Icons.play_arrow);
  });

  testWidgets('點擊上一句/下一句/語速/語音按鈕分別觸發對應 callback', (tester) async {
    var previous = false, next = false, speedTap = false, voiceTap = false;
    await tester.pumpWidget(buildPanel(
      onPrevious: () => previous = true,
      onNext: () => next = true,
      onSpeedTap: () => speedTap = true,
      onVoiceTap: () => voiceTap = true,
    ));
    await tester.tap(find.byKey(const Key('reader_tts_previous_button')));
    await tester.tap(find.byKey(const Key('reader_tts_next_button')));
    await tester.tap(find.byKey(const Key('reader_tts_speed_button')));
    await tester.tap(find.byKey(const Key('reader_tts_voice_button')));
    expect(previous, isTrue);
    expect(next, isTrue);
    expect(speedTap, isTrue);
    expect(voiceTap, isTrue);
  });

  testWidgets('sleepTimerRemaining 為 null 時按鈕文字為「睡眠定時器」', (tester) async {
    await tester.pumpWidget(buildPanel(sleepTimerRemaining: null));
    expect(find.text('睡眠定時器'), findsOneWidget);
  });

  testWidgets('sleepTimerRemaining 非 null 時按鈕文字反映剩餘分鐘數', (tester) async {
    await tester.pumpWidget(
      buildPanel(sleepTimerRemaining: const Duration(minutes: 30)),
    );
    expect(find.text('睡眠 30 分'), findsOneWidget);
  });

  testWidgets('點擊睡眠定時器按鈕觸發 onSleepTimerTap', (tester) async {
    var called = false;
    await tester.pumpWidget(buildPanel(onSleepTimerTap: () => called = true));
    await tester.tap(find.byKey(const Key('reader_tts_sleep_timer_button')));
    expect(called, isTrue);
  });

  testWidgets('isCollapsed: false 時收合按鈕文字為「收合成細列」，點擊觸發 onToggleCollapse',
      (tester) async {
    var called = false;
    await tester.pumpWidget(
      buildPanel(isCollapsed: false, onToggleCollapse: () => called = true),
    );
    expect(find.text('收合成細列'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader_tts_panel_collapse_button')));
    expect(called, isTrue);
  });

  testWidgets('isCollapsed: true 時收合按鈕文字為「展開控制列」', (tester) async {
    await tester.pumpWidget(buildPanel(isCollapsed: true));
    expect(find.text('展開控制列'), findsOneWidget);
  });

  testWidgets('點擊停止按鈕觸發 onStop', (tester) async {
    var called = false;
    await tester.pumpWidget(buildPanel(onStop: () => called = true));
    await tester.tap(find.byKey(const Key('reader_tts_stop_button')));
    expect(called, isTrue);
  });

  testWidgets('isEinkMode: true 時，展開列按鈕觸控目標實際渲染高度為 56dp', (tester) async {
    await tester.pumpWidget(buildPanel(isEinkMode: true));
    final size = tester.getSize(
      find.byKey(const Key('reader_tts_play_pause_button')),
    );
    expect(size.height, greaterThanOrEqualTo(56));
  });

  testWidgets('isEinkMode: false（預設）時，展開列按鈕觸控目標高度為 52dp', (tester) async {
    await tester.pumpWidget(buildPanel(isEinkMode: false));
    final size = tester.getSize(
      find.byKey(const Key('reader_tts_play_pause_button')),
    );
    expect(size.height, greaterThanOrEqualTo(52));
    expect(size.height, lessThan(56));
  });

  // 審查修正（review-plan-issue-2.md I2）：底層動作列（isCollapsed 時
  // 唯一還留在畫面上的一列）漏測，實際上這 3 顆 TextButton 原本沒有設定
  // minimumSize，isEinkMode 下並不會真的達到 56dp——這兩則測試就是抓這個
  // 回歸用的。
  testWidgets('isEinkMode: true 時，底層動作列按鈕觸控目標實際渲染高度為 56dp', (tester) async {
    await tester.pumpWidget(buildPanel(isEinkMode: true, isCollapsed: true));
    final size = tester.getSize(
      find.byKey(const Key('reader_tts_stop_button')),
    );
    expect(size.height, greaterThanOrEqualTo(56));
  });

  testWidgets('isEinkMode: false（預設）時，底層動作列按鈕觸控目標高度為 52dp', (tester) async {
    await tester.pumpWidget(buildPanel(isEinkMode: false, isCollapsed: true));
    final size = tester.getSize(
      find.byKey(const Key('reader_tts_stop_button')),
    );
    expect(size.height, greaterThanOrEqualTo(52));
    expect(size.height, lessThan(56));
  });
}
```

（比照 `reader_chrome_bottom_bar_test.dart` 既有審查修正：底層動作列每顆按鈕外層若有 `Expanded`，只驗證高度，不驗證寬度——見 Step 2 實作時的版面決定。）

- [x] **Step 2：執行測試確認失敗（`tts_panel.dart` 尚不存在）**

Run: `flutter test test/screens/tts_panel_test.dart`
Expected: 編譯錯誤（找不到 `package:elinkbook/screens/tts_panel.dart`）

- [x] **Step 3：實作 `TtsPanel`**

建立 `app/lib/screens/tts_panel.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/tts_controller.dart';

/// TTS 朗讀常駐面板（epic-38-reader-chrome-tts-redesign Issue 2，spec.md
/// §功能③）：取代 [TtsMiniPlayer]（`tts_mini_player.dart`，本 Issue 一併
/// 刪除），與呼叫端（[ReaderScreen]）的 `ReaderChromeBottomBar` 依
/// `TtsController.status` 衍生完全互斥（不設手動旗標，見
/// `reader_screen.dart` `_buildBottomChrome` 文件註解）。純
/// [StatelessWidget]，不直接持有 [TtsController]，只吃基本型別與
/// callback（比照既有 [TtsMiniPlayer] 慣例，spec.md「單一事實來源」
/// 要求）。
///
/// 兩排固定結構：
/// - **展開控制列**（[isCollapsed] 為 `true` 時整排不渲染）：上一句／
///   播放暫停／下一句／語速／語音，[isCbz] 為 `true` 時只渲染一顆停用
///   狀態的播放鍵（CBZ 為純圖像格式，無文字可朗讀，沿用既有
///   [TtsMiniPlayer] 降級語意）。
/// - **底層動作列**（睡眠定時器／收合展開／停止，恆常渲染，不受
///   [isCollapsed] 或 [isCbz] 影響——即使是 CBZ 的純裝飾面板，使用者仍
///   可能想直接跳出朗讀模式）。
///
/// 觸控目標依 `DESIGN.md` §7.2：一般模式 52dp（spec.md 對本元件「大按鈕」
/// 的既定基準，比 `ReaderChromeTopBar`／`ReaderChromeBottomBar` 的 48dp
/// 略大）、`isEinkMode` 時 56dp。
class TtsPanel extends StatelessWidget {
  final TtsPlaybackStatus status;
  final double speed;
  final bool isCbz;
  final bool isCollapsed;
  final Duration? sleepTimerRemaining;
  final Color backgroundColor;
  final Color iconColor;
  final Color disabledIconColor;
  final bool isEinkMode;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSpeedTap;
  final VoidCallback onVoiceTap;
  final VoidCallback onSleepTimerTap;
  final VoidCallback onToggleCollapse;
  final VoidCallback onStop;

  const TtsPanel({
    super.key,
    required this.status,
    required this.speed,
    required this.isCbz,
    required this.isCollapsed,
    required this.sleepTimerRemaining,
    required this.backgroundColor,
    required this.iconColor,
    required this.disabledIconColor,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onSpeedTap,
    required this.onVoiceTap,
    required this.onSleepTimerTap,
    required this.onToggleCollapse,
    required this.onStop,
    this.isEinkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final playing = status == TtsPlaybackStatus.playing;
    final minSize = isEinkMode ? 56.0 : 52.0;
    // 前景色／停用前景色交給 IconButton.styleFrom 統一管理（沿用
    // review-issue-1.md C-2 修法：Icon 不自帶 color，避免覆蓋掉 Material
    // 的停用色，讓 CBZ 停用播放鍵的視覺回饋不會與正常按鈕無異）。
    final buttonStyle = IconButton.styleFrom(
      minimumSize: Size(minSize, minSize),
      foregroundColor: iconColor,
      disabledForegroundColor: disabledIconColor,
    );
    return Material(
      color: backgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isCollapsed)
            SizedBox(
              height: minSize,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: isCbz
                    ? [
                        IconButton(
                          key: const Key('reader_tts_play_pause_button'),
                          icon: const Icon(Icons.play_arrow),
                          tooltip: 'CBZ 為純圖像格式，不支援語音朗讀',
                          style: buttonStyle,
                          onPressed: null,
                        ),
                      ]
                    : [
                        IconButton(
                          key: const Key('reader_tts_previous_button'),
                          icon: const Icon(Icons.skip_previous),
                          tooltip: '上一句',
                          style: buttonStyle,
                          onPressed: onPrevious,
                        ),
                        IconButton(
                          key: const Key('reader_tts_play_pause_button'),
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          tooltip: playing ? '暫停朗讀' : '開始朗讀',
                          style: buttonStyle,
                          onPressed: onPlayPause,
                        ),
                        IconButton(
                          key: const Key('reader_tts_next_button'),
                          icon: const Icon(Icons.skip_next),
                          tooltip: '下一句',
                          style: buttonStyle,
                          onPressed: onNext,
                        ),
                        IconButton(
                          key: const Key('reader_tts_speed_button'),
                          icon: Text(
                            '${speed.toStringAsFixed(2)}x',
                            style: TextStyle(
                              color: iconColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          tooltip: '朗讀語速：${speed.toStringAsFixed(2)}x（點擊切換）',
                          style: buttonStyle,
                          onPressed: onSpeedTap,
                        ),
                        IconButton(
                          key: const Key('reader_tts_voice_button'),
                          icon: const Icon(Icons.record_voice_over),
                          tooltip: '選擇語音',
                          style: buttonStyle,
                          onPressed: onVoiceTap,
                        ),
                      ],
              ),
            ),
          SizedBox(
            height: minSize,
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    key: const Key('reader_tts_sleep_timer_button'),
                    onPressed: onSleepTimerTap,
                    // 審查修正（review-plan-issue-2.md I2）：Row 的
                    // crossAxisAlignment 預設 center，外層 SizedBox 的
                    // height: minSize 只約束 Row 本身、不會讓子項自動
                    // 撐滿——TextButton 預設高度 48dp，isEinkMode: true
                    // 時若不明講 minimumSize，實際渲染高度仍是 48dp，
                    // 收合成細列時畫面上只剩這 3 顆按鈕，觸控目標達不到
                    // E-Ink 56dp 規範（`DESIGN.md` §7.2）。
                    style: TextButton.styleFrom(
                      foregroundColor: iconColor,
                      minimumSize: Size.fromHeight(minSize),
                    ),
                    icon: const Icon(Icons.bedtime_outlined),
                    label: Text(
                      sleepTimerRemaining == null
                          ? '睡眠定時器'
                          : '睡眠 ${sleepTimerRemaining!.inMinutes} 分',
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    key: const Key('reader_tts_panel_collapse_button'),
                    onPressed: onToggleCollapse,
                    style: TextButton.styleFrom(
                      foregroundColor: iconColor,
                      minimumSize: Size.fromHeight(minSize),
                    ),
                    icon: Icon(
                      isCollapsed ? Icons.expand_less : Icons.expand_more,
                    ),
                    label: Text(isCollapsed ? '展開控制列' : '收合成細列'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    key: const Key('reader_tts_stop_button'),
                    onPressed: onStop,
                    style: TextButton.styleFrom(
                      foregroundColor: backgroundColor,
                      backgroundColor: iconColor,
                      minimumSize: Size.fromHeight(minSize),
                    ),
                    icon: const Icon(Icons.stop),
                    label: const Text('停止'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [x] **Step 4：執行測試確認通過**

Run: `flutter test test/screens/tts_panel_test.dart`
Expected: PASS（全部案例）

- [x] **Step 5：`flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/tts_panel.dart app/test/screens/tts_panel_test.dart
git commit -m "feat(epic-38): Issue 2 Task 3 — 新增 TtsPanel 元件取代 TtsMiniPlayer" -m "格式無關的 StatelessWidget，展開控制列（上一句/播放暫停/下一句/語速/新增語音選擇）+ 底層動作列（睡眠定時器/收合/停止）兩排固定結構；isCbz 降級為單一停用播放鍵，isCollapsed 只隱藏展開列。補上 spec.md 程式碼片段遺漏的 isEinkMode 觸控目標放大參數（比照 ReaderChromeTopBar/BottomBar 既有慣例）。尚未接上 reader_screen.dart（Task 4 處理）。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 4：`reader_screen.dart` 接上 `_buildBottomChrome`（衍生切換＋CBZ 特例）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`

**Interfaces:**
- Consumes：Task 3 的 `TtsPanel`；既有 `ReaderChromeBottomBar`（Issue 1）；既有 `_ttsControllerOrNull`／`_themedFabBackgroundColor`／`_themedFabIconColor`／`_themedTtsDisabledIconColor`／`_nextTtsSpeedPreset`／`_pageProgressText`／`_buildFoliateEpubFooter`。
- Produces：`_ReaderScreenState._buildBottomChrome(BookFormat format)`（私有方法，回傳 `Widget`）；`_ReaderScreenState._buildFoliateChromeBottomBar(BookFormat format, {required VoidCallback? onTtsTap})`（私有 helper，避免 `ReaderChromeBottomBar(...)` 建構參數在三個分支重複三次）；新增私有欄位 `_cbzTtsPanelVisible`／`_ttsPanelCollapsed`。`_buildBottomChrome` 呼叫的 `_openSleepTimerPicker`／`_cancelTtsSleepTimer`／`_ttsSleepTimerDuration`／`_openTtsVoicePicker` 四個符號本 Task 先放**最小存根**（審查修正 C1，見 Step 3a），讓本 Task 能獨立通過 `flutter analyze` 與測試、獨立提交——Task 5（睡眠定時器）取代前三個存根為真正實作，Task 6（語音選擇）取代最後一個。

- [x] **Step 1：新增私有欄位，刪除 `_ttsMiniPlayerVisible`**

編輯 `app/lib/screens/reader_screen.dart`。

Before（`reader_screen.dart:283-287`）：
```dart
  // TTS Mini Player 是否顯示（epic-34-tts-readalong 追加需求）：預設隱藏，
  // 由新增的「朗讀」FAB 按鈕（麥克風圖示）切換，Mini Player 本身也有 X
  // 關閉鍵可收合——純顯示/隱藏開關，不影響 TtsController 播放狀態本身
  // （關閉 Mini Player 不會暫停朗讀）。
  bool _ttsMiniPlayerVisible = false;
```

After：
```dart
  // CBZ 專屬的 TtsPanel 展開/收合手動旗標（epic-38-reader-chrome-tts-
  // redesign Issue 2）：CBZ 為純圖像格式，_ttsControllerOrNull 刻意不對
  // 它建構（避免白白配置用不到的播放器資源，見該 getter 文件註解），故
  // 沒有真正的 TtsController.status 可供衍生顯示狀態——只有 CBZ 需要這個
  // 手動旗標，一般格式改用 _buildBottomChrome() 依 controller.status
  // 衍生切換，不受本旗標影響。
  bool _cbzTtsPanelVisible = false;
  // TtsPanel「收合成細列」子狀態（epic-38-reader-chrome-tts-redesign
  // Issue 2）：只影響展開控制列是否顯示，不影響朗讀播放本身，格式無關
  // （CBZ 的裝飾面板與一般格式共用同一個旗標）。
  bool _ttsPanelCollapsed = false;
```

- [x] **Step 2：新增 `_buildFoliateChromeBottomBar` helper 與 `_buildBottomChrome`，取代既有的 Foliate BottomBar／TtsMiniPlayer 兩個 `Positioned` 區塊**

Before（`reader_screen.dart:2126-2222`，緊接在 `_buildChromeTopBar(format)` 呼叫之後、PDF FAB 區塊之前）：
```dart
            // epic-38-reader-chrome-tts-redesign Issue 1：三格式共用同一份
            // ReaderChromeBottomBar，取代原本 Foliate 5 顆／PDF 4 顆各自
            // 獨立的 Positioned（見下方 PDF FAB 區塊對應段落，Step 3b 一併
            // 刪除）。`!_ttsMiniPlayerVisible` 是本 Issue 過渡期的互斥條件
            // ——舊 TtsMiniPlayer 膠囊固定貼底 12/40dp，新底部列三列合計
            // 154dp 也貼底，兩者同時渲染會互相遮擋，Issue 2 接上 TtsPanel
            // 後這個條件會被 AnimatedBuilder 依 TtsController.status 的
            // 正式衍生切換取代（見 issues.md Issue 2）。
            if (isFoliateFormat(format) && _chromeVisible && !_ttsMiniPlayerVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ReaderChromeBottomBar(
                  bookTitle: widget.bookTitle,
                  pageProgressText: _pageProgressText(format),
                  footer: _epubPositionInfo == null
                      ? const SizedBox.shrink()
                      : _buildFoliateEpubFooter(_epubPositionInfo!),
                  isBookmarked: _bookmarkAtCurrentPosition != null,
                  onBookmarkTap: widget.bookmarksRepository == null ||
                          _epubPositionInfo == null
                      ? null
                      : _toggleBookmark,
                  onAnnotationsTap: widget.bookmarksRepository == null ||
                          _autoDetectedWritingMode == null ||
                          _epubPositionInfo == null
                      ? null
                      : () => _openNotesSheet(format, initialTabIndex: 1),
                  onLayoutTap: _isFixedLayout
                      ? _openFxlSettings
                      : (_autoDetectedWritingMode == null
                          ? null
                          : _openLayoutSettings),
                  onTtsTap: widget.ttsProvider == null
                      ? null
                      : () => setState(
                          () => _ttsMiniPlayerVisible = !_ttsMiniPlayerVisible),
                  backgroundColor: _themedFabBackgroundColor,
                  iconColor: _themedFabIconColor,
                  isEinkMode: widget.isEinkMode,
                ),
              ),
            if (isFoliateFormat(format) &&
                _chromeVisible &&
                widget.ttsProvider != null &&
                _ttsMiniPlayerVisible)
              Positioned(
                left: 16,
                right: 16,
                bottom: _ttsMiniPlayerBottomOffset,
                child: Center(
                  // CBZ 為純圖像格式，無文字可朗讀——刻意不存取
                  // _ttsControllerOrNull（具副作用的 lazy getter，首次
                  // 存取即會建構 TtsController／原生 AudioPlayer），避免
                  // 每次開啟 CBZ 書籍都白白配置一顆用不到的播放器資源
                  // （見 review-issues.md Important #1）。isCbz 分支不會
                  // 讀取 status/speed，此處固定傳入預設值即可。
                  child: format == BookFormat.cbz
                      ? TtsMiniPlayer(
                          status: TtsPlaybackStatus.idle,
                          speed: 1.0,
                          isCbz: true,
                          backgroundColor: _themedFabBackgroundColor,
                          iconColor: _themedTtsDisabledIconColor,
                          onPlayPause: () {},
                          onPrevious: () {},
                          onNext: () {},
                          onSpeedTap: () {},
                          onClose: () =>
                              setState(() => _ttsMiniPlayerVisible = false),
                        )
                      : AnimatedBuilder(
                          animation: _ttsControllerOrNull!,
                          builder: (context, _) {
                            final controller = _ttsControllerOrNull!;
                            return TtsMiniPlayer(
                              status: controller.status,
                              speed: controller.speed,
                              isCbz: false,
                              backgroundColor: _themedFabBackgroundColor,
                              iconColor: _themedFabIconColor,
                              onPlayPause:
                                  controller.status == TtsPlaybackStatus.playing
                                      ? controller.pause
                                      : () => controller.play(),
                              onPrevious: () => controller.previousSegment(),
                              onNext: () => controller.nextSegment(),
                              onSpeedTap: () => controller.setSpeed(
                                  _nextTtsSpeedPreset(controller.speed)),
                              onClose: () =>
                                  setState(() => _ttsMiniPlayerVisible = false),
                            );
                          },
                        ),
                ),
              ),
```

After：
```dart
            // epic-38-reader-chrome-tts-redesign Issue 2：ReaderChromeBottomBar
            // 與 TtsPanel 依 TtsController.status 衍生切換，取代 Issue 1
            // 過渡期的 !_ttsMiniPlayerVisible 手動旗標與 TtsMiniPlayer（見
            // _buildBottomChrome 文件註解）。
            if (isFoliateFormat(format) && _chromeVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomChrome(format),
              ),
```

- [x] **Step 3：在 `_buildChromeTopBar()` 之後新增 `_buildFoliateChromeBottomBar`／`_buildBottomChrome` 兩個方法**

編輯 `app/lib/screens/reader_screen.dart`，在 `_buildChromeTopBar(BookFormat format)` 方法結尾（`reader_screen.dart:2031` 那個 `}`）之後、`Widget _buildBody(...)` 之前插入：

```dart

  /// `ReaderChromeBottomBar` 建構參數在 [_buildBottomChrome] 三個分支
  /// （尚未建構 controller／controller 存在但 idle／CBZ 未展開面板）完全
  /// 相同，只有 [onTtsTap] 不同——抽成獨立方法避免三份重複（epic-38-
  /// reader-chrome-tts-redesign Issue 2）。
  ReaderChromeBottomBar _buildFoliateChromeBottomBar(
    BookFormat format, {
    required VoidCallback? onTtsTap,
  }) {
    return ReaderChromeBottomBar(
      bookTitle: widget.bookTitle,
      pageProgressText: _pageProgressText(format),
      footer: _epubPositionInfo == null
          ? const SizedBox.shrink()
          : _buildFoliateEpubFooter(_epubPositionInfo!),
      isBookmarked: _bookmarkAtCurrentPosition != null,
      onBookmarkTap: widget.bookmarksRepository == null ||
              _epubPositionInfo == null
          ? null
          : _toggleBookmark,
      onAnnotationsTap: widget.bookmarksRepository == null ||
              _autoDetectedWritingMode == null ||
              _epubPositionInfo == null
          ? null
          : () => _openNotesSheet(format, initialTabIndex: 1),
      onLayoutTap: _isFixedLayout
          ? _openFxlSettings
          : (_autoDetectedWritingMode == null ? null : _openLayoutSettings),
      onTtsTap: onTtsTap,
      backgroundColor: _themedFabBackgroundColor,
      iconColor: _themedFabIconColor,
      isEinkMode: widget.isEinkMode,
    );
  }

  /// 底部 Chrome 列的衍生切換（epic-38-reader-chrome-tts-redesign Issue 2，
  /// spec.md §功能③）：`_ttsController` 為 `null`（使用者從未按過「◗
  /// 朗讀」）時回傳 `ReaderChromeBottomBar`；非 `null` 時依
  /// `controller.status` 衍生二擇一渲染，不設手動旗標——章節自然播完時
  /// `AnimatedBuilder` 會自動偵測到 `status == idle` 並切回
  /// `ReaderChromeBottomBar`，不需要額外程式碼。
  ///
  /// **CBZ 結構性例外（計劃範圍澄清第 1 點）**：CBZ 為純圖像格式，無文字
  /// 可朗讀，[_ttsControllerOrNull] 刻意不對 CBZ 存取（避免白白建構用不到
  /// 的 `TtsController`／原生 `AudioPlayer`，見該 getter 文件註解），故
  /// CBZ 沒有真正的 `controller.status` 可供衍生。改用獨立的
  /// [_cbzTtsPanelVisible] 手動旗標控制這個純裝飾、恆為停用狀態的
  /// `TtsPanel` 是否展開——沿用 Issue 1 之前 `TtsMiniPlayer` 對 CBZ 的既有
  /// 處理方式，不受一般格式「衍生而非手動旗標」設計原則影響（CBZ 根本
  /// 沒有可衍生的真實狀態）。
  Widget _buildBottomChrome(BookFormat format) {
    if (format == BookFormat.cbz) {
      if (widget.ttsProvider == null || !_cbzTtsPanelVisible) {
        return _buildFoliateChromeBottomBar(
          format,
          onTtsTap: widget.ttsProvider == null
              ? null
              : () => setState(() => _cbzTtsPanelVisible = true),
        );
      }
      return TtsPanel(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: true,
        isCollapsed: _ttsPanelCollapsed,
        sleepTimerRemaining: null,
        backgroundColor: _themedFabBackgroundColor,
        iconColor: _themedTtsDisabledIconColor,
        disabledIconColor: _themedTtsDisabledIconColor,
        isEinkMode: widget.isEinkMode,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
        onVoiceTap: () {},
        onSleepTimerTap: _openSleepTimerPicker,
        onToggleCollapse: () =>
            setState(() => _ttsPanelCollapsed = !_ttsPanelCollapsed),
        // 審查修正（review-plan-issue-2.md I4）：CBZ 底層動作列雖然沒有
        // 真正的 TtsController、_onTtsStatusChanged 邊緣偵測也不會對 CBZ
        // 觸發，但同一顆睡眠定時器按鈕（onSleepTimerTap 上面那行）與一般
        // 格式共用同一組 _ttsSleepTimer／_ttsSleepTimerDuration 欄位——
        // 若使用者在 CBZ 面板設定了定時器又按「停止」關閉面板，遺漏取消
        // 會讓計時器在背景繼續倒數，到期後對已經關閉的面板毫無意義地
        // 執行 _ttsController?.pause()（CBZ 恆為 null，no-op，但
        // _ttsSleepTimerDuration 狀態本身的殘留仍是明確的邏輯不一致）。
        onStop: () {
          _cancelTtsSleepTimer();
          setState(() => _cbzTtsPanelVisible = false);
        },
      );
    }
    final controller = _ttsController; // 不用 _ttsControllerOrNull，避免觸發 lazy 建構
    if (controller == null) {
      return _buildFoliateChromeBottomBar(
        format,
        onTtsTap: widget.ttsProvider == null
            ? null
            : () => _ttsControllerOrNull!.play(),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.status == TtsPlaybackStatus.idle) {
          return _buildFoliateChromeBottomBar(
            format,
            onTtsTap: () => controller.play(),
          );
        }
        return TtsPanel(
          status: controller.status,
          speed: controller.speed,
          isCbz: false,
          isCollapsed: _ttsPanelCollapsed,
          sleepTimerRemaining: _ttsSleepTimerDuration,
          backgroundColor: _themedFabBackgroundColor,
          iconColor: _themedFabIconColor,
          disabledIconColor: _themedTtsDisabledIconColor,
          isEinkMode: widget.isEinkMode,
          onPlayPause: controller.status == TtsPlaybackStatus.playing
              ? controller.pause
              : () => controller.play(),
          onPrevious: () => controller.previousSegment(),
          onNext: () => controller.nextSegment(),
          onSpeedTap: () =>
              controller.setSpeed(_nextTtsSpeedPreset(controller.speed)),
          onVoiceTap: () => _openTtsVoicePicker(controller),
          onSleepTimerTap: _openSleepTimerPicker,
          onToggleCollapse: () =>
              setState(() => _ttsPanelCollapsed = !_ttsPanelCollapsed),
          onStop: () async {
            _cancelTtsSleepTimer();
            await controller.stop();
          },
        );
      },
    );
  }
```

- [x] **Step 3a：新增暫時存根，讓本 Task 能獨立編譯與提交（審查修正 C1）**

`_buildBottomChrome` 呼叫的 `_openSleepTimerPicker`／`_cancelTtsSleepTimer`／`_ttsSleepTimerDuration`／`_openTtsVoicePicker` 四個符號分別由 Task 5（前三個）／Task 6（最後一個）才會定義真正實作。若不先放存根，本 Task 完成後 `reader_screen.dart` 完全無法編譯，連帶讓 `reader_screen_test.dart`（引入 `reader_screen.dart`）的任何測試都無法執行，Task 5 Step 8 會在編譯階段直接失敗，而非測試斷言失敗——這會讓 Task 4/5/6 之間失去逐 Task 獨立驗證的能力。在 `_buildBottomChrome` 方法之後新增：

```dart

  // ── 暫時存根（epic-38-reader-chrome-tts-redesign Issue 2 審查修正
  // C1）──：讓本 Task 能獨立通過 flutter analyze／flutter test、獨立
  // 提交，不需要等到 Task 6 完成才能驗證。Task 5 會把前三個換成真正的
  // 睡眠定時器實作，Task 6 會把最後一個換成真正的語音選擇實作——見各自
  // Task 的 Before/After。
  Duration? _ttsSleepTimerDuration;
  Future<void> _openSleepTimerPicker() async {}
  void _cancelTtsSleepTimer() {}
  Future<void> _openTtsVoicePicker(TtsController controller) async {}
```

- [x] **Step 3b：`flutter analyze` 確認本 Task 已可獨立通過**

Run: `flutter analyze`
Expected: `No issues found!`（四個存根讓 `_buildBottomChrome` 完整可編譯，不應再有任何符號未定義的錯誤）

- [x] **Step 4：刪除 `_ttsMiniPlayerBottomOffset`（不再被任何呼叫端使用）**

Before（`reader_screen.dart:2597-2604`）：
```dart
  /// Mini Player 底部邊距（epic-34-tts-readalong Issue 6）：當頁尾進度文字
  /// 可見時（showFooter 開啟且總頁數 > 0），往上抬高 40dp 避開頁尾；頁尾未顯示
  /// 則貼齊底邊 12dp。
  double get _ttsMiniPlayerBottomOffset {
    final footerVisible = (_resolved?.showFooter ?? false) &&
        (_epubPositionInfo?.displayTotalPages ?? 0) > 0;
    return footerVisible ? 40 : 12;
  }

```

After：（整段刪除，不留任何內容）

- [x] **Step 5：更新 import**

編輯 `app/lib/screens/reader_screen.dart` 頂部 import：

Before：
```dart
import 'tts_mini_player.dart';
```

After：
```dart
import 'tts_panel.dart';
```

Run: `flutter analyze`
Expected: `No issues found!`（不應再出現 `TtsMiniPlayer`／`_ttsMiniPlayerVisible`／`_ttsMiniPlayerBottomOffset` 相關的殘留引用錯誤——若有，代表 Step 1-4 遺漏了某個呼叫點，須先排除再繼續）。

- [x] **Step 6：執行 `reader_screen_test.dart` 確認本 Task 未破壞既有非 TTS 測試**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: 大量既有 TTS 相關測試群組會失敗（`TtsMiniPlayer`／`reader_tts_mini_player_close_button` 等既有假設在新架構下不再成立，這是已知、留給 Task 8 集中處理的既知狀態，見計劃範圍澄清第 2 點）；**非** TTS 相關的測試（書籤／目錄／頁尾／版面設定等既有 group）應全數維持 PASS，不應因為本 Task 的改動而新增任何非 TTS 相關的回歸——若有，代表 `_buildFoliateChromeBottomBar`／`_buildBottomChrome` 的建構參數轉譯有遺漏或筆誤，須先排除再繼續。

- [x] **Step 7：Commit（審查修正 C1：本 Task 現在可獨立提交，不需要等 Task 5/6）**

```bash
git add app/lib/screens/reader_screen.dart
git commit -m "feat(epic-38): Issue 2 Task 4 — TtsPanel 衍生切換接線（CBZ 特例＋暫時存根）" -m "新增 _buildBottomChrome() 依 TtsController.status 衍生切換 ReaderChromeBottomBar/TtsPanel，取代 Issue 1 過渡期的 !_ttsMiniPlayerVisible 手動旗標；CBZ 因結構性沒有真正的 TtsController，改用獨立的 _cbzTtsPanelVisible 手動旗標維持既有降級顯示行為（計劃範圍澄清第 1 點），onStop 一併取消睡眠定時器避免背景殘留（審查修正 review-plan-issue-2.md I4）。睡眠定時器與語音選擇相關的四個符號先放最小存根，讓本 Task 能獨立通過 flutter analyze 並提交（審查修正 C1），Task 5/6 會分別替換為真正實作。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 5：睡眠定時器

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Produces：`_ReaderScreenState._setTtsSleepTimer(Duration?)`／`_cancelTtsSleepTimer()`／`_openSleepTimerPicker()`／`_onTtsStatusChanged()`／`_isTtsActive`（getter）；`_TtsSleepTimerSheet`（私有 `StatelessWidget`）；`ReaderScreen.openSleepTimerPickerForTest(GlobalKey<State<ReaderScreen>>)`（公開 static test helper，比照既有 `openPdfToc`）。Task 4 的 `_buildBottomChrome` 已依賴 `_ttsSleepTimerDuration`／`_openSleepTimerPicker`／`_cancelTtsSleepTimer`；Task 7 的 `_buildChromeTopBar` 依賴 `_isTtsActive`。

- [x] **Step 1：以真正實作取代 Task 4 的暫時存根**

編輯 `app/lib/screens/reader_screen.dart`，找到 Task 4 Step 3a 新增的三個存根：

Before：
```dart
  Duration? _ttsSleepTimerDuration;
  Future<void> _openSleepTimerPicker() async {}
  void _cancelTtsSleepTimer() {}
```

After（`_ttsSleepTimerDuration` 欄位保留、補上文件註解；`_openSleepTimerPicker`／`_cancelTtsSleepTimer` 換成真正實作，並在附近新增 `_ttsSleepTimer`／`_isTtsActive`／`_wasTtsActive`／`_onTtsStatusChanged`）：

```dart

  /// 睡眠定時器目前設定的時長（epic-38-reader-chrome-tts-redesign
  /// Issue 2）：`null` 代表「不限時」（未設定，或已到期/取消）。只顯示
  /// 「已設定的時長」（如「睡眠 30 分」），不做逐秒刷新的倒數畫面——
  /// E-Ink 裝置不利於高頻率畫面刷新，spec.md「Out of Scope」已排除。
  Duration? _ttsSleepTimerDuration;
  Timer? _ttsSleepTimer;

  void _setTtsSleepTimer(Duration? duration) {
    _ttsSleepTimer?.cancel();
    setState(() => _ttsSleepTimerDuration = duration);
    if (duration == null) return; // 「不限時」：取消計時器，不排新的。
    _ttsSleepTimer = Timer(duration, () {
      _ttsController?.pause();
      if (mounted) setState(() => _ttsSleepTimerDuration = null);
    });
  }

  void _cancelTtsSleepTimer() => _setTtsSleepTimer(null);

  /// 供 `TtsPanel.onSleepTimerTap` 呼叫，開啟 15/30/45/60 分＋「不限時」
  /// 固定清單（spec.md「睡眠定時器」User Story 15）。也透過
  /// [ReaderScreen.openSleepTimerPickerForTest] 供測試直接呼叫——見
  /// 計劃範圍澄清第 3 點。
  Future<void> _openSleepTimerPicker() {
    return _showThemedModalBottomSheet<void>(
      builder: (_) => _TtsSleepTimerSheet(
        options: const [
          Duration(minutes: 15),
          Duration(minutes: 30),
          Duration(minutes: 45),
          Duration(minutes: 60),
        ],
        selected: _ttsSleepTimerDuration,
        onSelected: (duration) {
          Navigator.of(context).pop();
          _setTtsSleepTimer(duration);
        },
      ),
    );
  }

  /// 是否正在朗讀（idle 以外的任何狀態），供 [ReaderChromeTopBar]
  /// 小喇叭圖示（Task 7）與下方 [_onTtsStatusChanged] 邊緣偵測共用。讀
  /// 私有欄位 `_ttsController`（非 `_ttsControllerOrNull`），不觸發 lazy
  /// 建構。
  bool get _isTtsActive =>
      _ttsController != null && _ttsController!.status != TtsPlaybackStatus.idle;

  bool _wasTtsActive = false;

  /// 睡眠定時器自動取消機制（審查修正 `review-spec.md` C1 已於 spec.md
  /// 落地）：不可在 `AnimatedBuilder.builder` 內呼叫 `setState`（`builder`
  /// 在 build 階段執行，直接呼叫 `_cancelTtsSleepTimer()` 內部的
  /// `setState()` 會立即拋出 `AssertionError`）。改為 `TtsController`
  /// 的獨立 listener，在 build 週期之外偵測「原本正在朗讀、現在變成
  /// idle」的邊緣，此時才安全呼叫 `_cancelTtsSleepTimer()`——涵蓋「章節
  /// 自然播完」與「使用者按下停止」兩種轉為 idle 的途徑，避免朗讀已經
  /// 停止/播完後，定時器仍在背景倒數的視覺落差。
  void _onTtsStatusChanged() {
    final isActive = _isTtsActive;
    if (_wasTtsActive && !isActive) {
      _cancelTtsSleepTimer();
    }
    _wasTtsActive = isActive;
  }
```

- [x] **Step 2：`_ttsControllerOrNull` getter 掛上 `_onTtsStatusChanged` listener**

Before（`reader_screen.dart:2571-2572`）：
```dart
    _ttsController = controller;
    widget.ttsAudioHandler?.attachController(controller, bookTitle: widget.bookTitle);
```

After：
```dart
    _ttsController = controller;
    controller.addListener(_onTtsStatusChanged);
    widget.ttsAudioHandler?.attachController(controller, bookTitle: widget.bookTitle);
```

- [x] **Step 3：`dispose()` 新增清理**

Before（`reader_screen.dart:546-554`）：
```dart
  void dispose() {
    _syncCheckpointTimer?.cancel();
    _openBookTimeoutTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _volumeKeyChannel.setMethodCallHandler(null);
    _pdfSearchStateNotifier.dispose();
    _ttsAudioFocusCoordinator?.dispose();
    widget.ttsAudioHandler?.detachController();
    _ttsController?.dispose();
```

After：
```dart
  void dispose() {
    _syncCheckpointTimer?.cancel();
    _openBookTimeoutTimer?.cancel();
    _ttsSleepTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _volumeKeyChannel.setMethodCallHandler(null);
    _pdfSearchStateNotifier.dispose();
    _ttsAudioFocusCoordinator?.dispose();
    widget.ttsAudioHandler?.detachController();
    _ttsController?.removeListener(_onTtsStatusChanged);
    _ttsController?.dispose();
```

- [x] **Step 4：新增 `_TtsSleepTimerSheet` 私有 widget**

在 `_ReaderScreenState` 類別結尾（檔案內最後一個 `}`，即整個 class 定義的收尾）之後新增：

```dart

/// 睡眠定時器選單（epic-38-reader-chrome-tts-redesign Issue 2）：固定
/// 15/30/45/60 分＋「不限時」清單，[selected] 對應項目打勾（比照既有
/// `library_sort_option_${sortBy.name}` 勾選樣式慣例）。
class _TtsSleepTimerSheet extends StatelessWidget {
  final List<Duration> options;
  final Duration? selected;
  final ValueChanged<Duration?> onSelected;

  const _TtsSleepTimerSheet({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            ListTile(
              key: Key('reader_tts_sleep_timer_option_${option.inMinutes}'),
              title: Text('${option.inMinutes} 分鐘'),
              trailing:
                  selected == option ? Icon(Icons.check, color: primaryColor) : null,
              onTap: () => onSelected(option),
            ),
          ListTile(
            key: const Key('reader_tts_sleep_timer_option_none'),
            title: const Text('不限時'),
            trailing: selected == null ? Icon(Icons.check, color: primaryColor) : null,
            onTap: () => onSelected(null),
          ),
        ],
      ),
    );
  }
}
```

（若檔案結尾已有其他頂層宣告，插入在最後一個既有頂層宣告之後即可，不需要固定在檔案最末端——只要在 `_ReaderScreenState` 類別定義**之外**即可。）

- [x] **Step 5：新增測試專用 static helper（計劃範圍澄清第 3 點）**

編輯 `app/lib/screens/reader_screen.dart` 的 `ReaderScreen` 類別（注意：不是 `_ReaderScreenState`），在既有 `static void openPdfToc(...)` 方法（`reader_screen.dart:242-247`）之後新增：

```dart

  /// 供測試直接呼叫 [_ReaderScreenState._openSleepTimerPicker]（epic-38-
  /// reader-chrome-tts-redesign Issue 2，計劃範圍澄清第 3 點）：真正的
  /// UI 觸發入口 `TtsPanel.onSleepTimerTap` 只有在 `TtsController.status`
  /// 離開 `idle` 後才會出現在畫面上，但 `flutter_test` 環境下
  /// `FoliateReaderView.loadTtsSegments()` 恆回傳空清單（見
  /// `_ttsControllerOrNull` 文件註解既有的「誠實測試邊界」），`play()`
  /// 永遠無法真正離開 `idle`，導致 `TtsPanel` 在 widget test 環境下結構性
  /// 不可能出現。比照既有 [togglePdfBookmark]／[openPdfToc]「對應真實
  /// 觸發入口在測試環境下不可達」的既有模式新增本 helper，讓睡眠定時器
  /// 的 `Timer`／Bottom Sheet 選項邏輯本身仍可被完整測試。[key] 對應的
  /// State 若尚未掛載，靜默忽略。
  static void openSleepTimerPickerForTest(GlobalKey<State<ReaderScreen>> key) {
    final state = key.currentState;
    if (state is _ReaderScreenState) {
      state._openSleepTimerPicker();
    }
  }
```

- [x] **Step 6：`flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`（審查修正 C1：`_openTtsVoicePicker` 在 Task 4 已放好存根，本身是合法可編譯的程式碼，不會報錯；Task 6 才會把它換成真正實作）。

- [x] **Step 7：撰寫睡眠定時器 widget test（`tester.pump(Duration)` 驅動真實 `Timer`，比照 Global Constraints 說明）**

編輯 `app/test/screens/reader_screen_test.dart`，在既有 `group('安全視窗跟隨翻頁（epic-34-tts-readalong Issue 8）', ...)` 之後（緊接在該 group 的收尾 `});` 之後）新增：

```dart

  group('睡眠定時器（epic-38-reader-chrome-tts-redesign Issue 2）', () {
    testWidgets('選擇「30 分鐘」後，再次開啟選單該選項顯示已勾選', (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_sleep_timer_select',
            prefsManager: prefsManager,
            ttsProvider: FakeTtsProvider(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 審查修正（review-plan-issue-2.md M2）：先點一次「◗ 朗讀」讓
      // _ttsControllerOrNull 真正建構出 TtsController（status 仍停在
      // idle，flutter_test 環境下無法真正播放，見計劃範圍澄清第 2 點），
      // 讓下面的 Timer 到期時 _ttsController?.pause() 呼叫在一個真實
      // controller 而非 null 上，更貼近實際執行期路徑。
      await tester.tap(find.byKey(const Key('reader_chrome_tts_button')));
      await tester.pump();

      ReaderScreen.openSleepTimerPickerForTest(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byKey(const Key('reader_tts_sleep_timer_option_30')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      ReaderScreen.openSleepTimerPickerForTest(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final optionFinder =
          find.byKey(const Key('reader_tts_sleep_timer_option_30'));
      expect(
        find.descendant(of: optionFinder, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
    });

    testWidgets('選擇「30 分鐘」後經過 30 分鐘，再次開啟選單「不限時」變為已勾選'
        '（計時器已自動到期歸零）', (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_sleep_timer_expire',
            prefsManager: prefsManager,
            ttsProvider: FakeTtsProvider(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 審查修正（review-plan-issue-2.md M2）：見上一則測試的說明。
      await tester.tap(find.byKey(const Key('reader_chrome_tts_button')));
      await tester.pump();

      ReaderScreen.openSleepTimerPickerForTest(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('reader_tts_sleep_timer_option_30')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pump(const Duration(minutes: 30));

      ReaderScreen.openSleepTimerPickerForTest(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final noneFinder =
          find.byKey(const Key('reader_tts_sleep_timer_option_none'));
      expect(
        find.descendant(of: noneFinder, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('選擇「不限時」後，計時器不會在任何延遲後觸發任何狀態變化', (tester) async {
      final key = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            key: key,
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_sleep_timer_none',
            prefsManager: prefsManager,
            ttsProvider: FakeTtsProvider(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // 審查修正（review-plan-issue-2.md M2）：見第一則測試的說明。
      await tester.tap(find.byKey(const Key('reader_chrome_tts_button')));
      await tester.pump();

      ReaderScreen.openSleepTimerPickerForTest(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('reader_tts_sleep_timer_option_none')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pump(const Duration(hours: 2));

      expect(tester.takeException(), isNull);
    });
  });
```

- [x] **Step 8：執行測試確認通過（審查修正 C1：Task 4 已放好 `_openTtsVoicePicker` 存根，本步驟現在可以真正編譯執行，不再是預期中的編譯失敗）**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "睡眠定時器"`
Expected: PASS（3 個案例）

- [x] **Step 9：`flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 10：Commit（審查修正 C1：本 Task 現在可獨立提交，不需要等 Task 6）**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-38): Issue 2 Task 5 — 睡眠定時器" -m "取代 Task 4 的暫時存根為真正實作：新增睡眠定時器（15/30/45/60 分+不限時，到期為暫停）與 _onTtsStatusChanged 邊緣偵測自動取消機制（不在 AnimatedBuilder.builder 內呼叫 setState，見 spec.md/review-spec.md C1）；新增 ReaderScreen.openSleepTimerPickerForTest 測試專用入口（TtsPanel 在 flutter_test 環境下結構性不可達，計劃範圍澄清第 3 點）。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 6：語音選擇 Bottom Sheet（`_openTtsVoicePicker`）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `TtsController.voice`／`setVoice()`；既有 `TtsProvider.getAvailableVoices()`。
- Produces：以真正實作取代 Task 4 Step 3a 的 `_openTtsVoicePicker` 存根（`_ReaderScreenState._openTtsVoicePicker(TtsController)`，Task 4 的 `_buildBottomChrome` 已呼叫）。

- [x] **Step 1：以真正實作取代 Task 4 的 `_openTtsVoicePicker` 存根**

編輯 `app/lib/screens/reader_screen.dart`，找到 Task 4 Step 3a 新增的存根：

Before：
```dart
  Future<void> _openTtsVoicePicker(TtsController controller) async {}
```

After：
```dart

  /// 語音選擇 Bottom Sheet（epic-38-reader-chrome-tts-redesign Issue 2，
  /// spec.md §功能③）：本 Epic 只提供單次朗讀 session 內的臨時切換，不
  /// 讀取也不寫入 `GlobalReaderPrefs.ttsVoiceId`（spec.md「Out of
  /// Scope」）。比照既有 `TtsDefaultsScreen` 的 `RadioGroup`／`RadioListTile`
  /// 既有呼叫模式（`tts_defaults_screen.dart`），只是資料來源改為即時
  /// 呼叫 [TtsProvider.getAvailableVoices]、選擇結果直接呼叫
  /// [TtsController.setVoice]。`getAvailableVoices()` 回傳空清單時
  /// （裝置未安裝或不支援語音選擇，比照 `TtsDefaultsScreen` 既有處理）
  /// 靜默不開啟選單，不留一個空白 Bottom Sheet。
  ///
  /// **`SingleChildScrollView` 防溢位（審查修正 review-plan-issue-2.md
  /// I1）**：`_showThemedModalBottomSheet` 帶 `isScrollControlled: true`，
  /// 但這只讓 Bottom Sheet 本身可以撐到接近全螢幕高度，不會讓內容自動
  /// 變成可捲動——`TtsDefaultsScreen` 的既有參考實作是整個畫面包在
  /// `ListView` 裡（見 `tts_defaults_screen.dart`），本 Bottom Sheet 若
  /// 直接用 `Column` 承載，裝置若安裝了 Google/Samsung 等第三方 TTS
  /// 引擎、`getAvailableVoices()` 回傳 10-30+ 個語音選項時，會在真機上
  /// 觸發 `RenderFlex overflowed` 溢位。
  Future<void> _openTtsVoicePicker(TtsController controller) async {
    final provider = widget.ttsProvider;
    if (provider == null) return;
    final voices = await provider.getAvailableVoices();
    if (!mounted || voices.isEmpty) return;
    return _showThemedModalBottomSheet<void>(
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: RadioGroup<String>(
            groupValue: controller.voice.id,
            onChanged: (voiceId) {
              if (voiceId == null) return;
              final selected = voices.firstWhere((v) => v.id == voiceId);
              controller.setVoice(selected);
              Navigator.of(context).pop();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 審查修正（review-plan-issue-2.md M3）：補上標題列，
                // 讓使用者知道目前是在選語音，不是一份沒有上下文的清單。
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '朗讀語音',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                for (final voice in voices)
                  RadioListTile<String>(
                    key: Key('reader_tts_voice_option_${voice.id}'),
                    title: Text(voice.displayName),
                    value: voice.id,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
```

- [x] **Step 2：撰寫測試——直接呼叫 `_ttsController`（透過 `_buildBottomChrome`）不可行，改用 `_openTtsVoicePicker` 本身邏輯的可觀察子集**

由於 `TtsPanel.onVoiceTap` 同樣只有在 `TtsPanel` 可見（`controller.status != idle`）時才存在（計劃範圍澄清第 2 點的同一環境限制），本 Task 不新增依賴 `TtsPanel` 顯示的整合測試。改為驗證 `_openTtsVoicePicker` 在 `ttsProvider` 為 `null` 時安全 no-op（已由 Task 4 的 `onTtsTap: null` 分支間接保證，不需要額外測試）；`FakeTtsProvider.getAvailableVoices()` 回傳單一系統語音、`voices.isEmpty` 分支的靜默略過行為，已由 `TtsProvider` 介面本身的既有契約與 `TtsDefaultsScreen` 既有測試涵蓋（`tts_defaults_screen_test.dart`，若存在，不在本計劃重複驗證）。本 Step 因此不新增 `reader_screen_test.dart` 案例，Task 2 的純 Dart 單元測試（`TtsController.setVoice()`）已完整涵蓋這條功能鏈唯一可獨立測試的部分。

- [x] **Step 3：`flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 4：執行 `reader_screen_test.dart` 確認本 Task 未破壞既有測試（既有大量 TTS 相關測試預期在此刻仍然失敗，屬 Task 8 處理範圍）**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "睡眠定時器"`
Expected: PASS（Task 5 新增的 3 個案例，確認 Task 6 沒有意外破壞它們）

（**不要**在本步驟執行完整 `flutter test test/screens/reader_screen_test.dart`——既有 TTS 相關測試群組會大量失敗，這是預期中、留給 Task 8 集中處理的既知狀態，比照 `plan-issue-1.md` Task 5 Step 1「先讓遷移意圖在版本歷史中可追蹤」的既有做法，不需要在這個中間點就去追每一個失敗。）

- [x] **Step 5：Commit（審查修正 C1：本 Task 獨立提交，不再與 Task 4/5 綁在一起）**

```bash
git add app/lib/screens/reader_screen.dart
git commit -m "feat(epic-38): Issue 2 Task 6 — 語音選擇 Bottom Sheet" -m "取代 Task 4 的暫時存根為真正實作：新增語音選擇 Bottom Sheet（_openTtsVoicePicker），比照既有 TtsDefaultsScreen RadioGroup 模式，SingleChildScrollView 包住選項清單防止語音數量較多時溢位（審查修正 review-plan-issue-2.md I1），補上標題列（M3）。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 7：`showTtsIndicator` 真實邏輯

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 5 的 `_isTtsActive`。

- [x] **Step 1：撰寫失敗測試**

編輯 `app/test/screens/reader_screen_test.dart`，在 Task 5 新增的 `group('睡眠定時器...')` 之後新增：

```dart

  group('小喇叭圖示 showTtsIndicator（epic-38-reader-chrome-tts-redesign Issue 2）', () {
    testWidgets('未提供 ttsProvider 時，小喇叭圖示恆不存在（_chromeVisible 任一值）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts_indicator_no_provider',
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_chrome_tts_indicator_icon')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_chrome_tts_indicator_icon')),
        findsNothing,
      );
    });

    testWidgets('提供 ttsProvider 但從未按下「◗ 朗讀」（_ttsController 為 null）時，'
        '小喇叭圖示不存在', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts_indicator_not_built',
            prefsManager: prefsManager,
            ttsProvider: FakeTtsProvider(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_chrome_tts_indicator_icon')),
        findsNothing,
        reason: '_isTtsActive 讀 _ttsController（非 _ttsControllerOrNull），'
            '尚未按過朗讀鍵時恆為 false，不應觸發 lazy 建構',
      );
    });
  });
```

- [x] **Step 2：執行測試確認通過（本 Task 尚未修改程式碼，`showTtsIndicator` 目前固定為 `false`，兩個測試案例皆應已經通過——這一步是確認既有寫死值不會誤判為「功能已完成」）**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "小喇叭圖示"`
Expected: PASS（因為 `showTtsIndicator` 目前恆為 `false`，這兩個「不存在」案例本來就會通過——本 Task 真正的行為驗證留給 Step 4 新增的「存在」案例）

- [x] **Step 3：實作真實邏輯**

編輯 `app/lib/screens/reader_screen.dart` 的 `_buildChromeTopBar` 方法（`reader_screen.dart:2025`）：

Before：
```dart
        showTtsIndicator: false, // Issue 2 接上真實邏輯
```

After：
```dart
        showTtsIndicator: _isTtsActive && !_chromeVisible,
```

- [x] **Step 4：新增「應該存在」的測試案例——透過點擊「◗ 朗讀」讓 `_ttsController` 非 null（即使 `status` 仍是 `idle`，`_isTtsActive` 仍為 `false`，故本案例改為驗證另一個組合：`_chromeVisible == true` 時即使 `_isTtsActive` 為 `true` 也不應顯示）**

由於 `flutter_test` 環境下 `_isTtsActive` 無法真正變為 `true`（計劃範圍澄清第 2 點——`_ttsController.status` 永遠是 `idle`），`showTtsIndicator: true` 這個組合本身在 `ReaderScreen` 整合層無法被觸發、也就無法測試。在 `group('小喇叭圖示...')` 內、Step 1 兩個案例之後補一個文件型測試，明確記錄這個已知限制，避免未來有人誤以為遺漏：

```dart

    testWidgets('_isTtsActive && !_chromeVisible 兩個條件皆成立時才顯示（誠實測試邊界：'
        'flutter_test 環境下 TtsController.status 永遠是 idle，_isTtsActive 永遠為'
        'false，這個組合本身無法在本檔案驗證，正確性由 _isTtsActive 定義本身'
        '〔純欄位比對，無額外邏輯〕與上方兩個「不顯示」案例的互補覆蓋保證）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts_indicator_documented_gap',
            prefsManager: prefsManager,
            ttsProvider: FakeTtsProvider(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      // _chromeVisible 仍為 true（未觸發沉浸模式）時，即使 _ttsController
      // 已建構，小喇叭不應顯示——這個組合本身可以在測試環境驗證。
      await tester.tap(find.byKey(const Key('reader_chrome_tts_button')));
      await tester.pump();

      expect(
        find.byKey(const Key('reader_chrome_tts_indicator_icon')),
        findsNothing,
        reason: '_chromeVisible 仍為 true，即使 _isTtsActive 為 true 也不應顯示'
            '（本案例中 _isTtsActive 實際仍為 false，但斷言與其為 true 時的'
            '預期行為一致，兩者皆是 findsNothing）',
      );
    });
```

- [x] **Step 5：執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "小喇叭圖示"`
Expected: PASS（3 個案例）

- [x] **Step 6：`flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-38): Issue 2 Task 7 — ReaderChromeTopBar 小喇叭圖示接上真實邏輯" -m "showTtsIndicator 改為 _isTtsActive && !_chromeVisible（Issue 1 暫時固定 false 的位置）。新增測試記錄一個已知的誠實測試邊界：flutter_test 環境下 TtsController.status 永遠是 idle，_isTtsActive 永遠為 false，'顯示'這個分支本身無法在 ReaderScreen 整合層驗證，正確性依賴 _isTtsActive 定義本身的純欄位比對與其餘案例的互補覆蓋。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 8：既有測試遷移／清理＋收尾

**Files:**
- Delete: `app/lib/screens/tts_mini_player.dart`
- Delete: `app/test/screens/tts_mini_player_test.dart`
- Modify: `app/test/screens/reader_screen_test.dart`
- Modify: `DESIGN.md`（審查修正 review-plan-issue-2.md M1：實際位於倉庫根目錄，不是 `docs/DESIGN.md`）
- Modify: `docs/epics/epic-38-reader-chrome-tts-redesign/issues.md`
- Modify: `docs/epics/epic-38-reader-chrome-tts-redesign/epic.md`
- Modify: `docs/epics.md`

- [x] **Step 1：刪除 `TtsMiniPlayer` 與其測試檔**

```bash
git rm app/lib/screens/tts_mini_player.dart app/test/screens/tts_mini_player_test.dart
```

Run: `flutter analyze`
Expected: `reader_screen_test.dart` 開始出現大量「找不到 `TtsMiniPlayer`」的編譯錯誤——這是 Step 2 起要逐一修正的既知範圍。

- [x] **Step 2：刪除已完全失效的過渡期回歸測試**

`reader_screen_test.dart` 檔案結尾（`tearDownAll` 之前）有一則 Issue 1 專屬的過渡期回歸測試，整段驗證的行為（`_ttsMiniPlayerVisible` 手動互斥）已被本 Issue 的衍生切換取代，找到並整段刪除：

```dart
  testWidgets(
    '開啟舊 TtsMiniPlayer 膠囊時，新的 ReaderChromeBottomBar 不會同時顯示'
    '（review-issues.md I1 過渡期互斥回歸測試）',
    (tester) async {
      // ...（整段刪除，含收尾的 },\n  );）
```

- [x] **Step 3：遷移 `group('TTS 語音朗讀（epic-34-tts-readalong Issue 2）', ...)`**

這個 group 內 4 則測試：第 1 則（「未提供 ttsProvider 時，不顯示 TTS 播放按鈕」）從未點擊「◗ 朗讀」，完全不受本 Issue 影響，不需要修改。其餘 2 則與 CBZ 相關。CBZ 分支本 Issue 改用獨立的 `_cbzTtsPanelVisible` 手動旗標（見計劃範圍澄清第 1 點），**不受**「`TtsController.status` 永遠是 `idle`」這個環境限制影響（CBZ 根本不建構 controller），點擊「◗ 朗讀」後 `TtsPanel`（取代 `TtsMiniPlayer`）確實會出現，`find.byKey`／`tester.widget<IconButton>(...).onPressed` 這類斷言不需要修改（Key／型別在 `TtsPanel` 與 `TtsMiniPlayer` 之間沿用既有字面值，見 Task 3）。

但其中「CBZ 停用播放鍵圖示顏色與啟用狀態明確區隔（epic-34-tts-readalong Issue 10）」這一則直接檢查 `Icon.color`：

```dart
      final icon = tester.widget<Icon>(
        find.descendant(of: buttonFinder, matching: find.byType(Icon)),
      );
      expect(icon.color, Colors.grey);
```

`TtsPanel`（Task 3）比照 Issue 1 審查修正 C-2，圖示不再自帶 `color`，改由 `IconButton.styleFrom(foregroundColor:, disabledForegroundColor:)` 決定——`icon.color` 現在恆為 `null`，這一則**需要修改**，比照 Issue 1 審查修復時「深色主題下流式 EPUB『版面設定』浮動按鈕」測試的既有改法（`reader_screen_test.dart` 既有案例，讀取 `IconButton.style?.foregroundColor?.resolve(<WidgetState>{WidgetState.disabled})` 而非 `Icon.color`）：

Before：
```dart
      final icon = tester.widget<Icon>(
        find.descendant(of: buttonFinder, matching: find.byType(Icon)),
      );

      // CBZ 恆為固定版面，啟用狀態的既有圖示色固定為 Colors.white
      // （_themedFabIconColor，reader_screen.dart:2693-2694）；停用狀態
      // 須與其明確不同，且不得只是同一顏色套上透明度（見本計畫 Global
      // Constraints 說明），故直接斷言為不透明的 Colors.grey（已隱含
      // 「不是 Colors.white」，不需另外斷言 isNot）。
      expect(icon.color, Colors.grey);
    });
```

After：
```dart
      // 審查修正（epic-38-reader-chrome-tts-redesign Issue 2）：TtsPanel
      // 的 Icon 不再自帶 color，改由 IconButton.style 的
      // disabledForegroundColor 決定，比對 Icon.color（現在恆為 null）
      // 已不適用。CBZ 恆為固定版面，啟用狀態的既有圖示色固定為
      // Colors.white（_themedFabIconColor）；停用狀態須與其明確不同，
      // 且不得只是同一顏色套上透明度（見本計畫 Global Constraints
      // 說明），故直接斷言為不透明的 Colors.grey（已隱含「不是
      // Colors.white」，不需另外斷言 isNot）。
      final button = tester.widget<IconButton>(buttonFinder);
      expect(
        button.style?.foregroundColor?.resolve(<WidgetState>{WidgetState.disabled}),
        Colors.grey,
      );
    });
```

另一則 CBZ 案例（「TTS 按鈕顯示但為停用狀態」只檢查 `onPressed`）確實不需要任何修改。`flutter analyze` 在本 Step 之前的編譯錯誤只會來自 import 或型別引用了 `TtsMiniPlayer`——這 2 則 CBZ 案例從未直接引用 `TtsMiniPlayer` 型別本身（只用 `find.byKey`／`tester.widget<IconButton>`），故不會因為型別找不到而編譯失敗，「Issue 10」那則需要修改的原因純粹是 Icon 顏色的取值方式改變，不是編譯錯誤。

第 2 則「提供 ttsProvider 時，流式 EPUB 顯示 TTS 播放按鈕，初始為播放圖示」是唯一的非 CBZ 案例，點擊「◗ 朗讀」後斷言 `reader_tts_play_pause_button` 存在且圖示為 `Icons.play_arrow`——這個斷言在本 Issue 之後**不再成立**：點擊後呼叫的是 `_ttsControllerOrNull!.play()`，`status` 停在 `idle`（環境限制），`_buildBottomChrome` 因此繼續回傳 `ReaderChromeBottomBar`，`TtsPanel` 不會出現。改為驗證「點擊不崩潰、畫面維持在 `ReaderChromeBottomBar`」：

Before：
```dart
      // Mini Player 預設隱藏，須先按下朗讀 FAB 按鈕才會顯示
      // （epic-34-tts-readalong 追加需求）。
      await tester.tap(
        find.byKey(const Key('reader_chrome_tts_button')),
      );
      await tester.pump();

      final buttonFinder = find.byKey(
        const Key('reader_tts_play_pause_button'),
      );
      expect(buttonFinder, findsOneWidget);
      final icon = tester.widget<Icon>(
        find.descendant(of: buttonFinder, matching: find.byType(Icon)),
      );
      expect(icon.icon, Icons.play_arrow);

      await tester.tap(buttonFinder);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
```

After：
```dart
      // epic-38-reader-chrome-tts-redesign Issue 2 審查澄清：點擊後呼叫
      // _ttsControllerOrNull!.play()，flutter_test 環境下
      // FoliateReaderView.loadTtsSegments() 恆回傳空清單，status 永遠
      // 停在 idle，TtsPanel 結構性不會出現（見 plan-issue-2.md 計劃範圍
      // 澄清第 2 點）——這裡驗證的是「點擊不崩潰、維持在
      // ReaderChromeBottomBar」這個環境限制下仍可觀察的結構性保證，深層
      // 狀態機正確性由 tts_controller_test.dart 完整涵蓋。
      final toggleFinder = find.byKey(const Key('reader_chrome_tts_button'));
      await tester.tap(toggleFinder);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderChromeBottomBar), findsOneWidget);
      expect(find.byType(TtsPanel), findsNothing);
    });
```

（同時把這則測試的標題從「初始為播放圖示」改為更準確地反映新斷言範圍，例如「提供 ttsProvider 時，流式 EPUB 顯示 TTS 播放按鈕，點擊後不崩潰且維持在 ReaderChromeBottomBar（誠實測試邊界，見計劃範圍澄清第 2 點）」。）

- [x] **Step 4：執行測試確認 Step 3 範圍轉綠**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "TTS 語音朗讀"`
Expected: PASS（4 個案例）

- [x] **Step 5：依同一套規則遷移其餘 5 個既有 TTS 相關 group**

以下每個 group 內，凡是「點擊 `reader_chrome_tts_button` → 斷言 `reader_tts_play_pause_button`／`reader_tts_previous_button`／`reader_tts_next_button`／`reader_tts_speed_button` 存在或可繼續互動」的**非 CBZ**案例，一律套用 Step 3 呈現的同一種改法（斷言收斂為「點擊不崩潰＋維持在 `ReaderChromeBottomBar`＋`TtsPanel` 不存在」），CBZ 案例維持原樣（不受環境限制影響）：

| Group | 既有測試數 | 處理方式 |
|---|---|---|
| `同步高亮跟隨（epic-34-tts-readalong Issue 3）` | 見檔案內容 | 逐一核對每則是否點擊過 `reader_chrome_tts_button` 後續操作播放列——若有，套用 Step 3 改法 |
| `手動導覽自動暫停與恢復播放（epic-34-tts-readalong Issue 4）` | 同上 | 同上 |
| `上一句/下一句/語速調整控制（epic-34-tts-readalong Issue 5）` | 同上（含 CBZ 案例） | 非 CBZ 案例套用 Step 3 改法；CBZ 案例維持原樣 |
| `Mini Player 與既有底部元件顯示連動（epic-34-tts-readalong Issue 6）` | 4 則 | 全數為非 CBZ 案例，套用 Step 3 改法；其中「按 Mini Player 關閉鍵收合」與「點擊 Mini Player 的關閉鍵可收合」兩則整段驗證的行為（`reader_tts_mini_player_close_button`）在新設計下不存在對應概念（`TtsPanel` 沒有「關閉鍵」，只有恆常渲染的「停止」／「收合成細列」），這兩則**整段刪除**，不強行改寫成語意不通的斷言 |
| `背景播放與系統整合（epic-34-tts-readalong Issue 7）` | 同上 | 同上 |
| `安全視窗跟隨翻頁（epic-34-tts-readalong Issue 8）` | 同上 | 同上 |

逐一處理時，每完成一個 group 就跑一次 `flutter test test/screens/reader_screen_test.dart --plain-name "<group 關鍵字>"` 確認轉綠再處理下一個，不要一次改完全部才第一次執行測試（比照 `plan-issue-1.md` Task 5 Step 4 既有的漸進驗證慣例）。

- [x] **Step 6：執行 `reader_screen_test.dart` 全數確認 PASS**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（全部案例，0 skip、0 fail——比照 Issue 1 收尾標準，不遺留任何 `skip: true`）

- [x] **Step 7：`flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 8：執行整份 Epic Issue 2 收尾要求的完整測試套件**

Run: `flutter test`
Expected: PASS（全部案例，比照 `CLAUDE.md`「測試執行範圍」規範，本 Task 是本計劃最後一個 Task，跑一次完整套件確認無全域回歸）

- [x] **Step 9：`DESIGN.md` 文件同步**

編輯倉庫根目錄的 `DESIGN.md`（審查修正 M1：不是 `docs/DESIGN.md`）§12／§13 段落，依 `spec.md`「已解決的規格矛盾（新增）」與「Further Notes」訂正：
- §12 開頭「閱讀器畫面重構為統一的 `ReaderScaffold`」改為「新增 `ReaderChromeTopBar`／`ReaderChromeBottomBar` 取代兩套按鈕塔」（Issue 1 遺留事項，一併於本 Issue 收尾處理）。
- §12.1「⬓ 按鈕同時讀寫 §17.1 顯示頁首／頁尾設定」文字刪除或訂正為「⬓ 只切換 `_chromeVisible`，不讀寫 `showHeader`/`showFooter`」。
- §13 對應段落更新為 `TtsPanel` 兩排結構＋睡眠定時器＋語音選擇，取代原本描述 `TtsMiniPlayer` 的文字。

- [x] **Step 10：更新 `issues.md`／`epic.md`／`docs/epics.md`**

- `docs/epics/epic-38-reader-chrome-tts-redesign/issues.md`：Issue 2 的 `**Status:**` 從 `ready-for-agent` 改為 `completed`。
- `docs/epics/epic-38-reader-chrome-tts-redesign/epic.md`：比照 Issue 1 收尾時的既有記錄格式（本檔案內已有 2026-09-08 的 Issue 1 完成記錄可參照），追加一則 Issue 2 完成記錄，摘要本 Task 8 Step 1-9 的重點與計劃範圍澄清 1-6 點的處理結果。
- `docs/epics.md`：找到本 Epic 對應列（`epic-38-reader-chrome-tts-redesign`），備註欄改為「Issue 1-2 已完成；Epic 38 全數完成，待歸檔」。

- [x] **Step 11：Commit**

```bash
git add -A
git commit -m "test(epic-38): Issue 2 Task 8 — 遷移既有 TTS 測試、刪除 TtsMiniPlayer、文件收尾" -m "刪除 tts_mini_player.dart/tts_mini_player_test.dart 與 Issue 1 過渡期互斥回歸測試；既有 Issue 2-8 TTS 相關測試群組中依賴「點擊朗讀鍵→Mini Player 立即出現」的非 CBZ 案例，改為驗證「點擊不崩潰、維持在 ReaderChromeBottomBar」（flutter_test 環境下 TtsController.status 永遠是 idle 的既知限制，見 plan-issue-2.md 計劃範圍澄清第 2 點）；依賴已刪除 reader_tts_mini_player_close_button 概念的測試整段刪除。DESIGN.md §12/§13、issues.md、epic.md、docs/epics.md 同步更新為 Issue 2 完成狀態。全套 flutter test 與 flutter analyze 皆通過。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## 收尾提醒

- Task 8 完成即代表 Issue 2、也是整個 Epic 38 完成。完成後依 `sdd-workflow` skill 的生命週期第 7 步「歸檔」，向人類確認是否要把整個 Epic 目錄搬移至 `docs/archive/<YYYY-MM-DD>-<簡稱>/`——本計劃不代為執行歸檔（人類指定動作）。
- 動手實作前務必先發起審查（`requesting-code-review`），特別是「計劃範圍澄清」1-6 點——這些是本計劃在 spec.md 既有內容之外新增的設計決定，審查者應重點檢查它們是否合理，而非只核對是否機械照抄 spec.md。
