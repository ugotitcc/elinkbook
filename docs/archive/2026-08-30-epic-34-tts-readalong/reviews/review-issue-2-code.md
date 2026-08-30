# Epic 34 Issue 2 程式碼審查報告（Code Review）

**審查對象：** `feat/epic-34-issue-2-tts-readalong-mvp` 分支
**Base：** `4dd57c80acb559ca2af6d2d790a9bd9ec6dbf77f`
**Head：** `527f751e45131577e802add337ab221a024941a2`
**對應計畫：** `docs/epics/epic-34-tts-readalong/plans/plan-issue-2.md`
**審查日期：** 2026-08-27

---

## 審查方式說明

本次審查逐一比對 8 個 commit（`999f8117`～`527f751e`）與計畫檔案的對應 Task/Step，並在獨立的 `git worktree`（`/tmp/review-tts-issue2`，不影響本機工作目錄的 `main` checkout）實際執行：

- `flutter pub get`（成功，`pubspec.lock` diff 只新增 `flutter_tts`／`just_audio`／其 transitive 依賴，`share_plus`/`file_picker`/`package_info_plus`/`win32` 版本無變動，符合計畫 Task 1 Step 3 驗收）
- `flutter test test/reader/tts_provider_test.dart test/reader/system_tts_provider_test.dart test/reader/tts_controller_test.dart test/reader/foliate_bridge_codec_test.dart` → **74 個測試全數 PASS**
- `flutter test test/screens/reader_screen_test.dart` → **177 個測試全數 PASS**（含新增 3 個 TTS 測試）
- `flutter test`（全專案）→ **1739 個測試全數 PASS**，零回歸
- `flutter analyze` → `No issues found!`
- `node app/tool/check_foliate_es_compat.js` → 結束碼 0（乾淨）

以上皆為本次審查實際執行取得的結果，非採信 commit message 或計畫勾選狀態。

---

## Strengths

1. **與計畫的一致性極高。** 8 個 commit 逐一對應計畫 Task 1～7，型別簽章（`TtsProvider.synthesize()`、`TtsAudioPlayer` 四個方法、`TtsSegmentCfi` 三欄位、`TtsController` 建構子參數）與計畫程式碼區塊逐字相符，未發現未經說明的隨意偏離。
2. **測試金字塔實作確實。** `TtsController` 以 TDD 方式開發（先寫失敗測試、再寫實作），13→15 個測試涵蓋 idle/playing/paused 全狀態轉換、自動接續、例外重設、防重入，且測試斷言的是行為（呼叫順序 `callLog`、狀態值），不是空殼 mock 驗證。
3. **`main.js` 的 `<rt>`/`<script>` 過濾與跨標籤 Range 建構思路正確。** 兩階段（先建 `offsetMap` 再切句）避免了單階段跨 TextNode 邊界的狀態機錯誤，`view.getCFI()` 復用既有 API、未重新發明 CFI 轉換邏輯，符合 CLAUDE.md「不修改 vendored foliate-js、只擴充自有整合層」的原則。
4. **`FoliateReaderView.loadTtsSegments()` 的逾時防禦（5 秒）是真實有價值的健壯性補強**，避免 JS 端異常無回呼時呼叫端永久卡死——且沒有濫用逾時來掩蓋其他問題，逾時後乾淨回傳空清單並清空 `_pendingTtsSegments`。
5. **`system_tts_provider_test.dart` 對 `flutter_tts` MethodChannel 的 mock 手法紮實**，透過 `handlePlatformMessage` 模擬原生端非同步回呼 `synth.onComplete`/`synth.onError`，是真正驗證行為而非驗證呼叫存在。移植到本機（Windows）環境時測試作者用 `p.join()` 取代計畫原文的硬編碼 `/` 分隔符斷言，是正確的跨平台修正（優於計畫原文）。
6. **最後一個 commit（`527f751e`）本身是一次有意義的程式碼審查後修復**：把 `_status = playing` 的時機從「`synthesize()`＋`loadFile()` 都完成後」提前到「呼叫 `synthesize()` 之前」，確實關閉了「`loadSegments()` 完成、`_isLoadingSegments` 已重設為 `false`，但 `synthesize()` 尚未完成」這段期間的連點 `play()` 競態視窗（因為 Dart 同步執行直到第一個 `await`，`_status = playing` 與呼叫 `_playCurrentSegment()` 之間沒有讓出執行權的機會）。新增的防重入測試也確實可重現且驗證了這個修復。
7. **CBZ 排除方式符合驗收標準**：`isFoliateFormat(BookFormat.cbz)` 為 `true`，按鈕確實會被建構（非隱藏），但 `onPressed: null` 明確停用並附帶說明 tooltip，測試（`CBZ 格式提供 ttsProvider 時，TTS 按鈕顯示但為停用狀態`）也直接斷言 `button.onPressed` 為 `null`，不是只斷言按鈕存在。
8. **`ReaderScreen` 整合零回歸**：`ttsProvider` 為可選建構參數，未提供時完全不建構 `_ttsControllerOrNull`、不顯示按鈕，比照既有 `bookmarksRepository`/`highlightsRepository` nullable 慣例，`dispose()` 也補上了 `_ttsController?.dispose()`。

---

## Issues

### Critical (Must Fix)

無。未發現會導致崩潰、資料遺失或安全性問題的缺陷。

### Important (Should Fix)

#### 1. `pause()` 在朗讀段合成/載入期間呼叫時，不會真的停止播放，且會讓自動接續下一句永久卡死

**檔案：** `app/lib/reader/tts_controller.dart:81-86`（`pause()`）與 `:98-118`（`_playCurrentSegment()`）

修復 commit `527f751e`把 `_status = TtsPlaybackStatus.playing;` 提前到 `_playCurrentSegment()` 的 `try` 區塊最開頭（第 101-102 行），早於 `await provider.synthesize(...)`（第 103-106 行）與 `await player.loadFile(...)`（第 108 行）。這正確關閉了「連點 `play()`」的競態視窗（見 Strengths #6），但同時打開了另一個沒有被對應測試覆蓋的新視窗：

- `_status` 從呼叫 `_playCurrentSegment()` 那一刻起就已經是 `playing`，但 `player.play()` 要等到 `synthesize()`＋`loadFile()` 都完成後（第 110 行）才會真的被呼叫。
- 若使用者在這段「顯示暫停圖示、但實際上音訊還沒開始播放」的視窗內按下暫停鍵，`pause()`（第 81-86 行）的守衛 `if (_status != TtsPlaybackStatus.playing) return;` 會通過（因為 `_status` 已經是 `playing`），於是把 `_status` 設為 `paused` 並呼叫 `player.pause()`——但此時 `player` 尚未 `loadFile()`/`play()`，這個 `pause()` 呼叫對它而言是操作在一個還沒有音源的播放器上，不會有任何實際效果。
- 接著 `synthesize()`／`loadFile()` 完成，`_playCurrentSegment()` 並**沒有再檢查 `_status` 是否仍是 `playing`**，第 110 行 `await player.play();` 會無條件執行——於是音訊真的開始播放，但 UI（`AnimatedBuilder` 依 `controller.status` 決定圖示，`reader_screen.dart:2214` 附近）顯示的是「暫停」狀態下對應的播放鍵圖示，狀態與實際播放行為不一致。
- 更嚴重的是，這段音訊播放結束後觸發 `player.completedStream` → `_handleSegmentCompleted()`（第 120-133 行），但該方法第 122 行 `if (_status != TtsPlaybackStatus.playing) return;`——因為 `_status` 目前是 `paused`（使用者剛才按下暫停時被設定的值，之後沒有任何程式碼改回來），這裡會直接 `return`，**不會接續播放下一句**。使用者接下來即使再按一次「播放」鍵（此時圖示顯示的是播放鍵，因為 `_status == paused`），`play()` 的 `paused` 分支（第 61-66 行）只會呼叫 `player.play()`——但該次播放的音訊檔早已播放完畢，朗讀就此卡住，整個章節朗讀流程提前終止，且沒有任何錯誤訊息或狀態能提示使用者發生了什麼事。

**為什麼重要：** 這條路徑觸及的正是本 Issue 的核心交付物「可暫停/繼續」。`flutter_tts.synthesizeToFile()` 在真機上對一句較長中文句子的合成耗時通常有感（非零，可能是數百毫秒等級），此視窗並非理論上才存在的極端情況，而是每一句朗讀段轉換時都會重複出現的常態窗口；使用者在等待朗讀開始的當下按下暫停鍵，是完全合理、可預期會發生的操作。

**如何修復（建議方向，非唯一解）：** 在 `player.loadFile()` 完成後、呼叫 `player.play()` 之前，重新檢查 `_status` 是否仍為 `playing`（未被中途的 `pause()`/`dispose()` 改變）：

```dart
await player.loadFile(result.audioFilePath);
if (_disposed || _status != TtsPlaybackStatus.playing) return;
await player.play();
```

需要注意的是：若在 `_status` 已變成 `paused` 時仍然完成了 `loadFile()`，之後使用者再按下「播放」（`play()` 的 `paused` 分支）呼叫 `player.play()` 才會是符合預期的行為——上述修改讓「檔案已就緒但不自動播放」與「使用者主動點播放才真的出聲」正確對齊。建議針對這個情境（合成期間按下暫停）補一個新的 `TtsController` 單元測試，重現「`pause()` 在 `synthesize()`/`loadFile()` in-flight 期間被呼叫」的情境，斷言 `player.callLog` 不含多餘的 `play`，且事後呼叫 `play()` 能正確恢復。

---

### Minor (Nice to Have)

1. **`system_tts_provider.dart` class doc 描述了一個未實作的清理責任。**
   `app/lib/reader/system_tts_provider.dart:12-13`（class doc）寫道「呼叫端（`TtsController`）負責在播放完成/切換書籍/dispose 時視需要清除該檔案」，但檢視全部 diff，`TtsController`／`ReaderScreen` 皆未有任何刪除 `elinkbook_tts/current_segment.wav` 的程式碼。由於本 Issue 採固定單一檔名、每次覆寫（Global Constraints 已言明），暫存檔不會無限累積，此處並非功能性缺陷，但文件描述了一個實際不存在的責任歸屬，容易誤導後續維護者以為別處已經處理。建議調整註解措辭，或在後續 Issue（切換書籍/App 關閉時）補上實際清理邏輯後再讓文件與程式碼一致。

2. **`main.js` `buildTtsSegments()` 的標點切句規則在連續終止符號時可能產生單字元空段。**
   `app/android/app/src/main/assets/foliate/main.js` 新增區塊（約第 507-556 行）中，`terminators = /[。！？；.!?;]/` 逐字元掃描；若原文出現連續兩個終止符號（例如「真的假的？！」「等等......」中的省略號句點序列，或「?!」），第二個終止符號會單獨形成一個只含該符號本身的朗讀段（因為 `start = i + 1` 後緊接著下一輪迴圈 `rangeStart === i`，`trimmed` 就是那個單一符號）。這不影響本 Issue 播放功能本身（系統 TTS 唸一個單獨標點頂多是無聲或極短的雜音），但 Issue 3（同步高亮）接手後，畫面上會短暫高亮一個只有標點符號的區塊，觀感不佳。建議在切句迴圈中，若新段落 `trimmed` 長度為 1 且該字元本身也是 `terminators` 之一，考慮併入前一段而非獨立成段（可留到 Issue 3 一併處理，非阻塞本 Issue）。

3. **`main.js` 新增區塊末尾多出一個空白行。**
   `app/android/app/src/main/assets/foliate/main.js` diff 中 `window.buildTtsSegments` 函式結尾後有兩個連續空行才接續下一段既有註解區塊，屬純風格瑕疵，不影響功能。

4. **`TtsController.pause()` 與 `play()` 的 paused 分支對 `player.pause()`/`player.play()` 回傳的 `Future` 皆未附加錯誤處理。**
   `app/lib/reader/tts_controller.dart:81-86`（`pause()`）中 `player.pause();` 是 fire-and-forget，若 `just_audio` 在無音源或狀態不符時對 `.pause()` 拋出非同步例外（例如 `PlayerException`），會成為沒有 `Zone`/`catchError` 承接的未處理例外。目前程式庫其餘非同步呼叫多半有类似容忍度（比照既有 `catch (_)` 慣例），但這裡是新增程式碼、且直接與真機 TTS/音訊硬體互動，實際行為只能在真機上驗證（呼應計畫「測試策略總結」列出的「無法自動化、須真機手動驗證」項目）。建議在合併前的真機手動驗證清單中，額外加入「連續快速點擊播放/暫停鍵」這個情境，確認沒有未捕捉例外造成的 App 崩潰或主控台噴錯。

5. **`FoliateReaderView._pendingTtsSegments` 沿用既有 `_pendingToc` 的單欄位（非佇列）設計，若未來被多處併發呼叫會靜默丟失前一個請求。**
   `app/lib/reader/foliate_reader_view.dart:513`（欄位宣告）與 `:635-646`（`_requestTtsSegments`）目前只有 `TtsController.loadSegments` 這一個呼叫端，且已被 `_isLoadingSegments` 防重入旗標保護，實務上不會觸發。純粹記錄一個既有模式（`_pendingToc` 也是同樣設計）被複製到新功能上的既知限制，供未來如果有第二個呼叫端（例如背景預先擷取下一章朗讀段）時參考，非本 Issue 的缺陷。

---

## Recommendations

1. **合併前建議先處理 Important #1**，因為它直接影響「暫停」這個本 Issue 的核心驗收項目在真機上的實際可靠性，而且现有測試套件（`tts_controller_test.dart` 15 個測試）目前沒有任何一個案例覆蓋「暫停鍵在合成/載入期間被按下」這個情境，修復後應補上對應測試以避免回歸。
2. 計畫「測試策略總結」明確列出 4 項僅能在真機手動驗證的項目（`buildTtsSegments()` 對真實 DOM 的切句與跨標籤 CFI、`SystemTtsProvider` 真實合成、`JustAudioTtsPlayer` 真實播放與 `completedStream`、端到端播放/暫停/自動停止）——依 CLAUDE.md「兩層測試架構」的既有慣例，這些項目在 `app/test/` 的驗證範圍內天然無法涵蓋，屬合理且誠實揭露的邊界；**但截至本次審查的 diff 範圍內，沒有看到任何 `app/integration_test/` 新增或修改的檔案**，代表這些真機項目目前完全依賴人工手動驗證、沒有自動化的 device-level 回歸防護網。若本 Epic 後續 Issue（3/5/6/7）預計在此基礎上疊加更多真機相依邏輯，建議評估是否值得在後續 Issue 補一個最小的 `integration_test/tts_readalong_test.dart`，至少涵蓋「按下播放後 `reader_tts_play_pause_button` 圖示確實變成暫停」這類可觀察斷言，降低純人工驗證的長期成本。
3. Minor #1（文件描述與實作不符）建議在下一次觸碰 `system_tts_provider.dart` 時順手修正措辭，避免持續誤導。

---

## Assessment

**Ready to merge？** With fixes

**Reasoning：** 本次實作在架構分層、測試紀律與既有慣例的對齊上水準很高，`flutter analyze`／全專案 `flutter test`（1739 測試）／ES 相容性掃描皆乾淨通過，CBZ 排除、可選依賴注入零回歸等驗收標準也都有對應測試斷言而非空談。但 Important #1（`pause()` 在合成/載入期間被呼叫時無法真正停止播放，且會讓後續自動接續永久卡死）是一個會直接影響本 Issue 核心交付物（播放/暫停）在真機上實際可靠性的狀態機缺陷，且目前的 15 個 `TtsController` 單元測試沒有任何案例覆蓋這個情境，建議修復並補測試後再合併。

---

## 複審（Re-Review）— commit `159e9de7`

**複審對象：** `fix(epic-34): 依審查報告修訂 TtsController 合成載入期間暫停防禦與狀態機守衛`（`159e9de70a398dd0e6366c476801c4de47e582b1`，堆疊在原審查的 `527f751e` 之上）
**複審日期：** 2026-08-27
**複審方式：** 另開獨立 `git worktree`（`/tmp/review-tts-issue2-v2`，未觸碰任何既有 checkout／worktree）於 `159e9de7` 實際執行 `flutter pub get`／`flutter test test/reader/tts_controller_test.dart`／`flutter test`（全專案）／`flutter analyze`／`node app/tool/check_foliate_es_compat.js`，並逐行比對 diff 邏輯，非僅採信 commit message。

### 驗證結果

- `flutter test test/reader/tts_controller_test.dart` → **16 個測試全數 PASS**（原 15 個 + 新增 2 個，含本次要複審的兩個關鍵案例）。
- `flutter test`（全專案）→ **1741 個測試全數 PASS**（較上一輪 1739 個增加 2 個，零回歸）。
- `flutter analyze` → `No issues found!`
- `node app/tool/check_foliate_es_compat.js` → 結束碼 0（乾淨）。

### Important #1 覆核：已修正

`app/lib/reader/tts_controller.dart` 的 `_playCurrentSegment()` 把 `await player.loadFile(result.audioFilePath);` 之後的守衛從 `if (_disposed) return;` 改為 `if (_disposed || _status != TtsPlaybackStatus.playing) return;`。這精確對應審查建議的修法方向：

- 若使用者在 `synthesize()`／`loadFile()` 進行中按下暫停，`_status` 會變成 `paused`；`loadFile()` 完成後，新守衛會攔截，**不再呼叫 `player.play()`**——音訊不會在使用者已經按下暫停之後才突然開始播放。
- 新增的兩個測試（`play() 於 synthesize() 進行中呼叫 pause()...`／`play() 於 loadFile() 進行中呼叫 pause()...`）精確重現了原審查報告描述的兩個中斷點（`synthesize()` 進行中、`loadFile()` 進行中），並斷言：`player.callLog` 不含多餘的 `play`、`controller.status` 維持在 `paused`、事後使用者主動呼叫 `play()` 能正確恢復播放且 `currentIndex`/自動接續邏輯正常運作（測試甚至延伸驗證了恢復播放後下一句能正常自動接續，覆蓋面比我原本建議的更完整）。
- 我在原審查中同時指出的連鎖後果——`_status` 卡在 `paused` 會讓 `_handleSegmentCompleted()` 的 `if (_status != playing) return;` 守衛擋下自動接續，導致整個章節朗讀「靜默卡死」——由於 `player.play()` 從未被錯誤呼叫，音訊根本不會播放也不會觸發 `completedStream`，因此這條連鎖失效路徑已隨根因一併排除，不需要額外處理。
- 我在原審查中沒有明確要求、但實作額外主動補上的防禦（超出建議範圍但屬正確方向）：
  - `pause()` 內的 `player.pause()` 呼叫包了 `try { ... } catch (_) {}`（`tts_controller.dart:92-95`）。
  - `play()` 的 `paused → playing` 分支內 `await player.play();` 也包了 try-catch，失敗時正確重設回 `idle`（呼應原本 Minor #4 的顧慮）。
  - `system_tts_provider.dart` 的 class doc 已改寫，不再宣稱「`TtsController` 負責清理暫存檔」這個實際不存在的責任（Minor #1 已修正）。
  - `main.js` 多餘的空白行已移除（Minor #3 已修正）。

### 殘留的技術細節（不影響本次判定，僅記錄供後續參考）

`pause()`（`tts_controller.dart:88-95`）目前是：

```dart
void pause() {
  if (_status != TtsPlaybackStatus.playing) return;
  _status = TtsPlaybackStatus.paused;
  notifyListeners();
  try {
    player.pause();
  } catch (_) {}
}
```

`player.pause()` 回傳 `Future<void>`（`JustAudioTtsPlayer.pause() => _player.pause();`，非 `async` 函式本體、呼叫端也沒有 `await`）。這裡外層的 `try/catch` 只能攔截「呼叫當下同步拋出」的例外，若 `_player.pause()`（`just_audio` 底層）是回傳一個之後才 reject 的 `Future`（多數平台 channel 型 API 的常見模式），這個 `catch` **攔不到**，仍會成為未被承接的非同步例外。這是原審查 Minor #4 提出的顧慮的一個技術性殘留角落，嚴重度仍是 Minor（充其量在主控台噴出例外訊息，不影響本次 Important #1 的判定，也不阻擋合併），但既然這次修訂已經主動加了 `try/catch`，值得記錄：若要徹底堵住，需要 `player.pause().catchError((_) {})` 這種對 Future 本身掛載錯誤處理器的寫法，而非包一層同步 `try/catch`。建議留待下次觸碰此檔案時一併處理，非阻塞项目。

### 複審結論

原審查提出的唯一一項 Important 問題已被正確、完整地修正，且修正範圍比我建議的最小修法更完整（額外處理了 `paused→playing` 恢復路徑與 `pause()` 呼叫本身的例外防禦）；三項 Minor（#1 文件不實、#3 多餘空行）也一併修正。全專案測試（1741 個）、`flutter analyze`、ES 相容性掃描皆乾淨通過，零回歸。

**Ready to merge？（複審後）** Yes

**Reasoning：** 阻擋合併的唯一 Important 缺陷已修復並有對應測試覆蓋（含兩個直接重現原缺陷場景的新測試），其餘為文件/風格層級的 Minor 修正，且都已處理。殘留的 `pause()` 非同步例外處理角落是既存 Minor 等級的技術細節，不影響本次判定。
