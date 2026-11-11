# Issue 19：`integration_test/reader_screen_test.dart` 在 Windows 失敗診斷 Plan（輕量）

**Goal：** 查明該檔在 Windows 上 9 項失敗與「整份中斷」的原因，逐項分類並處理，讓它能在 Windows 穩定通過（或有明確 skip），並決定它放進哪個套件。

> 注意檔名：本 Issue 說的是 `app/integration_test/reader_screen_test.dart`（19 項、需要真實 App）。`app/test/screens/reader_screen_test.dart`（widget 測試，317 項）是另一個檔，Windows 上已全數通過，不在範圍內。
>
> 修訂記錄（2026-11-12，依 `reviews/review-plan-issue-19.md`）：失敗分類改為 A（測試端就緒時序，4 項）與 B（平台專屬行為，5 項），刪除原「類別 C」；更正手動裁切 `drag()` 警告的解讀；Task 1 補環境隔離；補套件時間預算評估；補完整路徑與 `--reporter=expanded`；刪除與程式不符的待確認第 2 點。

## 現況（2026-11-11 實測，一次執行）
指令：`flutter test integration_test/reader_screen_test.dart -d windows`（實作時改加 `--reporter=expanded`，原因見下），約 85 秒。

- **結果：19 項全部跑完，10 通過、9 失敗。App 沒有中途結束。** 與 Issue 13 報告（「第一支結束後整份中斷、exit 79」）**不一致**；原因未查明（可能 Issue 13 加的測試端 teardown 已有效，也可能只是偶發，**只跑了 1 次，不能下結論**）。
- 預設輸出把失敗清單截成 `... and 5 more`，**但失敗名稱在逐項輸出中都有**；9 項為：

| 類別 | 測試（檔內順序） | 現象 | 依據與成因 |
|---|---|---|---|
| **A. 測試端就緒時序（4 項）** | 4（字型大小）、5（記住字型大小）、6（強制直排）、7（滾動翻頁） | `tap()` 找不到 `reader_settings_font_size_increment`／`reader_settings_tab_presentation` | 讀碼確認：`reader_screen.dart:2128-2130` 書籍未載入（`_autoDetectedWritingMode == null`）時，`onLayoutTap` 指向 `_showLayoutLoadingHint`（**非 null**）；測試的 `_layoutSettingsButtonReady()`（`reader_screen_test.dart` 第 60-69 行）只檢查 `onPressed != null`，且其註解「載入前為 null」與現行程式不符，所以第一影格就誤判就緒、點到的是「載入中」提示而不是設定面板。**這是讀碼推論，實跑中沒看到 SnackBar，Task 2 要實證。** |
| **B. 平台專屬行為（5 項）** | 8、9、10（方向鎖定）、13、14（PDF 對比／亮度、加粗） | 8–10：`_pumpUntil` 等 10 秒逾時，條件是 `SystemChrome.setPreferredOrientations` 被呼叫；13、14：找不到 `pdf_settings_tab_filters` | 讀碼確認：`_applyScreenOrientation()` 在 `!supportsMobileReaderControls`（Windows）直接 return；`pdf_settings_sheet.dart:151、161` 的濾鏡分頁與其內容都受 `if (supportsMobileReaderControls)` 守衛，**Windows 上這個分頁根本不存在**。屬產品既有的平台設計，不是 bug。 |

- 手動裁切測試（第 17 項，`reader_screen_test.dart` 約第 855 行）的 `drag()` hit test 警告：**是預期現象，不是缺陷。** 該測試刻意對 `PdfReaderView` 拖曳，目的就是間接驗證裁切互動模式下翻頁手勢被覆蓋層阻斷（見測試內註解）；舊的「四角控制點」早已移除。**不得改拖曳座標。**

## 已定共識
- 第一步只重現與診斷，不改正式程式；測試檔的修改（就緒條件、`skipOnWindows`）屬測試端，可在診斷後直接做；**動到 `lib/` 的產品程式一律先停下回報人類**。
- 類別 B 走 `skipOnWindows('原因')`（慣例見 `integration_test/windows_skip.dart`），原因欄寫明對應的產品守衛；凡是產品在 Windows 上真的有問題，另開 Issue。
- 不為了讓測試變綠而放寬斷言（例如放大 10 秒逾時、拿掉 `expect`）。
- 只在這台 Windows 驗證；Android 行為與實機不動（Android 端失敗屬 Issue 21）。
- 所有診斷與連跑一律加 `--reporter=expanded`，避免失敗清單被截斷。

## Tasks
- [x] **Task 1：穩定性（環境隔離）。** 指令：`flutter test integration_test/reader_screen_test.dart -d windows --reporter=expanded`，**連跑 5 次**。每次之前：確認沒有殘留的 `elinkbook.exe`（沿用 `app/tool/run_windows_smoke.ps1` 的 `taskkill.exe /IM elinkbook.exe /F` 做法）、刪除暫存目錄中本檔產生的 `sample_*.epub`／`sample_*.pdf`。每次記錄：通過／失敗數、失敗項名稱、是否中途結束（exit code）、耗時。原始輸出存 `docs/epics/epic-66-windows-port/assets/issue-19-run-N.log`。目的：確認「整份中斷」現在會不會發生、9 項失敗是否穩定。
- [x] **Task 2：類別 A 實證。** 在失敗點暫時印出當時是否有 SnackBar（「版面載入中」提示）、`_layoutSettingsButtonReady` 回傳值與 `reader_loading_indicator` 狀態（拋棄式、不進 commit）。證實後，把就緒條件改成「按鈕存在、且書籍已載入完成（`reader_loading_indicator` 消失；或按鈕點擊後確認 `ReaderSettingsSheet` 真的出現再往下）」，同步更正該函式過時的註解。
- [x] **Task 3：類別 B 處理。** 對 8、9、10、13、14 加 `skip: skipOnWindows('…')`，原因分別指向 `supportsMobileReaderControls` 守衛（方向鎖定、E-Ink 濾鏡僅行動裝置）。確認 Windows 沒有對應的替代行為（Task 1 的日誌與讀碼）；若 Windows 其實有替代行為卻沒測，另立 Issue，不在此處補。
- [x] **Task 4：第 17 項。** 不改座標。可選：對該 `drag()` 傳 `warnIfMissed: false` 並加註解說明「此處刻意驗證手勢被阻斷」，只為消除警告；執行前確認這是人類要的（見待確認）。
- [x] **Task 5：回報。** 寫 `issue-19-report.md`：19 項逐項狀態表（通過／skip＋原因／另立 Issue）、成因證據、與 Issue 13 結論的差異及判斷依據；更正 Issue 13 報告中過時的描述。
- [x] **Task 6：驗證與歸屬。** 該檔連跑 5 次結果一致；量測加入後的總耗時；依人類決定放進 `windows_smoke_suite.txt` 或另立套件；`flutter analyze`；整份完成才跑全套 `flutter test`；更新 `issues.md` 第 19 列。

## 過關條件
1. 19 項各有明確狀態：通過、`skipOnWindows`（附原因）、或另立 Issue（附編號）；沒有「原因未明」。
2. 「整份中斷」有結論：連跑次數與結果有紀錄；不再發生就如實寫「無法重現」，不宣稱已修。
3. 沒有為了變綠而放寬斷言；第 17 項的測試目的未被改動。
4. 該檔連跑 5 次結果一致；歸屬決定（冒煙套件或另立套件）已由人類確認並完成。
5. `flutter analyze` 乾淨；產品程式未動（若動則已經人類同意）。

## Review Focus
1. **偶發 vs 穩定：** 只跑 1 次不能下結論；Task 1 的 5 次結果決定後面怎麼走。
2. **skip 不得掩蓋產品問題：** 類別 B 已由讀碼確認是產品的平台守衛，但仍要確認 Windows 沒有未被測到的替代行為；類別 A 先實證再改。
3. **「通過」不等於「有驗證到」：** 第 17 項只斷言「沒有錯誤畫面、設定面板沒被重新開啟」，**沒有直接斷言頁碼不變**；報告要如實寫這個測試強度，不誇大。
4. **環境汙染：** 連跑之間殘留進程或暫存檔會造成假性不穩定（Task 1 已規範清理）。
5. **與 Issue 13 結論衝突：** 本次實測與 Issue 13 報告不一致，報告要明確寫出差異與判斷依據。
6. **套件時間預算：** 該檔單次約 85 秒，現行冒煙套件 27 支約 3 分鐘、單檔逾時預設 420 秒；加入前要量測實際增幅。

## 待人類確認
1. Task 1 連跑 5 次約 7 分鐘，會開 Windows 桌面視窗，期間不要操作這台電腦，是否同意？
2. 歸屬：修好後放進 `windows_smoke_suite.txt`（日常冒煙，約增加 85 秒、約 +50%），還是另立「完整閱讀器整合測試」套件在發布前或特定流程執行？建議**先量測 Task 6 的實際耗時後再決定**，不在此預設。
3. 第 17 項是否要加 `warnIfMissed: false` 消除警告？（只影響警告輸出，不改測試行為；也可不處理。）
