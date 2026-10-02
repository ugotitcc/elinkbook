# elinkBook PocketBase 同步後端 Docker 部署說明

本目錄提供 elinkBook 雲端同步後端（PocketBase）的容器化架構檔。同步協定與 Collection 欄位定義請見 [`docs/sync-protocol.md`](../docs/sync-protocol.md)。

## 📁 檔案結構

```
docker/
├── Dockerfile                  # 容器建置檔 (Alpine 3.20 + 指定版本 PocketBase)
├── docker-compose.yml          # Docker Compose 設定檔
├── .env                        # 環境變數實體檔 (變數控管)
├── .env.example                # 環境變數範例檔
├── pb_migrations/              # 啟動時自動建立 4 個同步 Collection 的 migration
├── pb_hooks_example/           # PocketBase JS Hooks 範例
│   └── purge_tombstones.pb.js  # 定期自動清理 30 天以上軟刪除墓碑之 JS cron
└── pb_hooks/                   # Hooks 掛載目錄（需自行由範例複製，見下方快速啟動）
```

## 🚀 快速啟動

在 `docker/` 目錄下執行：

```bash
# 第一次使用：複製環境變數範例，並啟用墓碑清理 Hook
cp .env.example .env
cp -r pb_hooks_example pb_hooks

# 啟動容器 (背景執行)
docker compose up -d

# 檢視服務運作狀態
docker compose ps

# 檢視容器日誌
docker compose logs -f
```

啟動後即可透過瀏覽器存取管理員後台：
- **Admin Dashboard**: `http://localhost:8090/_/` (或改用你設定的 PORT)

## ⚙️ 環境變數說明 (.env)

| 變數名稱 | 預設值 | 說明 |
|---|---|---|
| `PB_VERSION` | `0.40.4` | PocketBase 版本 (必須 `>= 0.23` 以支援 Batch API) |
| `PORT` | `8090` | 宿主機映射之對外 HTTP 埠號 |
| `CONTAINER_NAME` | `elinkbook-pocketbase` | 容器名稱 |
| `DATA_PATH` | `./pb_data` | 資料持久化儲存目錄 |
| `HOOKS_PATH` | `./pb_hooks` | PocketBase JS Hooks 掛載目錄 |

## 📌 注意事項

1. **首次啟動管理員**：連線至 `http://localhost:8090/_/` 建立 PocketBase 系統管理員帳號。
2. **Collection 與 API Rules**：`pb_migrations/` 會在首次啟動時自動建立 `sync_reading_positions`、`sync_bookmarks`、`sync_highlights` 與 `sync_notes` 四個 Collection，API Rules 統一為 `user = @request.auth.id`。欄位定義請見 [`docs/sync-protocol.md`](../docs/sync-protocol.md)。
3. **啟用 Batch API**：請至 Dashboard `Settings -> Application` 啟用 Batch API，並確認單批上限設定不低於 `100`。
