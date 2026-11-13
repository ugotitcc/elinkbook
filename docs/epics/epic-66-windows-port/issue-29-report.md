# Epic 66 Issue 29 驗證與實作報告：Windows 資料收進 `文件\elinkbook`

- **對應規格**：[`docs/epics/epic-66-windows-port/issues.md`](issues.md)（Issue 29）、[`epic.md`](epic.md) 決策 33、[`ADR 0044`](../../adr/0044-windows-data-under-documents-elinkbook.md)、[`ADR 0043`](../../adr/0043-windows-installer-inno-setup-unsigned-per-user.md)
- **執行計畫**：[`docs/epics/epic-66-windows-port/plans/plan-issue-29.md`](plans/plan-issue-29.md)
- **日期**：2026-11-13
- **結論**：所有自動化單元測試、防散落掃描測試、本機安裝/升級/解除安裝自動化驗證、檔案落點驗證，以及使用者於另一台電腦的人工 GUI 驗證皆已通過。

---

## 一、已查證事實與實作摘要

1. **所有 `getApplicationDocumentsDirectory()` 呼叫點（共 9 個檔案）**：
   - 已替換為集中函式 `appDocumentsDirectory()`（[`app/lib/platform/app_paths.dart`](../../../app/lib/platform/app_paths.dart)）的 7 個檔案：
     - `lib/library/sqlite_library_repository.dart`（`defaultLibraryDatabasePath`）
     - `lib/dictionary/storage/dictionary_database.dart`（`defaultDictionaryDatabasePath`）
     - `lib/cloud_import/cloud_book_downloader.dart`
     - `lib/library/book_import_service_impl.dart`（3 處：`covers`、`imported_books`、`update_staging`）
     - `lib/main.dart`（`sweepUpdateStaging`）
     - `lib/remote/remote_book_downloader.dart`
     - `lib/wifi_transfer/wifi_transfer_http_server.dart`
   - 唯一保留直接呼叫的檔案：`lib/reader/foliate_native_bridge.dart`（第 187 行，僅在 Android 路徑執行，Windows 在第 173 行即提前返回）。
   - `lib/remote/remote_thumbnail_cache.dart` 第 66 行僅為文件註解提及。
2. **集中函式設計**：
   - `appDocumentsDirectory()` 以 `isWindowsPlatform`（`defaultTargetPlatform == TargetPlatform.windows`）判斷：Windows 回傳並遞迴建立 `<文件>\elinkbook`（`kWindowsAppFolderName = 'elinkbook'`）；非 Windows 平台原樣回傳 `getApplicationDocumentsDirectory()`，不建立任何子目錄。
3. **不遷移舊資料**：
   - 不讀、不改、不刪「文件」根目錄之舊資料，亦不在 App 內提示（見 ADR 0044）。
4. **解除安裝範圍縮減**：
   - [`app/windows/packaging/elinkbook.iss`](../../../app/windows/packaging/elinkbook.iss) 移除 `DocsFolderNames()` 與 `DocsDbNames()` 固定名稱清單，改為僅刪除 `{userappdata}\cc.ugotit\elinkbook` 與 `{userdocs}\elinkbook` 兩個明確資料夾（詢問框預設「否」，靜默模式不刪，App 執行中拒絕解除安裝）。
5. **說明文件更新**：
   - 更新 [`app/windows/packaging/README.txt`](../../../app/windows/packaging/README.txt) 第三節、第七節，與 [`app/tool/README.md`](../../../app/tool/README.md) 之 `verify_windows_uninstall_data.ps1` 小節；核對 [`ADR 0043`](../../adr/0043-windows-installer-inno-setup-unsigned-per-user.md) 決策 5 與後果已與最終實作一致。

---

## 二、單元測試與防散落掃描測試

1. **Task 1 新增測試**（`flutter test test/platform/app_paths_test.dart test/library/windows_data_location_test.dart`）：
   - `app_paths_test.dart`（4 項）：先紅（找不到 `app_paths.dart`）後綠（`00:00 +4: All tests passed!`），涵蓋含空格與中文假目錄、已存在不報錯、不碰「文件」根目錄舊檔、Android/iOS 原樣回傳不建資料夾。
   - `windows_data_location_test.dart`（2 項）：先紅（Windows 路徑缺少 `elinkbook` 層）後綠（`00:00 +6: All tests passed!`）。
2. **Task 2 防散落掃描測試**（`test/platform/documents_directory_usage_test.dart`）：
   - **先紅證據**（替換前執行）：準確抓出 5 個檔案共 7 行違規：
     ```text
     lib/cloud_import/cloud_book_downloader.dart:49
     lib/library/book_import_service_impl.dart:1379
     lib/library/book_import_service_impl.dart:1390
     lib/library/book_import_service_impl.dart:1403
     lib/main.dart:263
     lib/remote/remote_book_downloader.dart:67
     lib/wifi_transfer/wifi_transfer_http_server.dart:371
     ```
   - **替換後**：`00:00 +1: All tests passed!`
   - 受影響既有測試盤點：以 `Select-String` 掃描 `test/` 內同時使用 `debugDefaultTargetPlatformOverride` 與 `FakePathProviderPlatform`/`getApplicationDocumentsDirectory` 的檔案，僅有本次新增的兩個測試檔，無既有測試受影響。
   - 相關測試目錄（`test/library test/remote test/wifi_transfer test/cloud_import test/dictionary test/platform`）：`01:17 +1116 ~1: All tests passed!`（1 個既有的 skipped，0 失敗）。
3. **全套分析、l10n 與單元測試（最終版）**：
   - `flutter analyze`：`No issues found!`
   - `node tool/check_l10n_hardcoded_strings.js`：3 條檢查全數 PASS（337 個原始碼檔、399 個測試檔、58 個 integration 測試檔）。
   - 全套 `flutter test`：**`08:07 +5174 ~2: All tests passed!`**（0 失敗，2 skipped）。

---

## 三、本機實機檔案落點與舊資料隔離驗證

1. **啟動前基準（2026-11-13 15:55:47，開發機 `C:\Users\fycdc\Documents`）**：
   - `library.db`：172,032 bytes，`LastWrite=2026-11-06T12:53:44.6642641+08:00`
   - `covers`：116 檔，總大小 7,016,029 bytes，`LastWrite=2026-11-13T08:39:13.8358433+08:00`
   - `imported_books`：96 檔，總大小 1,947,056 bytes，`LastWrite=2026-11-13T08:39:10.0901936+08:00`
   - `dictionary.db`、`cloud_import_books`、`remote_books`、`wifi_transfer_uploads`、`update_staging`：均不存在（`MISSING`）。
2. **啟動暫存目錄版 `elinkbook.exe` 30 秒後結束行程樹（Task 4 Step 1，經由最新完整建置之 `app/build/windows_zip/stage/elinkbook/elinkbook.exe`）**：
   - 新位置 `C:\Users\fycdc\Documents\elinkbook\library.db`：已建立（172,032 bytes）。
   - 根目錄 `library.db`：172,032 bytes，`LastWrite=2026-11-06T12:53:44.6642641+08:00`（**完全不變**）。
   - 根目錄 `covers`：116 檔，7,016,029 bytes，`LastWrite=2026-11-13T08:39:13.8358433+08:00`（**完全不變**）。
   - 根目錄 `imported_books`：96 檔，1,947,056 bytes，`LastWrite=2026-11-13T08:39:10.0901936+08:00`（**完全不變**）。
   - 根目錄沒有新增任何 App 項目。

---

## 四、Windows 冒煙套件（`run_windows_smoke.ps1`）

- 28 支測試彙整結果：**通過 26 / 失敗 2 / 逾時 0 / 中止 0**。
- 連續跑測中失敗的 2 支（`integration_test/foliate_txt_test.dart`、`integration_test/foliate_cbz_test.dart`），於隨後單獨重跑皆全數通過（`+1: All tests passed!`、`+3: All tests passed!`），證實為連續跑測環境下的既有偶發不穩定，與本變更無關。

---

## 五、安裝程式本機自動驗證與解除安裝資料驗證

1. **最終打包產物**：
   - `app/build/windows_installer/elinkbook-1.1.0-b3-windows-x64-setup.exe`（17.76 MB）
   - SHA256：`F804E33BB07A515DE656F93878E969EA964F4F88D479FC8E5950CAB46D7E7B49`
2. **`verify_windows_installer.ps1`（29 項，含現場由新版暫存目錄編譯之 `1.0.9+1` 較舊版覆蓋升級驗證）**：
   - **29 項全數通過**（靜默安裝、HKCU 登錄項、無 HKLM、必備檔與無測試資源/除錯檔、逐檔比對 80 檔 0 差異、開始功能表與桌面捷徑、啟動存活 20 秒、執行中覆蓋升級、靜默解除安裝、取消桌面捷徑、執行中拒絕解除安裝、資料保護 341 檔 0 消失、結束無殘留）。
3. **`verify_windows_uninstall_data.ps1`（於使用者本機互動式桌面終端執行，UI Automation）**：
   - 假「文件」根目錄放入舊項目誘餌（`covers\a.bin`、`imported_books\b.bin`、`library.db`、`dictionary.db` 等），資料放入 `fake-docs\elinkbook\` 與 `fake-appdata\cc.ugotit\elinkbook`。
   - **正驗證（10/10 通過）**：
     ```text
     [通過] 0 編譯測試用安裝程式 :: 資料根目錄指向 C:\Users\fycdc\AppData\Local\Temp\含 空格 與 中文 uninstall-data-verify 下的假資料夾（不是真實的 %APPDATA% 與「文件」）
     [通過] 1a 安裝測試用安裝程式 :: 安裝到 C:\Users\fycdc\AppData\Local\Temp\含 空格 與 中文 uninstall-data-verify\app
     [通過] 1b 解除安裝時出現資料詢問框 :: 已偵測到含「所有資料（包含書庫）」的詢問框；處理訊息框 2 個
     [通過] 1c 詢問框預設按鈕為「否」 :: 「否」鈕取得鍵盤焦點: True
     [通過] 1d 程式已移除 :: 解除安裝行程結束、程式檔與登錄項皆消失
     [通過] 1e 選「否」：所有資料原封不動 :: 消失 0 項
     [通過] 2a 重新安裝測試用安裝程式 :: 安裝到 C:\Users\fycdc\AppData\Local\Temp\含 空格 與 中文 uninstall-data-verify\app
     [通過] 2b 解除安裝並選「是」 :: 詢問框已出現並按「是」；解除安裝行程結束: True
     [通過] 2c 選「是」：elinkbook 兩個資料夾已刪除 :: 仍存在 0 項（fake-docs\elinkbook 與 cc.ugotit\elinkbook）
     [通過] 2d 選「是」：根目錄的舊項目與其他檔案原封不動 :: 消失 0 項；文件根目錄存在: True
     全部檢查通過
     ```
   - **變異驗證（`DeleteAppData()` 暫時多加刪除根目錄 `covers`）**：
     ```text
     [失敗] 2d 選「是」：根目錄的舊項目與其他檔案原封不動 :: 消失 1 項：covers\a.bin；文件根目錄存在: True
     ```
     隨後已還原 `elinkbook.iss` 並比對差異為 0。

---

## 六、人工 GUI 驗證（另一台電腦，使用者操作）

使用者以最終打包之 `elinkbook-1.1.0-b3-windows-x64-setup.exe`（SHA256 `F804E33BB07A515DE656F93878E969EA964F4F88D479FC8E5950CAB46D7E7B49`）於另一台電腦進行以下三項驗證：
1. 安裝、匯入一本書、關閉 App 再開，書還在；
2. 確認書、封面、`library.db` 都在 `文件\elinkbook` 底下，「文件」根目錄沒有新增 App 項目；
3. 解除安裝選「是」，確認 `文件\elinkbook` 與 `%APPDATA%\cc.ugotit\elinkbook` 被刪除，「文件」內其他檔案沒動。

- **使用者回報原文**：「`1,2,3 都正確無誤`」（另一台電腦之硬體與系統環境未另行查證）。

---

## 七、舊項目手動清除清單（開發機與既有使用者注意）

本版採**不遷移舊資料**設計（見 ADR 0044），升級後書架為空，需要的書籍請重新匯入。舊版留在「文件」根目錄的檔案不會被讀取、修改或自動刪除，若欲清理可手動移除以下實際存在的項目（以本開發機 `C:\Users\fycdc\Documents` 為例）：

- `library.db`（172,032 bytes，2026-11-06）
- `covers\`（116 檔）
- `imported_books\`（96 檔）
- （若在其他機器曾使用對應功能，亦可能有：`dictionary.db`、`-wal`/`-shm`/`-journal` 附屬檔、`cloud_import_books\`、`remote_books\`、`wifi_transfer_uploads\`、`update_staging\`）

---

## 八、未驗證清單

1. **開發機 GUI 行為**：受限於 Issue 30（本機 release 版畫面空白），開發機僅驗證檔案落點，未驗證 GUI 操作。
2. **乾淨機器與舊版 Windows**：缺少 VC 執行階段與 WebView2 的乾淨環境、Windows 10 1809 相容性、真實環境 SmartScreen 行為，一律未驗證。
3. **特殊「文件」路徑環境**：OneDrive 重新導向後的「文件」資料夾、Windows 使用者帳號名稱含中文的真實系統路徑，於實機上均未驗證（僅以單元測試及假目錄覆寫測試）。
