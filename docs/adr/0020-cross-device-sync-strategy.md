# 跨裝置同步策略：內容指紋比對書籍、Checkpoint 批次觸發、清單型資料以 id 聯集合併

`epic-8-sync` 對應 FR-19（閱讀位置同步，單一值、衝突須詢問使用者）與 FR-20（劃線/備註/書籤同步，清單型資料）。現況：`Book.id` 是本機時間戳記＋URI hash 產生（`app/lib/library/book_import_service_impl.dart:197`），跨裝置不穩定；`bookmarks`/`highlights`/`notes` 用本機自增整數 id；資料庫完全沒有 `updated_at`/soft-delete 欄位；全專案零 connectivity/offline 既有模式。決策如下：

1. **跨裝置書籍身份比對改用「書籍內容指紋」，不用本機 `Book.id`**：EPUB 優先取 OPF identifier（通常是 ISBN 或出版社 UUID），缺漏時退而用檔案內容 hash；PDF/TXT 一律用檔案內容 hash。匯入時計算存入 `books.content_fingerprint`，同步邏輯以此指紋比對「是否為同一本書」。
2. **同步觸發採批次 checkpoint，不做逐筆即時同步**：checkpoint 定義為以下三者之一——(a) App 背景化（`AppLifecycleState.paused`）、(b) 書籍切換（離開閱讀器）、(c) 閱讀中每 5 分鐘的閒置計時器（避免「長時間不背景化也不切書」時另一裝置長期看不到最新異動的漏洞）。三者任一觸發即對期間累積的所有異動做一次批次同步請求。
3. **清單型資料（劃線/備註/書籤）以 id 聯集合併，不彈窗詢問使用者**：每筆新增全域唯一 `sync_id`（UUID）＋`updated_at`＋軟刪除墓碑 `deleted_at`（避免「A 已刪除、B 還沒同步到又同步回來復活」）；合併規則為雙方 id 聯集，同一 id 兩邊都有時比較 `updated_at`、新的蓋舊的（last-write-wins，不彈窗）。閱讀位置（FR-19，單一值）維持既有明文規則不變：本機與雲端不一致時彈窗詢問使用者，不自動合併。
4. **同步失敗（離線）採靜默重試，不做佇列/退避演算法**：本機異動一律先落地成功，失敗只代表「還沒同步過去」，`updated_at`/墓碑機制本身足以判斷待同步項目，下一次任何 checkpoint 觸發時自然重試。

## Considered Options

- 逐筆即時同步（每次異動都立刻嘗試同步）——與 FR-19 既有的批次觸發用詞（「App 關閉或書籍切換時」）不一致，且行動裝置頻繁打網路請求對電量/流量不友善，放棄。
- metadata 模糊比對書籍身份（書名+作者相同即視為同一本）——實作簡單但不精確（同名書、版本差異會誤判），放棄，改採內容指紋。
- 清單型資料衝突也彈窗詢問使用者（比照閱讀位置）——清單型資料多筆共存、多為新增而非互斥修改，逐筆彈窗會嚴重打斷使用體驗，放棄。

## Consequences

- 需要新的 schema migration（v15→v16）：`books` 新增 `content_fingerprint`；`bookmarks`/`highlights`/`notes` 三表各自新增 `sync_id`/`updated_at`/`deleted_at`；閱讀位置新增 `position_updated_at`。
- 需要新增 App 生命週期監聽＋書籍切換事件＋閒置計時器三種 checkpoint 觸發來源。
- TXT 格式的字元偏移量欄位本次不預留，留待 `epic-11-txt-engine` 啟動後另行 migration 補上。
