# Epic 34 Issue 11 實作計畫審查報告 (Plan Review Report)

**審查對象：** [`docs/epics/epic-34-tts-readalong/plans/plan-issue-11.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/plans/plan-issue-11.md)  
**對應工單：** [`docs/epics/epic-34-tts-readalong/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/issues.md) Issue 11（長段落缺乏終止標點時朗讀失敗——超出 TTS 引擎輸入長度上限）  
**診斷依據：**
- [`docs/epics/epic-34-tts-readalong/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/issues.md)（Issue 11 需求背景、設計要點與驗收標準）
- [`docs/epics/epic-34-tts-readalong/spec.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/spec.md)（TTS 朗讀管線、狀態機與錯誤處理規範）
- [`app/android/app/src/main/assets/foliate/main.js`](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/assets/foliate/main.js)（`window.buildTtsSegments()` 切句迴圈）
- [`app/lib/reader/tts_provider.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/tts_provider.dart)（`TtsProvider` 抽象介面）
- [`app/lib/reader/system_tts_provider.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/system_tts_provider.dart)（`SystemTtsProvider` 實作）
- [`app/lib/reader/tts_controller.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/tts_controller.dart)（`TtsController` 播放狀態機與 `_playCurrentSegment()`）
- [`app/test/support/fake_tts_provider.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/test/support/fake_tts_provider.dart)（測試 Fake Provider）
- [`app/test/reader/foliate_reader_view_test.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/test/reader/foliate_reader_view_test.dart)（`main.js` regression guard 測試）
- [`app/test/reader/system_tts_provider_test.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/test/reader/system_tts_provider_test.dart)（`SystemTtsProvider` 單元測試）
- [`app/test/reader/tts_controller_test.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/test/reader/tts_controller_test.dart)（`TtsController` 狀態機與切分測試）  
**審查日期：** 2026-08-29  
**審查結果：** **Approved（正式核准，可直接執行）**

---

## 1. 審查總結（Executive Summary）

經逐行核對現行 Codebase、既有測試架構與 Issue 11 驗收標準，[`plan-issue-11.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/plans/plan-issue-11.md) 是一份設計周密、邊界清晰且高度具備防禦性思維的實作計畫。

### 核心評估亮點：

1. **三層防禦架構層次分明、職責解耦**：
   - **第一道防線（`main.js` 次要切句邊界）**：在前端 DOM 解析端引入門檻常數 `TTS_SECONDARY_BOUNDARY_MIN_LENGTH = 200` 與 `\s`（已自然涵蓋全形空格 `\u3000`、半形空白與換行）。堅持「優先標點切句」原則，次要邊界只在「無主要標點且累積長度達標」時觸發，完全不破壞正常排版書籍的斷句行為。
   - **第二道防線（Dart 端硬性長度切分）**：`TtsProvider` 抽象介面擴充 `getMaxInputLength()`，`TtsController` 在進入播放迴圈前，依引擎實際回報上限將極端超長段落硬切為多個子段落。子段落安全繼承原始 CFI，並透過 `_capSegmentsToMaxLength` 返回的 `startOffsets` 精準校正 `lookupStartIndex` 反向查找的起始游標。
   - **第三道防線（`TtsController` 容錯與自動跳過）**：`_playCurrentSegment()` 改為 `while (true)` 容錯迴圈，單一段落合成/播放失敗時自動寫入 `ReaderConsoleLog` 診斷日誌並推進到下一段，避免單一問題段落導致整章卡死或靜默無聲。

2. **嚴密的世代防護（Generation Check）與並行安全性**：
   - Task 3 在 `play()` 的 idle 分支中新增 `provider.getMaxInputLength()` 呼叫，計畫嚴格遵循既有架構的防重入規範，將其納入 `_isLoadingSegments` 保護範圍，並在 `await` 之後立即補上 `if (_disposed || generation != _playGeneration) return;` 檢查，徹底杜絕手動導覽或連點產生的過期呼叫與狀態覆寫競態。

3. **誠實測試邊界與精準的 TDD 測試同步**：
   - 計畫在 Global Constraints 與測試策略中主動揭露 `flutter test` 環境下 WebView 渲染的誠實邊界，採用原始碼 regression guard 搭配真機樣本手動驗收；
   - 精確指出 Task 4 對 `_playCurrentSegment()` 容錯機制的修改會影響既有 2 則以「單次 `play()` 拋錯」斷言「重設回 idle」的測試，主動將其收斂為單一段落 fixture，並補上多段落自動跳過與 `ReaderConsoleLog` 診斷日誌的新增測試，邏輯嚴密。

---

## 2. 審查檢核清單（Review Checklist）

| 檢核維度 | 評估項目 | 狀態 | 備註與技術確認 |
|---|---|:---:|---|
| **規格符合度** | Issue 11 驗收標準覆蓋 | **✅ 完整** | 涵蓋無標點長段落朗讀、跨標籤句子零回歸、失敗自動跳過、`flutter analyze`/`flutter test` 乾淨。 |
| **三層防禦完整性** | JS 次要邊界 + Dart 硬切 + 狀態機容錯 | **✅ 優秀** | 三層防護互為補充，覆蓋預期與非預期之極端排版情境。 |
| **並行與防重入** | `_playGeneration` 與世代檢查 | **✅ 優秀** | `getMaxInputLength()` 呼叫前後皆有完整的世代編號與 dispose 檢查。 |
| **索引映射正確性** | `lookupStartIndex` 換算 | **✅ 精確** | `_capSegmentsToMaxLength` 使用 `startOffsets` 正確映射切分前後的游標索引。 |
| **向後相容性** | `maxInputLength == null` 處理 | **✅ 健全** | 引擎未回報上限時原樣回傳，既有測試與 `FakeTtsProvider` 零破壞。 |
| **ES 相容性** | 避免高版本 JS API | **✅ 優秀** | 僅使用基礎 RegExp、字串切片與迴圈，並納入 `check_foliate_es_compat.js` 驗證步驟。 |
| **檔案與行號精準度** | 實體檔案比對 | **✅ 精確** | `main.js`、`tts_controller.dart`、`tts_provider.dart` 等目標行號與上下文完全一致。 |
| **測試設計品質** | TDD 紅-綠循環與現有測試維護 | **✅ 健全** | 既有 2 則受影響測試精準調整情境，新增 5 則單元測試與 regression guard。 |

---

## 3. 核心設計亮點（Strengths to Preserve）

1. **`_capSegmentsToMaxLength` 的純函式設計與索引映射（Task 3）**：
   - 採用 Dart 3 Record 型別 `({List<TtsSegmentCfi> segments, List<int> startOffsets})`，將「切分後的段落清單」與「切分前索引至切分後起始位置的對照表」一次產出。
   - 解決了 `lookupStartIndex`（在切分前計算）與 `_segments`（在切分後賦值）之間的索引脫節難題，演算法簡潔且無副作用。
2. **`main.js` 次要邊界的條件防護（Task 1）**：
   - `isSecondaryBoundary` 明確要求 `!isPrimaryBoundary` 且 `(i - start) >= 200`，確保優先使用標點符號；只有在句子長達 200 字以上且遇到空白/換行時才進行安全截斷，不干擾一般正常長度的跨標籤句子。
3. **深入整合既有 `ReaderConsoleLog` 診斷機制（Task 4）**：
   - 錯誤訊息以 `[TTS Diagnostic]` 統一標記，同步輸出至 `debugPrint` 與 `ReaderConsoleLog.add()`，讓真機除錯無需透過電腦連接 `adb logcat` 即可在 App 內建畫面檢視。

---

## 4. 審查發現（Issues）

- **Critical (Must Fix)**: 無
- **Important (Should Fix)**: 無
- **Minor (Nice to Have / Observations)**:
  - **Minor 1（極端非同步暫停競態備忘）**：在 Task 4 的 `_playCurrentSegment()` 迴圈中，若在 `synthesize()` 執行期間使用者恰好按下「暫停」（`_status` 變為 `paused`），且此時 `synthesize()` 拋出異常進入 `catch (e)`：目前邏輯會記錄日誌、`_currentIndex++` 並繼續下一輪迴圈，在下一輪開頭重新將 `_status` 設為 `playing`。
    - *評估*：該競態觸發窗口極小（需同時滿足「該段語音合成失敗」且「使用者恰好在失敗前的數十毫秒內按下暫停」）；若真發生，使用者至多看到播放器跳過該壞段並繼續播放下一句，或在下一句播放時再次點擊暫停即可，不造成崩潰或死鎖。實作者可在實作時維持現狀，或在 `catch` 塊中補上一道防禦：若 `_status == TtsPlaybackStatus.paused` 則中止跳過迴圈並重設/維持暫停。此處列為 Minor 觀察，不阻礙計畫執行。

---

## 5. 實作建議（Recommendations）

1. **執行方式**：推薦直接使用 `superpowers:subagent-driven-development` 按 Task 1 至 Task 4 循序推進。
2. **真機驗收重點**：
   - 完成 Task 4 後，務必使用儲存庫 `tmp/2023大狀元經典會考經訓彙整.epub` 在真實 E-Ink 裝置上驗收無標點長章節（17,908 字 / 23,890 字）朗讀，確認不再出現 `ERROR_OUTPUT (-8)`。
   - 同步抽檢一本具備正常標點的標準 EPUB，確認常規朗讀體驗與斷句點零回歸。

---

## 6. 審查結論（Final Verdict）

- [x] **實作計畫審查正式通過（Approved）**
- **判定理由**：計畫邏輯嚴謹、三層防禦架構設計完整、狀態機並行安全性防護扎實，測試案例覆蓋率高且無破壞性變更，已具備立即投入實作之完整成熟度。
