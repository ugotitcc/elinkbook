# Epic 66 Issue 19：`integration_test/reader_screen_test.dart` 在 Windows 失敗診斷與分流報告

- **執行日期**：2026-11-12
- **測試環境**：Windows 11，Flutter 3.47.9，Dart 3.13.7，WebView2（本機版本），Debug 建置
- **涵蓋範圍**：`app/integration_test/reader_screen_test.dart`（19 項測試）
- **關聯文件**：
  - `docs/epics/epic-66-windows-port/plans/plan-issue-19.md`
  - `docs/epics/epic-66-windows-port/issue-13-report.md`
  - `docs/epics/epic-66-windows-port/reviews/review-plan-issue-19.md`

---

## 1. 執行總結

`app/integration_test/reader_screen_test.dart` 曾因 Issue 13 執行時出現「第一支測試結束後整份中斷、exit 79」而被隔離於日常冒煙測試之外。本次診斷在**完全不修改 `app/lib/` 產品程式**的前提下，找到可穩定消除中斷的觸發條件、修復 4 項測試端時序問題、並為 5 項行動裝置專屬行為標註平台略過：

- **最終狀態**：**14 項通過、5 項略過（`skipOnWindows`）、0 項失敗、0 項中斷、Exit Code 0**。
- **穩定度**：修復後連跑 5 次一致（14 通過／5 略過），另有獨立審查者實跑 2 次與整份冒煙套件 1 次，結果相同。
- **中斷原因**：找到可穩定消除的觸發條件（測試 1 結束時立即卸載），**但原生端機制是推測，沒有原生端證據**（見第 2 節）。
- **套件歸屬**：人類決定放進 `windows_smoke_suite.txt`，已落地並以整份套件實跑驗證（見第 7 節）。
- **產品程式碼變動**：**0 行**。所有調整均限於 `app/integration_test/reader_screen_test.dart`（該檔 diff 看起來很大是因為縮排重排；忽略空白後只有 +48／-16 行）。

---

## 2. 歷史「整份中斷（exit 79）」：觀察、推測與未解之處

### 2.1 歷史現象回顧（Issue 13）
Issue 13 報告（2026-11-10）記錄：
> 「連未修改的 HEAD 執行 `reader_screen_test.dart` 也會在第一支測試結束後整個結束（App 結束，exit 79，其餘 18 支 did not complete）；單獨跑第 1、2 支皆通過。初版報告的『10 通過、9 失敗』在這台機器上無法重現，原因未查明。」

### 2.2 觀察（有日誌證據）
- **基準（未修改）連跑 5 次**（`assets/issue-19-baseline-abort-run-1..5.log`）：**5/5 在測試 1 結束（日誌出現 `離開畫面 已刪快取目錄=是`）之後，App 即結束**，其餘 18 支顯示 `did not complete [E]`，並出現 `PathNotFoundException`（測試監聽的目錄已不存在）。
- **只在測試 1 結束前補 `await tester.pump(const Duration(seconds: 1))` 後**（`assets/issue-19-run-1..5.log`）：5/5 不再中斷、19 項都跑完；**但此時類別 A 尚未修，仍是 10 通過、9 失敗**（這 5 份日誌不是全綠）。
- **類別 A 與類別 B 都處理後**（`assets/issue-19-run-fixed-1..5.log`）：5/5 為 `+14 ~5: All tests passed!`。
- 前後對照：補 1 秒 `pump` 之前 5/5 中斷、之後 10/10 不中斷。

### 2.3 推測（沒有原生端證據）
推測機制：測試 1 結束時 `addTearDown` 立即卸載 Widget 樹與原生 `InAppWebView`，此時 WebView2 剛送出 `onPageRendered`、第一幀可能尚未完成交付，卸載與交付競爭導致 `elinkbook.exe` 結束，測試框架的連線斷開、其餘測試顯示未完成。

**這一整段是推測**：日誌中沒有任何原生端錯誤、堆疊或 WebView2 事件記錄，日誌裡也**沒有「exit 79」字樣**（該數字來自 Issue 13 報告，本次未在日誌中重現其輸出）。「單獨跑測試 1 會過是因為進程本來就在測試 1 結束而被遮蔽」同樣是推論，沒有實驗支持。

### 2.4 未調和的觀察
- 2026-11-11 計畫撰寫時，同一份未修改的測試曾**實跑一次、19 項全部跑完（10 通過、9 失敗），App 沒有中途結束**；同一份程式在 2026-11-12 的基準連跑卻是 5/5 中斷。兩者為何不同**未查明**（可能與機器負載、WebView2 狀態、暫存狀態有關，皆未驗證）。所以這是時間相關的競爭，補 1 秒是**縮小風險、不是證明消除**；10/10 通過是支持證據，不是證明。

### 2.5 修復手段與限制
在測試 1 與測試 5 卸載前加入：
```dart
await tester.pump(const Duration(seconds: 1));
```
- **測試 1**：有基準證據（5/5 中斷 → 10/10 不中斷）。
- **測試 5**：**預防性比照，沒有基準證據**（基準跑到測試 1 就中斷，從未跑到測試 5）。
- 這是固定時間的等待（經驗值），不是可觀察的「首影格已交付」條件；若日後再現中斷，優先考慮拉長等待或找可觀察條件，不應放寬其他斷言。

---

> **後續註記（2026-11-12，Issue 21）：** 上節的中斷機制是推測。之後在 Windows 冒煙套件內，**未改動的 `foliate_kf8_test`** 也出現同簽章中斷（第 1 項結束後整份 `did not complete`、日誌有 `flutter_tools` 暫存目錄的 `PathNotFoundException`；重跑 3 次中 1 次發生），`reader_screen_test` 在套件內也曾失敗 1 次（其後單檔與重跑 3/3 通過）。所以該中斷並非本檔獨有，也可能不只是測試端卸載時序；「補 1 秒後 10/10 不再中斷」仍是事實，但機制更不確定。詳見 `issue-21-report.md` 第 5、6 節。

## 3. 19 項測試逐項診斷與狀態矩陣

修復時序與加上平台守門後，19 項測試逐項狀態如下：

| # | 測試名稱 | 最終狀態 | 類別與成因說明 |
|---|---|:---:|---|
| 1 | ReaderScreen 開啟範例 EPUB 檔案，渲染出非空白內容 | 🟢 通過 | 基準測試；加入 teardown 1s pump 避免 WebView2 提前銷毀 |
| 2 | ReaderScreen 載入不存在的書籍路徑，顯示載入失敗畫面 | 🟢 通過 | 基準測試；錯誤畫面驗證 |
| 3 | FXL EPUB 點擊「⚙️版面」按鈕開啟 FxlSettingsSheet | 🟢 通過 | 基準測試；原先已包含 `_loadingIndicatorGone()` 判斷 |
| 4 | 開啟版面設定 Bottom Sheet，調整字型大小後畫面持續渲染成功、無 onError | 🟢 通過 | **類別 A 修復**：修正 `_layoutSettingsButtonReady` |
| 5 | 調整版面設定後關閉重開該書，設定被正確記住（驗證 initialPreferences 生效） | 🟢 通過 | **類別 A 修復**：修正 `_layoutSettingsButtonReady` |
| 6 | 點擊排版方向覆寫圖示「強制直排」後，畫面持續渲染成功、無 onError | 🟢 通過 | **類別 A 修復**：修正 `_layoutSettingsButtonReady` |
| 7 | 點擊翻頁模式覆寫圖示「滾動翻頁」後，畫面持續渲染成功、無 onError | 🟢 通過 | **類別 A 修復**：修正 `_layoutSettingsButtonReady` |
| 8 | 未覆寫螢幕方向時，進入 ReaderScreen 後依全域預設值呼叫 SystemChrome.setPreferredOrientations | ⚪ 略過 (`skipOnWindows`) | **類別 B 平台守門**：Windows 不支援螢幕方向鎖定（`supportsMobileReaderControls == false`，見 epic-66 Issue 10 與 `_applyScreenOrientation()`） |
| 9 | screenOrientationOverride=lock90 時，SystemChrome.setPreferredOrientations 帶入 landscapeLeft | ⚪ 略過 (`skipOnWindows`) | **類別 B 平台守門**：同上，Windows 略過螢幕方向調用 |
| 10 | 離開 ReaderScreen 後，SystemChrome.setPreferredOrientations([]) 被呼叫還原 | ⚪ 略過 (`skipOnWindows`) | **類別 B 平台守門**：同上，`reader_screen.dart:715` 具 `supportsMobileReaderControls` 守衛，Windows dispose 不調用還原 |
| 11 | PDF 點擊「⚙️版面」按鈕開啟 PdfSettingsSheet（非 ReaderSettingsSheet） | 🟢 通過 | 基準測試；PDF 版面設定面板 |
| 12 | PDF 切換三種 Fit 模式，畫面持續渲染成功、無 onError | 🟢 通過 | 基準測試；Fit 模式切換 |
| 13 | PDF 調整對比度／亮度後畫面持續渲染成功、無 onError | ⚪ 略過 (`skipOnWindows`) | **類別 B 平台守門**：PDF 濾鏡分頁（對比/亮度/加粗）僅在行動裝置（E-Ink 控制）啟用，Windows 上 `supportsMobileReaderControls == false`，分頁被 UI 守衛移除（見 `pdf_settings_sheet.dart:151, 161`） |
| 14 | PDF 調整加粗強度後畫面持續渲染成功、無 onError | ⚪ 略過 (`skipOnWindows`) | **類別 B 平台守門**：同上，Windows 不渲染此分頁 |
| 15 | PDF 切換至智慧自動裁切，畫面持續渲染成功、無 onError | 🟢 通過 | 基準測試；智慧裁切計算 |
| 16 | 智慧自動裁切計算後關閉重開該書，pdf_crop_rect 不重新計算（值一致） | 🟢 通過 | 基準測試；裁切持久化 |
| 17 | PDF 進入手動裁切互動模式後，翻頁手勢暫停回應（不觸發頁面錯誤或意外離開裁切模式） | 🟢 通過 | **Task 4 消除警告**：此處由 `PdfCropFrameOverlay` 攔截手勢驗證翻頁暫停，傳入 `warnIfMissed: false` 消除 false-alarm hit test 警告 |
| 18 | PDF 手動裁切拖拉四角控制點確認後，pdf_crop_mode/pdf_crop_rect 正確寫入且畫面套用新裁切結果 | 🟢 通過 | 基準測試；手動選區持久化 |
| 19 | PDF 手動裁切重新進入互動模式並再次確認（manual→manual），第二次確認寫入新的矩形值且持續正確持久化 | 🟢 通過 | 基準測試；手動選區二次確認 |

---

## 4. 類別 A 實證與修復詳情

### 4.1 實證數據（Task 2）
在 Test 4 失敗點插入暫時性偵測：
```dart
print('DEBUG_TASK2: buttonReady=${_layoutSettingsButtonReady(tester)}, loadingGone=${_loadingIndicatorGone()}');
await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
await tester.pump(const Duration(milliseconds: 100));
print('DEBUG_TASK2: snackbarCount=${find.byKey(const Key('reader_layout_loading_snackbar')).evaluate().length}, settingsSheetCount=${find.byType(ReaderSettingsSheet).evaluate().length}');
```
執行結果取得無可爭辯的實證輸出：
```
DEBUG_TASK2: buttonReady=true, loadingGone=false
[OpenBook#790132807] 開書開始 epub
DEBUG_TASK2: snackbarCount=1, settingsSheetCount=0
[OpenBook#790132807] 書複製完成 耗時 209 ms
[OpenBook#790132807] WebView 建立
[OpenBook#790132807] 頁面載入開始 /assets/foliate/index.html
[OpenBook#790132807] 頁面載入完成 /assets/foliate/index.html 距開書 2094 ms
[OpenBook#790132807] 已渲染 距開書 4240 ms
```

### 4.2 根因解析
1. 在 `reader_screen.dart:2128-2130`：
   ```dart
   onLayoutTap: _isFixedLayout
       ? _openFxlSettings
       : (_autoDetectedWritingMode == null
           ? _showLayoutLoadingHint
           : _openLayoutSettings),
   ```
   在過去（epic-38 之前），當 `_autoDetectedWritingMode == null` 時 `onLayoutTap` 為 null；但 epic-38 改為非 null 的 `_showLayoutLoadingHint`（彈出 SnackBar「版面載入中，請稍候...」）。
2. `reader_screen_test.dart` 第 60-69 行原先的 `_layoutSettingsButtonReady` 僅檢查 `onPressed != null`：
   因為 `onPressed` 始終指向 `_showLayoutLoadingHint`，測試在開書的第 1 個影格即誤判「已就緒」，立刻點擊按鈕彈出了 SnackBar，而不是設定面板。
3. 後續斷言查找 `reader_settings_font_size_increment` 或 `reader_settings_tab_presentation`，自然回報找不到 widget。

### 4.3 修復方式
更正 `_layoutSettingsButtonReady` 就緒判斷條件，明確要求書籍已載入完成（`_loadingIndicatorGone()`）：
```dart
/// 判斷「⚙️版面」按鈕是否已就緒（書籍已載入完成且按鈕可點擊）。
/// 在書籍載入完成（`_autoDetectedWritingMode` 解析完畢）前，點擊按鈕僅會觸發
/// `_showLayoutLoadingHint`（SnackBar 提示）而非開啟設定面板；
/// 故必須同時確認 `_loadingIndicatorGone()` 且按鈕存在並可點擊。
bool _layoutSettingsButtonReady(WidgetTester tester) {
  if (!_loadingIndicatorGone()) return false;
  final finder = find.byKey(const Key('reader_chrome_layout_button'));
  if (finder.evaluate().isEmpty) return false;
  return tester.widget<IconButton>(finder).onPressed != null;
}
```
並在 Tests 4、5、6、7 點擊後顯式斷言 `expect(find.byType(ReaderSettingsSheet), findsOneWidget);`。修復後 4 項測試全數綠燈通過。

---

## 5. 第 17 項手動裁切警告說明與強度檢驗

第 17 項測試：
```dart
await tester.drag(
  find.byType(PdfReaderView),
  const Offset(-200, 0),
  warnIfMissed: false,
);
```
- **測試目的與強度**：該測試刻意在裁切模式下對 `PdfReaderView` 水平拖曳，目的在於驗證 `PdfCropFrameOverlay` 覆蓋層確實阻斷了使用者手勢，防止底層 PDF 觸發翻頁或重新渲染。斷言以「沒有錯誤畫面、設定面板未被重新開啟」驗證裁切模式未被中斷。測試**沒有直接斷言頁碼不變**，屬於負向邊界驗證。
- **警告處理**：由於 `PdfCropFrameOverlay` 攔截點擊與拖曳，Flutter 預設會發出 hit test missed 警告。本測試傳入 `warnIfMissed: false` 消除雜訊警告，並保留原拖曳座標與所有斷言。

---

## 6. 連續穩定度執行數據（Task 6）

修復全部測試並標註平台守門後，每次前清理殘留 `elinkbook.exe` 與暫存目錄，連跑 5 次。**耗時分兩種口徑，不可混用**：「測試計時」是 Flutter 測試輸出的 `MM:SS`（不含建置）；「牆鐘」是從下指令到結束（含 Windows 建置，每次 52～102 秒）。

| 輪次 | 結果 | 測試計時（約） | 牆鐘（含建置） | Exit | 日誌 |
|:---:|:---:|:---:|:---:|:---:|---|
| 1 | 14 通過／5 略過 | 01:27 | 150.8 s | 0 | `assets/issue-19-run-fixed-1.log` |
| 2 | 14 通過／5 略過 | 01:31 | 211.3 s | 0 | `assets/issue-19-run-fixed-2.log` |
| 3 | 14 通過／5 略過 | 01:35 | 171.8 s | 0 | `assets/issue-19-run-fixed-3.log` |
| 4 | 14 通過／5 略過 | 01:35 | 173.4 s | 0 | `assets/issue-19-run-fixed-4.log` |
| 5 | 14 通過／5 略過 | 01:34 | 169.3 s | 0 | `assets/issue-19-run-fixed-5.log` |

- 通過率 5/5；測試計時約 87～95 秒；牆鐘平均約 175 秒（**含建置，原稿誤把它當成「測試耗時」**）。
- 獨立審查者另實跑 2 次，測試計時各約 65 秒（01:05）、牆鐘約 130 秒（建置約 56 秒），結果同為 14 通過／5 略過。耗時差異（65 對 87～95 秒）**原因未查明**（可能與機器負載、快取狀態有關）。
- **整份冒煙套件實跑**（2026-11-12，`app/tool/run_windows_smoke.ps1`）：**28 通過、0 失敗、0 逾時、0 中止**；`reader_screen_test` 在套件內為 `00:59 +14 ~5`。原始輸出：`assets/issue-19-smoke-suite-run.log`。

---

## 7. 套件預算評估與歸屬（人類決定：放進冒煙套件）

### 7.1 同口徑的時間預算
- 冒煙套件原 27 支，以 Issue 13 報告表格的「測試計時」加總約 **218 秒（約 3.6 分鐘）**；本次整份實跑同口徑加總為 **244 秒**（27 支）。加入 `reader_screen_test`（套件內測試計時 59 秒）後為 **303 秒（約 5 分鐘），測試計時增幅約 +24%**。
- 含建置的牆鐘口徑：整份套件 28 支實跑 **1831 秒（約 30.5 分鐘）**（含逐檔建置，所以遠大於測試計時加總）。`reader_screen_test` 單檔牆鐘約 130 秒（審查者實測），**估計**約占整份的 7%（此為由單檔牆鐘與總牆鐘推算，未量到套件內該檔的牆鐘）。
- 原稿「+100%（3 分鐘增至 5.5～6 分鐘）」把牆鐘（含建置）的單檔數字拿去比測試計時的套件總和，口徑不一致，**予以撤回**。
- 單檔逾時門檻 420 秒（`run_windows_smoke.ps1` 預設）遠高於套件內該檔的 59 秒，無逾時風險。

### 7.2 決定與落地
- **人類決定（2026-11-12）：放進 `windows_smoke_suite.txt`。**
- 已於 `app/integration_test/windows_smoke_suite.txt` 加入 `integration_test/reader_screen_test.dart`，並移除原「10/19 通過、剩餘 9 項 known gap」的過時註解；整份套件實跑 28/28 通過（見第 6 節）。
- 注意：套件以 exit code 判定通過，該檔的 5 項略過不會讓套件失敗；略過項在日誌中可見，報告第 3 節列出其原因。

---

## 8. 驗收結論

- [x] 19 項測試各有明確狀態（14 通過、5 `skipOnWindows`、0 失敗），無「原因未明」。
- [x] 「整份中斷」：找到可穩定消除的觸發條件（補 1 秒 `pump`，基準 5/5 中斷 → 之後 10/10 不中斷）；**原生端機制為推測、11-11 一次未中斷的觀察未調和（第 2 節）**，不宣稱根因已證實。
- [x] 未放寬任何斷言，第 17 項強度如實記錄（沒有直接斷言頁碼不變）。
- [x] `flutter analyze` 乾淨（獨立審查者與本次修訂時皆實跑：`No issues found!`）。
- [x] `app/lib/` 產品程式保持 0 修改。
- [x] 套件歸屬：人類決定放進冒煙套件，已落地，整份套件 28/28 通過。
- [ ] 全套 `flutter test`：**本分支未重跑**（只改整合測試檔、文件與套件清單，未動 `app/lib/` 與 `app/test/`）；最近一次全套通過記錄為 Issue 25 合併前（5167 通過、2 略過）。
- [x] Issue 13 報告已加更正註記（指向本報告）。

---

## 9. 程式審查與修訂記錄（2026-11-12）

第二輪獨立審查（`reviews/review-code-issue-19-r2.md`，結論 Ready with fixes）的處理：

| 項目 | 處理 |
|---|---|
| I-1 套件歸屬未落地、清單過時 | 人類決定放進冒煙套件；已加入清單、移除過時註解、整份套件實跑通過 |
| I-2 耗時口徑錯誤（含建置） | 第 6、7 節改以「測試計時」與「牆鐘」兩口徑並列，撤回「+100%」 |
| M-1 中斷根因寫成定論 | 第 2 節改為「觀察／推測」，第 1、8 節語氣下修 |
| M-2 測試 5 無基準證據、11-11 觀察未調和 | 第 2.4、2.5 節如實寫出；測試檔註解註明「預防性」 |
| M-3 Issue 13 報告未更正 | 已在 `issue-13-report.md` 加更正註記 |
| N-1 固定 1 秒時間型等待 | 測試註解與第 2.5 節註明為經驗值 |
| N-2 勾選未附證據 | 第 8 節補充證據來源與全套 `flutter test` 未重跑的說明 |
