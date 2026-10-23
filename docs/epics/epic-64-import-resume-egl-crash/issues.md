# Epic 64 — 檔案選擇器返回後 EGL context 遺失：工單清單 (Issues)

1 個 Issue。

---

## Issue 1：重現、定位與修復 Impeller／EGL context 遺失造成的 abort

**Status:** needs-triage

**依賴：** 無。

**背景：** 見 `epic.md`「背景」與「已知事實」。2026-10-22 在 WAVE E-Ink 機匯入書籍時三次 abort，logcat 顯示從 DocumentsUI 返回後 `eglMakeCurrentImpl: EGL_BAD_ACCESS`，Impeller 無法建立 framebuffer，於 raster 執行緒 `Check failed` 後 SIGABRT。

**What to build：**
- 先以 `/diagnose` 建立可控重現：開啟 SAF 檔案選擇器 → 取消或選檔返回，記錄「abort／正常」次數，至少 10 次。
- 分辨觸發範圍：只有檔案選擇器，還是任何前景切換（分享面板、系統設定、電源鍵）都會。
- 對照組（至少各 5 次）：release 版、關閉 Impeller（manifest `io.flutter.embedding.android.EnableImpeller=false`）或等效設定、基準 commit `d7d13e12`。
- 依診斷結果決定修法並實作；若需要跨多個 Task，先寫 `plans/plan-issue-1.md` 並送審查。

**測試要求：**
- 能用自動測試固定的部分（例如表面重建後的狀態機）補測試；純裝置／驅動層問題則以診斷紀錄的次數表為證據，不假造自動測試。
- `flutter analyze` 乾淨；`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js` 通過（若動到畫面字串或整合測試）。

**驗收標準：**
- 同一台 WAVE E-Ink 機，依診斷出的重現步驟連續 10 次，App 不再 abort（允許一次重繪失敗或黑屏後恢復）。
- 原本的書籍匯入流程（MD／EPUB）可完成且進入閱讀器。
- 診斷與驗收數字寫回 `epic.md`；若最後判定是引擎／驅動限制而無法在 App 層修，須寫明降級方案與已知限制，由人類決定是否接受。

**Blocked by：** 無（需要實機）。
