# Epic 52 — 上架 Google Play：Discovery 決策

2026-09-27 `/grill-with-docs` 的結果。上架流程本身寫在 `docs/research/google_play_release_sop.md`，這裡只記錄決策和原因。

## 已確認的事實

- 套件名稱是 `cc.ugotit.elinkbook`，版本是 `1.0.0+1`。
- `app/android/app/build.gradle.kts` 的 release 建置用 `signingConfigs.getByName("debug")` 簽章。
- `AndroidManifest.xml` 宣告了 `FOREGROUND_SERVICE_MEDIA_PLAYBACK`（朗讀功能）。
- App 只能登入 PocketBase 同步帳號，不能註冊（`app/lib/sync/sync_client.dart` 只呼叫 `authWithPassword`）。
- `app/config/cloud_oauth.json` 的 `GOOGLE_OAUTH_CLIENT_SECRET` 有值，表示 Google Drive 用的是 Desktop 類型用戶端，不綁 SHA-1。
- 隱私權政策在 `https://www.ugotit.cc/privacy`（原始檔 `site/privacy.html`），可以不登入打開，但沒有寫 PocketBase 同步服務。

## 決策

| # | 題目 | 決定 | 原因 |
|---|---|---|---|
| Q1 | SOP 的讀者 | 只給發布者本人 | 只有一個人發版 |
| Q2 | SOP 範圍 | 第一次上架、每次發新版、測試軌道推進 | — |
| Q3／Q8 | 開發者帳號 | 個人帳號，2023-11-13 以前建立 | 不用跑 12 人、連續 14 天的封閉測試 |
| Q4 | 簽章 | Play App Signing | 上傳金鑰遺失還能申請重設 |
| Q5 | 建置與上傳 | 手動 | 先走通流程，之後再考慮自動化 |
| Q6 | SOP 位置 | `docs/research/google_play_release_sop.md` | 跟 PocketBase SOP 放一起 |
| Q9 | 上傳金鑰位置 | `C:\Users\huthief\.android-keys\`，備份放密碼管理器 | 比照 `.gitea_token` 放家目錄 |
| Q10 | 版本號 | versionCode 每次上傳加 1；versionName 依修 bug／新功能／大改版調整 | — |
| Q11／Q14 | 隱私權政策網址 | `https://www.ugotit.cc/privacy` | 已經有獨立網址，不用 `#/privacy` |
| Q12 | Google Drive 用戶端 | 維持 Desktop 類型，不登記 SHA-1 | 已經能用；改 Android 類型要維護兩份設定檔 |
| Q13 | 隱私權政策缺同步服務 | 上架前補上 | 要跟資料安全性表單一致 |
| Q15 | 商店語言 | 只做正體中文 | 目標使用者讀直排中文 |
| Q16 | 價格 | 免費 | — |
| Q17 | 國家／地區 | 全部 | — |
| Q18 | 目標年齡 | 13 歲以上 | 不套用家庭政策 |
| Q19 | 朗讀前景服務 | 保留，錄不公開的 YouTube 示範影片 | 錄影比改程式簡單 |
| Q20 | 商店素材 | 放 `store/google-play/zh-TW/`；圖示從 `assets/appicon_v2.jpg`（1024×1024）轉檔 | 放進版控，改版時找得到 |
| Q21 | 程式變更 | 開本 Epic，不寫進 SOP | 符合 SDD 流程 |
| Q22 | 商店名稱 | `elinkBook 易閱書` | 跟網站一致 |
| Q23 | 版本號提醒 | `node app/tool/bump_version.js` 互動式腳本 | 會主動詢問，也會一起更新對照表 |
| Q24 | 版本對照表 | `store/google-play/release-log.md` | 只跟 Play 發布有關，跟素材放一起 |
| — | git tag | 每次上傳後打 `v<versionName>+<versionCode>` | 看 tag 就知道 Play 版本對應哪個 commit |
| Q25 | Google Drive／OneDrive 在政策裡的描述 | 「備份同步」改成「匯入書籍」 | 實際只用唯讀權限匯入，要跟資料安全性表單一致 |
| Q26 | 政策第三節的不實承諾 | 改成符合事實的寫法 | 本機資料庫沒有加密、一人維運沒有保密協議，寫了做不到的事反而是風險 |
| Q27 | 同步伺服器由誰提供 | 使用者自架，ugotit.cc 不提供 | `SyncAccountRepository.defaultBaseUrl` 是空字串；政策、SOP 2.2／2.3、Issue 2 都照此修正 |
| Q28 | Issue 2 的流程 | 不寫 `plan-issue-2.md`，由發布者直接審閱新舊文字 | 只有法律文字，只有發布者能判斷寫得對不對 |

## 不在範圍內

- 建置和上傳自動化（fastlane、CI）。
- Google OAuth 同意畫面的正式發布審查與 CASA 評估。這跟 Play 上架是兩條不同的審查，SOP 第 4 部分有說明。
- 英文商店頁面。
- 商店素材的設計製作。SOP 只列規格。
