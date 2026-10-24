# Issue 28：暫態高亮計時器 module 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 把搜尋跳轉暫態高亮的 3 秒自動清除計時器（含為測試捕捉 Zone 的手法）從 `reader_screen.dart` 抽成可單獨測試的小 module，行為不變。

**Architecture：** 新類別 `TransientHighlightTimer`（`app/lib/reader/transient_highlight_timer.dart`）只管計時器：`start(onExpire)`／`cancel()`／`isActive`，建構時捕捉 `Zone.current`，可選 `timerFactory` 供單元測試。`ReaderScreen` 在 `initState` 建構一個實例，取代 `_searchJumpHighlightTimer` 與 `_creationZone`。

**Tech Stack：** Flutter／Dart、`flutter_test`、`fake_async`（測試用；已在 `pubspec.yaml` 的 `dev_dependencies`，`^1.3.3`）。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`，設計依據是 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 28 設計決策」（決策 1～8）。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **純重構，行為不變**（決策 1）：搜尋跳轉高亮的顯示、3 秒清除、提前清除時機完全不變。
- **`ReaderScreen` 不新增公開建構參數**（決策 4）。
- **module 不依賴 `_surface`**（決策 3）：只管計時器。`_searchJumpHighlightTriggered` 旗標與 `clearTransientHighlight()` 呼叫留在畫面。
- **必須在 `initState` 明確建構 module**（決策 3）：不用 `late final` 延遲初始化，確保捕捉的是 `initState` 當下（fake-async）的 Zone。
- **到期路徑與提前清除路徑分開**（決策 3）：到期時 `isActive` 已為 false，`onExpire` 要直接清除高亮，不可再經過 `isActive` 判斷。
- **既有測試**：`reader_screen_test.dart` 的 3 秒與提前點擊案例（約 657～745、12233、12377 行）不改，必須全部維持綠燈。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，只跑一個）。
- **每個 Task／commit 結束都必須可編譯、`flutter analyze` 乾淨、被觸及的測試全綠**。
- **提交前**：`flutter analyze` 必須 "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`（本機 nvm 沒裝 Node 則無法執行，記錄在 `epic.md`）。
- **Windows 環境**：多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯以 `newline=''` 開檔；不要對整個既有檔案跑 `dart format`（會改到舊程式與換行字元；新檔可以格式化）。
- **Commit**：不加 `Co-Authored-By`；結尾加 `Claude-Session: https://claude.ai/code/session_019bmfxQJ1gaKoHGoWH7gJwD`。每個 Task 一個 commit。
- **不要提交** `app/android/gradle.properties`（使用者擱置的未提交變動）。
- **計畫與實作同分支同 PR**，不另開文件分支。

## Review Focus

1. **到期時高亮沒被清掉。** 到期後 `isActive` 為 false；若到期路徑誤走「`isActive` 為 false 就返回」的提前清除判斷，高亮永遠不消失。→ module 單元測試（到期呼叫 `onExpire`）＋ `reader_screen_test.dart` 既有「3 秒後自動清除」案例。
2. **Zone 捕捉時機。** module 必須在 `initState` 建構。若延遲到 `runAsync` 內才建構，計時器建在真實 Zone，`tester.pump` 推不動。→ 既有 PDF 案例（`pumpUntilPdfReady` 離開 fake Zone）。
3. **重新啟動。** 就地跳轉在 3 秒內再次跳轉，舊計時器必須取消，新的重新計 3 秒。→ module 單元測試。
4. **`dispose` 殘留。** 離開畫面時必須取消計時器，到期回呼不得在已 dispose 的 State 上呼叫 `_surface`。→ `dispose` 呼叫 `cancel()`；沿用現行 `dispose` 位置。
5. **提前清除可重複呼叫。** `_handleZoneAction` 對每次動作都無條件呼叫清除方法，沒有高亮時必須是安全的無動作。→ `isActive` 為 false 直接返回。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/transient_highlight_timer.dart` | 新增 | `TransientHighlightTimer`：start／cancel／isActive，建構時捕捉 Zone |
| `app/test/reader/transient_highlight_timer_test.dart` | 新增 | module 單元測試 |
| `app/lib/screens/reader_screen.dart` | 修改 | 改持有 `TransientHighlightTimer`；刪 `_searchJumpHighlightTimer`、`_creationZone` |
| `CONTEXT.md` | 不動 | 無新詞彙 |

---

### Task 0：提交設計文件與計畫

- [x] **Step 1：** 分支 `epic-54/issue-28-transient-highlight-timer`（已從含 PR #369 的 `main` 建立）。
- [x] **Step 2：** 提交 `epic.md`、`issues.md`、`docs/epics.md`、本計畫（純文件，一個 commit）。不提交 `app/android/gradle.properties`。

### Task 1：`TransientHighlightTimer` module 與單元測試

**Files：** `transient_highlight_timer.dart`、`transient_highlight_timer_test.dart`。

介面草案（以實際編譯為準）：

```dart
import 'dart:async';

/// 暫態高亮的自動清除計時器（epic-54 Issue 28）。
///
/// 只管計時：建構時捕捉 [Zone.current]，之後不論 [start] 在哪個 Zone 被呼叫，
/// 預設都在建構當下的 Zone 建立 [Timer]——測試的 `tester.runAsync` 會暫時離開
/// fake-async Zone，計時器若建在真實 Zone，`tester.pump` 就推不動。
///
/// 刻意使用裸 `Timer` 加 Zone 捕捉，不引入 `package:clock`：測試靠 fake-async
/// Zone 推進時間，不需要另一套可注入的時鐘（審查 M-2；原註解在 `ReaderScreen`
/// 的欄位上，搬到這裡）。
class TransientHighlightTimer {
  TransientHighlightTimer({
    this.duration = const Duration(seconds: 3),
    Timer Function(Duration duration, void Function() callback)? timerFactory,
  }) : _timerFactory = timerFactory ?? _zoneBoundFactory(Zone.current);

  final Duration duration;
  final Timer Function(Duration, void Function()) _timerFactory;
  Timer? _timer;

  /// 已啟動且未取消、未到期。
  bool get isActive => _timer != null;

  /// 重新計時：先取消舊的。到期時先把自己標成未啟動，再呼叫 [onExpire]。
  void start(void Function() onExpire) {
    _timer?.cancel();
    _timer = _timerFactory(duration, () {
      _timer = null;
      onExpire();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  static Timer Function(Duration, void Function()) _zoneBoundFactory(Zone zone) =>
      (duration, callback) => zone.run(() => Timer(duration, callback));
}
```

- [x] **Step 1（紅）：** 新增 `transient_highlight_timer_test.dart`，先寫測試、確認失敗（檔案不存在的編譯失敗即為紅燈）。多數案例用 `fakeAsync` 加預設工廠，不寫假 `Timer` 類別（審查 M-1）：
  - 到期：在 `fakeAsync` 內 `start`，`elapse(3 秒)` 後呼叫一次 `onExpire`，且 `onExpire` 執行當下 `isActive` 已為 false。
  - 未到期：`elapse(2 秒 999 毫秒)` 時尚未呼叫 `onExpire`，`isActive` 為 true。
  - 重新啟動：`start` 後過 2 秒再 `start`，再過 2 秒時第一次的 `onExpire` 沒被呼叫；從第二次 `start` 起滿 3 秒才呼叫第二次的 `onExpire`（舊計時器被取消、新的重新計 3 秒）。
  - `cancel()` 後 `elapse(5 秒)` 不呼叫 `onExpire`，`isActive` 為 false。
  - 沒有啟動時 `cancel()` 是安全的無動作。
  - 預設時長：只有這一個案例用 `timerFactory`，假工廠記錄收到的 `duration`，應為 3 秒；工廠回傳 `fakeAsync` 內建立的真 `Timer` 即可，不需假類別。
  - Zone：在 `fakeAsync` 內建構、再用 `Zone.root.run` 呼叫 `start`，`elapse(3 秒)` 後仍呼叫 `onExpire`（證明計時器建在建構時的 Zone）。
- [x] **Step 2（綠）：** 新增 `transient_highlight_timer.dart`，內容依上方草案；新檔可執行 `dart format`。
- [x] **Step 3：** `flutter analyze`；跑 `test/reader/transient_highlight_timer_test.dart`；commit。此時 `ReaderScreen` 還沒改，行為完全不變。

### Task 2：`ReaderScreen` 改用 module

**Files：** `reader_screen.dart`。

- [x] **Step 1：** 先跑一次基準，分三次執行（多個 `--plain-name` 會要求同時符合，所以分次跑）：`flutter test test/screens/reader_screen_test.dart --plain-name 暫態高亮`、`--plain-name 就地跳轉`、`--plain-name 搜尋跳轉`。計畫審查時已實測的基準：暫態高亮 8 個、就地跳轉 3 個、搜尋跳轉 5 個，全部通過（三組可能有重疊，不能相加；審查 M-3）。若實跑數字與此不同，先查明原因再動手。
- [x] **Step 2：** 修改 `reader_screen.dart`：
  - 刪 `Timer? _searchJumpHighlightTimer` 與 `late Zone _creationZone`（含其 doc 註解）；`initState` 的 `_creationZone = Zone.current;` 改成 `_searchJumpHighlightTimer = TransientHighlightTimer();`（欄位型別 `late final TransientHighlightTimer`，在 `initState` 第一行 `super.initState()` 之後賦值）。
  - `_startSearchJumpHighlightAutoClearTimer()`：改成 `_searchJumpHighlightTimer.start(() => _surface.clearTransientHighlight())`（到期路徑，直接清除高亮；用閉包而非 tear-off，到期當下才取 `_surface`）；更新 doc 註解，移除「使用捕捉到的 fake Zone」的說明，改指向 module。
  - `_clearSearchJumpHighlight()`（提前清除）：`if (!_searchJumpHighlightTimer.isActive) return; _searchJumpHighlightTimer.cancel(); _surface.clearTransientHighlight();`。
  - `dispose`：`_searchJumpHighlightTimer.cancel();`。
  - 補上 `import '../reader/transient_highlight_timer.dart';`（路徑依該檔既有 import 風格）。
  - 欄位 doc 註解（約 435～438 行）更新，不要留下已不存在的 `_creationZone` 說明；「刻意使用裸 `Timer`、不引入 `package:clock`」的理由已搬到 `TransientHighlightTimer` 的類別 doc 註解（審查 M-2），欄位註解只留「3 秒內提前清除、取兩者較早發生者」的說明；其餘程式碼不動。
- [x] **Step 3：** `flutter analyze`；重跑 Step 1 的三組測試，通過數與基準相同；再跑整個 `test/screens/reader_screen_test.dart` 一次（此檔是本 Issue 唯一觸及的畫面測試檔，完整檔案跑一次可抓到 Zone 相關回歸）；commit。

### Task 3：收尾

- [x] **Step 1：** `epic.md` 開發記錄；`issues.md` Issue 28 狀態；`docs/epics.md` 同步。
- [x] **Step 2：** 驗收：`grep -n "_creationZone\|_searchJumpHighlightTimer" app/lib/screens/reader_screen.dart` 中沒有 `_creationZone`，`_searchJumpHighlightTimer` 只剩宣告、初始化、啟動、清除、`dispose`；`git diff main --stat -- app/lib` 只有 `reader_screen.dart` 與新檔 `transient_highlight_timer.dart`。
- [x] **Step 3：** `flutter analyze`；兩個 `check_*.js`（沒有 Node 則記錄未執行）；完整 `flutter test`（`run_in_background`，只跑一個）。
- [x] **Step 4：** 程式審查（報告存 `reviews/review-code-issue-28.md`，不進版控）。
- [ ] **Step 5：** WAVE 真機抽驗（風險低，一輪即可）：在 EPUB 與 PDF 各做一次——(1) 從書內搜尋選一個結果就地跳轉，高亮約 3 秒後自動消失；(2) 再跳轉一次，在 3 秒內點擊畫面，高亮立刻消失；(3) 在 3 秒內連續跳轉兩次，高亮從第二次起重新計 3 秒。
- [ ] **Step 6：** 開 PR；PR 開出後把 Issue 28 的狀態同步（Issue 32 已在 Task 0 同步）。
