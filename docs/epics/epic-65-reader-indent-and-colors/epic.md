# `epic-65-reader-indent-and-colors` 版面設定增強：首行縮排與自訂閱讀顏色

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-65-reader-indent-and-colors/`
**關聯 PRD 章節：** 版面與排版（版面控制項、主題切換）；關聯 `epic-28-reader-settings-enhancements`（版面設定面板）、`epic-22-reader-theme-integration`（閱讀主題接上書本內容）

## 背景

使用者提出兩項閱讀體驗增強（2026-10-25）：

1. 版面設定增加「首行縮排」，縮排大小為兩個字。
2. 第一個佈景（淺色，晴空藍天）的閱讀器背景不是純白，而是 `#F0F6FC`（很淡的藍白）。使用者希望改成純白，或讓使用者自己調閱讀器背景色（滑桿加輸入色碼雙重輸入）。

事實盤點（已核對程式）：

- 全專案目前沒有任何縮排功能。版面設定走一條現成的路：偏好 → `foliate_reader_view.dart` 組 map → `main.js` 組 CSS（例如段距 `p { margin-block-end: … !important }`）。縮排可用同一條路加 `text-indent`。
- 單書偏好 `BookReaderPrefs` 存 SQLite（資料庫目前版本 28）；「版面預設集」另存 JSON（`prefs_json`），欄位新增時舊預設集要能讀。
- 淺色佈景 `scaffoldBackground` 為 `#F0F6FC`，閱讀器頁面背景取自 `Theme.scaffoldBackgroundColor`，**整個 App 的畫面共用它**；E-Ink 佈景為純白。
- 佈景（淺色／深色／宣紙）與 E-Ink 開關存在 `SharedPreferences`（`AppThemePreferences`），是全域設定。
- 版面設定面板有 4 個分頁（文字、邊界、呈現、偏好）；數值控制項都有滑桿加 +/- 按鈕（E-Ink 模式改用步進器）。

## Discovery 決策（`/grill-with-docs` 定案，2026-10-25）

1. **放在新 Epic**：兩項功能同屬「版面設定增強」，不併入 `epic-54`（架構優化）。兩張 Issue，Issue 1 先做。
2. **首行縮排（Issue 1）**：開關加字數滑桿（附 +/-）；範圍 0～4 字、每次調 0.5 字；開關打開預設 2 字；關閉＝維持書本原本的縮排。
3. **縮排的套用範圍**：只套用 Foliate 流式格式（EPUB、TXT、MD、KF8），PDF、固定版面（FXL）、CBZ 不套用；套用到所有 `p` 段落，置中、空白、只含圖片的段落不特別排除（先用 WAVE 實書確認，必要時另開修正）；`!important`，不受「停用書本 CSS」影響；直排時往下縮。
4. **縮排的儲存**：單書偏好，`BookReaderPrefs` 新增 `firstLineIndent`（`double?`，單位 em，`null`＝關閉）；SQLite 版本 28→29，`book_reader_prefs` 新增欄位；「版面預設集」JSON 含此欄位，舊預設集讀不到視為 `null`。
5. **自訂閱讀顏色（Issue 2）**：背景色與文字色都可自訂。每個佈景（淺色、深色、宣紙）各存一組，全域、不分書；沒設定就用佈景原本的顏色。
6. **自訂色的邊界**：E-Ink 模式一律不套用，維持純黑白高對比；只影響閱讀器頁面，不影響書庫、設定頁等其他畫面（閱讀器內另算背景色，不直接改共用的 `scaffoldBackgroundColor`）；只套用 Foliate 流式格式，PDF、固定版面不套用。
7. **自訂色的介面**：放在版面設定面板「呈現」分頁；背景色與文字色各有紅、綠、藍 3 條滑桿（0～255）加色碼輸入框，雙向即時同步，附「還原預設」按鈕；色碼格式 `#RRGGBB`，輸入無效時不套用、輸入框標紅。
8. **自訂色不做對比警告**，也不自動改字色（文字色已讓使用者自己調）。
9. **自訂色的儲存**：`SharedPreferences`（比照佈景偏好），不動 SQLite。
10. **範圍外**：把淺色佈景整體背景改純白（使用者選擇做自訂功能，而非單改色）；PDF／固定版面的背景與縮排；單書層級的自訂色。
11. **詞彙**：`CONTEXT.md` 新增「首行縮排」與「自訂閱讀顏色」兩個詞條。不需要 ADR。
12. **流程**：兩張 Issue 各自一個分支、一個 PR，計畫與實作同分支同 PR（不另開文件 PR）；先寫 `plans/plan-issue-N.md`、計畫審查後再動手；程式審查報告存 `reviews/`（不進版控）；完整 `flutter test` 只在 Issue 最後跑一次；WAVE 真機抽驗後才開 PR。

## 開發記錄

**2026-10-25** 登錄 Epic 並完成 Discovery 決策。尚未撰寫計畫、尚未寫程式。
