# Issue 40 實作計畫：書架操作殼評估與 `mounted` 缺口修補

**結論（2026-11-16 `/grilling`）**：**不抽書架操作殼 module。** `LibraryBatchActions` 已是純邏輯並有獨立測試；剩下的「取 id→確認→退出選取→呼叫→重載」每個方法僅約 5 行，抽成 helper 只會變淺 module（刪除測試：刪掉它複雜度不會轉移到呼叫端）。只修一個真缺口。

## 範圍

- `_moveSelectedBooksToGroup`：`await showDialog` 之後、`_exitSelectionMode()` 之前補 `if (!mounted) return;`。
- 刪除 `_deleteSelectedBooks` 註解中「`_moveSelectedBooksToGroup()` 缺這道檢查屬既有缺口」的過時說明。
- 另 3 個批次方法（強制固定版面、還原自動版面、移除本機快取）沒有 `await` 對話框，同步退出選取，不需檢查，不動。
- 單本 3 個方法（`_moveBookToGroup`、`_removeBookCache`、`_deleteBook`）已有 `mounted` 檢查，不動。

## Tasks

- [x] **Task 1（紅）**：`library_screen_test.dart` 新增測試：開「移動到分類」對話框後移除 `LibraryScreen`，再選分類；斷言無例外、書籍分類未變。現況下失敗（`_exitSelectionMode` 的 `setState` 在 dispose 後被呼叫）。
- [x] **Task 2（綠）**：補 `mounted` 檢查並更新過時註解。
- [x] **Task 3**：`library_screen_test.dart`、`library_batch_actions_test.dart`（149 通過）、`flutter analyze`（乾淨）。完整 `flutter test` 已跑：5286 通過、1 偶發失敗（`download_queue_controller_test`，單獨重跑通過、與本 Issue 無關）。

## 不做

不改 `LibraryBatchActions`、不新增 module、不動 `CONTEXT.md`／ADR。
