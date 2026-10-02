# elinkBook 雲端同步協定與 Collection 欄位定義

本文件說明 elinkBook（易閱書）如何與 PocketBase 後端同步資料。目標讀者有兩類：

- 自行架設同步後端的人：看「Collection 欄位定義」與「墓碑清理」。
- 想寫相容客戶端的人：看全部。

部署方式請見 [`docker/README.md`](../docker/README.md)。

## 1. 基本規則

- 後端是 PocketBase，版本需 `>= 0.23`（需要 Batch API）。
- 帳號使用 PocketBase 內建的 `users` Collection（email＋密碼）。
- 同步內容共 4 種：閱讀位置、書籤、劃線、備註。
- 書籍用「內容指紋」（`book_fingerprint`）辨識，不用檔名或本機 id。
- 所有衝突比較與下載游標，一律用 PocketBase 在伺服器蓋章的 `updated` 欄位。不使用任何裝置自己的時鐘，避免時鐘不準造成誤判。
- 4 個 Collection 都只允許本人讀寫。

## 2. 書籍內容指紋

`book_fingerprint` 的計算方式：

- EPUB：優先用 OPF 的 identifier。identifier 為空時，改用整份檔案的 SHA-256。
- PDF、TXT 等其他格式：用整份檔案的 SHA-256。
- 大檔案必須串流計算，不可一次讀進記憶體。

接收端收到指紋找不到對應書籍時，先暫緩這筆紀錄，等使用者匯入同一本書後再套用。

## 3. Collection 欄位定義

4 個 Collection 都是 `base` 類型。`pb_migrations/` 會在首次啟動時自動建立它們。

### 3.1 API rules

5 條規則（list、view、create、update、delete）統一為：

```
user = @request.auth.id
```

這條規則只驗證「送進來的 `user` 欄位值」。客戶端建立紀錄時，必須在 payload 明確帶入 `"user": "<目前登入者的 user id>"`，PocketBase 不會自動代入。

### 3.2 `created` 與 `updated`

PocketBase v0.23 起，這兩個欄位要明確宣告為 `autodate` 才會存在。4 個 Collection 都已宣告：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `created` | autodate | 建立時由伺服器蓋章 |
| `updated` | autodate | 每次寫入由伺服器蓋章，是衝突比對與下載游標的基準 |

### 3.3 `sync_reading_positions`

一筆代表「某使用者、某本書」的閱讀進度。

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| `user` | relation（users） | 是 | 擁有者 |
| `book_fingerprint` | text | 是 | 書籍內容指紋 |
| `epub_locator` | text | 否 | EPUB 系列格式的 CFI |
| `pdf_page_index` | number（整數） | 否 | PDF 頁碼 |
| `progress` | number | 是 | 進度百分比 |

唯一索引：`(user, book_fingerprint)`。每位使用者對每本書至多一筆。

### 3.4 `sync_bookmarks`、`sync_highlights`、`sync_notes` 共通欄位

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| `user` | relation（users） | 是 | 擁有者 |
| `client_id` | text | 是 | 客戶端產生的 UUID，同一位使用者底下唯一 |
| `book_fingerprint` | text | 是 | 書籍內容指紋，純文字，不是 relation |
| `deleted_at` | number（整數） | 否 | 軟刪除時間，毫秒時間戳記。`0` 表示未刪除 |

PocketBase 內建的 `id` 只供 PocketBase 內部使用。客戶端不讀取、不比對它。

### 3.5 `sync_bookmarks` 額外欄位

| 欄位 | 型別 | 必填 |
|---|---|---|
| `name` | text | 是 |
| `epub_locator_json` | text | 否 |
| `progression` | number | 否 |
| `pdf_page_index` | number（整數） | 否 |

### 3.6 `sync_highlights` 額外欄位

| 欄位 | 型別 | 必填 |
|---|---|---|
| `style` | text | 是 |
| `epub_locator_json` | text | 否 |
| `progression` | number | 否 |
| `pdf_page_index` | number（整數） | 否 |
| `pdf_rect_json` | text | 否 |

### 3.7 `sync_notes` 額外欄位

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| `text` | text | 是 | 備註內容 |
| `epub_locator_json` | text | 否 | |
| `progression` | number | 否 | |
| `highlight_client_id` | text | 否 | 這則備註依附的劃線 `client_id` |
| `pdf_page_index` | number（整數） | 否 | |
| `pdf_rect_json` | text | 否 | |

## 4. 同步流程

客戶端在 3 種時機觸發一次 checkpoint：App 進入背景、離開閱讀畫面、閱讀中閒置 5 分鐘。同一時間只執行一次 checkpoint。執行中又被觸發時，後來的觸發直接放棄。

一次 checkpoint 依序做 5 件事：

1. **閱讀位置衝突預檢**。本機這本書的位置有新異動時，先查伺服器上該筆紀錄的 `updated`。這個值跟本機上次同步時記下的值不同，代表其他裝置推送過新位置。此時詢問使用者要保留本機或雲端版本，選擇前不上傳這本書的位置。
2. **推送**。把本機自上次推送後的異動（含軟刪除）組成 Batch API 請求。每批最多 100 筆，超過就拆成多個請求依序送出。每筆 payload 都要帶 `user`。
3. **記錄推送完成**。推送成功後，更新本機的「上次推送完成時間」。
4. **下載**。對 4 個 Collection 各查詢一次「`updated` 晚於上次下載游標」的紀錄。找得到 `client_id` 就覆寫，找不到就新增。`deleted_at` 大於 0 的視同已刪除。
5. **更新下載游標**。游標設為這次查到的最大 `updated`。這次沒查到新紀錄就維持原值。

任何一步失敗，整次 checkpoint 視為失敗，不更新任何游標。下次觸發時整批重試。重複推送相同內容只會多一次無害的更新，不會造成資料錯誤。

## 5. 墓碑清理

刪除資料時不直接刪紀錄，而是把 `deleted_at` 設為刪除當下的毫秒時間戳記。這筆紀錄稱為墓碑。墓碑讓其他裝置在下次同步時知道要刪除本機資料。

墓碑保留 30 天，之後才真正刪除：

- **客戶端**：每次 checkpoint 成功後，刪除本機 `deleted_at` 早於 30 天前的紀錄。
- **伺服器**：由 PocketBase 的 cron hook 負責。範例在 [`docker/pb_hooks_example/purge_tombstones.pb.js`](../docker/pb_hooks_example/purge_tombstones.pb.js)，每天 03:00 執行。

**注意**：篩選條件要寫 `deleted_at > 0`，不可寫 `deleted_at != null`。PocketBase 的 number 欄位沒有 NULL，沒被刪除的紀錄存的是 `0`。寫成 `!= null` 會把所有正常紀錄當成墓碑刪掉。

## 6. 相關文件

- [`docker/README.md`](../docker/README.md)：用 Docker 部署 PocketBase。
- [`docs/research/synology_dsm7_pocketbase_sop.md`](research/synology_dsm7_pocketbase_sop.md)：Synology DSM 7 部署手冊。
- [`docs/research/oracle_cloud_pocketbase_sop.md`](research/oracle_cloud_pocketbase_sop.md)：Oracle Cloud 部署手冊。
