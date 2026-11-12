# Issue 21：Android 整合測試仍有失敗診斷 Plan（輕量）

**Goal：** 查明 BooksPad 上 `epub_toc_test`、`epub_highlights_notes_test`、`reader_screen_test` 的失敗，逐項分類處理，讓每個失敗都有證據支持的結論（修測試、略過、另立 Issue 或「不再重現」），不留「原因未查明」。

> 修訂記錄（2026-11-12，依 `reviews/review-plan-issue-21.md`）：Task 2 範圍擴大為 `epub_toc_test` 全檔所有開目錄位置，並改抽成檔案級共用函式；Task 3 更正「補量第 2 次」的說法；Task 5 與過關條件補 Windows 回歸驗證與 l10n 檢查；更正「同型 `onPressed != null`」的敘述（書籤與筆記按鈕未就緒時本來就是 null）。

## 已定共識（2026-11-12 grilling，Q1～Q10）
- **做完的標準：** 比照 Issue 19，不要求三個檔案全綠；每個失敗都要有證據支持的分類與處理。
- **產品問題：** 診斷若顯示是真的產品問題，只記錄證據、另立新 Issue，**不在本 Issue 修 `app/lib/`**；動到 `lib/` 一律先停下回報。
- **裝置範圍：** 只用 BooksPad（`B78CW2508006423`，Android 12，32 位元，WebView 91）。報告要寫明「只在這一台低階裝置驗證」。Air Viwood 無法 ADB，不驗證。
- **逾時政策：** 只有同時滿足 (a) 實測顯示更長逾時下穩定通過、且記錄量到的耗時，(b) 只有慢裝置才會不夠，才放寬逾時；否則視為失敗。不為了變綠放寬斷言。
- **範圍：** 只處理這三個檔案。Issue 13 說 Android 完整 27 支冒煙套件只跑了 11 支，其餘 16 支在報告中標「未驗證」，不補跑。
- **流程：** 輕量流程，短計畫加報告，同一分支同一個 PR。修完後同一檔案在 BooksPad 連跑 5 次一致才算穩定。
- **Android 實機操作規矩：** 螢幕保持亮著（`svc power stayon usb`，測完設回 0）；絕不用 `flutter install`（用 `adb install -r`）；跑完把一般 debug APK 裝回（`flutter build apk --debug --target-platform android-arm`）；每檔之間停掉 Gradle／Kotlin daemon；adb 為 `C:\Users\fycdc\AppData\Local\Android\Sdk\platform-tools\adb.exe`，Git Bash 需 `MSYS_NO_PATHCONV=1`；所有執行加 `--reporter=expanded`。

## 現況（2026-11-12 重測，`main` @ `e030d02a`，每檔 3 次，日誌 `assets/issue-21-baseline-*.log`）
| 檔案 | Issue 13 時 | 現在 |
|---|---|---|
| `epub_highlights_notes_test` | 0/1 | **3/3 通過** |
| `epub_toc_test` | 1/2 | 3 項測試；第 1 次全過，第 2、3 次各 1 項失敗（時好時壞） |
| `reader_screen_test` | 14/19 | 3/3 一致 18 通過、1 失敗（都是第 1 項） |

**`epub_toc_test` 第 3 項**（單一 spine 多目錄錨點，epic-54 Issue 20）：點目錄按鈕後 `TocBottomSheet` 找到 0 個。讀碼推論：`reader_screen.dart:2064-2070` 的 `_onTocTapFor` 在目錄未載入時把按鈕指向 `_showTocLoadingHint`（非 null），測試的 `_pumpUntilTocButtonEnabled` 只查 `onPressed != null`（其註解「目錄抓取未完成時按鈕是 disabled」與現行程式不符），所以可能點到的是提示而非目錄。與 Issue 19 類別 A 同型，也能解釋時好時壞。**這是推論，日誌沒看到提示 SnackBar，需實證。**

**`reader_screen_test` 第 1 項**：三次都是 `_pumpUntil` 等 10 秒逾時（`reader_screen_test.dart:163`）。日誌的「已渲染」第 1 次距開書 15,561 ms、第 3 次 14,247 ms（第 2 次未取得首項數字），之後各項 6～9 秒，逾時後渲染仍完成。符合「冷啟動 WebView 第一次建立特別慢」；屬 Q4 的慢裝置情境。

**觀察（未查明，不處理）：** Android 日誌每次開書都有 `載入錯誤 HOST_LOOKUP net::ERR_NAME_NOT_RESOLVED`（含通過的測試），Windows 日誌沒有。不影響結果，原因不明，只在報告記錄，不另立 Issue（人類決定）。

## Tasks
- [x] **Task 1：`epub_toc_test` 實證。** 暫時（拋棄式、不進 commit）在失敗點印出：點擊後 `reader_toc_loading_snackbar` 數量、`TocBottomSheet` 數量、`_pumpUntilLoaded` 完成時的狀態。在 BooksPad 跑至少 3 次，確認失敗時是否為「點到載入提示」。若實證不符（例如沒有提示卻仍找不到面板），**停下回報**，不套用下方修法。
- [x] **Task 2：`epub_toc_test` 修測試端。** 實證成立後：
  - 把「開目錄」抽成**檔案級頂層輔助函式** `_openToc(WidgetTester tester)`：點擊 `reader_chrome_toc_button`；若出現 `reader_toc_loading_snackbar`（目錄尚未載入），就等目錄載完再重點，直到 `TocBottomSheet` 出現；超過上限仍失敗並帶清楚訊息，**不可無限等、不可吞錯**。
  - 重試以小步長推進（例如每次 `pump(300 ms)`），重試前可呼叫 `ScaffoldMessenger.of(...).clearSnackBars()` 讓點擊不被殘留提示遮擋。（審查者認為 `pumpAndSettle()` 會被 2 秒提示拉長；我**沒有驗證**這點，但小步長本身是穩當做法，採用。）
  - **全檔所有開目錄的位置都改用它**：目前共 5 處獨立寫法——第一項測試的 `146`、`199` 行，第二項（桌面寬度，Issue 20）的 `269`、`277` 行，第三項的局部 `openToc()`（`341` 行，含其 `364`／`374`／`384` 三個呼叫）。（審查報告漏數了 `199` 行。）
  - 同步更正 `_pumpUntilTocButtonEnabled` 過時的註解（「目錄抓取未完成時按鈕是 disabled」與現行程式不符）。
  - **不放寬任何斷言。** 其他檔案不碰（見下方 Review Focus 7 與報告列出方式）。
- [x] **Task 3：`reader_screen_test` 第 1 項。** 只對「第一次冷啟動開書」把 `_pumpUntil` 上限由 10 秒放寬到 30 秒，註解寫明量測值（14～16 秒）與依據；其餘測試維持 10 秒。不改成暖機。量測值目前只有 2 筆（第 1 次 15,561 ms、第 3 次 14,247 ms；第 2 次在 10 秒逾時當下即被判負、日誌沒有輸出「已渲染」，**無法從舊日誌補量**）。第 3 筆在放寬逾時後的首次實測中採集。
- [x] **Task 4：`epub_highlights_notes_test`。** 不修改；報告記為「目前不再重現」，附 3/3 日誌，不宣稱是哪個 Issue 修好（沒有證據）。
- [x] **Task 5（Windows 整份套件 28/28 未達成，見報告第 5 節）：驗證。**
  - **BooksPad：** 修完後三個檔案各連跑 5 次；每次之間停 daemon、螢幕保持亮著；全部一致才算穩定。跑完還原 BooksPad（一般 debug APK、`stay_on_while_plugged_in` 0）。
  - **Windows 回歸（審查 I-2）：** `epub_toc_test.dart` 與 `reader_screen_test.dart` 都在 `windows_smoke_suite.txt` 內，修改後必須在 Windows 驗證：`flutter test integration_test/epub_toc_test.dart -d windows --reporter=expanded` 與 `flutter test integration_test/reader_screen_test.dart -d windows --reporter=expanded`（Windows 現況：`reader_screen_test` 14 通過／5 略過；`epub_toc_test` 3 項），不得有回歸；最後跑一次整份冒煙套件（`app/tool/run_windows_smoke.ps1`）確認 28/28 仍通過。
  - `flutter analyze`；`node tool/check_integration_keys.js`；`node tool/check_l10n_hardcoded_strings.js`（審查 N-1）。
- [x] **Task 6：報告與收尾。** 寫 `issue-21-report.md`：逐檔結果表（含 Issue 13 時與現在的對照）、各項成因與證據（區分實證與推論）、限制（只一台 BooksPad、其餘 16 支未驗證、`ERR_NAME_NOT_RESOLVED` 未查明）；更正 Issue 13 報告中 Android 失敗的過時描述；更新 `issues.md` 第 21 列。整份完成才跑全套 `flutter test`（本 Issue 只改整合測試檔，預期無影響，仍依慣例在合併前確認一次）。

## 過關條件
1. 三個檔案每個失敗都有明確結論：已修、略過（附原因）、另立 Issue（附編號）、或「不再重現」（附日誌）；沒有「原因未查明」。
2. 修過的檔案在 BooksPad 連跑 5 次一致；同兩個檔案在 Windows 無回歸，整份冒煙套件 28/28 仍通過。
3. 沒有為了變綠而放寬斷言；逾時放寬只用於第一次冷啟動開書，且附量測值。
4. `app/lib/` 產品程式 0 修改（若需修改，已先停下並經人類同意）。
5. BooksPad 已還原，報告寫明環境限制。
6. `flutter analyze` 乾淨。

## Review Focus
1. **推論 vs 實證：** `epub_toc_test` 的成因目前是讀碼推論，Task 1 的實證沒做完不得套用修法。
2. **偶發失敗要夠次數：** `epub_toc_test` 是時好時壞（3 次中 2 次失敗），修完要連跑 5 次；只跑 1 次通過不算。
3. **重試不得掩蓋產品問題：** Task 2 的「重點擊」若目錄永遠載不完，必須在上限後明確失敗，不可無限等或吞錯。
4. **逾時放寬的範圍：** 只放寬第一次冷啟動開書，不是整檔、不是全域預設。
5. **「不再重現」不是「已修」：** `epub_highlights_notes_test` 3/3 通過只代表目前通過；原因沒有證據，報告不得歸功於任何 Issue。
6. **裝置單一：** 全部結論只在 BooksPad（32 位元、WebView 91）成立；其他 Android 裝置未驗證。
7. **同型寫法的範圍要講準：** 「未就緒時 `onPressed` 仍非 null（指向載入提示）」的按鈕只有兩顆：版面按鈕（指向 `_showLayoutLoadingHint`，Issue 19 已處理）與目錄按鈕（指向 `_showTocLoadingHint`，本 Issue）。書籤與筆記按鈕未就緒時 `onPressed` 本來就是 null（`reader_screen.dart` 的 `onBookmarkTap`、`onAnnotationsTap`），其他檔案檢查 `onPressed != null` 對它們是正確的；報告要寫準，不要把它們說成同一種陷阱。其他檔案若用 `reader_chrome_toc_button` 或 `reader_chrome_layout_button` 的就緒判斷，才是同型，報告只列出、不改。
8. **實機操作殘留：** 測試後 App 會變成測試殼層，必須還原；daemon 吃記憶體，檔間要停。

## 待人類確認
1. 計畫是否同意？同意後我從 Task 1 開始（會再度佔用 BooksPad，約 40～60 分鐘，期間請勿拿走或操作平板）。
