# `epic-49-downloadable-fonts` 可下載字型

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-49-downloadable-fonts/`
**關聯 PRD 章節：** FR-09（內建字型）、FR-35（全域字型管理）

## 背景

`epic-48` 修正內建字型清單時發現：字型檔打包進 APK 的成本太高（思源黑體 34MB、思源宋體 57MB，5 款合計約 140MB），而之前開發版沒有打包思源兩款，選用時其實是系統字型補位。使用者詢問「不打包，讓使用者點『下載』後才下載該字型」是否可行，經 2026-09-25 `/grill-with-docs` 討論後定案：5 款內建字型一律改為「可下載字型」，字型檔放在 Cloudflare R2，透過 Cloudflare Worker 對外提供下載。

`epic-48` 已先把 `pubspec.yaml` 的字型全部移出；本 Epic 完成前，選思源兩款時由系統字型補位。

決策細節見 `design.md`。

## 開發記錄

**2026-09-25 Discovery**：`/grill-with-docs` 共 4 輪、20 題，產出 `design.md`；`CONTEXT.md` 新增「可下載字型」詞條。流程依使用者選擇採完整 SDD（design → spec → issues → plan → 審查）。
