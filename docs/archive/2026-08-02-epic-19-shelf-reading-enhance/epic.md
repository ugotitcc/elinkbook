# `epic-19-shelf-reading-enhance` 書架與閱讀體驗強化（全螢幕模式/刪除書籍/分類拼貼）

**狀態：** 🟢 已歸檔 (Archived)
**存放路徑：** `docs/archive/2026-08-02-epic-19-shelf-reading-enhance/`
**關聯 PRD 章節：** 無直接對應既有 FR 編號（全螢幕模式與 FR-42 相關但範圍不同，分類拼貼與 FR-33/34 相關但為全新顯示型態）

## 開發記錄

2026-07-28 使用者提出 3 項新功能需求（全螢幕閱讀選項／刪除書籍與分類／分類 2×2 拼貼格取代現有 Chip 列），經 `/grill-with-docs` Discovery 逐項釐清後合併立案，詳見 `design.md`；`spec.md` 經 `/superpowers:requesting-code-review` 審查（3 項 Critical＋3 項 Important，已修訂）；拆解為 3 個獨立工單（Issue 1 全螢幕模式／Issue 2 刪除書籍／Issue 3 分類拼貼格）皆已全數實作完成並經單元測試、審查與真機驗收（Issue 1 改採原生 `WindowInsetsControllerCompat` 並記錄 ADR 0015）。**Epic 19 全部 3 個 Issue（Issue 1-3）皆已完成**；2026-08-02 人類確認歸檔，搬移至 `docs/archive/2026-08-02-epic-19-shelf-reading-enhance/`
