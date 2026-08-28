# Issue 6：Mini Player 完整 UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Issue 2（播放/暫停）與 Issue 5（上一句/下一句/語速）目前各自獨立的陽春浮動圓形按鈕，整合成一顆正式的水平 Mini Player 橫條，鎖定在 Reader 畫面底部，並確保與既有頁尾進度文字、TOC 等既有底部元件不互相遮擋。本 Issue 只做 UI 整合，不新增任何播放邏輯——所有播放/暫停/上一句/下一句/語速的實際行為皆已由 `TtsController`（Issue 2／Issue 5）完成。

**Architecture:** 新增一個獨立的 `TtsMiniPlayer`（`app/lib/screens/tts_mini_player.dart`）——比照本專案既有 `AnnotationToolbar`（`app/lib/screens/annotation_toolbar.dart`）的既定慣例：純 `StatelessWidget`，不直接持有 `TtsController`，只吃基本型別（`status`／`speed`／`isCbz`）與 callback 參數，完全不知道 `ReaderScreen`／`FoliateReaderView` 存在。`ReaderScreen` 內既有的 `AnimatedBuilder(animation: _ttsControllerOrNull!, ...)` 訂閱模式維持不變，只是 builder 內部改成建構 `TtsMiniPlayer(...)` 而非四顆各自獨立的 `ClipOval` 圓形按鈕——這正是 `spec.md`「單一事實來源」要求（審查 `review-issues.md` Minor #1）的直接體現：`TtsMiniPlayer` 本身不維護任何私有狀態，畫面上顯示的一切都直接來自呼叫當下傳入的 `status`／`speed`，`TtsController.notifyListeners()` 觸發 `AnimatedBuilder` 重建時自動全部同步更新，不需要額外同步邏輯。四顆按鈕沿用完全相同的 `Key`（`reader_tts_play_pause_button`／`reader_tts_previous_button`／`reader_tts_next_button`／`reader_tts_speed_button`）與內部 `Icon`/`Text`/`tooltip`/`onPressed` 語意，只是排列方式從「四個各自獨立、垂直堆疊的浮動圓形」改成「同一個 `Material` 圓角橫條內的一列 `IconButton`」——這個決定讓 Issue 2／Issue 3／Issue 4／Issue 5 既有的 `reader_screen_test.dart` TTS 測試全數不需修改即可通過（`find.byKey`／`tester.widget<Icon>`／`tester.widget<IconButton>` 皆與版面結構無關）。

與既有「底部導覽列」（`_buildFoliateProgressText()` 頁尾進度文字，`Positioned(bottom: 0)`）的顯示連動：Mini Player 改用一個依「頁尾是否會顯示」計算的動態 `bottom` 偏移量，避免視覺重疊；與「目錄側邊欄」（`_openToc()` 開啟的 `showModalBottomSheet`）的連動則完全不需要額外程式碼——`showModalBottomSheet` 是 Flutter `Navigator` 推上去的獨立 Route，會以 `Overlay` 疊在目前畫面最上層並附帶點擊遮罩，Mini Player 身為底層畫面的一部分自然會被完全遮住，這是 Flutter 框架本身的既有保證，不是本專案自行實作的邏輯，因此不需要另外寫程式碼或測試去驗證。

CBZ（無文字可朗讀）維持 Issue 2 既有的「顯示但停用」設計——`TtsMiniPlayer` 新增 `isCbz` 旗標，為 `true` 時只在同一個 Material 橫條內顯示單顆停用的播放圖示（`onPressed: null`），不建構上一句/下一句/語速三顆按鈕（沿用 Issue 5 既有的 CBZ 排除範圍）；圖示顏色沿用目前既有的 `_themedFabIconColor`（Issue 10「CBZ 停用按鈕視覺區隔」是另一張獨立、目前尚未合併的工單，本 Issue 不預先假設它已完成，維持與目前 `main` 分支相同的視覺，之後 Issue 10 落地時只需要在 `TtsMiniPlayer` 的 CBZ 分支換一個顏色參數，不涉及本 Issue 建立的結構）。

**Tech Stack:** 純 Flutter widget 重構，沿用既有 `TtsController`（Issue 2／Issue 5，`ChangeNotifier`）、`Material`／`IconButton`／`AnimatedBuilder`，無新增套件依賴、無新增後端/JS 橋接。

**Spec:** `docs/epics/epic-34-tts-readalong/issues.md`「Issue 6」；`docs/epics/epic-34-tts-readalong/spec.md`「Implementation Decisions」「`ReaderScreen` 整合」段落（Mini Player 定案為新增畫面元件，須與底部導覽列/目錄側邊欄連動，堆疊層級由本計畫決定）；`docs/epics/epic-34-tts-readalong/reviews/review-spec.md` Minor #1（版面層級，已於上方 Spec 段落引用的原文中一併澄清）。

## Global Constraints

- **依賴 Issue 2、Issue 5 皆已合併**：本計畫的所有檔案路徑與程式碼錨點皆以 Issue 5（`feat/epic-34-issue-5-tts-controls`，含審查後的兩個 Minor 修復）合併後的程式碼為準。若實際執行本計畫時 Issue 5 的 PR 尚未合併到 `main`，須先確認合併完成、`reader_screen.dart` 內確實存在 `reader_tts_previous_button`／`reader_tts_next_button`／`reader_tts_speed_button` 三顆按鈕與 `_ttsSpeedPresets`／`_nextTtsSpeedPreset` 後才開始。
- **不新增播放邏輯**：`TtsController.play()`／`pause()`／`previousSegment()`／`nextSegment()`／`setSpeed()` 皆維持既有簽章與行為，本 Issue 只重新排列呼叫這些方法的 UI 觸發點。
- **既有 4 個 Key 名稱不可變更**：`reader_tts_play_pause_button`／`reader_tts_previous_button`／`reader_tts_next_button`／`reader_tts_speed_button`——Issue 2／3／4／5 的 `reader_screen_test.dart` 測試皆以這些 Key 尋找按鈕，改名會讓既有測試全數失敗。
- **CBZ 範圍不預先假設 Issue 10 已完成**：CBZ 停用按鈕圖示顏色沿用目前 `_themedFabIconColor`（與啟用狀態相同色），不在本 Issue 內順手修正 Issue 10 的視覺區隔問題——那是另一張獨立工單的範圍。
- **不涉及 Issue 7（背景播放/`audio_service`）／Issue 8（E-Ink 安全視窗）範圍**：Mini Player 本身的顯示/隱藏與版面，不處理背景播放通知、Audio Focus、或跨頁自動翻頁。
- 新增檔案沿用既有扁平結構（`app/lib/screens/`，比照 `annotation_toolbar.dart` 前例，不建子目錄）；測試沿用既有慣例（`app/test/screens/<widget>_test.dart`，比照 `annotation_toolbar_test.dart`）。

---

### Task 1：`TtsMiniPlayer` 獨立元件（TDD）

**Files:**
- Create: `app/lib/screens/tts_mini_player.dart`
- Test: `app/test/screens/tts_mini_player_test.dart`

**Interfaces:**
- Consumes：既有 `TtsPlaybackStatus`（`app/lib/reader/tts_controller.dart`，`enum TtsPlaybackStatus { idle, playing, paused }`）
- Produces：`class TtsMiniPlayer extends StatelessWidget`，建構參數 `status`（`TtsPlaybackStatus`，必要）／`speed`（`double`，必要）／`isCbz`（`bool`，必要）／`backgroundColor`（`Color`，必要）／`iconColor`（`Color`，必要）／`onPlayPause`（`VoidCallback`，必要）／`onPrevious`（`VoidCallback`，必要）／`onNext`（`VoidCallback`，必要）／`onSpeedTap`（`VoidCallback`，必要）——皆供 Task 2 的 `ReaderScreen` 使用。本元件不依賴 `TtsController`、不依賴 `ReaderScreen`，可被完全獨立 pump 測試（不像 `ReaderScreen` widget test 有 WebView 誠實邊界限制）。

- [ ] **Step 1：寫失敗測試**

建立 `app/test/screens/tts_mini_player_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tts_controller.dart';
import 'package:elinkbook/screens/tts_mini_player.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('非 CBZ：完整播放/暫停/上一句/下一句/語速控制', () {
    testWidgets('顯示四顆按鈕：播放/暫停、上一句、下一句、語速', (tester) async {
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
      )));

      expect(find.byKey(const Key('reader_tts_play_pause_button')), findsOneWidget);
      expect(find.byKey(const Key('reader_tts_previous_button')), findsOneWidget);
      expect(find.byKey(const Key('reader_tts_next_button')), findsOneWidget);
      expect(find.byKey(const Key('reader_tts_speed_button')), findsOneWidget);
    });

    testWidgets('status 為 idle/paused 時顯示播放圖示，playing 時顯示暫停圖示', (tester) async {
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
      )));
      var icon = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('reader_tts_play_pause_button')),
        matching: find.byType(Icon),
      ));
      expect(icon.icon, Icons.play_arrow);

      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.paused,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
      )));
      icon = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('reader_tts_play_pause_button')),
        matching: find.byType(Icon),
      ));
      expect(icon.icon, Icons.play_arrow);

      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.playing,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
      )));
      icon = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('reader_tts_play_pause_button')),
        matching: find.byType(Icon),
      ));
      expect(icon.icon, Icons.pause);
    });

    testWidgets('語速按鈕顯示 speed 的兩位小數＋x 後綴', (tester) async {
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.25,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
      )));

      expect(
        find.descendant(
          of: find.byKey(const Key('reader_tts_speed_button')),
          matching: find.text('1.25x'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('點擊播放/暫停觸發 onPlayPause', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () => tapped = true,
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
      )));

      await tester.tap(find.byKey(const Key('reader_tts_play_pause_button')));
      expect(tapped, isTrue);
    });

    testWidgets('點擊上一句觸發 onPrevious', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () => tapped = true,
        onNext: () {},
        onSpeedTap: () {},
      )));

      await tester.tap(find.byKey(const Key('reader_tts_previous_button')));
      expect(tapped, isTrue);
    });

    testWidgets('點擊下一句觸發 onNext', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () => tapped = true,
        onSpeedTap: () {},
      )));

      await tester.tap(find.byKey(const Key('reader_tts_next_button')));
      expect(tapped, isTrue);
    });

    testWidgets('點擊語速按鈕觸發 onSpeedTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () => tapped = true,
      )));

      await tester.tap(find.byKey(const Key('reader_tts_speed_button')));
      expect(tapped, isTrue);
    });
  });

  group('CBZ：只顯示停用的播放鍵', () {
    testWidgets('只顯示 reader_tts_play_pause_button，其餘三顆按鈕不存在', (tester) async {
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: true,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
      )));

      expect(find.byKey(const Key('reader_tts_play_pause_button')), findsOneWidget);
      expect(find.byKey(const Key('reader_tts_previous_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_next_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_speed_button')), findsNothing);
    });

    testWidgets('播放/暫停按鈕為停用狀態（onPressed 為 null），圖示固定為播放箭頭', (tester) async {
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: true,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
      )));

      final button = tester.widget<IconButton>(
        find.byKey(const Key('reader_tts_play_pause_button')),
      );
      expect(button.onPressed, isNull);
      final icon = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('reader_tts_play_pause_button')),
        matching: find.byType(Icon),
      ));
      expect(icon.icon, Icons.play_arrow);
    });
  });
}
```

- [ ] **Step 2：跑測試確認全數失敗**

```
flutter test test/screens/tts_mini_player_test.dart
```

Expected：FAIL——`package:elinkbook/screens/tts_mini_player.dart` 尚不存在，編譯期即報錯。

- [ ] **Step 3：實作 `TtsMiniPlayer`**

建立 `app/lib/screens/tts_mini_player.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/tts_controller.dart';

/// TTS 朗讀正式 Mini Player 控制列（epic-34-tts-readalong Issue 6）。
/// 比照本專案既有 [AnnotationToolbar]（`annotation_toolbar.dart`）的既定
/// 慣例：純 [StatelessWidget]，不直接持有 [TtsController]，只吃基本型別
/// 與 callback 參數——呼叫端（[ReaderScreen]）以
/// `AnimatedBuilder(animation: TtsController, builder: ...)` 包住本
/// widget，每次 [TtsController.notifyListeners] 觸發時傳入最新的
/// [status]／[speed]，本 widget 完全不維護任何私有狀態（`spec.md`
/// 「單一事實來源」要求，審查 `review-issues.md` Minor #1）。
///
/// [isCbz] 為 `true` 時，只顯示一顆停用狀態的播放鍵（CBZ 為純圖像格式，
/// 無文字可朗讀，見 Issue 2 既有設計），不建構上一句/下一句/語速三顆
/// 按鈕——沿用 Issue 5 既有的 CBZ 排除範圍，本 Issue 不新增播放邏輯。
class TtsMiniPlayer extends StatelessWidget {
  final TtsPlaybackStatus status;
  final double speed;
  final bool isCbz;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSpeedTap;

  const TtsMiniPlayer({
    super.key,
    required this.status,
    required this.speed,
    required this.isCbz,
    required this.backgroundColor,
    required this.iconColor,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onSpeedTap,
  });

  @override
  Widget build(BuildContext context) {
    final playing = status == TtsPlaybackStatus.playing;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: isCbz
            ? IconButton(
                key: const Key('reader_tts_play_pause_button'),
                icon: Icon(Icons.play_arrow, color: iconColor),
                tooltip: 'CBZ 為純圖像格式，不支援語音朗讀',
                onPressed: null,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('reader_tts_previous_button'),
                    icon: Icon(Icons.skip_previous, color: iconColor),
                    tooltip: '上一句',
                    onPressed: onPrevious,
                  ),
                  IconButton(
                    key: const Key('reader_tts_play_pause_button'),
                    icon: Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      color: iconColor,
                    ),
                    tooltip: playing ? '暫停朗讀' : '開始朗讀',
                    onPressed: onPlayPause,
                  ),
                  IconButton(
                    key: const Key('reader_tts_next_button'),
                    icon: Icon(Icons.skip_next, color: iconColor),
                    tooltip: '下一句',
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
                    onPressed: onSpeedTap,
                  ),
                ],
              ),
      ),
    );
  }
}
```

- [ ] **Step 4：跑測試確認全數通過**

```
flutter test test/screens/tts_mini_player_test.dart
```

Expected：全數 PASS（11 個測試）。

```
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/tts_mini_player.dart app/test/screens/tts_mini_player_test.dart
git commit -m "feat(epic-34): 新增 TtsMiniPlayer 獨立元件（Issue 6 Task 1）"
```

---

### Task 2：`ReaderScreen` 接線——以 `TtsMiniPlayer` 取代四顆獨立浮動按鈕

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`（既有檔案，新增測試案例；既有 Issue 2/3/4/5 的 TTS 測試組不修改）

**Interfaces:**
- Consumes：Task 1 的 `TtsMiniPlayer`；既有 `_ttsControllerOrNull`／`_themedFabBackgroundColor`／`_themedFabIconColor`／`_ttsSpeedPresets`／`_nextTtsSpeedPreset`／`_resolved`／`_epubPositionInfo`／`_chromeVisible`
- Produces：`ReaderScreen` 內部接線（無新增公開 API），新增私有 getter `double get _ttsMiniPlayerBottomOffset`

- [ ] **Step 1：寫失敗測試**

在 `app/test/screens/reader_screen_test.dart` 找到本檔案結尾（最後一個 `group` 之後、`main()` 函式收尾 `}` 之前——若不確定確切收尾位置，搜尋檔案最後一次出現的 `});` 後接 `}`），新增一個新的 group：

```dart
  group('Mini Player 與既有底部元件顯示連動（epic-34-tts-readalong Issue 6）', () {
    testWidgets(
        '頁尾預設顯示（showFooter 預設 null＝true）且提供 ttsProvider 時，頁尾進度'
        '文字與 Mini Player 播放鍵同時存在，互不排斥（驗證兩者顯示條件沒有誤觸'
        '互斥；比照本檔案既有「流式 EPUB：onLocatorChanged 回報 pageIndex/'
        'totalPages 後，頁尾顯示對應頁碼」測試的既有寫法，不需要另外設定'
        'prefsManager——BookReaderPrefs.showFooter 為 null 時預設即為顯示）',
        (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts6_footer_coexist',
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
      // EpubPositionInfo.displayPageIndex/displayTotalPages 是由
      // locationIndex/locationTotal（或 visualPageIndex/visualTotalPages）
      // 換算出的唯讀 getter，非建構子參數——比照本檔案既有「流式 EPUB：
      // onLocatorChanged 回報 pageIndex/totalPages 後，頁尾顯示對應頁碼」
      // 測試的既有寫法，直接傳入 locationIndex/locationTotal。
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          progression: 0.1,
          locationIndex: 9,
          locationTotal: 100,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('reader_foliate_progress_text')), findsOneWidget);
      expect(find.byKey(const Key('reader_tts_play_pause_button')), findsOneWidget);
    });

    testWidgets('未提供 ttsProvider 時，Mini Player 四顆按鈕皆不顯示（沿用既有 Issue 2 行為）',
        (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts6_no_provider',
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

      expect(find.byKey(const Key('reader_tts_play_pause_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_previous_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_next_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_speed_button')), findsNothing);
    });
  });
```

- [ ] **Step 2：跑測試確認新測試失敗（其餘既有測試仍應通過）**

```
flutter test test/screens/reader_screen_test.dart
```

Expected：新增的 2 個測試 FAIL（`TtsMiniPlayer` 尚未接線，`reader_foliate_progress_text` 與 `reader_tts_play_pause_button` 可能因版面衝突或尚未共存而失敗；實際失敗原因以當下執行結果為準），既有測試維持原本通過狀態。

- [ ] **Step 3：新增 `_ttsMiniPlayerBottomOffset` getter**

在 `app/lib/screens/reader_screen.dart` 找到 `_ttsSpeedPresets`／`_nextTtsSpeedPreset` 定義（Issue 5 已新增）：

```dart
  static const List<double> _ttsSpeedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  double _nextTtsSpeedPreset(double current) {
    final index =
        _ttsSpeedPresets.indexWhere((p) => (p - current).abs() < 0.001);
    if (index == -1) return 1.0;
    return _ttsSpeedPresets[(index + 1) % _ttsSpeedPresets.length];
  }
```

緊接其後新增：

```dart

  /// Mini Player 底部偏移量（epic-34-tts-readalong Issue 6）：與既有頁尾
  /// 進度文字（[_buildFoliateProgressText]，`Positioned(bottom: 0)`）的
  /// 顯示條件完全對齊——頁尾實際會顯示時（`showFooter` 開啟且已有分頁
  /// 資訊），Mini Player 往上讓出額外空間避免視覺重疊；頁尾不會顯示時
  /// （例如使用者關閉 `showFooter`，或尚未收到任何 `onLocatorChanged`
  /// 事件）Mini Player 可以貼近底部。數值為首次實作的合理預設，未經真機
  /// 像素級校準——若真機驗收發現仍有重疊或間距不理想，屬正常後續微調，
  /// 不影響本 Issue 的功能正確性驗收。
  double get _ttsMiniPlayerBottomOffset {
    final footerVisible = (_resolved?.showFooter ?? false) &&
        (_epubPositionInfo?.displayTotalPages ?? 0) > 0;
    return footerVisible ? 40 : 12;
  }
```

- [ ] **Step 4：以 `TtsMiniPlayer` 取代既有兩個 FAB 區塊**

在 `app/lib/screens/reader_screen.dart` 找到既有的播放/暫停 FAB 區塊（Issue 2）與上一句/下一句/語速 FAB 區塊（Issue 5）——從播放/暫停區塊的 `if (isFoliateFormat(format) &&\n                _chromeVisible &&\n                widget.ttsProvider != null)` 開始，到上一句/下一句/語速區塊結尾的 `],`（collection-if spread 結尾）為止，完整內容為：

```dart
            if (isFoliateFormat(format) &&
                _chromeVisible &&
                widget.ttsProvider != null)
              Positioned(
                top: 296,
                right: 16,
                child: format == BookFormat.cbz
                    // CBZ 為純圖像格式，無文字可朗讀——明確顯示停用狀態
                    // 的按鈕（onPressed: null），不是整個隱藏（見
                    // issues.md Issue 2 驗收標準：「CBZ 書籍 TTS 入口為
                    // 明確停用狀態，非靜默無反應」）。
                    ? ClipOval(
                        child: Container(
                          color: _themedFabBackgroundColor,
                          child: IconButton(
                            key: const Key('reader_tts_play_pause_button'),
                            icon: Icon(Icons.play_arrow,
                                color: _themedFabIconColor),
                            tooltip: 'CBZ 為純圖像格式，不支援語音朗讀',
                            onPressed: null,
                          ),
                        ),
                      )
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
                format != BookFormat.cbz) ...[
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
            ],
```

整段取代為：

```dart
            // Mini Player（epic-34-tts-readalong Issue 6）：取代 Issue 2／
            // Issue 5 各自獨立的浮動圓形按鈕，整合為一顆水平橫條，鎖定在
            // 畫面底部。CBZ 的「顯示但停用」邏輯與其餘三顆按鈕的排除範圍
            // 皆下放給 TtsMiniPlayer 的 isCbz 分支處理（見該檔案）——這裡
            // 只需要判斷「要不要建構 TtsMiniPlayer」，不需要再另外判斷
            // CBZ（跟舊版兩個區塊各自判斷 CBZ 的寫法不同，此處單一入口
            // 已足夠）。bottom 偏移量見 _ttsMiniPlayerBottomOffset 文件
            // 註解。
            if (isFoliateFormat(format) &&
                _chromeVisible &&
                widget.ttsProvider != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: _ttsMiniPlayerBottomOffset,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _ttsControllerOrNull!,
                    builder: (context, _) {
                      final controller = _ttsControllerOrNull!;
                      return TtsMiniPlayer(
                        status: controller.status,
                        speed: controller.speed,
                        isCbz: format == BookFormat.cbz,
                        backgroundColor: _themedFabBackgroundColor,
                        iconColor: _themedFabIconColor,
                        onPlayPause: controller.status == TtsPlaybackStatus.playing
                            ? controller.pause
                            : () => controller.play(),
                        onPrevious: () => controller.previousSegment(),
                        onNext: () => controller.nextSegment(),
                        onSpeedTap: () => controller
                            .setSpeed(_nextTtsSpeedPreset(controller.speed)),
                      );
                    },
                  ),
                ),
              ),
```

- [ ] **Step 5：新增 import**

在 `app/lib/screens/reader_screen.dart` 找到既有的：

```dart
import 'annotation_toolbar.dart';
```

緊接其後新增：

```dart
import 'tts_mini_player.dart';
```

- [ ] **Step 6：跑測試確認全數通過、零回歸**

```
flutter test test/screens/reader_screen_test.dart
```

Expected：全數 PASS——含新增的 2 個 Issue 6 測試，以及 Issue 2／3／4／5 既有全部 TTS 相關測試（`reader_tts_play_pause_button`／`reader_tts_previous_button`／`reader_tts_next_button`／`reader_tts_speed_button` 相關斷言）皆維持原樣通過，零回歸。

```
flutter test
```

Expected：全專案測試全數通過，零回歸。

```
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-34): ReaderScreen 接線——以 TtsMiniPlayer 取代四顆獨立浮動按鈕（Issue 6 Task 2）"
```

---

## 測試策略總結（Self-Review 用，非額外步驟）

- **`TtsMiniPlayer` 獨立單元測試**（Task 1，`tts_mini_player_test.dart`）：這是本 Issue 最扎實的測試層——不像 `ReaderScreen` widget test 受限於 `flutter_test` 環境下 `FoliateReaderView` 的 WebView 誠實邊界，`TtsMiniPlayer` 是純 `StatelessWidget`，可以直接 pump 真實的 `status`/`speed`/`isCbz` 組合、直接 tap 按鈕、直接斷言 callback 真的被呼叫——涵蓋播放/暫停圖示切換、語速文字格式、CBZ 模式下三顆按鈕不存在且播放鍵停用、四個 callback 皆正確觸發。
- **`ReaderScreen` widget test**（Task 2）：驗證 UI 接線層級——`TtsMiniPlayer` 與既有頁尾進度文字能同時存在（不互相排斥）、未提供 `ttsProvider` 時 Mini Player 完全不顯示（沿用 Issue 2 既有行為）。與目錄側邊欄（`showModalBottomSheet`）的遮擋關係由 Flutter `Navigator`/`Overlay` 機制本身保證，不需要另外寫測試（見本計畫 Architecture 段落）。
- **零回歸驗證**：Issue 2／3／4／5 在 `reader_screen_test.dart` 累積的所有 TTS 相關測試（`find.byKey('reader_tts_*')`／`tester.widget<Icon>`／`tester.widget<IconButton>`）完全不修改，直接依賴 Task 1／Task 2 保留相同 Key 與相同 `Icon`/`IconButton`/`Text` 語意來維持通過。
- **無法自動化、須真機手動驗證的部分**（比照既有 Issue「測試策略總結」慣例，合併前建議至少手動跑一次）：
  1. 開啟一本已啟用頁尾（`showFooter`）的 EPUB，確認 Mini Player 橫條與頁尾進度文字（例如「3/120」）不會視覺重疊、彼此可辨識。
  2. 直排（`vertical-rl`）模式下頁尾改用旋轉的 `RotatedBox`（靠左側邊緣），確認 Mini Player 橫條（`left:16, right:16`）與旋轉頁尾沒有明顯視覺衝突；若有，記錄下來另立後續微調（本計畫 `_ttsMiniPlayerBottomOffset` 未針對直排模式做特殊處理，屬已知未涵蓋情境）。
  3. 開啟目錄（TOC）Bottom Sheet 時，確認 Mini Player 確實被完全遮住、不會穿透顯示或造成點擊衝突。
  4. 點擊 Mini Player 上的播放/暫停/上一句/下一句/語速，確認實際朗讀行為與 Issue 2／Issue 5 真機驗收時完全一致（本 Issue 未改動任何播放邏輯，僅重新排列 UI）。
  5. CBZ 書籍開啟時，確認 Mini Player 只顯示一顆停用狀態的播放鍵，形狀/位置與非 CBZ 書籍的完整橫條相比合理（矮橫條 vs. 完整橫條），不會有明顯跳動或裁切。

---

## Self-Review 檢查結果

- **Spec coverage**：`issues.md` Issue 6 設計要點與驗收標準逐條對應——Mini Player 掛載於既有 Reader 底部工具列體系並整合 Issue 2/5 邏輯（Task 1／Task 2）、與底部導覽列/目錄側邊欄顯示連動避免遮擋（Task 2 `_ttsMiniPlayerBottomOffset`＋Architecture 段落對目錄側邊欄遮擋機制的說明）、單一事實來源（Task 1 `TtsMiniPlayer` 不維護私有狀態，Task 2 `AnimatedBuilder` 每次重建皆傳入最新 `controller.status`/`controller.speed`）、`flutter analyze`／`flutter test` 全數通過且既有底部工具列相關測試零回歸（Task 2 Step 6）。無缺口。
- **Placeholder scan**：全文搜尋未發現「TBD」/「之後補」/「處理錯誤」等空話；所有程式碼步驟皆有完整程式碼區塊與精確的既有程式碼比對錨點。
- **Type consistency**：`TtsMiniPlayer` 建構參數（Task 1 定義：`status`/`speed`/`isCbz`/`backgroundColor`/`iconColor`/`onPlayPause`/`onPrevious`/`onNext`/`onSpeedTap`）與 Task 2 `ReaderScreen` 呼叫端逐一對應一致；`_ttsMiniPlayerBottomOffset`（Task 2 Step 3 定義為 `double` getter）與 Step 4 `Positioned(bottom: _ttsMiniPlayerBottomOffset, ...)` 呼叫端一致；四個既有 Key 名稱在 Task 1（`TtsMiniPlayer` 內部）與既有 Issue 2/3/4/5 測試斷言中完全一致，未被更動。
