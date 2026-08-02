# Epic 8 Issue 7 — PocketBase 自架 SOP 文件 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 產出一份完整、可實際照做的 PocketBase 自架 SOP 文件，涵蓋最低版本需求、4 個同步用 collection 的建立步驟、部署方式、備份建議、墓碑清理排程；並依此文件實際建立一個可連線的測試用 PocketBase 實例，供 Epic 8 其餘 Issue（2／4／5）的 `integration_test` 使用。

**Architecture:** 純文件交付物（不含 App 程式碼），單一 Markdown 檔案 `docs/epics/epic-8-sync/pocketbase-self-hosting.md`，依 `spec.md`「PocketBase Collection Schema」逐欄位對照撰寫。每個 Task 撰寫文件的一個章節後，**立即依該章節的步驟實際操作一次**（啟動真實 PocketBase 實例、真的建立 collection、真的送一次 Batch API 測試請求、真的載入 `pb_hooks` 腳本），用實際操作結果驗證文件本身寫得對不對——這是本 Issue 唯一的「測試」方式（issues.md 已明訂為「人工檢核，非自動化測試」），不是自動化 `flutter test`。

**Tech Stack:** PocketBase（Go 單一執行檔／Docker）、JavaScript（`pb_hooks`）、curl（驗證 API）。**不需要** Flutter/Dart 環境。

## Global Constraints

- **PocketBase 版本 ≥ 0.39.10**（撰寫本計畫時查證的目前最新版本，遠高於 spec.md 訂出的最低需求 ≥ 0.23／Batch API 所需版本）；文件本身標註「≥ 0.23」為最低需求、同時建議實際使用時盡量抓最新穩定版。
- **修正 spec.md／issues.md 原文措辭的一項事實錯誤**：issues.md Issue 7「基本部署建議」原文寫「官方 Docker image」，經查證 PocketBase 官方（`pocketbase.io/docs`、GitHub repo `pocketbase/pocketbase`）**並未發布任何官方 Docker image**，官方唯一發布的產物是可直接執行的單一二進位檔（`pocketbase_<version>_<os>_<arch>.zip`，見 GitHub Releases）。本計畫因此改為文件同時提供「直接下載執行檔執行」（最簡單、最貼近官方唯一支援的方式）與「自製最小 Dockerfile」（給想要容器化部署的自架者）兩種選項，**不聲稱**任何一種是「官方」提供的容器映像。
- **Batch API 需要在 Dashboard 手動啟用**（撰寫本計畫時查證 `pocketbase.io/docs/api-records/` 得知，spec.md／issues.md 原文皆未提及此步驟）：預設關閉，須在 `Settings → Application` 找到 Batch API 相關設定並啟用，否則 App 端呼叫 `/api/batch` 會失敗。這是本文件必須新增、原規格沒有涵蓋到的關鍵步驟。
- **`deleted_at` 欄位單位約定為毫秒**（`DateTime.now().millisecondsSinceEpoch`，與本機 SQLite `deleted_at` 欄位同單位、同值直接透傳，不做秒/毫秒轉換）——這是本文件新訂的慣例，供 Issue 4（同步引擎）推送 `deleted_at` 值時遵循，也是 Task 3 的 `pb_hooks` 清理腳本篩選邏輯的前提。
- **文件語言**：正體中文（比照全專案文件慣例），程式碼／指令／欄位名稱維持原文。
- **良好驗收判準**（比照 issues.md 既有慣例，非自動化測試）：每個 Task 結尾皆要求「實際操作一次、貼上真實輸出」，不是「理論上應該可行」。

---

### Task 1：最低版本需求 + 啟動一個 PocketBase 實例

**Files:**
- Create：`docs/epics/epic-8-sync/pocketbase-self-hosting.md`

**Interfaces:**
- Consumes：無（本 Task 是整份文件的起點）
- Produces：一個實際運作中的本機 PocketBase 實例（`http://127.0.0.1:8090`），供 Task 2-4 接續操作；文件「最低版本需求」與「啟動方式」兩節，供 Task 2-4 的讀者接續閱讀

- [x] **Step 1：建立文件檔案，寫入標題與最低版本需求章節**

建立 `docs/epics/epic-8-sync/pocketbase-self-hosting.md`：

```markdown
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
```

- [x] **Step 2：撰寫「啟動方式」章節（兩種選項）**

在上一步內容之後新增：

```markdown

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
```

- [x] **Step 3：實際操作一次，驗證章節內容正確**

依 Step 2 寫的「選項 A」（或選項 B，擇一即可，兩者皆驗證過更好）實際執行：

```bash
curl -LO https://github.com/pocketbase/pocketbase/releases/download/v0.39.10/pocketbase_0.39.10_linux_amd64.zip
unzip pocketbase_0.39.10_linux_amd64.zip -d pocketbase
cd pocketbase
./pocketbase serve &
sleep 2
curl -sf http://127.0.0.1:8090/api/health
```

Expected：`curl` 對 `/api/health` 回傳 HTTP 200 與類似 `{"code":200,"message":"API is healthy.","data":{}}` 的 JSON；瀏覽器開啟 `http://127.0.0.1:8090/_/` 能看到建立管理員帳號的畫面。若指令或版本號與實際查證結果有出入（例如查證當下已有更新的版本、或 zip 檔名格式有變動），回頭修正 Step 1/2 的文件內容，確保文件寫的是**親自驗證過的真實步驟**，不是憑印象寫的。

- [x] **Step 4：Commit**

```bash
git add docs/epics/epic-8-sync/pocketbase-self-hosting.md
git commit -m "docs(epic-8-sync): Issue 7 Task 1 — PocketBase 自架 SOP：最低版本需求與啟動方式"
```

---

### Task 2：Collection 建立步驟 + 啟用 Batch API

**Files:**
- Modify：`docs/epics/epic-8-sync/pocketbase-self-hosting.md`

**Interfaces:**
- Consumes：Task 1 產出的運作中 PocketBase 實例（管理員帳號已建立）
- Produces：4 個 collection（`sync_reading_positions`／`sync_bookmarks`／`sync_highlights`／`sync_notes`）與 Batch API 皆已在該實例上實際建立/啟用完成，供 Task 3/4 接續使用；文件「Collection 建立步驟」章節

- [x] **Step 1：撰寫「建立 collection」章節**

在 `docs/epics/epic-8-sync/pocketbase-self-hosting.md` 「啟動方式」章節之後新增：

```markdown

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
```

- [x] **Step 2：撰寫「啟用 Batch API」章節**

緊接著新增：

```markdown

## 啟用 Batch API

**這是容易漏掉的一步**：PocketBase 的 `/api/batch` 端點預設是**關閉**
的，需要手動啟用，否則 App 端 checkpoint 同步的批次上傳會直接失敗。

前往 **Settings → Application**，找到 Batch API 相關設定並啟用；同時
確認「單批最大請求數」一類的上限設定 **不低於 100**（App 端每批次最多
送 100 筆異動，見 `spec.md`「同步引擎」，伺服器端上限設太低會導致
偶爾的大批次同步被拒絕）。不同 PocketBase 版本這個設定畫面的確切
欄位名稱可能略有差異，以自己安裝的版本畫面實際顯示的文字為準。
```

- [x] **Step 3：實際操作一次，驗證章節內容正確**

依 Step 1 的表格，在 Task 1 啟動的 PocketBase 實例上，透過 Admin UI 實際建立全部 4 個 collection 與對應欄位/規則，並依 Step 2 啟用 Batch API。完成後，執行以下驗證：

```bash
# 確認 4 個 collection 皆存在（需要先在 Admin UI 用管理員帳號登入，
# 從瀏覽器開發者工具或 Dashboard 的 API 預覽功能取得一個有效的管理員
# token，替換下方 <ADMIN_TOKEN>）
curl -s http://127.0.0.1:8090/api/collections \
  -H "Authorization: <ADMIN_TOKEN>" | grep -o '"name":"sync_[a-z_]*"'
```

Expected：輸出包含 `"name":"sync_reading_positions"`、`"name":"sync_bookmarks"`、`"name":"sync_highlights"`、`"name":"sync_notes"` 四筆。

再驗證 Batch API 確實已啟用且可用（此時尚未有任何使用者帳號，改用管理員權限直接測試端點是否回應，不驗證實際的 `user = @request.auth.id` 規則行為——規則行為留給 Task 4 用真實使用者帳號驗證）：

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8090/api/batch \
  -H "Content-Type: application/json" \
  -d '{"requests": []}'
```

Expected：回傳 HTTP 狀態碼非 `404`（`/api/batch` 端點存在，若 Batch API 未啟用，PocketBase 會回傳能辨識的錯誤而非 404 not found，若這裡确實是 404 代表版本太舊或啟用步驟有誤，回頭檢查 Step 2 的操作）。

- [x] **Step 4：Commit**

```bash
git add docs/epics/epic-8-sync/pocketbase-self-hosting.md
git commit -m "docs(epic-8-sync): Issue 7 Task 2 — PocketBase 自架 SOP：4 個 collection 建立步驟與 Batch API 啟用"
```

---

### Task 3：備份建議 + 墓碑清理 `pb_hooks` Cron 範例

**Files:**
- Modify：`docs/epics/epic-8-sync/pocketbase-self-hosting.md`
- Create：`docs/epics/epic-8-sync/pb_hooks_example/purge_tombstones.pb.js`（文件內附的可直接複製範例檔案，非 App 程式碼）

**Interfaces:**
- Consumes：Task 2 已建立的 4 個 collection（`sync_bookmarks`／`sync_highlights`／`sync_notes` 的 `deleted_at` 欄位）
- Produces：`pb_hooks` cron 範例腳本，實際載入 Task 1/2 的 PocketBase 實例後可正常運作；文件「備份建議」／「墓碑清理」兩節

- [x] **Step 1：撰寫「備份建議」章節**

在「建立 Collection」章節之後新增：

```markdown

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
```

- [x] **Step 2：撰寫「墓碑清理」章節與範例腳本**

先建立範例腳本 `docs/epics/epic-8-sync/pb_hooks_example/purge_tombstones.pb.js`：

```javascript
/// @file purge_tombstones.pb.js
/// 定期清理 sync_bookmarks/sync_highlights/sync_notes 三個 collection
/// 中超過 30 天的軟刪除紀錄（deleted_at 為毫秒時間戳記，與本機 App 端
/// 透傳的值同單位，見 docs/epics/epic-8-sync/spec.md「墓碑清理」）。
/// 使用方式：把本檔案複製到 PocketBase 執行檔同層的 pb_hooks/ 目錄下
/// （沒有這個目錄就自己建立一個），重啟 PocketBase 即會自動載入。

cronAdd("purgeOldTombstones", "0 3 * * *", () => {
  const collections = ["sync_bookmarks", "sync_highlights", "sync_notes"];
  const thirtyDaysMillis = 30 * 24 * 60 * 60 * 1000;
  const cutoffMillis = Date.now() - thirtyDaysMillis;

  for (const collectionName of collections) {
    const records = $app.findRecordsByFilter(
      collectionName,
      "deleted_at != null && deleted_at < {:cutoff}",
      "",
      500,
      0,
      { cutoff: cutoffMillis }
    );
    let purged = 0;
    for (const record of records) {
      // 個別紀錄刪除失敗（例如資料庫瞬間鎖定）不應該中斷整批清理——
      // 沒清到的紀錄下一次排程（明天同一時間）會再嘗試一次，不需要
      // 在單一次失敗時就放棄同一批次裡其餘本來刪得掉的紀錄。
      try {
        $app.delete(record);
        purged++;
      } catch (e) {
        console.log(
          `[purgeOldTombstones] ${collectionName}: 刪除紀錄 ${record.id} 失敗，將於下次排程重試：${e}`
        );
      }
    }
    console.log(
      `[purgeOldTombstones] ${collectionName}: 清理 ${purged}/${records.length} 筆超過 30 天的墓碑`
    );
  }
});
```

接著在 `pocketbase-self-hosting.md`「備份建議」章節之後新增：

```markdown

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
```

- [x] **Step 3：實際操作一次，驗證 `pb_hooks` 腳本正確載入**

把 Step 2 建立的 `purge_tombstones.pb.js` 複製進 Task 1 啟動的 PocketBase 實例的 `pb_hooks/` 目錄，重新啟動該實例：

```bash
mkdir -p pocketbase/pb_hooks
cp docs/epics/epic-8-sync/pb_hooks_example/purge_tombstones.pb.js pocketbase/pb_hooks/
cd pocketbase
./pocketbase serve
```

Expected：啟動輸出**不應**出現任何 JS 語法錯誤或 `cronAdd` 相關的錯誤訊息（PocketBase 載入 `pb_hooks/*.pb.js` 時若語法有誤會在啟動 log 直接報錯並中止）。

若可行，額外驗證排程確實已註冊（Admin UI 的 **Settings → Crons** 頁面應該會列出 `purgeOldTombstones` 這個工作項目，含下次執行時間）；不需要真的等到凌晨 3 點才能驗證，看到它出現在 Crons 清單即代表 `cronAdd` 呼叫成功、語法正確。

- [x] **Step 4：Commit**

```bash
git add docs/epics/epic-8-sync/pocketbase-self-hosting.md docs/epics/epic-8-sync/pb_hooks_example/purge_tombstones.pb.js
git commit -m "docs(epic-8-sync): Issue 7 Task 3 — PocketBase 自架 SOP：備份建議與墓碑清理 pb_hooks 範例"
```

---

### Task 4：建立測試用 PocketBase 實例供 Issue 2／4／5 使用 + 端到端驗收

**Files:**
- Modify：`docs/epics/epic-8-sync/pocketbase-self-hosting.md`

**Interfaces:**
- Consumes：Task 1-3 的全部產出（運作中的 PocketBase 實例，4 個 collection、Batch API、`pb_hooks` 皆已就緒）
- Produces：一個持續運作、可供 Issue 2／4／5 的 `integration_test` 實際連線使用的測試用 PocketBase 實例；文件「測試環境」章節，記錄該實例的連線資訊供後續 Issue 的實作者查閱

- [x] **Step 1：撰寫「測試環境」章節**

在文件結尾（「墓碑清理」章節之後）新增：

```markdown

## 測試環境（供 Epic 8 其餘 Issue 使用）

依本文件 Task 1-3 的步驟，已實際建立一份測試用 PocketBase 實例，供
`epic-8-sync` Issue 2（同步帳號模組）／Issue 4（同步引擎核心）／
Issue 5（閱讀位置衝突彈窗）的 `integration_test` 連線使用。

- **Base URL（從開發機本身連線）**：`http://127.0.0.1:8090`
- **Base URL（從 Android 模擬器內連線）**：`http://10.0.2.2:8090`
  ——Android 模擬器把 `10.0.2.2` 保留為「宿主機的 localhost」，這是
  Android 官方模擬器網路轉發的既定行為，`integration_test` 若跑在
  模擬器上須改用這個位址，不能直接用 `127.0.0.1`（那會指向模擬器
  自己）。跑在實體裝置上時兩者皆不適用，需改成開發機在區網內的實際
  IP（例如 `http://192.168.x.x:8090`），且手機與開發機須在同一個
  區網。
- **測試帳號**：`integration_test` 執行前，先透過 Admin UI 或
  `POST /api/collections/users/records` 建立至少一個測試用 email+
  password 帳號（不要用 Task 1 建立的 PocketBase **管理員**帳號，
  那是另一套系統，見 Task 1「首次啟動」一節的提醒）。
- **保持運作**：這個測試實例在 Issue 2／4／5 開發期間需要持續運作，
  建議用 Task 1「選項 B」的 Docker 方式跑在背景（`docker run -d`），
  不要用「選項 A」的前景 `./pocketbase serve` 跑完就關掉終端機。
```

- [x] **Step 2：端到端驗收（對照 issues.md Issue 7 的 4 項人工驗收標準逐一確認）**

依序確認以下 4 點，每點皆為**實際操作**而非紙上檢查：

1. **依文件步驟可從零開始成功建立一個運作中的 PocketBase 實例**：找一個全新的暫存目錄，只依照 `pocketbase-self-hosting.md` 從頭到尾的文字步驟操作（不看本計畫、不使用任何個人記憶捷徑），確認能順利跑到 `curl http://127.0.0.1:8090/api/health` 回應 200。

2. **4 個 collection 皆正確建立，欄位/型別/API rule 與 `spec.md` 一致**：對照 `spec.md`「PocketBase Collection Schema」章節的表格，逐一核對 Admin UI 上 4 個 collection 的欄位名稱/型別/必填/API Rules 是否完全一致（含 `sync_reading_positions` 沒有自訂 `updated_at` 欄位、其餘三者皆有 `client_id`/`book_fingerprint`/`deleted_at`）。

3. **依文件建立的測試用 PocketBase 實例可供 Issue 2／4／5 的 `integration_test` 實際連線使用**：用 curl 建立一個測試帳號並登入，確認能拿到有效的 auth token：

   ```bash
   curl -s http://127.0.0.1:8090/api/collections/users/records \
     -H "Content-Type: application/json" \
     -d '{"email":"test@example.com","password":"test1234","passwordConfirm":"test1234"}'

   curl -s http://127.0.0.1:8090/api/collections/users/auth-with-password \
     -H "Content-Type: application/json" \
     -d '{"identity":"test@example.com","password":"test1234"}'
   ```

   Expected：第二個指令回應內含 `"token"` 欄位（非空字串），證明帳密登入流程確實可用。再用這個 token 對 `sync_bookmarks` 送一筆測試 create，確認 `user = @request.auth.id` 規則生效（用這個使用者自己的 token 可以新增成功；換一個不同使用者的 token 或不帶 token 應該被拒絕）：

   ```bash
   TOKEN="<上一步取得的 token>"
   curl -s http://127.0.0.1:8090/api/collections/sync_bookmarks/records \
     -H "Authorization: $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"user":"<上一步登入回應內的使用者 id>","client_id":"test-bm-1","book_fingerprint":"fp1","name":"測試書籤"}'
   ```

   Expected：回應為 HTTP 200，回傳的紀錄內容含剛剛送出的欄位值。

4. **`pb_hooks` 墓碑清理範例語法正確、可實際載入運作**：已在 Task 3 Step 3 驗證過（PocketBase 啟動 log 無錯誤、Crons 頁面出現 `purgeOldTombstones`），此處只需確認測試用實例（Task 1-3 建立的同一個）仍帶著這個 `pb_hooks` 腳本持續運作，不需要重複驗證一次。

若以上任何一點驗證失敗，回到對應的 Task 修正文件內容（而不是在這裡想辦法繞過去讓驗證「看起來」通過）。

- [x] **Step 3：Commit**

```bash
git add docs/epics/epic-8-sync/pocketbase-self-hosting.md
git commit -m "docs(epic-8-sync): Issue 7 Task 4 — PocketBase 自架 SOP：測試環境章節與端到端驗收"
```

---

## Self-Review Notes（撰寫計劃時的自我檢查）

**Spec 覆蓋檢查**（對照 `issues.md` Issue 7「驗收標準」4 項，皆為人工檢核）：

1. 依文件步驟可從零開始成功建立一個運作中的 PocketBase 實例 → Task 1（撰寫＋實際操作驗證）＋ Task 4 Step 2 第 1 點（用全新暫存目錄重跑一次，排除「作者自己記得怎麼做」的偏差）。
2. 4 個 collection 皆正確建立，欄位/型別/API rule 與 `spec.md` 一致 → Task 2（撰寫＋逐一在真實實例上建立）＋ Task 4 Step 2 第 2 點（逐欄位對照 `spec.md` 表格複查）。
3. 依文件建立的測試用 PocketBase 實例可供 Issue 2／4／5 的 `integration_test` 實際連線使用 → Task 4 Step 1（記錄連線資訊，含 Android 模擬器 `10.0.2.2` 這個容易漏掉的細節）＋ Step 2 第 3 點（實際跑一次帳密登入＋API rule 生效驗證）。
4. `pb_hooks` 墓碑清理範例語法正確、可實際載入運作 → Task 3（撰寫＋實際複製進真實實例重啟驗證，含查看 Crons 頁面確認排程確實註冊）。

**Placeholder 掃描**：全文無 TBD/TODO 字樣，`pb_hooks` 範例、Dockerfile、curl 驗證指令皆為完整可執行內容（`cronAdd`／`$app.findRecordsByFilter`／`$app.delete` 語法已對照 PocketBase 官方文件查證，非憑印象杜撰；Docker release 檔名已對照 GitHub Releases API 實際回應確認）。

**型別一致性檢查**：Task 2 文件表格定義的 4 個 collection 欄位名稱與型別，與 `spec.md`「PocketBase Collection Schema」章節逐字對應（`client_id`／`book_fingerprint`／`deleted_at`／各 collection 專屬欄位）；Task 3 的 `deleted_at` 毫秒單位約定與 Task 2 表格的欄位備註一致；Task 4 的驗收 curl 範例使用的欄位名稱（`user`／`client_id`／`book_fingerprint`／`name`）與 `sync_bookmarks` 的欄位定義一致。

**與既有專案慣例的差異說明**：本 Issue 是 Epic 8 第一個「純文件、需要實際操作真實外部服務驗證」的工單，測試方式與其餘程式碼類工單（`flutter test`/`flutter analyze`）不同，改用「每個 Task 結尾實際操作一次、貼真實輸出」——這與 issues.md Issue 7 本身標注的「驗收標準（人工檢核，非自動化測試）」完全一致，不是計畫本身自創的例外。

**對 spec.md／issues.md 原文的修正**：撰寫計畫過程中查證發現「官方 Docker image」這個說法不準確（PocketBase 官方未發布任何 Docker image），已在 Task 1 的 Global Constraints 與文件內容中改為「直接執行檔（官方唯一支援方式）＋自製最小 Dockerfile（非官方）」兩個選項，並在計畫開頭明確記錄此修正，供合併後若要回頭同步修正 `spec.md`/`issues.md` 措辭時參考（本計畫不代為修改那兩份文件，依專案慣例「審查/計畫階段發現的既有文件問題先記錄、不擅自修改」）。另外查證發現 spec.md 未提及的「Batch API 需要在 Dashboard 手動啟用」這個必要步驟，已補進 Task 2。

## 審查修正紀錄（`tmp/epic-8/plan-issue-7-review.md`）

程式碼審查（`/superpowers:requesting-code-review`，2026-08-03）結論「正式通過」，0 Critical。逐項核對後採納 2 項 Minor：

- **確認屬實，已採納**：Task 3 的 `purge_tombstones.pb.js` 迴圈內 `$app.delete(record)` 若單筆拋出例外（例如資料庫瞬間鎖定）會中斷整個 cron handler，讓同一批次裡本來刪得掉的其餘紀錄也一併沒清到。已改為單筆 `try/catch` 包裹，個別失敗只記錄 log（含失敗紀錄 `id`，供事後排查）並繼續處理下一筆，不影響同批次/同批 collection 其餘紀錄的清理；`console.log` 統計文字同步改為 `已清理筆數/總筆數`，反映真實成功比例。
- **確認屬實，已採納**：PocketBase 的 `user = @request.auth.id` 規則只驗證「送進來的紀錄本身」欄位值，不會自動幫忙把 `user` 欄位填成目前登入者——這點容易被誤解成「規則裡寫了 `@request.auth.id` 就會自動代入」。已在 Task 2「建立 Collection」章節的 API Rules 說明後補上明確提醒，且指出 Task 4 的 `curl` 驗收範例已示範正確帶法（原本就有帶，只是前面章節缺一句提醒讀者「這是必要的、不是自動的」）。
