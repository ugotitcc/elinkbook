# `epic-48-font-and-language-labels` （缺陷）內建字型清單精簡、不打包字型檔，字型名稱與語言選項的語系顯示修正

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-48-font-and-language-labels/`
**關聯 PRD 章節：** FR-09（內建字型）、FR-49（多語系介面）

## 背景

2026-09-25 使用者回報三項問題：

1. **內建字型精簡**：預設字型只保留思源黑體、思源宋體，其餘 3 款（原俠正楷、台灣圓體、源流明體）先停用，不顯示在字型選單，字型檔也不打包進 APK。
2. **字型名稱未翻譯**：介面語系選「English」時，「字型管理」的內建字型仍顯示「思源黑體」「思源宋體」。
3. **語言選項名稱被翻譯**：語言選擇的選項應固定顯示「正體中文」「简体中文」「English」（各語言的固有名稱），不應隨介面語系變成「Traditional Chinese」「Simplified Chinese」。

## 開發記錄

**2026-09-25 `/diagnosing-bugs` 診斷**。依使用者選擇採直接 TDD：不另寫 `plans/plan-issue-N.md` 與計畫審查，保留程式審查。

### 根因

- **問題 1**：`AppFont` enum 列出 5 款，字型管理畫面、閱讀設定下拉選單、`buildFontFaceCss()` 都直接走訪 `AppFont.values`。另外，commit `eddcc85e`（開發期加速建置）讓 `pubspec.yaml` 只打包原俠正楷。
- **問題 2**：`font_management_screen.dart` 的 `_builtInDisplayName()` 與 `reader_settings_sheet.dart` 的 `_fontDisplayName()` 各自硬寫中文字型名稱，沒有經過 `AppLocalizations`。
- **問題 3**：`settingsLanguageZhTW／ZhCN` 在各 arb 檔都被翻譯（en 為「Traditional Chinese」「Simplified Chinese」，zh／zh_TW 的簡體選項寫成「簡體中文」，zh_CN 的正體選項寫成「正体中文」）。設定頁「語言」列的副標題與「跟隨系統（…）」共用同一組字串。

### 釐清：思源兩款未打包為何仍「正常顯示」

使用者指出，思源兩款之前沒有打包，選用時仍然正常顯示。追查程式碼後確認：`main.js` 輸出單一字型名稱的 `font-family: 'SourceHanSansTC' !important`，`@font-face` 指向的 asset 未宣告，`loadFlutterFontAsset()` 回傳 null，字型載入失敗後 WebView 退回系統預設字型。Android 內建的 Noto Sans CJK 和思源黑體是同一套字型設計，所以看起來完全正常。選思源宋體時，退回的預設字型很可能是黑體而不是宋體（尚未在真機確認）。

### 使用者決策

- 停用方式：註解掉 enum 值與所有 switch 分支，統一加上 `[字型停用]` 標記，恢復時 grep 即可找回。
- 舊偏好值：只在閱讀設定面板做防呆，顯示成「使用書本字型」，不改資料庫；字型恢復後舊偏好自然生效。
- 修正範圍：閱讀設定的字型下拉選單一併翻譯；語言列副標題與「跟隨系統（…）」也改用固有名稱。
- 字型檔來源（`/grill-with-docs` 討論後定案）：5 款內建字型**一律不打包進 APK**，改為「可下載字型」，另開 `epic-49-downloadable-fonts` 實作。本 Epic 只把 `pubspec.yaml` 的字型全部移出；下載功能完成前，選思源兩款會由系統字型補位（與先前實際行為相同）。
- 字型名稱依語系顯示和 `CONTEXT.md` 原本「內建字型名稱不翻譯」的規定衝突，已改以本次需求為準，同步修改 `CONTEXT.md`（改為顯示該字型官方發行的對應名稱）。

### 回饋迴圈與修正

- **紅燈測試**（修正前 12 個失敗，皆對應回報的症狀）：`app_font_test`（enum 只剩 2 款）、`foliate_native_bridge_test`（`@font-face` 只剩 2 條）、`font_management_screen_test`（只列 2 款、英文顯示「Source Han Sans／Serif」、簡中顯示「思源黑体／宋体」）、`reader_settings_sheet_test`（英文下拉選單、存著 `GuanKiapTsingKhai` 時面板正常且顯示「使用書本字型」）、`settings_scaffold_test`（英文介面下三個選項與副標題皆為固有名稱）。決定不打包字型後，再新增「5 款字型 asset 一律讀不到」的測試（先確認紅燈再改 `pubspec.yaml`）。
- **修正**：
  - `app_font.dart`：3 款字型的 enum 值與分支加上 `[字型停用]` 註解；新增 `displayName(AppLocalizations)`，兩個畫面改共用，刪除原本兩份重複的硬編碼函式。
  - 新增 l10n key `fontNameSourceHanSans／fontNameSourceHanSerif`（zh_TW／zh：思源黑體、思源宋體；zh_CN：思源黑体、思源宋体；en：Source Han Sans、Source Han Serif）。
  - 各 arb 檔的語言選項一律改為「正體中文」「简体中文」「English」，zh_TW 範本的 description 註明「固有名稱，不翻譯」。
  - `reader_settings_sheet.dart`：下拉選單的 `value` 不在選項中時顯示為 `null`（只影響顯示，不改寫偏好）。
  - `pubspec.yaml`：5 款字型全部不宣告。原俠正楷字型檔仍在 `assets/fonts/`（之後由 epic-49 決定去留）。
  - 文件：`docs/prd.md` FR-09、`CLAUDE.md`「版面與排版」、`CONTEXT.md`（介面語系詞條、自訂字型詞條、新增「可下載字型」詞條）。
- **修正後**：受影響的測試檔全部通過；`flutter analyze` 乾淨；`check_l10n_hardcoded_strings.js` PASS。

### 影響

- APK 不再包含任何字型檔（原本開發版包含 14.7MB 的原俠正楷）。

**2026-09-25 PR #275 已合併進 `main`**（merge commit `21e33dc7`）。修正已全數完成；可下載字型由 `epic-49-downloadable-fonts` 接續。
