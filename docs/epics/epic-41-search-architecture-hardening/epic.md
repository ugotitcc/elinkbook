# `epic-41-search-architecture-hardening` 全文檢索模組架構深化機會（epic-10-search 開發後盤點）

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-41-search-architecture-hardening/`
**關聯 PRD 章節：** 無直接對應（架構深化，源自 `epic-10-search`〔全文檢索〕開發完成後的 `/improve-codebase-architecture` 盤點，不新增產品功能）

## 開發記錄

2026-09-14 依 `/improve-codebase-architecture` 產出的候選深化機會（範圍：`epic-10-search` 開發出的 `app/lib/search/*`、`app/lib/screens/library_search_screen.dart`、`app/lib/screens/book_search_screen.dart`、`app/lib/reader/reader_jump_target.dart` 等程式碼，6 個候選）立案，跳過 Discovery/Architecting（來源已是整合後的候選清單，非從零探索，比照 `epic-26-architecture-hardening` 既有慣例）。六個候選已逐一用 `/grilling` 敲定實作細節，拆為 Issue 1-6：Issue 1（收斂 `ReaderScreen` 組裝工廠）、Issue 2（`ContentIndexStatusStore`）、Issue 3（`ReaderJumpTarget.applyTo()`）、Issue 4（`splitHighlightSegments` 純函式）、Issue 5（`FullTextSearchTogglesController`）皆標記 `ready-for-agent`；Issue 6（`JsBridgeGateway` correlation id 模式）刻意標記 `needs-info`——只記錄現況與觸發重新評估的條件，不擴充介面（`/grilling` Q8：目前只有一個真實呼叫端，「一個轉接器只是假設性接縫」，避免投機抽象）。

`epic-10-search` 本身維持「Issue 0-8 全部完成，全部工單結案，待歸檔」現狀不受影響——本 Epic 是它的後續深化，獨立立案，不併入其 `issues.md`。

**2026-09-14 `/superpowers:requesting-code-review` 審查 `epic.md`／`issues.md` 文件本身**（`reviews/review-epic-and-issues.md`，0 Critical／3 Important／3 Minor）並已依審查意見修訂 `issues.md`：I-1（Issue 3 `applyTo()` 改為同步、回傳 `bool`、Key 型別改用專案既有 `GlobalKey<State<PdfReaderView>>`/`GlobalKey<State<FoliateReaderView>>`）、I-2（Issue 2 `ContentIndexStatusStore` 移除不存在的 `category` 欄位、拆分 `markIndexing`/`updateProgress`、補齊 `backfillPending`/`clearByCategory` 批次方法）、I-3（Issue 1 函式更名 `buildReaderScreen`、回傳具體型別 `ReaderScreen`）皆已修正；M-1（Issue 4 `HighlightSegment` 補齊 `operator ==`/`hashCode`、函式改為公開頂層）、M-2（Issue 5 明訂可空 `repository` no-op 語意、controller 維持純資料物件）、M-3（本檔案路徑補齊）亦已修正。六個 Issue 的 `Status` 維持不變（Issue 1-5 `ready-for-agent`、Issue 6 `needs-info`）。

**2026-09-14 Issue 1 已完成並合併回 `main`（PR [#240](https://git.jigong.org/huthief/elinkBook/pulls/240)，分支 `epic/41-issue-1-reader-screen-route`，合併後 main 為 `eda628d0`）**：`plans/plan-issue-1.md` 4 個 Task 全數完成，新增 `buildReaderScreen()` 工廠函式，三個呼叫點皆已改用，`flutter analyze`／`flutter test` 全數通過零回歸；獨立程式審查（`reviews/review-issue-1.md`，本機保存、未進版控，見 `.gitignore`）確認 0 Critical／0 Important／1 Minor（純風格瑕疵），結論 Ready to merge: Yes。

**2026-09-14 Issue 2 已完成並合併回 `main`（PR [#241](https://git.jigong.org/huthief/elinkBook/pulls/241)，分支 `epic/41-issue-2-content-index-status-store`，合併後 main 為 `3e8dbdeb`）**：新增 `ContentIndexStatusStore` 收斂 `content_index_status`／`book_content_index` 狀態存取，`ContentIndexCategory` 搬遷並以 `export` 維持既有匯入者零改動，`ContentIndexingScheduler`／`SqliteFullTextSearchSettingsRepository` 皆已改用手寫 SQL 收斂，`flutter analyze`／`flutter test` 全數通過零回歸（僅 `adaptive_shell_scaffold_test.dart` 2 個既有失敗案例）。獨立程式審查（`reviews/review-issue-2.md`，本機保存、未進版控）確認 0 Critical／0 Important／1 Minor，結論 Ready to merge: Yes。**M-1（技術債，暫緩不修）**：本次異動的 3 個 `lib/search/*.dart` 檔案過不了本機 `dart format --set-exit-if-changed`，但交叉驗證同資料夾內完全未異動的既有檔案（`foliate_content_indexer.dart`／`pdf_content_indexer.dart`／`search_repository.dart`）同樣過不了，證實是全庫既有的 Dart SDK 格式化基準線落差，非本次實作引入；依審查建議與人類決策，不夾帶進本 Issue 修正，待之後另開一個獨立、範圍明確的格式化 Issue 統一處理。

**依賴順序：**

```
Issue 1 → Issue 3（Issue 3 的 applyTo() 由 Issue 1 收斂後的 ReaderScreen 開書路徑呼叫）

Issue 2／Issue 4／Issue 5（皆獨立，無依賴，可平行進行）

Issue 6（記錄用，暫不動手）
```

## 下一步

依 `issues.md` 逐一實作，建議順序：Issue 1 → Issue 3（一條鏈，且風險最低，優先做）；Issue 2、Issue 4、Issue 5 皆可任意順序或平行處理；Issue 6 暫緩，等待「出現第二個需要同樣按序配對模式的呼叫端」再重新評估是否拆案。
