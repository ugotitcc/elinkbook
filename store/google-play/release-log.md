# Google Play 版本對照表

每次上傳到 Google Play 都記一筆。流程見 `docs/research/google_play_release_sop.md`。

- 建置前在 `app/` 下執行 `node tool/bump_version.js`，腳本會自動加一筆「內部測試」紀錄。
- 推到正式版時，手動加一筆，軌道寫「正式版」，commit 欄位抄內部測試那一筆。
- 內部測試版有問題、沒推到正式版時，在說明欄註記「棄用」。
- 日期格式：`YYYY-MM-DD`。
- commit：執行 `bump_version.js` 當下的 HEAD，也就是這一版程式碼的最後一個 commit。git tag 指向之後的版本號 commit，兩者相差一個 commit。
- **表格必須放在檔案最後**。腳本會把新紀錄加在檔案結尾。
- 腳本以表格裡**最大的** versionCode 檢查新號碼，不是最後一列。把較舊的版本推到正式版時，最後一列會比較小，這是正常的。

| versionName | versionCode | 日期 | 軌道 | commit | 說明 |
|---|---|---|---|---|---|
