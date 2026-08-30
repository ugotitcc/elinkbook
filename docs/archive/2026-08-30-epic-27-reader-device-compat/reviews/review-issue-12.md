# Review — Epic 27 Issue 12：觸控硬體「彈跳」訊號導致連續失控自動翻頁

**審查範圍：** `0c500de9b887b81d07cc4e95c16a52c78beb790b..7f47290eedf8bf02907de9a379a5c0651e6adf69`
（commits `4f7653b` 實作 + `7f47290` 計畫進度歸檔）
**審查對象檔案：** `app/lib/reader/tap_zone_detector.dart`、`app/lib/reader/foliate_reader_view.dart`、`app/lib/reader/pdf_reader_view.dart`、`app/test/reader/tap_zone_detector_test.dart`
**審查方式：** 逐行比對實作計畫 `plans/plan-issue-12.md`（含其計畫審查報告 `reviews/review-plan-issue-12.md`）與實際 diff、手動逐步推算測試時間軸算術、實際執行 `flutter analyze` 與 `flutter test`（於已存在、與 head 完全一致的 worktree `.worktrees/epic-27-issue-12` 中執行，未變動主要 checkout）。

---

## Strengths

1. **狀態作用域正確、與計畫設計理由一致**：`_lastQualifyingTapUpTimeMs` 是 `_TapZoneDetectorState` 的實例欄位，九宮格每一格各自獨立一份，天生就對齊計畫「同一格熱區」的物理事實，不需要額外跨元件協調狀態。已用 `git grep` 確認全專案僅有 4 處建構 `TapZoneDetector`（`foliate_reader_view.dart:826`、`pdf_reader_view.dart:979`、測試檔 `wrap()` helper、`TapZoneDetector` class 本身），兩個生產呼叫端皆已補上 `tapDebounceMs: 350`，無漏改。
2. **「冷卻窗隨每次彈跳延展」的設計已逐行追蹤確認正確**：`onPointerUp` 內，只要 `elapsed`/`distance` 判定成立（進入合格點擊分支），`_lastQualifyingTapUpTimeMs = now;` 這一行**無條件**執行——不論這次是否真的會呼叫 `widget.onTap()`。也就是說任意長度的連續彈跳序列，每一次都會刷新冷卻窗基準時間，確實只會放行序列中的第一次，與文件註解及計畫描述完全相符。
3. **`tapDebounceMs` 真的是 `required` 建構參數**，且與既有 `tapMaxDurationMs`／`tapSlop` 的既定慣例（呼叫端明確注入、不設 module 內共用預設值）保持一致。
4. **與音量鍵翻頁完全無互動**：已追查 `reader_screen.dart` 的 `_handleVolumeKeyCall` 直接呼叫 `_handleZoneAction`，完全繞過 `TapZoneDetector`，音量鍵翻頁不受本次防彈跳窗口影響。
5. **與 PDF 自身的長按拖曳框選手勢無互動**：`pdf_reader_view.dart` 的拖曳選取邏輯（`_activePointerCount`／`_cancelSelectionDrag`）是 Stack 中另一個獨立的 `Listener`，與疊加在上層的 `TapZoneDetector` 九宮格各自獨立判讀同一組觸控事件，防彈跳邏輯只影響 `onTap` 是否觸發，不影響選取拖曳判斷。
6. **`onPointerCancel` 不清除 `_lastQualifyingTapUpTimeMs` 是正確決策**：`onPointerCancel` 本來就不會進入「合格點擊」分支，因此無論清不清除都不影響行為；而該欄位本來就該在單次按壓的 down/up 週期之間存活（這正是吸收彈跳序列的核心機制），刻意不清除是合理、經過推敲的設計。
7. **數值選擇有實證支撐**：對照 `bugfix-repro.md`「Issue 10」新問題 B 段落原始側錄資料（第一段 7 次按下、相鄰間隔 86～326ms），350ms 大於已觀測到的最大間隔 326ms，且計畫「設計決策 3」明確承認這是根據目前證據推出的起始值、日後真機使用可能需要另立工單校準（並非包裝成一勞永逸的定案）。
8. **驗證結果全數通過**：`flutter analyze` 乾淨（"No issues found!"）；`tap_zone_detector_test.dart` 8 則測試全數 PASS；全專案 `flutter test` 共 1654 個測試全數 PASS、零回歸（實際執行確認，非僅閱讀程式碼推測）。

---

## Issues

### Critical (Must Fix)

無。

### Important (Should Fix)

**1. ~~「重現真機側錄間隔」回歸測試的時間推算未套用計畫審查已核准的精確度修正，實際不是精確重播真機資料~~——已處理（`9c15ec3`）**

- 檔案：`app/test/reader/tap_zone_detector_test.dart`，測試「重現真機 adb getevent 側錄到的實際硬體彈跳間隔序列，連續 7 次快速觸發只會觸發 1 次 onTap」
- 計畫 `plan-issue-12.md`（Step 1，經 `review-plan-issue-12.md` Minor 1 建議修正後的版本）明確寫出：
  ```dart
  for (final gapMs in observedGapsMs) {
    fakeNowMs += gapMs - 20;   // 先扣掉本次模擬按壓耗時，確保 DOWN-to-DOWN 間隔精確等於 gapMs
    ...
  }
  ```
  並附上完整說明「確保兩次 `startGesture()` 之間量到的 DOWN-to-DOWN 間隔精確等於 `gapMs` 本身」。
- 實際交付的程式碼卻是：
  ```dart
  final bounceIntervalsMs = [86, 152, 261, 326, 87, 207];
  final firstGesture = await tester.startGesture(const Offset(50, 50));
  fakeNowMs += 30;                 // 計畫版本此處是 20ms
  await firstGesture.up();
  ...
  for (final interval in bounceIntervalsMs) {
    fakeNowMs += interval;         // 沒有扣掉前次持壓時間，與計畫版本不同
    final bounceGesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 20;
    await bounceGesture.up();
  }
  ```
  即計畫核准的「先扣減再相加」精確度修正**沒有**被實作採用，變數命名（`observedGapsMs` → `bounceIntervalsMs`）與註解內容也不同，看起來是實作時用了另一版更簡化的草稿，而非計畫文件裡經審查核准的版本。

  **已處理**：`9c15ec3` 補上 `interval - 20` 的扣減，並將首次按壓耗時由 30ms 改回計畫版本的 20ms，確認重播出來的最大 DOWN-to-DOWN 間隔精確等於真機側錄值 326ms（而非 346ms）。修正後重跑 `flutter test test/reader/tap_zone_detector_test.dart`（8 則全過）與全專案 `flutter analyze`／`flutter test`（1654 項，零回歸，含一次因無關的 `remote_catalog_screen_test.dart` 偶發性 flaky 測試導致的失敗，重跑後確認與本次改動無關、乾淨通過）。
- **實際影響（已逐步手算驗證）**：由於每次迴圈相加的是「原始 gap」而非「gap − 前次持壓時間」，實際重播出來的 DOWN-to-DOWN 間隔會比真機側錄值多出前次持壓時間（首次 30ms、之後每次 20ms）：

  | 真機側錄（原始） | 86 | 152 | 261 | 326 | 87 | 207 |
  |---|---|---|---|---|---|---|
  | 測試實際重播出的 DOWN-to-DOWN | 116 | 172 | 281 | **346** | 107 | 227 |

  測試實際涵蓋的最大間隔是 **346ms**，不是真機側錄到的 326ms（也不是任何一次測試內部註解宣稱的數值——實際程式碼裡的註解已經沒有再宣稱「精確重播 DOWN-to-DOWN」這件事，只泛稱「6 段彈跳間隔」，所以程式碼本身沒有說謊；但測試**方法名稱**「重現真機...實際硬體彈跳間隔序列」與計畫文件的精確度承諾對不上）。
- **是否影響正確性**：不影響。346ms 仍小於 350ms 門檻，測試依然是有效的迴歸測試，甚至可以說是「更嚴苛版本」的重播（用比真機更大的間隔去驗證仍能被吸收），並未讓測試更容易通過或掩蓋任何缺陷。因此**不是功能性錯誤**，只是「實作結果與計畫核准版本不一致」＋「測試名稱／描述略為誇大精確度」的落差。
- **建議處理方式**：二擇一——(a) 按計畫原文補上 `fakeNowMs += gapMs - 20`（並將首次持壓改回 20ms）讓測試真正精確重播真機 DOWN-to-DOWN 間隔；或 (b) 保留目前寫法，但把測試名稱／註解改為誠實描述「以真機側錄間隔為基礎、經過保守放大的重播」，避免文件（計畫）與程式碼（測試）兩邊對「是否精確重播」這件事各說各話。不阻塞合併，建議另開小工單或下次順手修正。

### Minor (Nice to Have)

**1. `onPointerUp` 實際採用的收尾風格與計畫文件裡的 Step 3 程式碼草稿不同（但方向是更好的一邊）**

- 計畫 `plan-issue-12.md` Step 3 的程式碼草稿使用「提早 `return`」風格（婉拒了 `review-plan-issue-12.md` Minor 2 建議的單一出口寫法），本次交辦的任務描述也是依此草稿轉述「作者已明確婉拒單一出口重構」。
- 但實際交付的 `tap_zone_detector.dart:99-112`：
  ```dart
  if (previousTapUpTimeMs == null ||
      now - previousTapUpTimeMs >= widget.tapDebounceMs) {
    widget.onTap();
  }
  ```
  並**沒有** `return`，反而正是計畫審查 Minor 2 建議的單一出口寫法。也就是說，實際程式碼與計畫文件的 Step 3 草稿本身不一致——不是「婉拒了建議、維持提早 return」，而是最終產出**採用了**審查建議的版本。
- 功能上兩種寫法完全等價（本次已用測試與人工邏輯推演確認皆正確），這個落差本身無害、甚至讓程式碼更乾淨（`onPointerUp` 現在只有最上方 guard clause 那一處提早 `return`，其餘邏輯是巢狀 if 包裹，減少多重出口）。列為 Minor 純粹是提醒：不能只憑計畫文件裡的程式碼草稿判斷最終行為，這次交辦任務描述引用的「作者婉拒建議」這個前提與實際程式碼不符。
2. **350ms 需要真機校準的但書只留在計畫文件、沒有反映在原始碼註解裡**：`tap_zone_detector.dart` class doc 與兩個呼叫端目前的行內註解只說明機制本身與「Epic 27 Issue 12」出處，並未在原始碼裡重申「這個數值可能需要真機使用後再校準、有誤傷刻意快速連點的風險」——這段但書目前只寫在 `plan-issue-12.md`「設計決策 3」裡。日後只看原始碼（不回頭查計畫文件）的工程師可能不會注意到這是待驗證數值。建議在 `tapDebounceMs: 350,` 旁補一行簡短提示並指向 Epic 26 Issue 3 / Epic 25 Issue 1 的先例即可，不必大改。
3. **一個未在本 Issue 範圍內、但被本次改動放大的既有互動邊界情況，值得記錄追蹤**：EPUB 端 `onTap` 內的 `if (_hasActiveSelection) return;`（Epic 25 Issue 1 既有防呆）是在 `TapZoneDetector.onPointerUp` 判定「合格點擊」**之後**才被檢查——也就是說 `_lastQualifyingTapUpTimeMs` 的更新，發生在 `_hasActiveSelection` 判斷之前。若使用者長按選字但幾乎沒有拖曳（停留在 `tapSlop` 內、耗時在 `tapMaxDurationMs` 內，Issue 9 的移動熔斷不會介入），放開手指時會被判定為一次「合格點擊」並刷新該格熱區的冷卻窗，即使因為 `_hasActiveSelection` 為真而沒有真正觸發翻頁。若使用者緊接著在 350ms 內於同一格熱區點擊一次意圖翻頁的操作，該次操作可能被防彈跳機制誤吸收。此情境較窄（多數選字手勢都會有明顯拖曳、會被 Issue 9 熔斷排除），非本次改動引入的新 bug、也不在 Issue 12 驗收範圍內，但值得記錄，供日後真機測試觀察是否真的發生。

---

## Recommendations

- 建議另開一個小工單（或直接在下一次順手修正）處理上方 Important 1，讓測試與計畫文件對「是否精確重播真機 DOWN-to-DOWN 間隔」的說法一致，避免未來有人依據測試名稱誤以為間隔數值是逐位元精確重播。
- 建議在真機驗證階段，除了既有的「連續快速按壓同一熱區」與「間隔明顯的刻意連續翻頁」情境外，額外驗證一次「長按選字放開後，緊接著快速點擊同一熱區翻頁」的操作手感，對照 Minor 3 的邊界情況觀察是否有感。
- `plan-issue-12.md` 目前保留了「設計決策」與驗收 checklist（已全部打勾），但 Step 1～6 的詳細程式碼草稿已在完成後被清空——這是這個專案既有的計畫歸檔慣例，沒有問題，只是提醒未來若要「以計畫文件程式碼片段核對實作」，須拿完成前的版本（本次是用 base SHA `0c500de9b8`）才看得到完整草稿。

---

## Assessment

**Ready to merge？** Yes（可直接合併）

**Reasoning：** 核心防彈跳機制（`_TapZoneDetectorState._lastQualifyingTapUpTimeMs` 滾動冷卻窗）經逐行追蹤與獨立人工邏輯推演確認正確、範圍界定精準（僅影響對應熱區格子的 `onTap`，不影響音量鍵翻頁與 PDF 拖曳選取），`flutter analyze` 乾淨、`tap_zone_detector_test.dart` 8 則測試與全專案 1654 則測試皆實際執行通過、零回歸。發現的唯一 Important 問題（真機側錄間隔重播測試未套用計畫核准的精確度修正）不影響功能正確性、測試仍然有效且方向偏保守（用更大的間隔驗證吸收效果），不構成合併阻礙，建議列入後續小修但不必卡關本次交付。
