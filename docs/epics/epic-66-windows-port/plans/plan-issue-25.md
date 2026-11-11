# Issue 25：Windows 封面型別檢查 Plan（輕量）

**Goal：** Windows 的 EPUB 詮釋資料抽取，在探針回傳的封面 `coverType` 非 `image/*` 時拒收封面（`coverBytes` 為 `null`），與 Android（Issue 18 的 `mapProbeResult`）一致；並確認有沒有書已經存了壞封面。

## 現況（2026-11-11 讀碼確認）
- Windows：`windows_epub_metadata.dart` 的 `readEpubMetadataInWebView()` 在函式內直接 `jsonDecode` 後把 `coverBase64` 一律解碼，**沒讀 `coverType`**。解析寫在需要 WebView 的函式裡，無法單元測試。
- Android：`android_epub_metadata.dart` 的 `mapProbeResult(String json)` 是純函式，已有檢查與 7 個單元測試（`android_epub_metadata_test.dart`）。
- 兩邊用同一支 `metadata-probe.js`，輸出 JSON 結構相同（含 `coverBase64`、`coverType`）。
- 這台 Windows 的 `Documents/library.db` 只有 1 本書（PNG 封面、正常），**掃描沒有代表性**，只能證明工具可用，不能證明 Windows 使用者沒中招。

## 已定共識（待人類確認的項目見最後）
- 修法：Windows 改呼叫同一個 `mapProbeResult`，不再自己複製一份解析邏輯（避免兩邊再次分歧）。
- 為避免 Windows 檔案 import「android_」命名的檔，把 `mapProbeResult` **原封不動**搬到新檔 `app/lib/library/epub_probe_result.dart`；`android_epub_metadata.dart` 保留 `export 'epub_probe_result.dart' show mapProbeResult;`，既有 import 與測試不必改。
- 不改 `metadata-probe.js`、不動 Android 行為。
- Windows 回傳 Map 多一個 `'coverType'` 鍵（與 Android 一致）；確認 `windows_book_metadata.dart` 消費端忽略未知鍵，不受影響。
- 書庫掃描只讀：複製 `library.db` 到暫存、用檔頭魔術位元組（JPEG／PNG／GIF／WebP）判斷每本 `coverPath`，不碰原檔。

## Tasks
- [x] **Task 1：搬移。** 建 `epub_probe_result.dart`，內容＝`mapProbeResult` 原樣；`android_epub_metadata.dart` 改為 export 並移除原定義。跑 `android_epub_metadata_test.dart` 確認 7 項仍通過（純搬移，行為不變）。
- [x] **Task 2：Windows 測試先行。** 在 `windows_book_metadata_test.dart`（或新檔 `epub_probe_result_test.dart`）加一個以「Windows 路徑會收到的 JSON」餵 `mapProbeResult` 的案例，覆蓋：`application/xhtml+xml` 拒收、`image/jpeg` 解碼、`coverType` 缺漏相容。另加一個**接線測試**：`readEpubMetadataInWebView` 的結果映射確實走 `mapProbeResult`（若該函式因 WebView 無法單測，改為把「JSON → Map」抽成它呼叫的函式並測該函式；接線本身由 Task 4 實機確認）。確認修前失敗。
- [x] **Task 3：實作。** `readEpubMetadataInWebView` 內以 `mapProbeResult(resultJson)` 取代自己的解析；刪除該處已無用的 `base64Decode` 區塊。
- [x] **Task 4：Windows 實機驗證。** 用 `integration_test` 在 Windows 以真實 EPUB 跑一次詮釋資料抽取（沿用既有 Windows 詮釋資料整合測試，若無則以 fixture 跑）；另以一份**封面只能從 `guide` 頁取得**的 EPUB 驗證回傳 `coverBytes == null`。找不到這種 EPUB 時，以記憶體組出的最小 EPUB（比照 harness 場景的 `buildStoredZip` 寫法）產生，並在報告註明。
- [x] **Task 5：書庫掃描與報告。** 掃這台的 `library.db`（1 本）；請人類確認是否有其他 Windows 書庫可掃。寫 `issue-25-report.md`：改了什麼、測試結果、掃描結果與限制（樣本數）。
- [x] **Task 6：收尾。** `flutter analyze`；涉及測試檔跑單檔；整份完成後跑一次全套 `flutter test`；改了 `lib/` 任何 Key 時才跑 `check_integration_keys.js`。更新 `issues.md` 第 25 列。

## 過關條件
1. 非 `image/*` 的 `coverType` 在 Windows 也回傳 `coverBytes == null`，並保留 `coverType`。
2. 測試在修前失敗、修後通過；Android 既有 7 項測試仍通過。
3. 沒有第二份解析邏輯：Windows 與 Android 共用 `mapProbeResult`。
4. `flutter analyze` 乾淨。
5. 報告誠實記載掃描樣本數與限制（目前只有 1 本）。

## Review Focus
1. **只搬不改：** Task 1 之後 Android 測試必須原樣通過，diff 中 `mapProbeResult` 本體不得有任何字元差異。
2. **`coverType` 為 `null`／空字串：** 要照舊解碼（相容舊探針輸出與既有案例），不可因此丟掉有效封面。
3. **`coverBase64` 損壞：** 仍回傳 `null`、不丟例外（沿用現行行為）。
4. **Windows 消費端：** 多出的 `coverType` 鍵不得讓 `windows_book_metadata.dart` 或匯入服務出錯。
5. **舊資料：** 本 Issue 只擋新匯入，已存的壞封面不會自動修正；若掃描發現有，另開項目，不在此處理。

## 人類決定（2026-11-11）
同意共用 `mapProbeResult`；沒有其他 Windows 書庫（掃描只有 1 本，樣本不足）；接受合成 fixture。實作時 Task 2 的「純單元接線測試」不可行（解析在 WebView 函式內），改以 Windows 整合測試（修前紅、修後綠）取代。

## 原待確認項目
1. 是否同意「搬 `mapProbeResult` 到共用檔、Windows 直接呼叫」（建議），而非在 Windows 檔再複製一份檢查。
2. 這台書庫只有 1 本，是否另有 Windows 書庫（其他電腦或備份）可供掃描？沒有的話，報告就如實寫「樣本不足」。
3. Task 4 找不到「封面只在 `guide` 頁」的真書時，是否接受用最小 EPUB 組出的合成案例替代。
