# Epic 66 Issue 21 報告：Android 整合測試失敗診斷（epub_toc_test／epub_highlights_notes_test／reader_screen_test）

- **日期**：2026-11-12　**分支**：`fix/epic-66-issue-21-android-integration`
- **裝置**：BooksPad（`B78CW2508006423`，Android 12，32 位元，WebView 91，MemTotal 約 4 GB），螢幕常亮。**只在這一台裝置驗證。**
- **範圍**：只處理這 3 個檔案（人類決定）；Android 完整 27 支冒煙套件中其餘 16 支未驗證。
- **程式變更**：只動 `app/integration_test/epub_toc_test.dart`、`app/integration_test/reader_screen_test.dart`；`app/lib/` 0 行。

## 1. 結論摘要

| 檔案 | Issue 13 時（BooksPad） | 基準重測（`main` @ `e030d02a`，各 3 次） | 修復後（BooksPad） | 處理 |
|---|---|---|---|---|
| `epub_highlights_notes_test` | 0/1 | 3/3 通過 | 3/3 通過 | **不再重現**，未修改（不歸功任何 Issue） |
| `epub_toc_test` | 1/2 | 3 項；第 1 次全過，第 2、3 次各 1 項失敗 | **5/5 全過**（3 項） | 修測試端：`_openToc()` |
| `reader_screen_test` | 14/19 | 18 通過、1 失敗（第 1 項冷啟動逾時），3/3 一致 | 5/5 全過；**但另有一批 5 次不明中斷未解釋**（第 4.2 節） | 第 1 項放寬冷啟動逾時 |

## 2. `epub_toc_test`：點到「目錄載入中」提示

- **實證（Task 1）**：暫時在失敗點印出狀態，BooksPad 4/4 失敗皆為：點擊前 `snackbar=0`，點擊後 100 ms `snackbar=1 sheet=0`，`pumpAndSettle` 後仍 `snackbar=1 sheet=0`（`assets/issue-21-diag-toc-run1..4.log`）。
- **成因**：`reader_screen.dart:2064-2070` 的 `_onTocTapFor` 在目錄尚未載入時把按鈕指向 `_showTocLoadingHint`（非 null）；測試的 `_pumpUntilTocButtonEnabled` 只看 `onPressed != null`，其註解「目錄抓取未完成時按鈕是 disabled」與現行程式不符，所以第一影格就誤判就緒。與 Issue 19 的類別 A 同型。
- **修法（只動測試）**：新增檔案級 `_openToc(tester)`：點擊後若面板沒開，等 300 ms 再點，直到 `TocBottomSheet` 出現；10 秒內沒出現則明確失敗（訊息區分「仍顯示載入提示」與「原因不明」），不吞錯。全檔 5 處開目錄的位置（第一項測試 2 處、第二項（桌面寬度，Issue 20）2 處、第三項的局部 `openToc()`）全部改用；更正過時註解。未放寬任何斷言；第二項兩處原本沒有 `expect(TocBottomSheet)`，現在由 `_openToc` 一併檢查（略嚴格）。
- **結果**：BooksPad 修復後連跑 5 次 **5/5 全過、各 3 項**（`assets/issue-21-fixed-epub_toc_test-run1..5.log`，測試計時約 57～60 秒）。
- **審查報告的一個說法未成立**：計畫審查（M-3）認為 `pumpAndSettle()` 會被 2 秒提示拉長；實測 `pumpAndSettle()` 結束時提示仍在（`snackbar=1`），並未等它消失。小步長重試仍是穩當做法，已採用。
- **同型寫法的範圍**：「未就緒時 `onPressed` 非 null（指向載入提示）」的按鈕只有版面按鈕（`reader_chrome_layout_button`，Issue 19 已處理 `reader_screen_test`）與目錄按鈕（`reader_chrome_toc_button`，本 Issue）。書籤與筆記按鈕未就緒時 `onPressed` 本來就是 null。`foliate_highlights_notes_test`、`foliate_single_column_test` 也用版面按鈕的就緒判斷，**目前沒失敗，本 Issue 不改，僅列出**。

## 3. `epub_highlights_notes_test`：目前不再重現

基準 3/3、修復後 3/3 全過（另有 1 次因系統記憶體不足被中止，日誌不完整，不計）。Issue 13 時的失敗（找不到「已編輯的純備註」）**原因未知**；可能受 Issue 18／19／20 影響，但**沒有證據證明是哪一個**，也不排除是 Issue 13 時螢幕熄滅等環境因素。未修改。

## 4. `reader_screen_test`

### 4.1 第 1 項：冷啟動逾時（已處理）
- 基準 3/3：第 1 項 `_pumpUntil` 等 10 秒逾時（`reader_screen_test.dart:163`），其餘 18 項通過。
- 冷啟動「已渲染 距開書」實測（共 13 筆，BooksPad）：15,561／14,247（基準）、11,062／11,769／12,107／11,462／11,661（中斷批次）、11,214（logcat 現行版）、11,439／11,444／11,601／11,962／11,850（5 次連跑）；範圍 11.1～15.6 秒，**全部超過 10 秒**。之後暖機開書 6～9 秒。
- 對照實驗：把第 1 項改回 10 秒，同一次診斷 18 通過、1 失敗（第 1 項）；現行版 19/19（`assets/issue-21-logcat-{cur,ctrl}-test.log`）。放寬確實是必要的。
- 修法：只有第 1 次開書的 `_pumpUntil` 上限 10→30 秒，註解寫明量測值；其餘維持 10 秒。符合逾時政策（有實測、只放寬冷啟動）。

### 4.2 一批 5 次不明中斷（**原因未查明**）
- 放寬到 30 秒後第一批連跑 5 次，**5/5 在測試計時約 1:56～1:58 中斷**：通過 6 項後其餘 `did not complete`，exit 1，日誌沒有例外（`assets/issue-21-fixed-reader_screen_test-run1..5.log`）。第 1 項這 5 次都通過。
- 之後同一份程式碼：logcat 診斷 1 次 19/19、再連跑 5 次 **5/5 全為 19/19**（`assets/issue-21-five-run1..5.log`，每輪同步抓 logcat，篩選結果 `issue-21-five-run*-logcat-filtered.txt`）；logcat 中**沒有**看到 `cc.ugotit.elinkbook` 被系統殺掉或崩潰的記錄。
- 已檢驗並**未被支持**的假設：(1) 開發機記憶體吃緊——中斷批次開跑時可用約 5.08 GB，之後第 1 次連跑結束時 5.11 GB 也通過；(2) BooksPad 記憶體不足——`MemTotal` 約 4 GB、可用約 2.6 GB，logcat 無行程被殺記錄。我先前口頭說 BooksPad「只有 1 GB」是錯的，予以更正。
- **現在能寫的結論**：同一份程式碼出現過 5/5 中斷，之後 11 次（含 logcat 診斷）不再發生，原因未查明。**不宣稱已修、也不宣稱是環境問題。**（人類判斷為資源吃緊，見第 6 節；我量到的數據不支持，也無法排除其他資源。）

## 5. Windows 回歸驗證（計畫 I-2）
- 單檔：`epub_toc_test` **3/3**（00:22）；`reader_screen_test` **14 通過、5 略過**（01:06），與修改前一致。
- **整份冒煙套件（28 支）：26 通過、2 失敗**：`foliate_kf8_test` 與 `reader_screen_test`（耗時 2074 秒）。兩者單獨跑都通過；失敗日誌結尾都是整份 `did not complete` 加 `PathNotFoundException: Deletion failed … flutter_tools.XXXX\flutter_test_listener…`。
- 重跑（用冒煙腳本把這兩個檔案各跑 3 輪，`assets/issue-21-windows-rerun-suite.log`）：`reader_screen_test` **3/3 通過**；**`foliate_kf8_test` 3 次有 1 次失敗**，同一簽章。
- **`foliate_kf8_test` 這次沒有任何修改**，所以套件內的偶發中斷**不是本 Issue 的修改造成的**；但它與 Issue 19 基準的中斷簽章相同（見第 6 節）。
- 該次套件內失敗的 per-file 原始日誌已被後續重跑覆蓋，僅保存套件摘要（`assets/issue-21-windows-smoke-suite.log`）與上述節錄；這是證據缺口。

## 6. 對 Issue 19 結論的影響
Issue 19 報告把「測試 1 結束後整份中斷」解釋為 WebView2 卸載競爭，並以補 1 秒 `pump` 緩解（報告已寫明機制是推測）。本次新證據：沒有任何改動的 `foliate_kf8_test` 在 Windows 套件內也出現同簽章中斷（第 1 項結束、離開畫面後就 `did not complete`，且日誌有 `flutter_tools` 暫存目錄的 `PathNotFoundException`）。**這表示該中斷並非 `reader_screen_test` 獨有，也可能不只是測試端的卸載時序**；Issue 19 的「補 1 秒後 10/10 不再中斷」仍是事實，但機制更不確定。已在 Issue 19 報告加註記。**人類決定（2026-11-12）：不另立 Issue。** 人類的判斷是「資源吃緊造成的」。這是人類的判斷，**本報告沒有證據證實它**：我檢驗過的兩個資源假設（開發機可用記憶體、BooksPad 記憶體與 logcat 行程死亡記錄）都沒有被數據支持（見 4.2）；但我沒有量到其他資源（CPU、磁碟 I/O、Windows 上的暫存目錄清理等），所以也無法排除。因此中斷原因在本報告中仍記為「未查明」，並保留這個人類判斷作為後續參考。

## 7. 其他觀察與限制
- Android 日誌每次開書都有 `載入錯誤 HOST_LOOKUP net::ERR_NAME_NOT_RESOLVED`（通過的測試也有），Windows 日誌沒有；**原因未查明，不影響結果，未另立 Issue（人類決定）**。
- 只在一台 BooksPad（32 位元、WebView 91）驗證；其他 Android 裝置、Air Viwood 未驗證；Android 其餘 16 支冒煙測試檔未驗證。
- 30 秒上限是依 13 筆冷啟動實測（最大 15.6 秒）取的餘裕值，不是測得的邊界。

## 8. 驗收
- [x] 三個檔案的失敗都有結論：`epub_toc_test` 已修（有實證）、`epub_highlights_notes_test` 不再重現、`reader_screen_test` 第 1 項已修；**另有一批 5 次中斷原因未查明（已如實記錄）**。
- [x] 修過的檔案在 BooksPad 連跑 5 次一致：`epub_toc_test` 5/5、`reader_screen_test` 5/5（外加較早一批 5 次不明中斷，見 4.2）。
- [x] 未放寬斷言；逾時放寬只用於第一次冷啟動開書並附量測值。
- [x] `app/lib/` 0 行；BooksPad 已還原（一般 debug APK，`stay_on_while_plugged_in` 0）。
- [x] `flutter analyze`、`check_integration_keys.js`、`check_l10n_hardcoded_strings.js` 皆乾淨。
- [ ] **Windows 整份冒煙套件 28/28**：本次實跑 26/28（偶發中斷，含未改動的 `foliate_kf8_test`），**未達成**；單檔皆通過。
- [x] 全套 `flutter test`：見第 9 節。

## 9. 全套 `flutter test`

2026-11-12 在 `fix/epic-66-issue-21-android-integration`（尚未 commit 的工作區）跑 `flutter test`：**5167 通過、2 略過、0 失敗**（耗時約 8 分 20 秒）。本 Issue 只改整合測試檔與文件，預期無影響，此結果與 Issue 25 合併前的 5167 通過、2 略過一致。
