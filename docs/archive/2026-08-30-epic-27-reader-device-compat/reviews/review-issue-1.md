# Epic 27 Issue 1 程式碼審查報告

**審查對象：** commit 範圍 f804cf1..47184bc（分支 epic-27-issue1-loading-guard）
**審查目標：** 審查「`_handleZoneAction` 新增 loading 狀態防呆，避免 EPUB/PDF 載入中點擊熱區崩潰」實際程式碼變更是否忠實對應 `plans/plan-issue-1.md` 與 `issues.md` Issue 1 的驗收標準。
**審查標準：** 計畫對齊度、程式碼品質（單一權責、錯誤處理、邊界情境）、架構整合、測試有效性（含實際執行 `flutter test`／`flutter analyze` 驗證，非僅閱讀程式碼推測）。
**審查狀態：** 已完成（含實機執行測試驗證）

---

## 1. 優點與亮點 (Strengths)

1. **與計畫逐字對齊，零範圍外變更**：`git diff --stat` 顯示本次變更只觸及 `app/lib/screens/reader_screen.dart`（+9）與 `app/test/screens/reader_screen_test.dart`（+126），無其他檔案異動；`reader_screen.dart` 的兩處 `if (_state == _RenderState.loading) return;` 插入點、位置、註解文字，與 `plan-issue-1.md` Step 3 給出的程式碼片段逐字相符。`FoliateEpubReaderView`／`PdfReaderView` 內部完全未被觸碰，符合計畫「單一防呆點、不做第二層防禦」的設計決策 #1。

2. **正確辨識並修正既有測試地雷**：計畫文件中特別標註的「PDF 換頁時應清除既有選取狀態」既有測試（修改前未呼叫 `onPageRendered()`），經比對 base commit 的原始內容確認：該測試原本確實在 `_state` 仍為 `loading` 的情況下呼叫 `triggerZoneAction`，只是因為當時尚無防呆邏輯才能通過。本次變更在該測試中插入 `pdfView.onPageRendered(); await tester.pump();`，忠實對應計畫描述的修法，且未更動測試其餘斷言語意。

3. **新增測試設計精巧，在無法直接觀察 JS 呼叫的純 Dart widget test 環境下建構出有效的間接斷言**：PDF 端利用「換頁應清除選取／AnnotationToolbar 消失」這個既有副作用，反向驗證「loading 中換頁被忽略時 AnnotationToolbar 應該還在」；EPUB 端則退而求其次，僅斷言 `tester.takeException()` 為 `null`（不拋例外）。這與計畫 Global Constraints 中誠實記載的測試局限（`FakeInAppWebViewPlatform` 下 `_controller` 恆為 `null`，無法驗證真實 JS 攔截）完全吻合，測試斷言的強度與其能力上限相稱，沒有過度宣稱。

4. **回歸測試齊全**：新增了「`_state` 已是 `rendered` 後換頁行為不受影響」的顯式回歸測試（第 3 則新測試），且原有涉及此路徑的其餘測試（例如「長按拖曳框選進行中換頁應一併中止」，該測試以 30 次 100ms 輪詢等待真實非同步開檔完成，未在本次變更中被觸碰）在完整測試套件執行下也全數通過，證明此測試因等待方式本就充分而未落入計畫描述的「地雷」情境，判斷準確。

5. **架構決策合理且已用程式碼驗證**：`_handleVolumeKeyCall` 與 `TapZoneDetector` 熱區點擊皆收斂呼叫 `_handleZoneAction`，防呆加在此單一入口即同時涵蓋兩種觸發來源，不需要重複測試音量鍵路徑（`ReaderScreen.triggerZoneAction` 直接呼叫的正是同一個私有方法，架構上等價）。另外經追查 `_buildBody()`（`reader_screen.dart` 約 1971 行）確認：`_state == _RenderState.error` 時整個 body 會被替換為純文字錯誤畫面，熱區 widget 樹根本不存在，因此本次只防 `loading`、不順便防 `error` 的範圍界定是正確且充分的，不是遺漏。

6. **文件註解到位**：新增的 dartdoc 註解清楚交代了根因（`window.previousPage`/`nextPage` 賦值早於 `view.renderer` 建立的空窗期）與 `menu` 動作不受影響的理由，與 `bugfix-repro.md` 的診斷內容一致，未來讀者不需要回頭查證即可理解這行防呆的存在理由。

---

## 2. 問題與疑慮 (Issues)

經完整審查程式碼異動、比對計畫文件，並實際於獨立 git worktree（HEAD `47184bc`）執行 `flutter pub get`／`flutter test test/screens/reader_screen_test.dart`／`flutter analyze`，**未發現任何 Critical 或 Important 等級問題**。

### Critical (必須修正)
*無*

### Important (應該修正)
*無*

### Minor (建議與注意事項)

#### 【Minor #1】真機驗證仍為待辦事項（已於 2026-08-14 完成，本項解除）
- **說明：** 如計畫自身已誠實記載的已知局限，本次新增的 3 則 widget test 只能驗證 Dart 端 `_state == loading` 時提早 `return`，無法驗證真機上 JS 呼叫是否真的被攔截（`FakeInAppWebViewPlatform` 下 `_controller` 恆為 `null`）。`plan-issue-1.md` 文末「完成後的驗證」清單中，真機驗證項目原為未勾選狀態（`- [ ]`）。
- **後續狀態：** 使用者已於 2026-08-14 在真機（Mobiscribe WAVE）完成驗證：開啟較大 EPUB、在載入轉圈期間點擊左右熱區，確認不再出現 `window.nextPage is not a function` 崩潰畫面。`plan-issue-1.md` 對應勾選框已補上，本項不再是待辦事項。

#### 【Minor #2】doc 註解掛載位置略為反直覺（屬既有慣例延續，非本次引入的新問題）
- **說明：** 新增的 `epic-27-reader-device-compat Issue 1` dartdoc 區塊實際上是接在既有的「熱區動作統一分派入口」大段註解之後，而該註解整體掛在 `_handleVolumeKeyCall` 方法上方（Dart 語法上會被解讀為 `_handleVolumeKeyCall` 的文件），但內容描述的其實主要是下方的 `_handleZoneAction` 行為。此佈局在本次變更之前就已存在（原註解本就描述 `_handleZoneAction` 但掛在 `_handleVolumeKeyCall` 之上），本次只是照既有慣例接續補一段，並未新增這個問題，也完全符合計畫 Step 3 給出的精確插入位置。
- **建議：** 不需要在本 Issue 範圍內處理；若未來有機會重構這兩個方法的相對位置或拆分文件註解，可以一併修正掛載歸屬，非阻塞項目。

---

## 3. 實作建議 (Recommendations)

1. 合併前後，找一次機會完成 Minor #1 的真機驗證，並回頭把 `plan-issue-1.md` 文末驗證清單中唯一剩的 `- [ ]` 項目勾選，讓計畫文件與實際完成狀態一致。
2. 其餘無額外建議——本次變更範圍精簡、測試覆蓋與計畫設計決策高度一致，可視為本 Epic 後續 Issue（例如 Issue 2）在「小範圍防呆型修復」上的良好參考範本。

---

## 4. 評估結論 (Assessment)

- **是否可合併 (Ready to merge)？** 是
- **評估理由：**
  程式碼變更與 `plan-issue-1.md` 逐字對齊，未發現任何範圍外改動或偏離計畫的設計決策；三個計畫中要求定案的開放問題（防呆放置位置、PDF 端空窗期查證、UI 文案是否調整）皆已如計畫所述落實。實際於獨立 worktree（HEAD `47184bc`）執行 `flutter pub get` 後，`flutter test test/screens/reader_screen_test.dart` 全數 162 項測試通過（含本次新增 3 則測試與修正後的既有測試），`flutter analyze` 回報 "No issues found!"，與計畫聲稱的驗證結果一致，非僅憑閱讀程式碼推測。剩餘事項僅為 Minor 等級的流程收尾（真機最終驗收），不構成合併阻礙。
