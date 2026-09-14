# 儲存權限失效復原：維持 SAF 路線＋失效偵測，不採用 MANAGE_EXTERNAL_STORAGE 全域權限

`epic-15-storage-permission` Discovery 階段評估「SAF 持久化權限（`takePersistableUriPermission()`，見 ADR 0002）在部分裝置上失效、需重新選取檔案／資料夾」的補強方案時，決定**不採用** `MANAGE_EXTERNAL_STORAGE`（Android 11+ All Files Access 全域儲存權限）路線，改為在既有 SAF 架構上強化失效偵測與使用者重新授權引導。

原因：App 已規劃上架 Google Play，而 Play 政策將 `MANAGE_EXTERNAL_STORAGE` 保留給檔案總管／備份／防毒等特定類別 App，「電子書閱讀器」申請此權限通過審核的風險高；同時產品仍須維持非 Google Play 商城（側載）安裝路徑正常運作，若採用此權限還需額外處理雙通路相容性，進一步降低此方向的效益。

## Considered Options

- `MANAGE_EXTERNAL_STORAGE`（全域儲存權限）——一次授權後不需逐檔/逐資料夾重新選取，體驗最佳，但因上述 Play 政策風險予以排除。
- 維持現況、不做任何補強——但問題曾經實際發生過且原因未查明，貿然放棄追蹤有隱性風險，故仍以「失效偵測＋提示重新授權」這個低成本方向保留補強空間。

## Consequences

- 若使用者遇到 persistable permission 失效，仍需手動重新走一次 SAF 選取流程（本決策只改善為「明確被告知需要重新選」，非「完全免除重新選取」）。
- 此決策目前尚未實際排入開發（`epic-15-storage-permission` 現況為 Discovery 完成、待評估是否拆分 Issue），若未來要重新考慮 `MANAGE_EXTERNAL_STORAGE` 路線，需先確認發行策略是否仍要求 Google Play 上架。
