# Epic 34 Issue 10 — CBZ 朗讀停用按鈕視覺區隔 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CBZ 書籍的朗讀停用播放鍵，圖示顏色須與啟用狀態明確區隔，讓使用者不需要長按看 tooltip 就能一眼看出「這顆按鈕按了沒用」。

**Architecture:** 新增一個固定回傳不透明顏色的 `_themedTtsDisabledIconColor` getter（`ReaderScreen` 私有），套用到 CBZ 分支唯一的 `TtsMiniPlayer` 建構點的 `iconColor` 參數。不新增任何狀態、不動 `TtsController`／`SystemTtsProvider`，純粹是一個顏色參數的替換。

**Tech Stack:** Flutter/Dart、`flutter_test` widget test。

**Spec：** `docs/epics/epic-34-tts-readalong/issues.md` Issue 10（第 288-312 行）。

**⚠️ 與 `issues.md` 描述有出入之處（動工前必讀）：** `issues.md` 寫的檔案位置是「`app/lib/screens/reader_screen.dart:2223-2262`」，這是 Issue 9 真機驗收當下（Issue 6 尚未合併）的舊行號。**Issue 6（Mini Player）合併後，播放/暫停按鈕已搬進獨立元件 `app/lib/screens/tts_mini_player.dart`（`TtsMiniPlayer` widget）**，`reader_screen.dart` 現在只負責「呼叫 `TtsMiniPlayer(...)` 時傳入哪個顏色」。本計畫依實際現況（已於撰寫計畫前重新讀過原始碼確認）撰寫，不依 `issues.md` 的舊行號。

## Global Constraints

- 純視覺調整，不得修改 `TtsController`／`SystemTtsProvider` 既有邏輯（`issues.md` Issue 10 設計要點第 4 點）。
- 僅限 CBZ 停用按鈕本身，不得影響其他既有 FAB／按鈕的顏色邏輯（`issues.md` Issue 10 設計要點第 3 點）。
- **不得使用 alpha 透明度**（例如 `Color.withValues(alpha: ...)`）做為區隔手段——`reader_screen.dart:2678-2690` 既有 doc comment 記錄了 epic-22-reader-theme-integration Issue 4 的真機教訓：alpha 混合運算出的「即時中間灰」在電子紙硬體上會落在灰階抖動渲染最弱的區間，圖示完全無法辨識形狀，該次已改為不透明實色修復。本 Issue 若沿用 alpha 透明度，會重蹈相同問題（本計畫因此在下方 Task 1 選擇不透明實色 `Colors.grey`，是刻意偏離 `issues.md` 設計要點第 1 點字面建議「降低透明度」的部分，理由如上）。
- `flutter analyze`／`flutter test` 全數通過，`reader_screen_test.dart` 既有測試零回歸。

---

### Task 1: 新增 CBZ 停用圖示色 getter 並套用到 CBZ 播放鍵

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:2693-2694`（在既有 `_themedFabIconColor` getter 後新增 `_themedTtsDisabledIconColor` getter）
- Modify: `app/lib/screens/reader_screen.dart:2261`（CBZ 分支的 `TtsMiniPlayer(...)` 呼叫點，`iconColor` 參數改用新 getter）
- Test: `app/test/screens/reader_screen_test.dart`（「TTS 語音朗讀（epic-34-tts-readalong Issue 2）」group 內，緊接在既有「CBZ 格式提供 ttsProvider 時，TTS 按鈕顯示但為停用狀態」測試之後新增一個測試）

**Interfaces:**
- Consumes：既有 `TtsMiniPlayer` widget 的 `iconColor` 參數（`Color` 型別，`app/lib/screens/tts_mini_player.dart:22`，已是建構參數，不需修改該檔案）；既有 `_isFixedLayout`（`bool`，`reader_screen.dart:270`）僅供 doc comment 說明對照，不在本 getter 邏輯中使用。
- Produces：`Color get _themedTtsDisabledIconColor`（`reader_screen.dart`，`ReaderScreen` state class 私有 getter），固定回傳 `Colors.grey`，供 CBZ 分支的 `TtsMiniPlayer` 呼叫點使用。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/screens/reader_screen_test.dart` 第 7461 行（既有「CBZ 格式提供 ttsProvider 時，TTS 按鈕顯示但為停用狀態」測試的結尾 `});`）之後，新增以下測試：

```dart
    testWidgets(
        'CBZ 停用播放鍵圖示顏色與啟用狀態明確區隔（epic-34-tts-readalong Issue 10）',
        (tester) async {
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.cbz',
            bookId: 'b_tts_cbz_disabled_color',
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
        const EpubLayoutInfo(
          isFixedLayout: true,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      final buttonFinder =
          find.byKey(const Key('reader_tts_play_pause_button'));
      final icon = tester.widget<Icon>(find.descendant(
        of: buttonFinder,
        matching: find.byType(Icon),
      ));

      // CBZ 恆為固定版面，啟用狀態的既有圖示色固定為 Colors.white
      // （_themedFabIconColor，reader_screen.dart:2693-2694）；停用狀態
      // 須與其明確不同，且不得只是同一顏色套上透明度（見本計畫 Global
      // Constraints 說明），故直接斷言為不透明的 Colors.grey。
      expect(icon.color, isNot(Colors.white));
      expect(icon.color, Colors.grey);
    });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "CBZ 停用播放鍵圖示顏色與啟用狀態明確區隔"`（於 `app/` 目錄下執行）

Expected: FAIL —— `icon.color` 目前仍是 `Colors.white`（沿用既有 `_themedFabIconColor`），`expect(icon.color, isNot(Colors.white))` 這一行斷言失敗。

- [ ] **Step 3: 寫最小實作**

在 `app/lib/screens/reader_screen.dart` 第 2694 行（`_themedFabIconColor` getter 結尾）之後，新增：

```dart

  /// CBZ 朗讀停用播放鍵專用的圖示色（epic-34-tts-readalong Issue 10）——
  /// 與 [_themedFabIconColor] 明確區隔，讓「按了沒用」不需要依賴
  /// tooltip 就能一眼辨識（Issue 9 真機驗收發現：兩者顏色目前完全
  /// 相同，且 tooltip 在觸控裝置上要長按才會出現，等同視覺上仍是靜默
  /// 無反應）。CBZ 恆為固定版面（`Book.isFixedLayout == true`，見
  /// CLAUDE.md「技術棧」段），本 getter 因此不需要比照
  /// [_themedFabIconColor] 依 `_isFixedLayout` 分支——固定寫死單一值
  /// 即可，避免引入永遠不會被走到的分支。**刻意不使用 alpha 透明度**
  /// （例如 `Colors.white.withValues(alpha: 0.4)`）：
  /// epic-22-reader-theme-integration Issue 4 已在真機電子紙硬體實測
  /// 發現，alpha 混合運算出的「即時中間灰」會落在電子紙灰階抖動渲染
  /// 最弱的區間，圖示無法辨識形狀（詳見 [_themedFabIconColor] 上方
  /// doc comment）；改用不透明實色 [Colors.grey]，避免重蹈相同問題。
  Color get _themedTtsDisabledIconColor => Colors.grey;
```

再修改同檔案第 2261 行，把 CBZ 分支 `TtsMiniPlayer(...)` 呼叫點的 `iconColor` 參數由 `_themedFabIconColor` 改為 `_themedTtsDisabledIconColor`：

```dart
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
                        )
```

（只改這一行的 `iconColor:` 參數值；`backgroundColor`、`onPlayPause` 等其餘參數與非 CBZ 分支的 `TtsMiniPlayer(...)` 呼叫點——`reader_screen.dart:2267-2287`——維持不動。）

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "CBZ 停用播放鍵圖示顏色與啟用狀態明確區隔"`（於 `app/` 目錄下執行）

Expected: PASS

- [ ] **Step 5: 執行本檔案完整測試，確認零回歸**

Run: `flutter test test/screens/reader_screen_test.dart`（於 `app/` 目錄下執行）

Expected: 全數 PASS，特別留意既有「CBZ 格式提供 ttsProvider 時，TTS 按鈕顯示但為停用狀態」（斷言 `button.onPressed` 為 `null`）與「提供 ttsProvider 時，流式 EPUB 顯示 TTS 播放按鈕，初始為播放圖示」（斷言 `icon.icon == Icons.play_arrow`，非 CBZ 情境，走 `_themedFabIconColor` 分支不受影響）兩個既有測試依然通過。

- [ ] **Step 6: 執行 `flutter analyze` 與全專案 `flutter test`**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
flutter test
```

Expected: `flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過（本計畫為 Issue 10 唯一一個 Task，依 `CLAUDE.md`「測試執行範圍」慣例，計畫最後一個 Task 完成時須跑一次完整 `flutter test`）。

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-34): Issue 10 CBZ 朗讀停用按鈕圖示顏色與啟用狀態明確區隔"
```

---

## Self-Review（撰寫計畫後自我檢查）

**1. Spec 覆蓋度**（對照 `issues.md` Issue 10 四條驗收標準）：
- 「CBZ 書籍的朗讀停用按鈕，圖示顏色/透明度與啟用狀態有明確視覺區隔」→ Task 1 Step 3。
- 「新增 widget test 驗證停用狀態顏色與啟用狀態不同」→ Task 1 Step 1。
- 「既有 `reader_screen_test.dart` 零回歸」→ Task 1 Step 5。
- 「`flutter analyze`／`flutter test` 全數通過」→ Task 1 Step 6。
四條皆有對應步驟，無缺口。

**2. Placeholder 掃描：** 全文無「TBD」/「稍後補上」/「加上適當的錯誤處理」等字樣，所有程式碼區塊皆為可直接套用的完整內容。

**3. 型別/命名一致性：** `_themedTtsDisabledIconColor` 在 Interfaces 區塊、Step 3 定義、Step 3 套用點、Self-Review 全文一致；未與既有 `_themedFabIconColor`／`_themedFabBackgroundColor` 命名混淆。

本 Issue 範圍單純（單一檔案的一個顏色參數替換 + 一個新測試），只需一個 Task，不需拆分。
