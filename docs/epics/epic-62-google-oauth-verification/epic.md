# `epic-62-google-oauth-verification` Google OAuth 驗證回覆（隱私權政策修訂＋登出撤銷授權）

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-62-google-oauth-verification/`
**關聯 PRD 章節：** 檔案匯入（Google Drive）；關聯已歸檔 `epic-29-cloud-import`

## 背景

專案 `jielink` 申請 `drive.readonly`（受限範圍）驗證，Google 於 2026-10-06 退回，要求：

1. 補充為何需要該 scope、為何不能用更窄的 scope。
2. 隱私權政策不得有「用於提供／改善功能以外的用途」與「轉移給第三方」的敘述。
3. 重錄完整展示 scope 使用情境的 Demo 影片（同意畫面完整展開、scope 與 Console 完全一致）。

## 決策

- 維持 `drive.readonly`（方案 C）。App 內建資料夾瀏覽（`files.list`）與資料夾批次匯入無法以 `drive.file`＋Picker 取代；Picker 在無 Google Play Services 的 E-Ink 裝置上不可靠。
- 不改為 SAF 或 Picker（已評估並否決）。

## 範圍

- `site/privacy.html`：新增「Google 使用者資料」一節與 Limited Use 聲明；第五節刪除學術／公務機關統計分析與違反條款兩項例外，授權同意與急迫危險兩項註明不適用於 Google 使用者資料。
- `GoogleDriveOAuthClient.unlink()`：登出時先盡力呼叫 `https://oauth2.googleapis.com/revoke` 撤銷 refresh token，再清除本機憑證；撤銷失敗不擋登出。OneDrive 不在範圍。

## 非程式待辦（使用者執行）

- [ ] 部署 `site/` 並確認 `https://www.ugotit.cc/privacy` 顯示新內容。
- [ ] Cloud Console 的 scope 清單與程式碼一致（`drive.readonly`、`email`、`openid`、`profile`）。
- [ ] 更新 scope 使用理由、重錄 Demo 影片（測試環境錄製）、回信給 Google。
- [ ] 回信詢問：資料只存裝置本機，是否仍需 CASA 資安評估（以 Google 實際回覆為準）。

## 開發記錄

**2026-10-06 直接 TDD**

- 處理方式：直接 TDD，不寫 `plan-issue-N.md`。
- 紅燈：`google_drive_oauth_client_test.dart` 新增「unlink 向 Google 撤銷授權」4 個測試（正常撤銷、斷網、回 400、未連結），修正前撤銷請求未送出而 FAIL。
- 驗證：`test/cloud_import` 與 `cloud_account_settings_screen_test.dart` 共 79 通過；`flutter analyze` 乾淨。僅跑受影響測試檔，未跑全套，未在真機實測撤銷。
