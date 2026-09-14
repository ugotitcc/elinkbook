# Epic 15：儲存權限失效偵測與復原

## 背景

App 匯入書籍與字型檔案一律不複製檔案，直接以 SAF（Storage Access Framework）取得的 `content://` URI 搭配 `takePersistableUriPermission()` 持久化授權引用原始檔案（見 ADR 0002、ADR 0021）。專案初期曾實際發生「部分裝置重新選取子資料夾體驗不佳」的狀況，但當時未查明具體觸發裝置/ROM 或根本原因，也沒有針對性修復；後續開發至今，所有測試機皆未再重現這個問題，目前沒有可鎖定的具體場景或使用者回報。

由於問題不再重現、成因不明，這個 Epic 長期停留在 `docs/epics.md` 的 Backlog 備註，一句話帶過（「傳統儲存權限機制」）。2026-09-14 透過 `/grill-with-docs` 對此重新展開 Discovery，釐清方向。

## 目標

本次僅進行風險評估與方案調查（Discovery），**非**直接排入開發：

1. 釐清問題目前的風險狀態（是否仍可能發生、影響範圍多大）。
2. 排除技術上不可行或高風險的解法方向。
3. 提出若未來問題重現時的候選補強方向，降低下次重新評估的成本。

## Discovery 結論（2026-09-14 `/grill-with-docs`）

- **問題現況**：不再重現，無具體裝置/ROM 線索，原因不明（開發過程中未曾針對性修復，純粹是後續測試都沒再撞到）。
- **影響範圍**：SAF 檔案匯入與資料夾匯入兩條路徑皆可能受影響。
- **排除方向**：`MANAGE_EXTERNAL_STORAGE`（Android 11+ 全域儲存權限，All Files Access）——App 已規劃上架 Google Play，此權限對「電子書閱讀器」類別的審核風險高，且仍須維持非商城（側載）安裝路徑正常運作，兩個約束疊加使此方向不可行。詳見 [ADR 0029](../../adr/0029-storage-permission-saf-resilience-over-manage-external-storage.md)。
- **候選補強方向**：不新增權限，改為強化既有 SAF 路線的容錯——偵測 persistable permission 是否已失效（例如透過 `ContentResolver.getPersistedUriPermissions()`），失效時主動提示使用者重新授權，而非靜默失敗或整批要求重新走一次匯入流程。詳見 [design.md](./design.md)。
- **後續**：本 Epic 目前停留在 Discovery 完成階段。是否排入 Issue 拆分、實際開發，待有具體重現案例或使用者回報後再評估，不強制排期。

## 目前狀態

Discovery 完成，`design.md` 已產出。尚未進入 Architecting（`spec.md`）／Issue 拆分（`issues.md`）。
