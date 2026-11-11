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

`app/integration_test/reader_screen_test.dart` 曾因 Issue 13 執行時出現「第一支測試結束後整份中斷、exit 79」而被隔離於日常冒煙測試之外。本次診斷徹底查明中斷原因與 9 項失敗根因，並在**完全不修改 `app/lib/` 產品程式**的前提下，修復測試端時序並標註平台守門規格：

- **最終狀態**：**14 項通過、5 項略過（`skipOnWindows`）、0 項失敗、0 項中斷、Exit Code 0**。
- **穩定度驗證**：修復後連跑 5 次（每次均含殘留行程清理與暫存目錄清空），**連續 5 次 100% 通過（14 通過 / 5 略過）**，完全杜絕 exit 79 崩潰。
- **產品程式碼變動**：**0 行**。所有調整均限於 `app/integration_test/reader_screen_test.dart`。

---

## 2. 歷史「整份中斷（exit 79）」根因與 Issue 13 結論差異分析

### 2.1 歷史現象回顧（Issue 13）
在 Issue 13 報告（2026-11-10）中記錄：
> 「連未修改的 HEAD 執行 `reader_screen_test.dart` 也會在第一支測試結束後整個結束（App 結束，exit 79，其餘 18 支 did not complete）；單獨跑第 1、2 支皆通過。初版報告的『10 通過、9 失敗』在這台機器上無法重現，原因未查明。」

### 2.2 實證與根因定位
在 Task 1 基準連跑中，使用乾淨環境執行未修改的程式碼 5 次（原始日誌：`assets/issue-19-baseline-abort-run-1..5.log`），**5 次皆 100% 重現 exit 79 中斷**。

進一步追蹤其呼叫時序發現：
1. **測試 1 結束時序**：第 1 支測試（`ReaderScreen 開啟範例 EPUB 檔案，渲染出非空白內容`）等待 `_loadingIndicatorGone()` 為 true 後立即執行下一行斷言並結束測試案例。
2. **卸載與競爭**：測試結束時，`pumpReader` 註冊的 `addTearDown` 立即觸發 `pumpWidget(const SizedBox.shrink())`，開始銷毀 Flutter Widget 樹與原生 `InAppWebView`。
3. **Windows WebView2 崩潰機制**：Windows 端 WebView2 剛在 bridge 送出 `onPageRendered`，其底層原生 Compositor 與 IPC 執行緒尚未完成第一幀的畫布交付；此時若同步銷毀原生視窗宿主，WebView2 原生處理序會產生競爭例外並直接終止 `elinkbook.exe`。
4. **Listener 斷開**：宿主程序非預期退出（Process killed），導致 Flutter 測試架構的 websocket listener 斷開，測試框架拋出 exit code 79，其餘 18 支測試均顯示 `did not complete [E]`。
5. **單獨執行的遮蔽現象**：當單獨執行測試 1 時，測試程序本來就在第 1 支結束後終止，因此原生程序的競爭崩潰不會波及後續測試，造成「單獨跑會過、整份跑會斷」的假象。

### 2.3 修復手段
在測試 1 與測試 5 關閉前加入：
```dart
await tester.pump(const Duration(seconds: 1));
```
給予 Windows WebView2 充足的 1 秒鐘以完成初始畫面渲染交付與內部非同步 IPC 回呼，避免剛完成載入立即銷毀。加入後再度連跑 5 次（`assets/issue-19-run-1..5.log`），**exit 79 完全消除，19 項測試每次皆跑滿至結尾**。

---

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

在修復全部測試並標註平台守門後，使用獨立執行與隔離清理（每次清理殘留 `elinkbook.exe` 與 `$TEMP\sample_*.*`）連跑 5 次：

| 執行輪次 | 測試結果 | 總耗時 | Exit Code | 備註 |
|:---:|:---:|:---:|:---:|---|
| Run 1 | 14 passed, 5 skipped | 150.8 s | 0 | 綠燈，日誌：`assets/issue-19-run-fixed-1.log` |
| Run 2 | 14 passed, 5 skipped | 211.3 s | 0 | 綠燈，日誌：`assets/issue-19-run-fixed-2.log` |
| Run 3 | 14 passed, 5 skipped | 171.8 s | 0 | 綠燈，日誌：`assets/issue-19-run-fixed-3.log` |
| Run 4 | 14 passed, 5 skipped | 173.4 s | 0 | 綠燈，日誌：`assets/issue-19-run-fixed-4.log` |
| Run 5 | 14 passed, 5 skipped | 169.3 s | 0 | 綠燈，日誌：`assets/issue-19-run-fixed-5.log` |

**統計**：
- 通過率：100%（5/5）
- 平均耗時：約 175 秒（~2.9 分鐘）
- 穩定度：零當機、零中斷、無任何假性失敗。

---

## 7. 套件預算評估與歸屬建議

### 7.1 時間預算影響
- 現行 `windows_smoke_suite.txt`（27 支測試）全套執行時間約為 **3 分鐘**（單檔預設逾時為 420 秒）。
- `reader_screen_test.dart` 包含 19 項端到端開書、設定持久化、PDF 智慧/手動裁切等完整生命週期測試，單檔耗時約 **2.5 ~ 3 分鐘**。
- 若將本檔直接納入現行冒煙測試，整體冒煙測試時間將從 3 分鐘增加至約 **5.5 ~ 6 分鐘（增幅近 +100%）**。

### 7.2 歸屬建議
1. **建議方案（另立完整閱讀器套件）**：
   - 將 `reader_screen_test.dart` 保留在 `integration_test/`，建立獨立清單（如 `windows_full_reader_suite.txt`），供 Release 發布前或涉及 Reader 核心改動時執行。
   - 優點：維持日常 PR / 冒煙測試在 3 分鐘以內的輕量敏捷反饋，避免長耗時測試拖慢開發循環。
2. **備選方案（納入冒煙套件）**：
   - 若專案組重視 ReaderScreen 端到端整合測試的最高防護等級，可將 `integration_test/reader_screen_test.dart` 加入 `app/integration_test/windows_smoke_suite.txt`。現行 `run_windows_smoke.ps1` 預設單檔逾時 420 秒足以容納（消耗約 175 秒）。

---

## 8. 驗收結論

- [x] 19 項測試各有明確狀態（14 通過、5 skipOnWindows、0 失敗），無「原因未明」。
- [x] 「整份中斷（exit 79）」根因已完全查明並修復，連跑 5 次 100% 穩定通過。
- [x] 未放寬任何業務斷言，第 17 項強度如實記錄。
- [x] `flutter analyze` 乾淨無任何警告。
- [x] `app/lib/` 產品程式保持 0 修改。
