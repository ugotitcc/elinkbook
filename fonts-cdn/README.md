# `fonts-cdn/`：elinkBook 可下載字型服務

App 不打包任何字型檔（見 `docs/adr/0035-downloadable-fonts-via-r2-worker.md`）。使用者在「字型管理」點下載時，App 從這裡部署的 Cloudflare Worker 取得字型；Worker 從 R2 bucket `elinkbook-fonts` 讀檔。

## 目錄內容

| 路徑 | 用途 |
|---|---|
| `fonts.json` | 字型清單：`id`（對應 App 的 `AppFont` 列舉名）、本機檔案、發布路徑、位元組大小、SHA-256。**單一事實來源**，App 端的字型目錄必須和它一致（Issue 4 有 Dart 測試比對） |
| `fonts/` | 5 款字型原檔；`fonts/licenses/` 是各字型的 SIL OFL 授權檔 |
| `worker/index.js` | Worker：只提供 `GET`／`HEAD /v<N>/<檔名>.ttf` |
| `scripts/` | 自我檢查、上傳、線上驗證腳本 |
| `test/` | Worker 與腳本的 Node 測試 |
| `deploy-wizard.sh` | 第一次部署的引導腳本 |

## 發布規則

- 已發布的檔案**永遠不覆蓋、不刪除**。已安裝的舊版 App 寫死了網址與 SHA-256，覆蓋會讓它們下載失敗。
- 字型改版時，發布到新的版本路徑（例如 `v2/<檔名>`），並在 `fonts.json` 新增或更新條目，App 發新版時同步更新字型目錄。
- `upload.mjs` 上傳前會逐一檢查目標 key：不存在就上傳；已存在且內容和清單完全一致（大小與 SHA-256）就略過；已存在但內容不同，就整批中止、不上傳任何檔案。所以上傳到一半中斷時，直接重跑就能補傳剩下的字型，不需要也不可以刪除已上傳的檔案。
- `upload.mjs` 是透過 `--base-url` 檢查 key 是否已存在，實際上傳則寫到 `--bucket`。兩者必須是同一套服務：`--base-url` 一定要填正在服務該 bucket 的 Worker 網址，填錯的話，「不覆蓋」的保護會失效。

## 常用指令（在 repo 根目錄執行，只需要 Node.js 24）

```bash
node fonts-cdn/scripts/check_manifest.mjs                     # 本機檔案與清單是否一致
node fonts-cdn/test/test_worker.mjs                           # Worker 測試
node fonts-cdn/test/test_scripts.mjs                          # 上傳／驗證腳本測試
node fonts-cdn/scripts/verify_remote.mjs --base-url <網址>     # 線上驗證
bash fonts-cdn/deploy-wizard.sh                               # 第一次部署
```

## 費用

R2 免費額度：儲存 10GB、每月 1,000 萬次讀取、下載流量不收費；Worker 免費額度：每天 10 萬次請求。目前 5 款字型合計約 140MB，遠低於上限。啟用 R2 必須綁定付款方式。
