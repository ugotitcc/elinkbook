# elinkBook PocketBase 同步後端 Docker 部署說明

本目錄提供依據 [`docs/epics/epic-8-sync/pocketbase-self-hosting.md`](../docs/epics/epic-8-sync/pocketbase-self-hosting.md) SOP 製作之容器化架構檔。

## 📁 檔案結構

```
docker/
├── Dockerfile                  # 容器建置檔 (Alpine 3.20 + 指定版本 PocketBase)
├── docker-compose.yml          # Docker Compose 設定檔
├── .env                        # 環境變數實體檔 (變數控管)
├── .env.example                # 環境變數範例檔
└── pb_hooks/                   # PocketBase JS Hooks 掛載目錄
    └── purge_tombstones.pb.js  # 定期自動清理 30 天以上軟刪除墓碑之 JS cron
```

## 🚀 快速啟動

在 `docker/` 目錄下執行：

```bash
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
| `PB_VERSION` | `0.39.10` | PocketBase 版本 (必須 `>= 0.23` 以支援 Batch API) |
| `PORT` | `8090` | 宿主機映射之對外 HTTP 埠號 |
| `CONTAINER_NAME` | `elinkbook-pocketbase` | 容器名稱 |
| `DATA_PATH` | `./pb_data` | 資料持久化儲存目錄 |
| `HOOKS_PATH` | `./pb_hooks` | PocketBase JS Hooks 掛載目錄 |

## 📌 注意事項

1. **首次啟動管理員**：連線至 `http://localhost:8090/_/` 建立 PocketBase 系統管理員帳號。
2. **Collection 建立與 API Rules**：請對照 [`pocketbase-self-hosting.md`](../docs/epics/epic-8-sync/pocketbase-self-hosting.md) 新增 `sync_reading_positions`、`sync_bookmarks`、`sync_highlights` 與 `sync_notes` 四個 Collection，並將 API Rules 統一設為 `user = @request.auth.id`。
3. **啟用 Batch API**：請至 Dashboard `Settings -> Application` 啟用 Batch API，並確認單批上限設定不低於 `100`。
