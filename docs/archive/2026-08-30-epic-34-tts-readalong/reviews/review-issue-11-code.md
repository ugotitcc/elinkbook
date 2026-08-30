# Epic 34 Issue 11 程式審查報告——長段落缺乏終止標點時朗讀失敗

**審查範圍：** `82888906..6b8c7d92`（分支 `feat/epic-34-issue-11-tts-long-segment`，共 5 個 commit）  
**對應計畫：** [`docs/epics/epic-34-tts-readalong/plans/plan-issue-11.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/plans/plan-issue-11.md)  
**對應工單：** [`docs/epics/epic-34-tts-readalong/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/issues.md) Issue 11  
**審查方式：** `git diff` 逐行審查 + 工作樹實測 `flutter analyze`／`node tool/check_foliate_es_compat.js`／`flutter test`（單元測試、跨標籤句子與 regression guard）。全程未修改任何原始碼或被審查文件。  
**變更檔案：**
- `app/android/app/src/main/assets/foliate/main.js`（+32/-1）
- `app/lib/reader/tts_provider.dart`（+9/-0）
- `app/lib/reader/system_tts_provider.dart`（+15/-0）
- `app/lib/reader/tts_controller.dart`（+102/-27）
- `app/test/reader/foliate_reader_view_test.dart`（+60/-0）
- `app/test/reader/system_tts_provider_test.dart`（+30/-0）
- `app/test/reader/tts_controller_test.dart`（+182/-14）
- `app/test/support/fake_tts_provider.dart`（+9/-0）
- `docs/epics/epic-34-tts-readalong/plans/plan-issue-11.md`（+10/-0）

---

## 1. 核心優勢與亮點（Strengths）

1. **三層防禦架構完整落地、職責分明：**
   - **第一層（`main.js` 次要切分邊界）**：在前端切句迴圈中設置 `TTS_SECONDARY_BOUNDARY_MIN_LENGTH = 200` 與 `secondaryBoundary = /\s/`。堅持標點符號優先（`!isPrimaryBoundary` 為必要前提），只有句子累積長度達 200 字且遇到空白（含全形空格 `\u3000`、半形空白、換行）時才切句。既有跨標籤句子與 `<rt>` 過濾測試零回歸。
   - **第二層（Dart 端硬性長度切分）**：`TtsProvider` 新增 `getMaxInputLength()`，`SystemTtsProvider` 串接 `flutter_tts` 既有 `getMaxSpeechInputLength`；`TtsController` 透過純函式 `_capSegmentsToMaxLength()` 在進入播放前將極端超長段落硬切為多個子段落，並利用 `startOffsets` 正確映射 `lookupStartIndex` 反向查找游標。
   - **第三層（狀態機容錯與自動接續）**：`_playCurrentSegment()` 改為 `while (true)` 容錯迴圈，單一段落合成/播放拋出異常時不會導致整章朗讀假死，而是自動記錄 `[TTS Diagnostic]` 日誌至 `ReaderConsoleLog` 並跳至下一段。

2. **嚴密的世代防護（Generation Check）與防重入保證：**
   - Task 3 在 `play()` 的 idle 分支中新增 `final maxInputLength = await provider.getMaxInputLength();`，呼叫前後皆受 `_isLoadingSegments` 保護，並在 await 回來後嚴格執行 `if (_disposed || generation != _playGeneration) return;`，徹底防止連按播放鍵或手動導覽引發的狀態覆寫與競態。

3. **`_capSegmentsToMaxLength` 純函式演算法健全：**
   - 採用 Dart 3 Record 型別 `({List<TtsSegmentCfi> segments, List<int> startOffsets})`，回傳切分後清單與映射位移；
   - 處理 `maxLength == null || maxLength <= 0` 時無副作用原樣回傳；
   - 子段落沿用父段落 CFI，`segmentId` 採用 `${segment.segmentId}_$chunkIndex` 命名規範，且追加了「`lookupStartIndex` 恰好指向被切分段落本身」時正確定位至第一個子段落的回歸測試（commit `6b8c7d92`）。

4. **架構決策與邊界取捨交代明確（commit `6b8c7d92`）：**
   - 對於 `issues.md` 設計要點字面提到的「區塊層級標籤邊界」，程式碼與計畫文件補上了清晰的架構說明：`main.js` TreeWalker 串接 `textContent` 時刻意不合成標記，以保持 `offsetMap` 與 CFI 計算簡潔，由後方第二層（Dart 硬切）與第三層（跳段接續）安全兜底，職責劃分合理。

5. **測試設計嚴謹且現有測試無縫同步：**
   - 準確識別 Task 4 容錯修改對既有 2 則以拋錯斷言 `idle` 測試的影響，將其收斂為單一段落 fixture，並補上多段落自動跳過與 `ReaderConsoleLog` 診斷驗證；
   - `FakeTtsProvider` 預設 `maxInputLength = null`，全專案其餘 40+ 處既有 TTS 測試完全未受影響。

6. **靜態分析與相容性檢查全數通過：**
   - `flutter analyze` 顯示 `No issues found!`；
   - `node tool/check_foliate_es_compat.js` 掃描結果乾淨；
   - 相關測試檔案（`foliate_reader_view_test.dart`、`system_tts_provider_test.dart`、`tts_controller_test.dart`、`foliate_bridge_codec_test.dart`）共 216 個測試全數 PASS。

---

## 2. 審查發現（Issues）

### Critical (Must Fix)
無。

### Important (Should Fix)
無（先前審查提及之決策記錄已於 commit `6b8c7d92` 補齊）。

### Minor (Nice to Have / Observations)
1. **`_playCurrentSegment()` 非同步暫停邊界狀況備忘：**
   - 若在 `synthesize()` 執行期間使用者按下暫停（`_status` 變為 `paused`），且該次 `synthesize()` 恰好拋出例外：目前的 `catch (e)` 區塊會記錄日誌、`_currentIndex++` 並繼續下一輪迴圈，在下一輪開頭將 `_status` 重新設為 `playing`。
   - *評估*：該窗口極小且屬於容錯降級行為，不引發死鎖或崩潰，符合計畫審查預期，無需額外改動。
2. **`getMaxInputLength()` 呼叫快取考量：**
   - 目前每次播放啟動皆重新透過 MethodChannel 查詢一次長度限制。由於原生端常數查詢開銷極小，現行無快取實作已足夠輕量，後續若有整體架構整理需求可再行納入快取。

---

## 3. 實作建議（Recommendations）

1. **合併後真機驗收：**
   - 依計畫「測試策略總結」，於實體 E-Ink 裝置上開啟 `tmp/2023大狀元經典會考經訓彙整.epub`，驗證 17,908 字與 23,890 字的無標點章節可正常發聲且不再出現 `ERROR_OUTPUT (-8)`。
   - 抽檢一般排版 EPUB，確認正常書籍的朗讀與斷句體驗零回歸。

---

## 4. 審查結論（Assessment）

- **Ready to merge？** **Yes**
- **判定理由：** 程式碼品質優秀，三層防禦架構完整對齊 Issue 11 驗收標準；世代防護與並行安全性扎實；測試覆蓋全面且靜態分析乾淨，具備直接合併之品質水準。
