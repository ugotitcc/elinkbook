# Epic 28 Issue 1：流式 EPUB 版面設定新增字距選項 程式審查報告

- **審查對象**：`feature/epic28-letter-spacing` 分支（`0475ebe`..`d306c0c`，4 個 commit，對應 `plan-issue-1.md` Task 1-4）
- **審查方式**：`git diff main...feature/epic28-letter-spacing` 逐行核對程式碼與測試、對照 `plan-issue-1.md`／`design.md`／`spec.md`；獨立執行 `flutter analyze` 與全部受影響測試檔案（非僅信任計畫文件的「預期結果」敘述）

---

## 1. 驗證結果

- `flutter analyze`：**No issues found!**
- `flutter test test/reader/book_reader_prefs_test.dart test/reader/reader_prefs_manager_test.dart test/reader/foliate_epub_reader_view_test.dart test/screens/reader_settings_sheet_test.dart test/library/sqlite_library_repository_test.dart`：**223 項全數通過**
- `git diff --stat` 確認改動範圍與 `plan-issue-1.md` 宣告的檔案清單一致，4 個 commit 訊息與 Task 1-4 一一對應

## 2. 優點

1. 完整、忠實地執行了 `plan-issue-1.md` 的每一步（含 2026-08-14 審查後補上的 `reader_prefs_manager_test.dart` 透傳測試），資料流五層（`BookReaderPrefs`→`ResolvedPreferences`→`resolve()`→`FoliateEpubReaderView`→`main.js`）逐一比對皆正確銜接，無漏接。
2. `fromMap()` 的 `letterSpacing: (map['letter_spacing'] as num?)?.toDouble()` 正確遵循 `spec.md`「反序列化容錯要求」的既有轉型慣例，並有專門測試餵入 `int` 型別值驗證不拋例外（`test('fromMap 餵入 int 型別的 letter_spacing...')`）。
3. SQLite migration 正確比照 `_addFullscreenColumn` 既有慣例（表存在性檢查、`else` 分支內的 `if (oldVersion < 19)` 巢狀防呆、`_createBookReaderPrefsTable` 同步更新供全新安裝），並有真實模擬 version 18→19 升級路徑的測試（非僅測全新安裝）。
4. UI 滑桿完全複用 `_buildSliderRow`／`?? _defaultXxx` 具現化既有模式，`initState()`／`didUpdateWidget()` 兩處同步更新沒有遺漏（這是這類多處鏡射欄位最容易漏改的地方）。
5. 測試覆蓋面完整：null/具體值 round-trip、int 型別防呆、`copyWith` 隔離性、map 含/不含 key、`foliatePreferencesChanged` 變動偵測、UI 初始值/預設值/互動觸發，密度與既有 `fullscreen`/`marginTop` 等鄰近欄位的既有測試一致。

## 3. 問題與疑慮

### Important（建議處理，非阻塞）

#### 【Important #1】`EpubPageEstimator` 的版面密度估算公式未納入新的 `letterSpacing` 變數 — **已修正（commit `ed5b221`）**

- **檔案**：`app/lib/reader/epub_page_estimator.dart`（`estimateCharsPerScreen()`，`:48-97`）
- **相關呼叫端**：`app/lib/screens/reader_screen.dart:2068-2080`（`_buildEpubFooter()`，頁尾頁碼顯示）、`app/lib/screens/toc_bottom_sheet.dart:226-241`（`_buildEntryRow()`，TOC 項目頁碼標籤）
- **問題內容**：
  `estimateCharsPerScreen()` 目前已把 `fontSize`／`lineHeight`／`paragraphSpacing`／四邊 `margin` 皆納入「每螢幕可容納字元數」的幾何估算公式（`epic-18-reader-device-qa` Issue 46 精準度優化的既有成果），但這次新增的 `letterSpacing` 完全沒有出現在這個函式的參數列或公式裡。`charsPerLine = (availableWidth / fontSizePx).floor()`（`:89`）沿用「每字元寬度 = fontSizePx」的假設，未把 `letterSpacing` 造成的額外字距（實際渲染時每字元多佔 `letterSpacing * fontSizePx` 的水平空間）計入。
- **影響**：
  使用者一旦調整字距（尤其正值，拉開字距），`charsPerLine` 的估算值會比 foliate-js 實際渲染結果偏高，連帶讓 `estimateTotalPages()`／`estimateCurrentPage()` 算出的總頁數與目前頁碼比實際情況更不準確——且誤差會隨字距數值增加而擴大，直接與這次新增的功能成正比。這兩個呼叫端（頁尾頁碼、TOC 頁碼標籤）都會受影響。
- **性質澄清**：這不是本次實作偏離 `plan-issue-1.md` 或 `design.md`／`spec.md` 的錯誤——這兩份文件從未要求更新 `EpubPageEstimator`，屬於 Issue 1 原始範圍界定時的一個遺漏，非本次程式碼品質問題。`EpubPageEstimator` 本身文件已聲明「模擬估算值，不保證與 foliate-js 實際渲染逐頁精確對齊」，故此問題不影響核心功能（CSS 字距套用本身正確無誤），只影響一個本來就是近似值的輔助顯示數字，不阻塞本 Issue 驗收。
- **建議**：留給人類決定是否要在本 Issue 補上（`estimateCharsPerScreen()` 新增 `letterSpacing` 參數，仿照 `lineHeightFactor` 的既有模式調整 `charsPerLine` 公式），或另立小工單追蹤。
- **修正結果（2026-08-14，commit `ed5b221`）**：`estimateCharsPerScreen()` 新增 `letterSpacing` 具名參數，仿照 `lineHeightFactor` 模式算出 `letterSpacingFactor = max(0.1, 1 + (letterSpacing ?? 0.0))`，每字元有效寬度改為 `fontSizePx * letterSpacingFactor`；`_buildEpubFooter()`／`TocBottomSheet._buildEntryRow()` 兩個呼叫端同步傳入 `resolved.letterSpacing`／`widget.resolved.letterSpacing`。`epub_page_estimator_test.dart` 新增 3 則測試（正值、UI 下限負值 -0.05、極端負值 -9.0 防呆），`letterSpacing` 省略時（`null`）公式行為與修正前逐位元組相同，全專案 1186 項測試（`flutter test`）與 `flutter analyze` 皆零回歸通過。

### Minor

無新增項目——先前 `plan-issue-1.md` 審查階段已處理過的 Minor #2（`PRAGMA table_info` 欄位檢查，不採納，已記錄理由）與 Minor #3（`letterSpacing===0` 覆寫書本原生字距，已另立 `docs/epics/epic-28-reader-settings-enhancements/issues.md` Issue 4 追蹤，非本次程式碼審查範圍）皆為既有已決議事項，不重複列出。

## 4. 評估結論

- **是否可合併回 `main`**：**可以**——核心功能（資料層、持久化、CSS 套用、UI 控制項）正確且測試完整，`flutter analyze`／`flutter test` 皆乾淨通過；唯一的 Important 發現已於 commit `ed5b221` 修正並驗證零回歸。
- **理由**：Important #1 是一個真實存在、已用原始碼確認的估算精準度落差，影響範圍侷限在一個本來就聲明為近似值的輔助顯示功能（頁尾頁碼／TOC 頁碼標籤），不影響字距這個核心功能本身的正確性；人類已指示在本 Issue 內一併修正，修正後全專案測試套件零回歸，本 Issue 可合併。
