# Issue 4 程式審查報告

**Base:** `c41fef4f37dfeab47fc7fb3b20a331d67e41e1ec` / **Head:** `62793f2d` / **審查日期：** 2026-08-28

## Strengths

- **與計畫逐字對齊，三個 Task 的 commit 邊界清楚。** 逐段比對 `plans/plan-issue-4.md` 三個 Task 的程式碼片段與實際 diff（`main.js`／`foliate_reader_view.dart`／`tts_controller.dart`／`reader_screen.dart` 及三份對應測試檔），插入位置、程式內容、註解文字幾乎逐字相符，未發現未經說明的隨意加料。
- **`_disposed` 防護確實落地。** `review-plan-issue-4.md` Important #1 要求的 `handleExternalPositionChange()` 開頭 `if (_disposed) return;` 防護確實存在（`app/lib/reader/tts_controller.dart:163`），不是只停留在計畫文字。
- **重用 `epubcfi.js` 既有 `compare()` 的架構選擇經原始碼交叉驗證屬實。** 實際讀取 vendored `epubcfi.js`（釘定版本內第 163 行附近）確認 `export const compare = (a, b) => { ... }` 簽章接受字串或已解析物件、回傳 `-1`/`0`/`1`，`main.js` 只 `import { compare as compareCfi } from './epubcfi.js'`（`app/android/app/src/main/assets/foliate/main.js:3`），`git diff --stat` 確認 `foliate/` 目錄下本次唯一變動檔案是 `main.js`，`epubcfi.js` 本身的 diff 為空——符合 ADR 0011「不修改 vendored 檔案」的要求，且未重新實作一套 CFI 排序邏輯。
- **`window.lookupTtsSegmentIndex` 的「找不到就退回最後一段」語意正確。** `compareCfi(cfi, visibleCfi) >= 0` 找第一個「在可視位置之後（含相等）」的段落，找不到（使用者已捲動過本章最後一段）時退回最後一段而非固定 0，避免章節結尾按播放被拉回開頭；空陣列安全回傳 `-1`，Dart 端 `FoliateReaderView.lookupSegmentByCfi()`（`app/lib/reader/foliate_reader_view.dart:529-538`）與 `TtsController.play()`（`tts_controller.dart:119-122`）皆有 clamp，行為鏈路完整。
- **`_playCurrentSegment()` 既有的 `_status != playing` 守衛，確實能攔住「單純一次手動導覽、之後不立刻按播放」情境下的殘留播放。** 已實際追蹤程式路徑並確認：`handleExternalPositionChange()` 於合成期間觸發時，即使稍後 `loadFile()` 仍會被舊呼叫執行完（`just_audio` 的 `setFilePath()` 本身不會自動播放，見 `app/lib/reader/tts_audio_player.dart:42-44`），但 `_status != TtsPlaybackStatus.playing` 這道既有守衛（`tts_controller.dart:198`）會擋下後續的 `player.play()`，高亮也已被 `handleExternalPositionChange()` 清除且不會被舊呼叫再次寫回——這部分的架構主張基本成立（但見下方 Important #1，僅在「導覽後立刻重按播放」的疊加情境下失效）。
- **`ReaderScreen` 對 `_ttsController`（nullable 欄位）而非 `_ttsControllerOrNull`（lazy getter）的選擇確實避免了「每次翻頁都意外建構 `TtsController`」的問題**——已確認 `_ttsController` 欄位本身宣告為 `TtsController? _ttsController;`（`reader_screen.dart:293`），`onLocatorChanged` 內直接用 `_ttsController?.handleExternalPositionChange();`（`reader_screen.dart:2784`），TTS 從未被使用時維持 `null`、無副作用。
- **一個正確、經驗證的計畫外微調：移除 `reader_screen.dart` 中不再需要的 `TtsSegmentCfi` 型別標註與其 import。** 計畫 Task 3 Step 1 的「找到」錨點文字其實已經是 `onHighlightSegment: (segment) {`（無型別標註），但比對 base commit 實際內容是 `onHighlightSegment: (TtsSegmentCfi? segment) {`（`reader_screen.dart:2697`於 base）。實作把顯式型別標註拿掉並同步移除了因此變成未使用的 `import '../reader/tts_segment_cfi.dart';`——已確認頭端 `reader_screen.dart` 全檔案不再有任何 `TtsSegmentCfi` 字面引用，這是正確且必要的調整（否則 `flutter analyze` 會噴 unused import），值得記錄為一個經確認的正向偏離，不是問題。
- **測試邊界誠實。** `main.js` regression guard（`foliate_reader_view_test.dart`）明講只驗證原始碼字串存在、不驗證瀏覽器內真實 CFI 排序結果；`ReaderScreen` widget test 明講 `flutter_test` 環境下 `loadSegments()` 恆回傳空清單、無法真正進入 `playing`，只驗證 wiring 不崩潰——皆與計畫「測試策略總結」的誠實框架一致，未誇大涵蓋範圍。
- **`flutter analyze`／`flutter test` 皆已實測通過（見下方 Verification），非僅信任計畫聲稱。**

## Issues

### Critical (Must Fix)

無。未發現會導致崩潰、資料遺失或安全性問題的缺陷；下方 Important #1 雖是真實可重現的狀態污染，但不會拋出未捕捉例外或損毀持久化資料，且下一次自然的分段完成/導覽事件會讓狀態自我修復。

### Important (Should Fix)

#### 1. `play()` 的 idle 分支新增的 `lookupStartIndex` await，重新打開了 Issue 2 review 曾經抓到並修復過的「連按播放鍵」競態視窗——經實測可重現「同一句話被合成兩次、`loadSegments()` 被呼叫兩次」

`app/lib/reader/tts_controller.dart:101-123`：

```dart
_isLoadingSegments = true;
List<TtsSegmentCfi> loaded;
try {
  loaded = await loadSegments();
} finally {
  _isLoadingSegments = false;   // ← 防重入旗標在這裡就解除了
}
if (_disposed) return;
if (loaded.isEmpty) return;
_segments = loaded;
final startIndex =
    lookupStartIndex == null ? 0 : await lookupStartIndex!(loaded);  // ← 新增的第二個 await，不受 _isLoadingSegments 保護
if (_disposed) return;
_currentIndex =
    (startIndex >= 0 && startIndex < _segments.length) ? startIndex : 0;
await _playCurrentSegment();
```

`_isLoadingSegments` 這個防重入旗標只包住 `loadSegments()` 這一個 await，`finally` 區塊讓它在 `loadSegments()` 一結束就被重設為 `false`——而本 Issue 新增的 `lookupStartIndex` 是**第二個** JS bridge 往返 await，落在旗標保護範圍**之外**。同時 `play()` 在整個 idle 分支期間都不會呼叫 `notifyListeners()`（要等到 `_playCurrentSegment()` 內部才會），代表 UI 上播放/暫停按鈕在這整段等待期間仍顯示「播放」圖示，使用者若因為看不到反應而再按一次播放鍵，第二次 `play()` 呼叫會直接通過所有既有守衛（`_status==playing`？否；`_isLoadingSegments`？已是 `false`；`_status==paused`？否）重新進入 idle 分支，與第一次呼叫並行執行。

**這正是 `review-issue-2-code.md` Strengths #6 記錄過的同一類競態**（該次修復把 `_status = playing` 的時機從「`synthesize()`＋`loadFile()` 都完成後」提前到「呼叫 `synthesize()` 之前」，目的就是關閉「`_isLoadingSegments` 已重設為 `false`，但 `_status` 尚未變成 `playing`」這段期間的連點競態）。Issue 4 在同一個視窗裡插入了一個新的、可能耗時（JS bridge 往返，最長可達 5 秒逾時）的 await，等於重新打開了這個已經修好一次的洞。

**已實測重現**（測試性質、跑完即刪，未留在 diff 中）：用可控 `Completer` 卡住第一次 `lookupStartIndex` 呼叫，模擬「按下播放鍵後、`lookupStartIndex` 尚未回應前又按一次播放鍵」（第二次的 `loadSegments()`／`lookupStartIndex` 回傳不同的章節/段落清單，模擬使用者在等待期間也翻了頁）：

```
loadSegmentsCall after 2nd tap (before 1st lookup resolves) = 2
lookupCallCount after 2nd tap = 2
final controller.segments.length = 1
final controller.currentIndex = 0
final controller.status = TtsPlaybackStatus.playing
synthesizedTexts = [B第一句。, B第一句。]
```

結果：`loadSegments()` 被呼叫兩次（第二次呼叫在第一次「應該」還在進行中時就發生了，證明防重入失效）；`_segments` 被第二次呼叫覆寫，導致第一次呼叫算出來的 `startIndex`（原本要用來播放章節 A 的第二句）在被覆寫後的 `_segments`（章節 B，只有一句）上被 clamp 回 `0`；最終使用者會聽到「同一句話被朗讀兩次」（`synthesize()` 被呼叫兩次、且文字相同），而不是預期的「章節 A 第二句」或乾淨的「章節 B 第一句」。雖然本次重現沒有觸發 `RangeError`（因為 `_currentIndex` 的 clamp 邏輯剛好兜住了），但 `_playCurrentSegment()` 內 `final segment = _segments[_currentIndex];`（`tts_controller.dart:188`）這一行本身**不在** `try`/`catch` 保護範圍內——如果兩個並行呼叫的時序稍有不同（例如覆寫發生在 `_currentIndex` 已經設定、但 `_segments` 尚未被覆寫完成之間的另一種交錯），存在丟出未捕捉 `RangeError` 的可能性，只是本次重現的特定時序沒有踩到。

**為什麼重要**：這不是需要罕見裝置/網路條件才能觸發的邊界案例，而是「使用者對著沒有立即視覺回饋的按鈕連按兩下」這個完全合理、常見的互動即可觸發；朗讀合成在真機上耗時可能達數百毫秒到數秒（見 `docs/epics/epic-34-tts-readalong` 既有測試策略對「真機合成延遲」的多次提及），使這個競態視窗在真實裝置上並不算窄。

**建議修法**：把防重入旗標的保護範圍延伸到涵蓋 `lookupStartIndex` 這個 await（例如把 `_isLoadingSegments = false` 的 `finally` 移到 `_currentIndex` 賦值之後、`_playCurrentSegment()` 呼叫之前，或乾脆重新命名/擴大旗標語意涵蓋整個「play() 正在啟動中」的區間），並補一個對應的重入測試（比照 Issue 2 review 對這類修復要求「修復後應補上對應測試以避免回歸」的既有慣例）。

#### 2. `handleExternalPositionChange()` 在 `play()` 的 loading／lookup 等待期間（`_status` 仍是 `idle`）被呼叫時是 no-op，無法攔截「按下播放鍵後立刻手動導覽」這個情境

`app/lib/reader/tts_controller.dart:162-181`：

```dart
void handleExternalPositionChange() {
  if (_disposed) return;
  if (_status == TtsPlaybackStatus.idle) return;   // ← play() 的 loading/lookup 階段，_status 仍是 idle
  ...
}
```

`play()` 的 idle 分支從呼叫 `loadSegments()` 開始、一直到 `_playCurrentSegment()` 內部把 `_status` 設為 `playing` 為止，這整段期間 `_status` 恆為 `idle`。若使用者在按下播放鍵後、朗讀真正開始前（也就是 `loadSegments()`／`lookupStartIndex()` 兩次 JS bridge 往返尚未完成時）手動翻頁或捲動，`ReaderScreen.onLocatorChanged` 仍會呼叫 `_ttsController?.handleExternalPositionChange()`，但因為 `_status == idle`，這次呼叫會被第一行的 no-op 守衛直接吞掉——不會清空 `_segments`、不會讓 `play()` 之後重新查詢起始位置。結果是：`loadSegments()` 用的仍是使用者按下播放鍵當下（導覽之前）的章節，`lookupStartIndex` 用的 `visibleCfi` 則是 `ReaderScreen._epubPositionInfo` 在呼叫當下的最新值（已經是導覽之後的新位置）——兩者不一致，可能在錯誤的章節內比對一個屬於別的章節的 CFI，得到語意上沒有意義但仍會被 clamp 到某個「合法索引」的結果，開始朗讀使用者已經離開的舊位置內容。

**為什麼重要**：這與本 Issue 的核心驗收標準（「手動導覽時自動暫停」「首次播放從畫面目前位置開始」）直接相關，卻正好落在兩者的交集空隙——`handleExternalPositionChange()` 的 no-op 判斷式假設「`idle` 就是真的什麼都沒在做」，但 Issue 4 新增的 `lookupStartIndex` await 讓「`idle` 但其實有一個 `play()` 正在啟動中」成為可能狀態，這個假設不再成立。

**建議修法**：與 Important #1 的修法本質相同——如果把「play() 正在啟動」納入某種可觀察狀態（旗標或状态枚舉），`handleExternalPositionChange()` 的 no-op 判斷也應該一併涵蓋這個狀態，才能讓「按下播放鍵後立刻導覽」正確中止或至少重新查詢起始位置。

### Minor (Nice to Have)

1. **`_playCurrentSegment()` 因 Important #1 的競態而被重複呼叫時，會產生浪費的重複 `player.loadFile()`／`provider.synthesize()` 呼叫。** `app/lib/reader/tts_controller.dart:188-206`。即使 Important #1 修復後這個情況不會再發生，記錄於此供追蹤：真機上重複呼叫 `synthesize()` 對電量/TTS 引擎資源並非免費，即使結果不影響最終播放內容正確性。
2. **`docs/epics/epic-34-tts-readalong/plans/plan-issue-4.md` 的「測試策略總結」列出的 5 項真機手動驗證項目，未包含「連按播放鍵兩次」或「按下播放鍵後立刻手動導覽」這兩個情境**（對應本報告 Important #1／#2）。建議在真機驗收清單中補上，即使程式修復後也值得留下人工驗證記錄。

## Verification（本次審查實測，非僅靜態閱讀）

審查全程未觸碰本次審查所在的原始 checkout（`main` HEAD），改用已存在的獨立 worktree `.worktrees/feat-epic-34-issue-4-tts-nav`（已位於 `62793f2d`，依賴已預先 `pub get`）執行：

- `flutter analyze`：`No issues found!`（約 45 秒）。
- `flutter test test/reader/tts_controller_test.dart`：**30 個測試全數通過**，與計畫「既有 22 個測試零回歸＋新增 8 個測試，共 30 個」的宣稱精確吻合。
- `flutter test test/reader/foliate_reader_view_test.dart`：**86 個測試全數通過**，含新增的 2 個 `main.js` 朗讀段反向查找 regression guard 測試。
- `flutter test test/screens/reader_screen_test.dart`：**296 個測試全數通過**，含新增的 1 個「手動導覽自動暫停與恢復播放」測試，既有 TTS Issue 2／Issue 3 測試與其餘既有劃線/備註/版面設定測試零回歸。
- `flutter test`（全專案）：**1767 個測試全數通過**，零回歸。
- `git diff --stat` 確認 vendored `foliate-js` 目錄下（`view.js`／`overlayer.js`／`epubcfi.js`／`epub.js` 等）僅 `main.js` 有變動；`epubcfi.js` 本身的 diff 為空，確認只有新增的 `import` 陳述式引用它，未編輯其內容。
- 交叉核對 vendored `epubcfi.js` 原始碼確認 `export const compare = (a, b)` 簽章與回傳語意（`-1`/`0`/`1`）與 `main.js`／計畫敘述一致。
- **針對 Important #1，在此 worktree 內另外撰寫並執行了一個一次性驗證測試**（用 `Completer` 控制 `lookupStartIndex` 的完成時機，模擬連按播放鍵）以取得實測證據而非僅靠程式碼推理，驗證後已刪除該檔案、確認 `git status --short` 乾淨、未留在 diff 或本次審查的任何產出中。

未新開額外 worktree（沿用既有的），審查結束未對其做任何清理以外的異動；本次審查所在的原始 checkout（`main` HEAD）全程未被觸碰。

## Recommendations

- **合併前建議先處理 Important #1／#2**，兩者根因相同（`play()` idle 分支新增的 `lookupStartIndex` await 未被既有防重入機制／`handleExternalPositionChange()` 的 no-op 判斷式涵蓋），建議合併修復並補上對應的重入/競態測試，而不是分開修兩次。
- 若時間壓力大、決定先合併：至少應在計畫或 issues.md 記錄這是已知限制，並在真機手動驗證清單補上「連按播放鍵」「按播放後立刻翻頁」兩項情境（Minor #2），避免真機驗收時被誤判為未知的新 bug。
- 兩項 Minor 不阻擋合併，可與 Important #1／#2 一併處理或留待下次觸碰 `tts_controller.dart` 時處理。

## Assessment

**Ready to merge？** With fixes

**Reasoning：** 三個 Task 的實作與計畫高度一致、`_disposed` 防護與「首次播放/導覽後恢復播放共用同一路徑」的核心架構主張經程式碼交叉驗證大致成立，`flutter analyze`／全專案 `flutter test`（1767 項）皆通過、零回歸；但 Task 2 新增的 `lookupStartIndex` await 重新打開了本專案 Issue 2 review 曾明確抓到並修復過的「連按播放鍵競態」，且已用一次性測試實際重現（`loadSegments()` 被呼叫兩次、同一句話被合成兩次），並連帶讓 `handleExternalPositionChange()` 在這段新視窗內失去攔截手動導覽的能力——兩者根因相同、直接關係到本 Issue 自身的核心驗收標準，建議修復後再合併。
