# Synology DSM 7 Container Manager 部署 PocketBase (elinkBook 雲端同步) SOP 教學

本 SOP 教學指導如何在 **Synology DSM 7** 的 **Container Manager（容器總管）** 上建置並營運 [PocketBase](https://pocketbase.io/) 後端服務，專供 **elinkBook** 電子書閱讀器之雲端同步功能（閱讀進度、書籤、劃線、畫線備註）使用。

本文件整合了 [`docs/archive/2026-08-05-epic-8-sync/pocketbase-self-hosting.md`](../archive/2026-08-05-epic-8-sync/pocketbase-self-hosting.md) 的服務規範、Collection Schema 與自動化腳本，針對 Synology NAS 環境進行專屬步驟拆解。

---

## 1. 前置需求與架構規劃

### 1.1 系統需求
- **Synology NAS**：DSM 7.0 或以上版本。
- **套件**：已於 DSM 套件中心安裝 **Container Manager**（即 DSM 7 版本的 Docker）。
- **PocketBase 版本**：必須 **≥ v0.23**（elinkBook checkpoint 同步引擎依賴 Batch API `/api/batch`）。本 SOP 示範使用 **v0.39.10**（自架時亦可使用當時最新穩定版）。

### 1.2 目錄結構規劃 (File Station)
建議在 Synology 預設的 `docker` 共用資料夾下建立專用目錄 `/volume1/docker/elinkbook-pocketbase`：

```text
/volume1/docker/elinkbook-pocketbase/
├── docker-compose.yml                             # Docker Compose 部署檔
├── Dockerfile                                     # 自建 Alpine 容器定義檔
├── pb_data/                                       # SQLite 資料庫與檔案上傳持久化目錄
├── pb_migrations/                                 # 雲端同步 Collection Schema 遷移腳本
│   ├── 1785715200_create_sync_collections.js     # 建立 4 個同步 Collection
│   ├── 1785801600_add_created_updated_autodate_fields.js # 自動新增 created/updated 時間戳記
│   └── 1785801700_add_reading_positions_unique_index.js  # 強制單一使用者單本書閱讀位置唯二性
└── pb_hooks/                                      # 伺服器端排程腳本
    └── purge_tombstones.pb.js                     # 每日凌晨自動清理 30 天以上軟刪除墓碑
```

---

## 2. 步驟一：準備 NAS 檔案與設定檔

請先透過 Synology **File Station** 或 SSH 連線至 NAS，建立專案目錄結構並複製專案現有腳本。

### 2.1 建立 NAS 目錄
開啟 File Station，在 `docker` 共用資料夾下建立資料夾：
- `elinkbook-pocketbase`
  - `pb_data`
  - `pb_migrations`
  - `pb_hooks`

### 2.2 複製 Migration 與 Hook 腳本
將本專案內 [`docs/archive/2026-08-05-epic-8-sync/`](../archive/2026-08-05-epic-8-sync/) 隨附的範例腳本複製至 NAS 對應目錄：

1. **Schema 遷移腳本（複製至 `/volume1/docker/elinkbook-pocketbase/pb_migrations/`）**：
   - `pb_migrations_example/1785715200_create_sync_collections.js`
   - `pb_migrations_example/1785801600_add_created_updated_autodate_fields.js`
   - `pb_migrations_example/1785801700_add_reading_positions_unique_index.js`
   
   > **注意**：全新部署請務必將上述三支 Migration 檔案**同時複製**進去，以確保 `created`/`updated` 系統欄位與 unique index 完整套用。

2. **墓碑清理排程腳本（複製至 `/volume1/docker/elinkbook-pocketbase/pb_hooks/`）**：
   - `pb_hooks_example/purge_tombstones.pb.js`

### 2.3 準備 Dockerfile 與 docker-compose.yml

在 `/volume1/docker/elinkbook-pocketbase/` 目錄下建立以下兩個檔案：

#### 檔案 A: `Dockerfile`
```dockerfile
FROM alpine:3.20
ARG PB_VERSION=0.39.10

RUN apk add --no-cache unzip ca-certificates wget

# 下載官方 PocketBase Linux amd64 執行檔
RUN wget https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip && \
    unzip pocketbase_${PB_VERSION}_linux_amd64.zip -d /pb && \
    rm pocketbase_${PB_VERSION}_linux_amd64.zip

EXPOSE 8090

VOLUME ["/pb/pb_data", "/pb/pb_migrations", "/pb/pb_hooks"]

ENTRYPOINT ["/pb/pocketbase", "serve", "--http=0.0.0.0:8090"]
```

#### 檔案 B: `docker-compose.yml`
```yaml
version: '3.8'

services:
  pocketbase:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: elinkbook-pocketbase
    restart: always
    ports:
      - "8090:8090"
    volumes:
      - ./pb_data:/pb/pb_data
      - ./pb_migrations:/pb/pb_migrations
      - ./pb_hooks:/pb/pb_hooks
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8090/api/health"]
      interval: 10s
      timeout: 5s
      retries: 5
```

---

## 3. 步驟二：於 Synology Container Manager 建置並啟動專案

### 方式一：使用「專案 (Project)」一鍵部署（推薦）

1. 開啟 DSM **Container Manager**。
2. 點擊左側選單的 **專案 (Project)**，再點擊 **新增**。
3. 填寫專案設定：
   - **專案名稱**：`elinkbook-pocketbase`
   - **路徑**：選擇 `/docker/elinkbook-pocketbase`
   - **來源**：選擇「使用現有的 docker-compose.yml 建立專案」。
4. 系統會自動讀取步驟 2 建立的 `docker-compose.yml` 與 `Dockerfile`。
5. 點擊 **下一步** -> **完成**。
6. Container Manager 會自動編譯 Dockerfile 並啟動容器。

![Container Manager Project Setup Illustration](https://placeholder.local/container_manager_project)

### 方式二：手動介面建立（若不使用 Compose）

1. 在 Container Manager -> **映像檔 (Image)** 下載或匯入 Alpine 映像檔。
2. 至 **容器 (Container)** 點擊 **新增**：
   - **容器名稱**：`elinkbook-pocketbase`
   - **連接埠設定**：本機連接埠 `8090` ↔ 容器連接埠 `8090` (TCP)。
   - **儲存空間設定 (Volume Binding)**：
     - `/docker/elinkbook-pocketbase/pb_data` ↔ `/pb/pb_data`
     - `/docker/elinkbook-pocketbase/pb_migrations` ↔ `/pb/pb_migrations`
     - `/docker/elinkbook-pocketbase/pb_hooks` ↔ `/pb/pb_hooks`
   - **執行指令**：`/pb/pocketbase serve --http=0.0.0.0:8090`

---

## 4. 步驟三：初始化 PocketBase 與關聯設定

啟動容器後，請進行首次登入與關鍵 API 設定。

### 4.1 建立超級管理員 (Superuser) 帳號
1. 使用瀏覽器連線至 `http://<NAS_IP>:8090/_/`（請注意網址結尾必須包含 `/_/`）。
2. **正常狀態**：若是全新的 PocketBase 實例，畫面會自動顯示 **"Create first superuser"**（建立第一個超級管理員）引導頁面，要求設定管理員 Email 與密碼。
3. **異常狀態（直接顯示登入頁面而非建立帳號）**：
   若連線後直接出現「Email / 密碼」登入輸入框，代表 `pb_data` 目錄下**已有既存的 SQLite 資料庫**或已經存在管理員帳號。
   
   **解決方法（透過 CLI 手動新增/重設 Superuser）**：
   可開啟 NAS SSH 或 Synology **Container Manager → 容器 → `elinkbook-pocketbase` → 終端機 (Terminal)**，執行以下 CLI 命令手動建立超級管理員帳號：
   ```bash
   # 在 Synology SSH 終端機執行 (Docker Exec)
   docker exec -it elinkbook-pocketbase /pb/pocketbase superuser create admin@example.com password123
   ```
   *註：PocketBase ≥ v0.23 已將原本的 `admin` 命令改為 `superuser` 子命令。*

   > **提醒**：此帳號為 PocketBase **超級管理員帳號**，用於登入管理後台 (`/_/`)，與 elinkBook App 使用者（`users` collection）獨立分開。

### 4.2 確認 Collection 自動建立狀態
進入管理後台 **Collections** 分頁，確認以下 4 個同步 Collection 已由 Migration 自動建立完畢：

| Collection 名稱 | 說明 | API Rules (全項目) |
|---|---|---|
| `sync_reading_positions` | 閱讀進度同步 | `user = @request.auth.id` |
| `sync_bookmarks` | 書籤同步 | `user = @request.auth.id` |
| `sync_highlights` | 劃線同步 | `user = @request.auth.id` |
| `sync_notes` | 劃線備註同步 | `user = @request.auth.id` |

> **重要**：API Rule 設定 `user = @request.auth.id` 表示僅限紀錄擁有者讀寫。App 端發送 Request JSON Body 時**必須包含 `"user": "<User_ID>"` 欄位**，否則會觸發權限驗證失敗。

### 4.3 啟用 Batch API（關鍵步驟，切勿遺漏！）
elinkBook 雲端同步引擎依賴批次更新端點 `/api/batch`，預設為**停用**狀態。

1. 登入 PocketBase Admin UI (`http://<NAS_IP>:8090/_/`)。
2. 前往 **Settings → Application**。
3. 找到 **Batch API** 設定選項並勾選 **Enable**。
4. 確認「Max batch requests」（單批最大請求數）設定值 **≥ 100**。
5. 點擊 **Save changes** 儲存。

---

## 5. 步驟四：設定 Synology 反向代理與 SSL 憑證 (HTTPS)

為確保手機/閱讀器在網際網路或家用外網能安全連線，建議使用 Synology DSM 內建的反向代理伺服器與 Let's Encrypt 免費憑證。

### 5.1 設定反向代理 (Reverse Proxy)
1. 開啟 DSM **控制台 → 登入門戶 → 進階**。
2. 點擊 **反向代理伺服器 → 新增**。
3. **一般** 分頁設定：
   - **反向代理伺服器名稱**：`PocketBase-elinkBook`
   - **來源**：
     - 協定：`HTTPS`
     - 主機名稱：`pocketbase.yourdomain.com`（請替換為你的 DDNS 或自訂網域）
     - 連接埠：`443`
   - **目標**：
     - 協定：`HTTP`
     - 主機名稱：`localhost` (或 `127.0.0.1`)
     - 連接埠：`8090`
4. **自訂標頭** 分頁設定（保障 SSE 即時連線）：
   - 點擊 **新增 → WebSocket**。
   - 系統會自動建立 `Upgrade` 與 `Connection` 標頭。
5. 點擊 **儲存**。

### 5.2 套用 Let's Encrypt SSL 憑證
1. 開啟 DSM **控制台 → 安全性 → 憑證**。
2. 點擊 **新增 → 新增憑證 → 從 Let's Encrypt 取得憑證**。
3. 輸入網域名稱 `pocketbase.yourdomain.com` 並完成驗證。
4. 憑證核發後，點擊 **設定** 鈕，找到 `pocketbase.yourdomain.com` 反向代理條目，將其憑證切換為剛申請的 Let's Encrypt 憑證。

---

## 6. 步驟五：設定 Synology 任務排程表自動備份 SQLite

PocketBase 的所有資料庫與設定皆儲存於 `pb_data/data.db`。透過 DSM 任務排程表定期自動備份打包，確保資料安全。

1. 開啟 DSM **控制台 → 任務排程表**。
2. 點擊 **新增 → 排程的任務 → 使用者自訂的腳本**。
3. **一般** 分頁：
   - 任務名稱：`Backup PocketBase`
   - 使用者帳號：`root`
4. **排程** 分頁：
   - 設定每日凌晨 03:00 執行。
5. **任務設定** 分頁（使用者自訂腳本）：
   ```bash
   #!/bin/bash
   BACKUP_DIR="/volume1/docker/backups/pocketbase"
   DATA_DIR="/volume1/docker/elinkbook-pocketbase/pb_data"
   DATE=$(date +%Y%m%d_%H%M%S)

   mkdir -p ${BACKUP_DIR}

   # 打包 pb_data 資料庫
   tar -czf ${BACKUP_DIR}/elinkbook-pb-${DATE}.tar.gz -C ${DATA_DIR} .

   # 自動清理超過 30 天的舊備份檔
   find ${BACKUP_DIR} -name "elinkbook-pb-*.tar.gz" -mtime +30 -delete
   ```
6. 點擊 **確定** 儲存排程。

---

## 7. 驗收測試與常見陷阱 (Troubleshooting)

### 7.1 CLI 連線驗收測試
在個人電腦或 NAS 終端機執行以下命令，測試 API 存取與使用者註冊：

```bash
# 1. 測試 Health Check
curl -i https://pocketbase.yourdomain.com/api/health

# 2. 測試建立 App 使用者 (users collection)
curl -X POST https://pocketbase.yourdomain.com/api/collections/users/records \
  -H "Content-Type: application/json" \
  -d '{"email":"testuser@example.com", "password":"password123", "passwordConfirm":"password123"}'

# 3. 測試 Batch API 是否已正常開啟 (若未開啟會回傳 404 或 405)
curl -X POST https://pocketbase.yourdomain.com/api/batch \
  -H "Content-Type: application/json" \
  -d '{"requests":[]}'
```

### 7.2 常見陷阱與排查對照表

| 症狀 / 錯誤訊息 | 可能原因 | 排除方法 |
|---|---|---|
| App 批次上傳回傳 `HTTP 404` 或 `405` | 忘記開啟 Batch API | 前往 Admin UI (`/ _ /`) → **Settings → Application** 啟用 Batch API 並設定最大單批次 ≥ 100。 |
| App 同步寫入回傳 `HTTP 400 Validation Error` | API Rule 阻擋，或請求漏帶 `user` 欄位 | 檢查 Client 端 Request JSON 是否明確傳遞 `"user": "<user_id>"` 欄位。 |
| 容器啟動崩潰 (Panic: unexpected hook script) | Volume 雙重掛載 | 確認 `docker-compose.yml` 中 `pb_hooks` 與 `pb_migrations` 掛載路徑獨立，不可重疊。 |
| `sync_reading_positions` 寫入重複紀錄 | 缺少 Unique Index | 確認已執行 `1785801700_add_reading_positions_unique_index.js` 遷移腳本。 |
| 外網連線 `Connection Refused` | 反向代理或 Port 未對應 | 若採用 Synology 反向代理，App 設定的 Base URL 應為 `https://pocketbase.yourdomain.com`（不加 `:8090`）。 |

---

## 8. 相關參考文件
- [`docs/archive/2026-08-05-epic-8-sync/pocketbase-self-hosting.md`](../archive/2026-08-05-epic-8-sync/pocketbase-self-hosting.md)：PocketBase 原始架設說明與開發環境規格
- [`docs/archive/2026-08-05-epic-8-sync/spec.md`](../archive/2026-08-05-epic-8-sync/spec.md)：elinkBook 雲端同步 Protocol 與 Collection 欄位定義
