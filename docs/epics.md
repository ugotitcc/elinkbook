# 🗺️ 專案 Epic 狀態看板

| Epic 代號 & 名稱 | 當前狀態 | 實際存放路徑 | 關聯 PRD 需求章節 | 備註 |
|---|---|---|---|---|
| `epic-0-skeleton` 技術骨架 | 🟡 開發中 (Active) | `docs/epics/epic-0-skeleton/` | 無對應 FR，技術地基 | Issue 1（Flutter 骨架+導航殼）已合併 main；Issue 2（ReaderScreen 格式偵測）計劃已寫好，執行中 |
| `epic-1-library` 圖書庫基礎 | ⚪ 未開始 (Backlog) | N/A | FR-01, 02, 03, 26, 27, 28, 29 | |
| `epic-2-vertical-core` 排版切換與直排核心 | ⚪ 未開始 (Backlog) | N/A | FR-05, 06, 32 | |
| `epic-3-fonts-layout` 字型與版面設定 | ⚪ 未開始 (Backlog) | N/A | FR-09, 10, 31 | |
| `epic-4-pdf-enhance` PDF 專業增強 | ⚪ 未開始 (Backlog) | N/A | FR-11 | |
| `epic-5-toc-pagination` 目錄與頁碼 | ⚪ 未開始 (Backlog) | N/A | FR-07, 08, 12, 22, 23 | |
| `epic-6-annotations` 註記與知識管理 | ⚪ 未開始 (Backlog) | N/A | FR-13, 14, 15, 16, 25 | |
| `epic-7-interaction` 互動控制 | ⚪ 未開始 (Backlog) | N/A | FR-18, 24 | |
| `epic-8-sync` 雲端同步 | ⚪ 未開始 (Backlog) | N/A | FR-19, 20, 30 | |
| `epic-9-stats` 閱讀統計 | ⚪ 未開始 (Backlog) | N/A | FR-17 | |
| `epic-10-search` 全文檢索 | ⚪ 未開始 (Backlog) | N/A | FR-04 | 獨立於圖書庫之外的子系統（SQLite FTS5） |
| `epic-11-txt-engine` TXT 直排引擎 | ⚪ 未開始 (Backlog) | N/A | 無直接對應 FR | 自訂輕量排版引擎，後續評估 Rust/C++ 共用核心 |
| `epic-12-social` 社群分享 | ⚪ 未開始 (Backlog) | N/A | FR-21 | P3，最低優先 |
| `epic-13-ios` iOS 移植 | ⚪ 未開始 (Backlog) | N/A | 無直接對應 FR | 待 Android 版本（epic-0/2/3/4/5）穩定後啟動 |

**狀態燈號定義**：
- ⚪ **未開始 (Backlog)**：已被規劃但尚未啟動。無實際目錄。
- 🟡 **開發中 (Active)**：目前正在進行設計探索或程式碼編寫。目錄存放於 `docs/epics/`。
- 🟢 **已歸檔 (Archived)**：實作完成、測試通過且併入主線。目錄已移至 `docs/archive/`。
