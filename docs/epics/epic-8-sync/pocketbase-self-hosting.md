# PocketBase 自架 SOP（elinkBook 雲端同步）

本文件供自行架設 elinkBook 雲端同步後端使用，對照
[`spec.md`](spec.md)「PocketBase Collection Schema」／「墓碑清理」／
「同步引擎」撰寫。伺服器部署本身（雲端主機選擇、網域/HTTPS 憑證等）
不在本文件範圍內（見 `design.md`「明確排除」），本文件只涵蓋「PocketBase
本身要怎麼裝、怎麼設定成 elinkBook 可用的狀態」。

## 最低版本需求

- **PocketBase ≥ 0.23**（App 端 checkpoint 同步依賴 Batch API `/api/batch`，
  該端點需要這個版本以上才有）。
- 建議實際使用時直接抓
  [GitHub Releases](https://github.com/pocketbase/pocketbase/releases)
  最新穩定版，不需要刻意鎖在 0.23——本文件撰寫當下最新版本為
  `0.39.10`，後續章節的指令皆以此版本號示範，自架時請自行替換成當時的
  最新版本號。

## 啟動方式

PocketBase 官方只發布單一可執行檔（不含任何官方 Docker image，見
[GitHub Releases](https://github.com/pocketbase/pocketbase/releases)
與[官方文件](https://pocketbase.io/docs/)——皆未提供任何容器映像）。
以下提供兩種啟動方式，擇一即可。

### 選項 A：直接執行（最簡單，官方唯一直接支援的方式）

```bash
# Linux amd64 範例，其他平台請至 Releases 頁面換成對應檔名
# （例如 darwin_arm64／windows_amd64／linux_arm64）
curl -LO https://github.com/pocketbase/pocketbase/releases/download/v0.39.10/pocketbase_0.39.10_linux_amd64.zip
unzip pocketbase_0.39.10_linux_amd64.zip -d pocketbase
cd pocketbase
./pocketbase serve
```

啟動後終端機會顯示類似：

```
Server started at http://127.0.0.1:8090
├─ REST API:  http://127.0.0.1:8090/api/
└─ Dashboard: http://127.0.0.1:8090/_/
```

### 選項 B：自製最小 Dockerfile（非官方映像，自行容器化用）

```dockerfile
FROM alpine:3.20
ARG PB_VERSION=0.39.10
RUN apk add --no-cache unzip ca-certificates && \
    wget https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip && \
    unzip pocketbase_${PB_VERSION}_linux_amd64.zip -d /pb && \
    rm pocketbase_${PB_VERSION}_linux_amd64.zip
EXPOSE 8090
VOLUME /pb/pb_data
ENTRYPOINT ["/pb/pocketbase", "serve", "--http=0.0.0.0:8090"]
```

```bash
docker build -t elinkbook-pocketbase .
docker run -d --name elinkbook-pocketbase -p 8090:8090 -v $(pwd)/pb_data:/pb/pb_data elinkbook-pocketbase
```

### 首次啟動：建立管理員帳號

不論選哪個選項，首次啟動後瀏覽器開啟 `http://127.0.0.1:8090/_/`
會要求建立第一個管理員帳號（email + 密碼），這是 **PocketBase 管理員
帳號**，與 App 使用者的 elinkBook 同步帳號（PocketBase Auth `users`
collection）是完全不同的兩件事，不要混淆。

## 建立 Collection

登入管理後台（`http://127.0.0.1:8090/_/`）之後，依序建立以下 4 個
collection。每個都在 **Collections → New collection** 建立，**Type**
選 **Base**，逐一在 **Fields** 分頁新增欄位，再到 **API Rules** 分頁
設定規則。所有欄位除了下表標「必填」的以外皆為選填（`Nonempty`
不勾）。

**批次建立（可取代下方逐一手動點 Admin UI 的步驟）**：把
`pb_migrations_example/1785715200_create_sync_collections.js` 複製到
PocketBase 執行檔同層的 `pb_migrations/` 目錄下（沒有這個目錄就自己
建立一個），重啟 PocketBase（或執行 `./pocketbase migrate up`）即會
在一個交易內自動建立好全部 4 個 collection，欄位/型別/必填/API
Rules 皆與下方表格逐項對應。適合需要重複自架多個測試環境、或想把
整個 schema 納入版本控制的情況；只想快速看一次 Admin UI 長怎樣的話，
仍可照下方步驟手動建立，兩種方式擇一即可，不需要都做。

四個 collection 的 **API Rules** 分頁皆設為同一組規則（4 個 List/
Search、View、Create、Update、Delete 規則欄位皆填相同內容）：

```
user = @request.auth.id
```

這確保每個使用者只能讀寫自己名下的紀錄（`user` 欄位見下方，是一個
指向 PocketBase 內建 `users` collection 的 relation 欄位）。

**容易誤解的地方**：`user = @request.auth.id` 這條規則只是「驗證送進來
的紀錄，其 `user` 欄位值是否等於目前登入者」，PocketBase **不會**自動
幫忙把 `user` 欄位填成目前登入者——App 端呼叫 Create API（或本文件
稍後的 Batch API）時，**必須在請求的 JSON body 裡明確帶上
`"user": "<目前登入者的 user id>"` 這個欄位**，漏帶會被這條規則直接
擋下、回傳 validation error，不是「自動判斷失敗」。下方 Task 4 的
`curl` 驗收範例已示範這個帶法。

### `sync_reading_positions`

一筆代表「某使用者、某本書」的閱讀進度（FR-19）。

| 欄位名稱 | 型別 | 必填 | 設定備註 |
|---|---|---|---|
| `user` | Relation | 是 | 目標 collection 選 `users`，Max select 選 `Single` |
| `book_fingerprint` | Text | 是 | |
| `epub_locator` | Text | 否 | |
| `pdf_page_index` | Number | 否 | |
| `progress` | Number | 是 | |

不需要額外新增 `updated_at`——PocketBase 每個 collection 內建的
`updated`／`created` 系統欄位（Dashboard 上會自動出現，不需手動新增）
已足夠作為衝突比對基準（見 `spec.md`「PocketBase Collection Schema」）。

### `sync_bookmarks`

| 欄位名稱 | 型別 | 必填 | 設定備註 |
|---|---|---|---|
| `user` | Relation | 是 | 同上，目標 `users`，Single |
| `client_id` | Text | 是 | |
| `book_fingerprint` | Text | 是 | |
| `deleted_at` | Number | 否 | 毫秒時間戳記（`DateTime.now().millisecondsSinceEpoch`），與本機 SQLite `deleted_at` 同單位、同值直接透傳，非 PocketBase 系統時間 |
| `name` | Text | 是 | |
| `epub_locator_json` | Text | 否 | |
| `progression` | Number | 否 | |
| `pdf_page_index` | Number | 否 | |

### `sync_highlights`

| 欄位名稱 | 型別 | 必填 | 設定備註 |
|---|---|---|---|
| `user` | Relation | 是 | 同上 |
| `client_id` | Text | 是 | |
| `book_fingerprint` | Text | 是 | |
| `deleted_at` | Number | 否 | 同 `sync_bookmarks`，毫秒時間戳記 |
| `style` | Text | 是 | |
| `epub_locator_json` | Text | 否 | |
| `progression` | Number | 否 | |
| `pdf_page_index` | Number | 否 | |
| `pdf_rect_json` | Text | 否 | |

### `sync_notes`

| 欄位名稱 | 型別 | 必填 | 設定備註 |
|---|---|---|---|
| `user` | Relation | 是 | 同上 |
| `client_id` | Text | 是 | |
| `book_fingerprint` | Text | 是 | |
| `deleted_at` | Number | 否 | 同 `sync_bookmarks`，毫秒時間戳記 |
| `text` | Text | 是 | |
| `epub_locator_json` | Text | 否 | |
| `progression` | Number | 否 | |
| `highlight_client_id` | Text | 否 | 依附劃線時填該劃線的 `client_id`，見 `spec.md`「跨裝置參照設計」 |
| `pdf_page_index` | Number | 否 | |
| `pdf_rect_json` | Text | 否 | |

PocketBase 內建的 `id` 系統欄位（每個 collection 皆自動具備）**不要**
跟上表的 `client_id` 搞混——`id` 純粹是 PocketBase 內部管理用途，
App 端完全不讀取/比對它（見 `spec.md`）。

## 啟用 Batch API

**這是容易漏掉的一步**：PocketBase 的 `/api/batch` 端點預設是**關閉**
的，需要手動啟用，否則 App 端 checkpoint 同步的批次上傳會直接失敗。

前往 **Settings → Application**，找到 Batch API 相關設定並啟用；同時
確認「單批最大請求數」一類的上限設定 **不低於 100**（App 端每批次最多
送 100 筆異動，見 `spec.md`「同步引擎」，伺服器端上限設太低會導致
偶爾的大批次同步被拒絕）。不同 PocketBase 版本這個設定畫面的確切
欄位名稱可能略有差異，以自己安裝的版本畫面實際顯示的文字為準。

## 備份建議

PocketBase 本身用單一 SQLite 檔案（`pb_data/data.db`，隨執行檔/容器
啟動目錄而定）當儲存後端，備份只需要定期複製整個 `pb_data` 目錄。

最簡單的做法是 cron 排程搭配 `tar`：

```bash
# 加進 crontab（crontab -e），每天凌晨 3 點備份一次，保留最近 7 份
0 3 * * * tar -czf /backups/elinkbook-pb-$(date +\%Y\%m\%d).tar.gz -C /path/to/pocketbase pb_data && find /backups -name 'elinkbook-pb-*.tar.gz' -mtime +7 -delete
```

備份前建議先確認 PocketBase 沒有正在寫入中的長時間交易（一般個人
自架、低流量情境下直接複製檔案已經足夠安全；高流量正式環境建議另外
研究 SQLite 線上備份 API，不在本文件範圍內）。

## 墓碑清理

App 端刪除劃線/備註/書籤時採軟刪除（寫入 `deleted_at` 而非真的刪除，
供其他裝置同步時判斷「這筆已被刪除」，見 `spec.md`「本機 Schema
變更」／「同步引擎」）。本機端的墓碑由 App 自己的同步引擎清理
（`SyncEngine.runCheckpoint()` 每次成功推送後自動清理超過 30 天的本機
墓碑），但**伺服器端**（PocketBase 上 `sync_bookmarks`／
`sync_highlights`／`sync_notes` 三個 collection）不會有任何一台裝置
主動幫忙清，需要自架者自行設定伺服器端排程清理，否則刪除紀錄會在
PocketBase 端無限期累積。

PocketBase 支援用 `pb_hooks` 目錄下的 JS 檔案定義排程工作（cron）。
把 [`pb_hooks_example/purge_tombstones.pb.js`](pb_hooks_example/purge_tombstones.pb.js)
複製到自己 PocketBase 執行檔同層的 `pb_hooks/` 目錄下（沒有這個目錄
就自己建立一個），重啟 PocketBase 即會自動載入、每天凌晨 3 點執行一次
清理超過 30 天的墓碑。

30 天是初始建議值（與 App 端本機清理用同一個數字，比照 5 分鐘閒置
計時器同等級的「非定案硬性需求」），可依實際自架規模自行調整
`purge_tombstones.pb.js` 內的 `thirtyDaysMillis` 常數。

## 測試環境（供 Epic 8 其餘 Issue 使用）

依本文件 Task 1-3 的步驟（實際透過 `pb_migrations_example/
1785715200_create_sync_collections.js` 批次建立），已在
`http://pbdev.jigong.org` 架好一份**持續運作**的測試用 PocketBase
實例（Docker + Traefik，容器名稱 `elinkbook-pocketbase`），供
`epic-8-sync` Issue 2（同步帳號模組）／Issue 4（同步引擎核心）／
Issue 5（閱讀位置衝突彈窗）的 `integration_test` 連線使用，取代原本
規劃「開發者各自在本機起一個臨時測試實例」的做法——這是實際網路上
可連到的網域，開發機／Android 模擬器／實體裝置皆可直接用同一個
base URL 連線，不需要再依連線來源切換 `127.0.0.1`／`10.0.2.2`／
區網 IP（2026-08-03 改為此環境後的修正，見下方「已知部署細節」）。

- **Base URL（任何連線來源皆同一個，不需依裝置別切換）**：
  `http://pbdev.jigong.org`——目前是 **HTTP，不是 HTTPS**（Traefik
  只設定了 `web`／HTTP entrypoint，未掛 HTTPS 憑證，見下方「已知
  部署細節」）。**不要加 `:8090` 埠號**——Traefik 對外只監聽標準
  HTTP（80）埠並反向代理到容器內部的 8090，`http://pbdev.jigong.org:8090`
  連不到（外部沒有對應這個埠的路由），只有不含埠號的
  `http://pbdev.jigong.org` 才是正確的對外連線位址（2026-08-03
  Issue 2 `integration_test` 除錯時實測確認過這個混淆點，記錄於此
  避免下次重蹈覆轍）。
- **裝置端必須連上 Tailscale 才能連到這個網域**：`pbdev.jigong.org`
  實際掛在 Tailscale 私有網路（DNS 解析出的是 Tailscale 內部的
  CGNAT IP，例如 `100.98.175.79`），**不是**公開網際網路可直接連到
  的網域。任何要執行 `integration_test` 的裝置（開發機／Android
  模擬器／實體裝置）都必須先在該裝置上啟動並登入 Tailscale（連上
  同一個 tailnet），否則 DNS 雖然解析成功、但實際連線會 100% 逾時／
  失敗——`SyncClient.testConnection()` 遇到這種情況會正確地回傳
  `false`（連線失敗的預期行為，不是程式碼 bug）。2026-08-03 Issue 2
  的 `integration_test` 真機驗證時，就是先在裝置上把 Tailscale
  連線起來後才測試通過，先前失敗正是因為裝置上的 Tailscale 沒有
  連線／登入。
- **測試帳號**（`epic-8-sync` Issue 2 起各 Issue 的 `integration_test`
  共用，已建立於上述實例）：
  - email：`epic8-issue2-test@example.com`
  - password：`epic8-test-password-123`
  - 不要跟 PocketBase **管理員**（superuser）帳號搞混，那是另一套
    系統，見 Task 1「首次啟動」一節的提醒；管理員密碼不落地存放在
    版本控制內，需要時另外詢問。
- **已知部署細節**（供之後排查連線問題參考）：自架端的
  `docker-compose.yml` 曾發生 `HOOKS_PATH`／`MIGRATIONS_PATH` 兩個
  volume 掛載誤用同一個環境變數、導致 `pb_hooks/` 內容被同時掛進
  `/pb/pb_migrations`，PocketBase 把 `purge_tombstones.pb.js` 誤當
  migration 執行、撞上 migration 執行環境沒有 `cronAdd` 全域函式而
  panic 崩潰——已修正為各自獨立的 `HOOKS_PATH`／`MIGRATIONS_PATH`
  變數（`docker/.env`／`docker/.env.example`／
  `docker/docker-compose.yml`，非本文件所在的 App 版本控制範圍，
  是另一個自架用的 Docker 專案目錄）。
