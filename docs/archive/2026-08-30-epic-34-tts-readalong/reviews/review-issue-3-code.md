# Issue 3 程式審查報告

**Base:** `c2c22d9599d24aecdb0832e2e5925f30b147a919` / **Head:** `c41fef4f37dfeab47fc7fb3b20a331d67e41e1ec` / **審查日期：** 2026-08-27

## Strengths

- **完全依計畫執行、逐字對齊。** 逐一比對 `plans/plan-issue-3.md` 三個 Task 的程式碼片段與實際 diff（`main.js`／`tts_controller.dart`／`foliate_reader_view.dart`／`reader_screen.dart` 及三份對應測試檔），程式內容、註解文字、插入位置皆與計畫完全一致，沒有臨場加料或偷改範圍。計畫 self-review 唯一提出的 Important 項目（`reader_screen.dart` 顯式 `import '../reader/tts_segment_cfi.dart';`）也確認已折入實作（`app/lib/screens/reader_screen.dart:25`）。
- **`foliate-note:` key 空間隔離架構經原始碼交叉驗證屬實，非僅信任計畫敘述。** 實際讀取 vendored `view.js`（`app/android/app/src/main/assets/foliate/view.js:394-446`）確認 `addAnnotation()` 對帶 `NOTE_PREFIX` 的 value 會 `resolveNavigation()` 去除前綴取得 Range，並透過 `draw-annotation` 事件把完整 `annotation` 物件（含新增的 `vertical` 欄位）交還監聽器；`overlayer.js` 的 `Overlayer.add()`/`remove()`（`overlayer.js:136-148`）內部 `#map` 是以完整傳入字串為 key，故 `"foliate-note:" + cfi` 與劃線/備註直接以裸 cfi 當 key 確實是兩個不相交的 Map key，`remove()` 也會正確 `#svg.removeChild()` 清掉 SVG 元素，無殘留風險。這與 ADR 0026「使用獨立 annotation key」的要求及計畫聲稱的行為完全吻合。
- **`??` 而非 `||` 的正確性有測試把關。** `main.js:917`（`draw-annotation` 監聽器）的 `annotation.vertical ?? (currentWritingMode === 'vertical')` 正確處理了「橫排時 `vertical: false` 是合法值，不能被誤判為未設定」這個邊界情況，`foliate_reader_view_test.dart` 新增的 regression guard 直接斷言原始碼字串含這個確切運算式，防止日後被誤改回 `||`。
- **關注點分離乾淨。** `TtsController.onHighlightSegment`（`tts_controller.dart:37`）簽章只認識 `TtsSegmentCfi?`，完全不知道 `FoliateReaderView`／WebView／排版方向的存在；`ReaderScreen._ttsControllerOrNull`（`reader_screen.dart:2666-2711`）是唯一同時知道「怎麼呼叫 `FoliateReaderView`」與「目前實際生效的排版方向是什麼」（`_resolved?.writingMode`，與既有頁首/頁尾直排判斷用同一個 getter，非另外發明新的判斷依據）的地方；JS 橋接完全侷限在 `main.js` 自有整合層，未修改任何 vendored 檔案（`git diff --stat` 確認 `foliate/` 目錄下唯一變動檔案是 `main.js`）。
- **四個 idle-reset 路徑全數正確清除高亮。** `tts_controller.dart` 內 paused-resume 失敗 catch（79 行附近）、`_playCurrentSegment()` 的 synthesize/loadFile 失敗 catch（146 行附近）、`_handleSegmentCompleted()` 章節唸完（159 行附近）三處都補上了 `onHighlightSegment?.call(null)`，加上 `_playCurrentSegment()` 成功路徑一開始就呼叫 `onHighlightSegment?.call(segment)`（125 行附近），四個呼叫點與計畫程式碼逐行相符，且五個新增單元測試（`play()` 開始播放／自動接續／播放結束回 idle／合成失敗回 idle／不提供 callback 時不拋例外）分別驗證了對應狀態轉換，非空洞斷言。
- **安全性無虞。** `FoliateReaderView.showTtsHighlight()`（`foliate_reader_view.dart:546-549`）用 `jsonEncode(cfi)` 組出 JS 字串字面值送給 `_evaluate()`，`vertical` 是 Dart `bool` 插值（只會是 `true`/`false` 字面文字），CFI 字串不會有跳脫不完整導致 JS 注入的問題。
- **測試邊界誠實，且與專案既有慣例一致（非本次新發明的說法）。** 已實際核對 `reader_screen_test.dart` 既有的 `setDecorations` 測試（3283 行附近）確實使用同一套「`flutter_test` 無法攔截 JS 呼叫，僅驗證 wiring 不崩潰」措辭，Issue 3 新增的兩個 widget test 的註解與這個既有先例完全對應，沒有誇大成「已驗證真實高亮渲染」。

## Issues

### Critical (Must Fix)

無。

### Important (Should Fix)

無。

### Minor (Nice to Have)

1. **`issues.md` Issue 3「測試要求」字面上要求 `ReaderScreen` widget test「斷言 fake `FoliateReaderView` 收到正確的高亮指令參數（segment CFI、`vertical` 旗標）」，但實作的兩個 widget test 只驗證直排/橫排下 wiring 不崩潰＋ADR 0026 不寫資料表，並未直接斷言 `showTtsHighlight`/`clearTtsHighlight` 收到的參數。**
   - File: `app/test/screens/reader_screen_test.dart:7457-7568`
   - 這不是本次實作臨時決定的走樣——`plans/plan-issue-3.md`（已通過 `review-plan-issue-3.md` 審查）在 Task 3 測試區塊已明確記錄這個測試縫隙的分工理由（`FoliateReaderView._controller` 在 `flutter_test` 環境下恆為 `null`，`evaluateJavascript` 呼叫參數無法在這層攔截，比照既有 `setDecorations` 測試先例），並將實際的參數正確性驗證拆給 `tts_controller_test.dart`（`onHighlightSegment` 收到正確 `TtsSegmentCfi`）＋`foliate_reader_view_test.dart` 的 `main.js` regression guard（`vertical` 覆寫邏輯存在於原始碼），加上計畫「測試策略總結」明列的真機手動驗證清單。整體驗收覆蓋鏈是完整的，只是不是 issues.md 字面描述的那個單一測試位置——記錄於此供追蹤，不影響本次合併判斷。
2. **`TtsController.dispose()`（`tts_controller.dart:168-173`）未呼叫 `onHighlightSegment?.call(null)`。** 若使用者在朗讀進行中（高亮顯示中）直接離開 `ReaderScreen`（觸發 `ReaderScreen.dispose()` → `_ttsController?.dispose()`），高亮不會被主動清除。實務上不構成殘影風險——`ReaderScreen.dispose()` 時整個 `FoliateReaderView`／底層 WebView 連同 `GlobalKey` 一併銷毀，沒有殘留的畫面可供殘影顯示，下次開書是全新的 WebView 實例。純粹是防禦性完整度的建議，不阻擋合併。

## Verification（本次審查實測，非僅靜態閱讀）

審查在唯讀 checkout 上未動本次審查所在的 `main` HEAD，改用已存在的獨立 worktree `.worktrees/feat-epic-34-issue-3-tts-highlight`（已位於 `c41fef4f`，依賴已預先 `pub get`）執行：

- `flutter analyze`：`No issues found!`（7.6s）。
- `flutter test test/reader/tts_controller_test.dart`：**22 個測試全數通過**，與計畫「既有 17 個測試零回歸＋新增 5 個高亮回呼測試，共 22 個」的宣稱精確吻合。
- `flutter test test/reader/foliate_reader_view_test.dart`：**106 個測試全數通過**，含新增的 3 個 `main.js` 朗讀高亮 regression guard 測試。
- `flutter test test/screens/reader_screen_test.dart`：**179 個測試全數通過**，含新增的 2 個「同步高亮跟隨」測試，既有 TTS Issue 2 測試與其餘既有劃線/備註/版面設定測試零回歸。
- `flutter test`（全專案）：**1756 個測試全數通過**，零回歸。
- `git diff --stat` 確認 vendored `foliate-js` 目錄下（`view.js`／`overlayer.js`／`epubcfi.js`／`epub.js` 等）僅 `main.js` 有變動，其餘檔案完全未觸碰。
- 交叉核對 `view.js`（`addAnnotation()`）與 `overlayer.js`（`Overlayer.add()`/`remove()`）原始碼，確認 `foliate-note:` 前綴 key 空間隔離機制真實成立（見上方 Strengths），非僅信任計畫文件敘述。

未新開額外 worktree（沿用既有的），審查結束未對其做任何清理以外的異動；本次審查所在的原始 checkout（`main` HEAD）全程未被觸碰。

## Recommendations

- 無阻擋合併的必要修正。上方兩項 Minor 建議可視情況於後續 Issue（例如 Issue 4 處理清除時機時）一併考慮，不需要為此另開工單。

## Assessment

**Ready to merge？** Yes

**Reasoning：** 三個 Task 的實作與計畫逐字對齊，`foliate-note:` key 空間隔離與 `??` 覆寫邏輯經 vendored 原始碼交叉驗證屬實而非僅計畫聲稱；四個高亮清除呼叫點與 ADR 0026「不寫入資料表」的自動化迴歸測試皆到位；`flutter analyze` 與全專案 `flutter test`（1756 項）皆通過、零回歸；未發現任何 Critical 或 Important 問題，兩項 Minor 皆為已知、已記錄且不影響正確性的邊界觀察。
