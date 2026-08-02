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
