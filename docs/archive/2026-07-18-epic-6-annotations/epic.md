# `epic-6-annotations` 註記與知識管理

**狀態：** 🟢 已歸檔 (Archived)
**存放路徑：** `docs/archive/2026-07-18-epic-6-annotations/`
**關聯 PRD 章節：** FR-13, 14, 15, 16, 25

## 開發記錄

2026-07-16 完成 Discovery（`design.md`，15 項決策，含審查修正）、Architecting（`spec.md` + ADR 0008：PDF 劃線長按觸發框選）、Scrum Master 階段（`issues.md`，最終共 6 個垂直切片工單：Issue 1 書籤+統一筆記入口／Issue 2 EPUB 劃線與備註／Issue 3 PDF 劃線與備註／Issue 4 FXL 書籤支援／Issue 5 Markdown 匯出／Issue 6 正式圖書庫流程貫穿 Repository，Issue 1 可立即開始）。**開發順序決議（2026-07-14 `/grill-with-docs`）：單機閱讀優先波次第 4 順位**，排在 Epic 14 之後；FR-13/FR-15 涉及 TXT 定位（字元偏移量）的部分暫緩，比照 Epic 5 FR-12 的處理原則，僅在 `epic-11-txt-engine` 完成後才補，本 epic 初版範圍僅涵蓋 EPUB/PDF。2026-07-17 完成並合併 **Issue 1**（書籤管理 + 統一「📚 筆記」入口）：8 個 Task（`bookmarks` 表 v7→v8 累加式 migration、`BookmarksRepository`、`Bookmark`／`BookmarkPositionContext`／`defaultName`、`NotesBottomSheet` 雙分頁籤外殼、書籤 toggle/重新命名/單筆刪除/批次刪除、`ReaderScreen` 接線）逐一審查通過，最終整體分支審查修正 EPUB 📚 按鈕定位就緒判斷競速問題（比照既有 `_tocLoaded` 防呆模式）與 `TextEditingController` 洩漏；`flutter test` 386 個全過、`flutter analyze` 乾淨；已透過 PR #49 合併回 `main`。完成並合併 **Issue 2**（EPUB 劃線與備註）：`highlights`／`notes` 表 v8→v9 累加式 migration（含可為空的 `highlight_id REFERENCES highlights(id) ON DELETE SET NULL`）、`HighlightsRepository`／`NotesRepository`、`AnnotationToolbar` 浮動工具列、`EpubReaderView.kt`／`.dart` 選字攔截／Decorator 疊加／標記點擊，`ReaderScreen` 接上 EPUB 端到端流程；審查修正 `mergeAnnotations` 孤兒備註退化邏輯；已透過 PR #50 合併回 `main`。完成並合併 **Issue 3**（PDF 劃線與備註）：長按拖曳框選改由 Flutter `GestureDetector` 主導辨識（原生端僅被動接收四個 method call，避免攔截既有滑動翻頁手勢）、`highlights`／`notes` 表新增 PDF 欄位（v9→v10 migration）、`refreshAnnotations()` 原生 Bitmap 疊加渲染；`flutter test` 466 個全過、Kotlin JVM 測試 73 個全過；已透過 PR #51 合併回 `main`。完成並合併 **Issue 4**（FXL 固定版面書籤支援）：懸浮 🔖 書籤 toggle／📚 筆記按鈕，複用 Issue 1 邏輯，書籤跳轉比照既有 `onFixedLayoutPageTurn` 慣例強制收合懸浮控制面板；已透過 PR #52 合併回 `main`。完成並合併 **Issue 5**（Markdown 匯出）：`generateMarkdownExport()` 純函式＋`NotesBottomSheet`「導出為 Markdown」按鈕，寫入 `getTemporaryDirectory()` 並透過 `share_plus` 觸發系統分享；`share_plus` 因 `win32` 相依衝突鎖定 `^11.1.0`（已於 `pubspec.yaml` 記錄具體衝突鏈結）；`flutter test` 483 個全過；已透過 PR #53 合併回 `main`。2026-07-18 完成並合併 **Issue 6**（正式圖書庫流程貫穿 `highlightsRepository`／`notesRepository`，修正 Issue 4/5 審查發現的既有貫穿缺口）：`LibraryScreen`／`ElinkBookApp`／`main.dart` 依樣新增可選具名參數並貫穿（比照既有 `bookmarksRepository` 注入模式），新增端到端測試驗證正式書架開書流程下劃線/備註分頁與 Markdown 匯出皆確實反映真實資料而非固定空狀態；`flutter test`（全專案 486 個）全過、`flutter analyze` 乾淨；已透過 PR #54 合併回 `main`。**Epic 6 全部 6 個 Issue（Issue 1-6）皆已完成**；2026-07-18 人類確認歸檔，搬移至 `docs/archive/2026-07-18-epic-6-annotations/`

## 逐 Issue 完成記錄（原「單機閱讀優先波次」進度表內容，順位 4）

**提前於 `epic-7`／`epic-14` 之前完成**（既成事實，已合併回 `main`，不可逆），是本波次唯一的順序偏離
