# Epic 34 Issue 5 程式碼審查報告 (Code Review Report)

**審查對象：** `feat/epic-34-issue-5-tts-controls` 分支（commit 063efeab7..9cc64924c）
**對應工單：** docs/epics/epic-34-tts-readalong/issues.md Issue 5（上一句/下一句/語速調整控制）
**對應計畫：** docs/epics/epic-34-tts-readalong/plans/plan-issue-5.md
**審查日期：** 2026-08-28
**審查結果：** Approved with minor notes

## 1. 總結評估（Executive Summary）

本次審查比對了三個 commit（Task 1「`TtsController` 核心邏輯」、Task 2「`ReaderScreen` UI 接線」、以及合併前既有的一次「審查修正」commit）與 `plan-issue-5.md` 的逐步指示，結果是**高度一致，幾乎逐字相符**——`app/lib/reader/tts_audio_player.dart`／`app/lib/reader/tts_controller.dart`／`app/lib/screens/reader_screen.dart` 及三份對應測試檔的插入位置、方法簽章、guard 條件、Key 名稱皆與計畫文字比對相符，未發現未經說明的隨意加料。

語速契約（`review-spec.md` Minor #2：目前段落零延遲變速、下一段才用新語速合成）在程式碼與單元測試中都有確實落地與驗證：`setSpeed()` 在非 `idle` 狀態呼叫 `player.setSpeed()` 且不重新呼叫 `synthesize()`；`_playCurrentSegment()` 呼叫 `provider.synthesize()` 時帶入目前 `_speed`。`_segmentGeneration` 防重入機制（比照既有 `_playGeneration` 手法）正確涵蓋了 `nextSegment()`／`previousSegment()` 首次帶來的「連續快速呼叫、彼此重疊」情境，且 `review-plan-issue-5.md` 建議 1（`handleExternalPositionChange()` 一併使 `_segmentGeneration` 提前失效）也確實落實並有專屬單元測試驗證。

第三個「審查修正」commit（`9cc64924c`）修的是一個真實、會被使用者實際感知到的 bug：`nextSegment()` 在章節最後一句時提前 return，之前漏了呼叫 `player.pause()`——若使用者在最後一句仍在播放時按下「下一句」，畫面會顯示 `idle`（朗讀已停止），但底層播放器其實還在放最後一句的殘餘音訊，造成「畫面說停了、耳朵還聽得到」的狀態不同步。這個修正正確、有對應測試（`callLog` 包含 `pause`），且同時補上了 `_segmentGeneration++`，讓這條分支也納入既有的防重入世代保護，邏輯自洽。`ReaderScreen` 三顆按鈕的渲染條件重複三次的問題也在同一個 commit 用 collection-if spread 語法整併為一次判斷，是單純的 DRY 重構，行為等價。

`flutter analyze` 在本次審查建立的獨立 worktree（`9cc64924c` HEAD）上執行結果為 `No issues found!`；`flutter test test/reader/tts_controller_test.dart test/screens/reader_screen_test.dart` 兩份直接相關的測試檔案合計 232 個測試全數通過，含新增的 Task 1／Task 2 測試案例與第三個 commit 補上的斷言。全專案 `flutter test` 亦已於同一個 worktree 實測完成：**1789 個測試全數通過（exit code 0），零回歸**。未發現 Critical 或 Important 等級問題，僅有兩項 Minor（見下方）。

## 2. 計畫符合度檢查（Plan Alignment Checklist）

| 計畫步驟 / 驗收標準 | 實際實作狀況 | 結果 |
|---|---|---|
| Task 1 Step 1：`FakeTtsAudioPlayer.speedCalls`／`FakeTtsProvider.synthesizeSpeeds` | 逐字相符（`app/test/support/fake_tts_audio_player.dart`／`fake_tts_provider.dart`） | ✅ |
| Task 1 Step 4：`TtsAudioPlayer.setSpeed()` 抽象方法＋`JustAudioTtsPlayer` 實作（`_player.setSpeed(speed)`） | 逐字相符（`app/lib/reader/tts_audio_player.dart:16`／`:63`），確認 `AudioPlayer.setSpeed()` 為 `just_audio` 真實 API | ✅ |
| Task 1 Step 5：`TtsController._speed`／`speed` getter，初始值 `1.0` | 逐字相符（`tts_controller.dart:72-76`） | ✅ |
| Task 1 Step 6：`setSpeed()` 無條件更新 `_speed`＋非 idle 才呼叫 `player.setSpeed()`；`nextSegment()`／`previousSegment()` guard 條件（idle no-op、最後一段視同播放完畢、第一段不迴繞） | 逐字相符（`tts_controller.dart:165-224`） | ✅ |
| Task 1 Step 7：`handleExternalPositionChange()` 新增 `_segmentGeneration++`（`review-plan-issue-5.md` 建議 1） | 逐字相符（`tts_controller.dart:262`），並有專屬單元測試驗證 `player.loadedFiles` 不含過期音訊 | ✅ |
| Task 1 Step 8：`_segmentGeneration` 欄位＋`_playCurrentSegment()` 三處世代比對＋`synthesize()` 帶入 `speed: _speed` | 逐字相符（`tts_controller.dart:280-321`） | ✅ |
| Task 1 驗收：純 Dart 單元測試涵蓋 idle/playing/paused/首段/末段等邊界 | `tts_controller_test.dart` 新增 15 個測試，涵蓋 speed 三態、next/previous 各邊界、防重入、`handleExternalPositionChange` 交互、dispose 後安全性 | ✅ |
| Task 2 Step 3：`_ttsSpeedPresets`／`_nextTtsSpeedPreset()` helper | 逐字相符（`reader_screen.dart:2815-2825`） | ✅ |
| Task 2 Step 4：三顆 FAB（`reader_tts_previous_button`/`reader_tts_next_button`/`reader_tts_speed_button`），CBZ 排除、`top: 352/408/464` | 逐字相符（`reader_screen.dart:2264-2346`，第三個 commit 後改為 collection-if 但顯示條件與座標不變） | ✅ |
| Task 2 驗收：widget test 涵蓋按鈕顯示/隱藏（未提供 provider／CBZ）、點擊不崩潰、語速循環 UI 同步 | `reader_screen_test.dart` 新增 5 個 `testWidgets`，逐字相符計畫內容，含誠實測試邊界註解 | ✅ |
| 語速契約：目前段落零延遲變速、下一段才用新語速合成（`review-spec.md` Minor #2） | `setSpeed()`＋`_playCurrentSegment()` 程式碼與對應單元測試（`setSpeed() 後，自動接續下一段時 synthesize() 收到新的 speed 值`）皆確認 | ✅ |
| `flutter analyze`／`flutter test` 全數通過 | 本次審查實測：`flutter analyze` → `No issues found!`；`tts_controller_test.dart`＋`reader_screen_test.dart` 合計 232 測試全數通過；全專案 `flutter test` → 1789 個測試全數通過，零回歸 | ✅ |
| 第三個 commit（審查修正）：`nextSegment()` 末段分支補 `player.pause()`＋`_segmentGeneration++` | 正確識別並修復真實狀態不同步 bug，補上對應斷言 | ✅ |
| 第三個 commit：`ReaderScreen` 三顆按鈕渲染條件整併為 collection-if | 純重構，行為等價，未見副作用 | ✅ |

## 3. 細部技術優點（Strengths）

1. **`_segmentGeneration` 防重入設計嚴謹且有文件記錄的推理過程。** 註解明確列出四個呼叫端（`play`／`_handleSegmentCompleted`／`nextSegment`／`previousSegment`）並解釋為何前兩者天然不重疊、後兩者為何需要新機制——不是憑空加鎖，而是有清楚的因果鏈。專屬單元測試（`nextSegment() 連續快速呼叫兩次...`）用兩個可控 `Completer` 刻意讓「較舊的呼叫反而較晚完成合成」，實際驗證了世代比對能擋下過期音訊，而不是只靠邏輯推理。
2. **語速刻度不做轉換的已知限制記錄完整、多處一致。** `plan-issue-5.md` Global Constraints、`tts_audio_player.dart` 的 `setSpeed()` doc comment、`reader_screen.dart` 的 `_ttsSpeedPresets` doc comment 三處對「大於 1.0 的語速選項在下一段合成時會被 `SystemTtsProvider` 的 `clamp(0.0, 1.0)` 收斂」這件事描述一致，沒有互相矛盾或遺漏。
3. **第三個 commit 抓到並修復的 bug 是真實、可感知的體驗缺陷，而非吹毛求疵。** 使用者在最後一句仍在播放時按「下一句」，UI 若顯示 idle 但音訊仍在播，是一個會被真機測試立刻發現的落差；`player.pause()` 的補法對稱於 `handleExternalPositionChange()` 既有的 `player.pause().catchError((_) {})` 寫法，風格一致。
4. **`ReaderScreen` widget test 延續 Issue 3／4 建立的「誠實測試邊界」慣例。** 新增測試明確在測試名稱與內文註解中說明 `flutter_test` 環境下 `TtsController` 永遠不會真正進入 `playing`，只驗證 UI 接線不崩潰，並清楚指出真正的段落跳轉行為由 `tts_controller_test.dart` 涵蓋——不誇大測試涵蓋範圍。
5. **一處經確認的計畫外正向修正**：Task 1 Step 2 計畫原文對 `handleExternalPositionChange()` 測試的斷言寫的是 `expect(player.loadedFiles, isEmpty);`，但實際程式碼改為 `expect(player.loadedFiles, ['/fake/segment_1.wav']);`（`tts_controller_test.dart`）。這是正確的修正——`play()` 本身在測試一開始就已經合成並載入了第 0 段（`/fake/segment_1.wav`），計畫草稿的 `isEmpty` 斷言其實會誤判（第 0 段的 `loadFile()` 呼叫確實發生過），實作端正確地把斷言改成反映真實狀態，並在程式碼註解中說明了為什麼。
6. **語速調整不受狀態影響，`idle` 狀態下呼叫 `setSpeed()` 仍會先更新 `_speed` 並 `notifyListeners()`**，讓 UI 上的語速數字即時反映使用者的選擇，即使當下還沒開始播放——避免「調了語速結果畫面沒變」的困惑，且不會遺漏到下一次 `play()`。
7. **無違反 ADR 0011／ADR 0026 的變動**：未觸碰任何 vendored `foliate-js` 檔案；未新增任何對 `highlights`/`notes` 資料表的寫入路徑。

## 4. 問題清單（Issues）

### Critical (Must Fix)

無。

### Important (Should Fix)

無。

### Minor (Nice to Have)

#### 1. `system_tts_provider.dart` 的既有註解在 Issue 5 之後已經過時，但本次未同步更新

`app/lib/reader/system_tts_provider.dart:92-94`：

```dart
// flutter_tts 的語速範圍是 0.0（最慢）～1.0（最快），本專案呼叫端
// 目前恆傳 1.0（Issue 5 才會有語速調整 UI），clamp 純防禦。
await _flutterTts.setSpeechRate(speed.clamp(0.0, 1.0));
```

這段註解是 Issue 5 開發前寫下的「未來式」註解（預告「Issue 5 才會有語速調整 UI」），但現在 Issue 5 已經完成——`TtsController._playCurrentSegment()` 目前會把使用者實際選擇的 `_speed`（可能是 `0.5`／`0.75`／`1.5` 等非 `1.0` 值）透過 `provider.synthesize(..., speed: _speed)` 傳進來，「呼叫端目前恆傳 1.0」這句陳述已不再成立。`plan-issue-5.md` Global Constraints 明確記錄「本 Issue 不修改該檔案」，所以這是計畫刻意排除的範圍，`clamp(0.0, 1.0)` 的**行為**本身沒有錯（也如實反映在 `reader_screen.dart` 的 `_ttsSpeedPresets` 註解中），純粹是這一處**文字描述**現在對不上實際呼叫模式，可能誤導日後讀這段程式碼的人以為語速調整還沒接上這個檔案。

**建議修法**：下次觸碰 `system_tts_provider.dart` 時（或另立一個小 commit）把註解改為描述現況，例如「呼叫端（`TtsController`）現在會傳入使用者選擇的語速，經 `clamp(0.0, 1.0)` 收斂——大於 1.0 的加速選項在這裡會被統一收斂成最快速，只有播放器端 `setSpeed()` 的執行期變速才能呈現差異化效果（見 Issue 5 `plan-issue-5.md` 已知限制）」。不阻擋合併。

#### 2. 第三個 commit 新增的 `_segmentGeneration++`（`nextSegment()` 末段分支）沒有專屬回歸測試

`app/lib/reader/tts_controller.dart:192-201`（`nextSegment()` 章節末尾分支）：

```dart
if (nextIndex >= _segments.length) {
  _segmentGeneration++;
  _status = TtsPlaybackStatus.idle;
  ...
```

這次修正對 `player.pause()` 補上了測試斷言（`expect(player.callLog, contains('pause'));`），但 `_segmentGeneration++` 本身要防範的情境——「另一個 `nextSegment()`／`previousSegment()` 呼叫正在等待 `synthesize()` 回應，此時使用者又快速點擊『下一句』直到跳出章節範圍，觸發這個末段分支」——目前沒有專屬的單元測試重現並驗證「過期呼叫確實被這個世代遞增攔下、不會在章節已回到 idle 之後又意外呼叫 `player.loadFile()`」。這與計畫既有的「連續快速呼叫 nextSegment()」測試（`tts_controller_test.dart`）、以及 `handleExternalPositionChange()` 的對應測試風格一致，只是還沒有針對這個新分支複製一份。

**建議修法**：比照既有的「`nextSegment()` 連續快速呼叫兩次」測試手法，補一個「第一次 `nextSegment()` 呼叫尚在合成中、第二次 `nextSegment()` 呼叫直接跳出章節範圍」的測試，斷言第一次呼叫的合成結果完成時不會再有任何 `player.loadFile()`／狀態寫入發生。不阻擋合併，可與 Minor #1 一併留待下次觸碰此檔案時處理。

## 5. 建議（Recommendations）

- 兩項 Minor 皆不阻擋合併，可與下一次觸碰 `tts_controller.dart`／`system_tts_provider.dart` 時一併處理，或另開一個小型技術債 Issue 追蹤。
- 真機手動驗證清單（`plan-issue-5.md`「測試策略總結」5 項）已涵蓋本次審查最關注的「章節最後一句按下一句」情境（第 5 項），建議驗收時特別留意第三個 commit 修的這個 bug 是否真的在真機上感受不到「音訊殘留」。
- 語速刻度不轉換的已知限制（`clamp(0.0, 1.0)` 導致下一段合成語速被收斂）建議依計畫既有約定，在真機測試回報體感不理想時再另立校準工單，不需要現在處理。

## 6. 審查結論（Final Verdict）

- **審查結論：** Approved with minor notes——三個 commit 與計畫高度一致，語速契約與防重入機制皆有程式碼與測試雙重驗證，第三個「審查修正」commit 修復的是真實可感知的 bug 且修法正確、有對應測試。僅有兩項 Minor（一處過時註解、一處新分支缺少專屬回歸測試），皆不影響功能正確性，不阻擋合併。
- **後續步驟：** 可依 SDD 工作流程將本報告交回人類或原作者決定是否處理兩項 Minor；`flutter analyze`／目標測試檔案已於本次審查實測通過，建議合併前依 `plan-issue-5.md` 測試策略總結完成真機手動驗證清單（尤其第 5 項「章節最後一句按下一句」）。

---

**2026-08-28 追加：兩項 Minor 已修復（commit `8c9919cc`）。**
- Minor #1：`system_tts_provider.dart` 過時註解已改為描述現況（`TtsController` 會傳入使用者實際選擇的語速，經 `clamp(0.0, 1.0)` 收斂）。
- Minor #2：已補上「`nextSegment()` 合成進行中、另一次 `nextSegment()` 呼叫直接跳出章節範圍」的專屬回歸測試（`tts_controller_test.dart`），驗證過期呼叫完成後不會再呼叫 `player.loadFile()`。
- 驗證：`flutter test test/reader/tts_controller_test.dart`（48 個測試全數通過，含新增測試）、`flutter analyze`（`No issues found!`）。
